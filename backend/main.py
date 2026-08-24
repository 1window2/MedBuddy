# 파일명: main.py
# 역할: MedBuddy FastAPI 애플리케이션을 생성하고 구성한다.

import asyncio
import logging
import time
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager
from pathlib import Path

from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from alembic.util.exc import CommandError
from fastapi import FastAPI, HTTPException
from redis.asyncio import Redis
from redis.exceptions import RedisError
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from starlette.concurrency import run_in_threadpool
from starlette.middleware.trustedhost import TrustedHostMiddleware

from api.chat_router import router as chat_router
from api.pharmacy_router import router as pharmacy_router
from api.router import auth_router, router as medication_router
from api.dependencies import (
    close_pharmacy_boundary,
    close_medication_detail_cache,
    close_pill_identification_boundaries,
    close_public_drug_boundaries,
    get_app_check_token_verifier,
    get_oidc_token_verifier,
    get_push_notification_boundary,
)
from boundaries.firebase_admin_boundary import verify_firebase_admin_credentials
from boundaries.pill_identification_boundary import MAX_PILL_IMAGE_BYTES
from core.config import settings
from core.api_contract import ApiContractMiddleware
from core.database import Base, SessionLocal, engine
from core.request_limits import RequestBodyLimitMiddleware
from core.request_rate_limits import (
    DEFAULT_RATE_LIMIT_RULES,
    RequestRateLimitMiddleware,
    RequestRateLimitStore,
)
from entities import health_recommendation_cache_entity  # noqa: F401
from entities import medication_detail_entity  # noqa: F401
from entities import medication_completion_entity  # noqa: F401
from entities import medication_alarm_entity  # noqa: F401
from entities import caregiver_notification_entity  # noqa: F401
from entities import caregiver_alert_outbox_entity  # noqa: F401
from entities import chat_message_entity  # noqa: F401
from entities import device_push_token_entity  # noqa: F401
from entities import patient_caregiver_link_entity  # noqa: F401
from entities import pill_identification_entity  # noqa: F401
from entities import pharmacy_catalog_entity  # noqa: F401
from entities import saved_medication_entity  # noqa: F401
from entities import user_setting_entity  # noqa: F401
from entities import user_account_entity  # noqa: F401
from entities.caregiver_notification_entity import ensure_caregiver_notification_schema
from entities.medication_completion_entity import ensure_medication_completion_schema
from entities.medication_alarm_entity import ensure_medication_alarm_schema
from entities.saved_medication_entity import ensure_saved_medication_schema
from entities.user_setting_entity import ensure_user_setting_schema
from services.data_maintenance import PeriodicDataMaintenanceRunner
from services.caregiver_alert_outbox_worker import CaregiverAlertOutboxWorker
from services.chat_connection_manager import ChatConnectionManager


_BACKEND_ROOT = Path(__file__).resolve().parent
_READINESS_CACHE_TTL_SECONDS = 5.0
_READINESS_EXCEPTIONS = (
    SQLAlchemyError,
    CommandError,
    RedisError,
    RuntimeError,
    ValueError,
    OSError,
)


# 클래스명: _ReadinessProbeCache
# 역할: 운영 의존성에 대한 반복 준비 상태 검사를 제한한다.
# 주요 책임:
#   - 동시에 들어온 준비 상태 요청을 한 번의 의존성 검사로 합친다.
#   - 준비 여부만 짧은 시간 동안 저장한다.
#   - 예외 상세와 외부 서비스 응답 데이터는 보관하지 않는다.
# 속성:
#   - ttl_seconds: 저장된 결과가 만료되기까지의 초 단위 시간
class _ReadinessProbeCache:
    def __init__(self, ttl_seconds: float) -> None:
        self.ttl_seconds = ttl_seconds
        self._lock = asyncio.Lock()
        self._expires_at = 0.0
        self._is_ready = False

    # 함수이름: request_readiness
    # 함수역할: 짧게 저장된 준비 상태를 반환하고 만료 시 의존성을 한 번만 검사한다.
    # 매개변수: check - 사용할 수 없는 서비스에서 예외를 발생시키는 비동기 검사
    # 반환값: 모든 의존성이 준비됐으면 true, 아니면 false
    async def request_readiness(
        self,
        check: Callable[[], Awaitable[None]],
    ) -> bool:
        now = time.monotonic()
        if now < self._expires_at:
            return self._is_ready

        async with self._lock:
            now = time.monotonic()
            if now < self._expires_at:
                return self._is_ready
            try:
                await check()
                self._is_ready = True
            except _READINESS_EXCEPTIONS:
                self._is_ready = False
            self._expires_at = time.monotonic() + self.ttl_seconds
            return self._is_ready

    # 함수이름: reset
    # 함수역할: 애플리케이션 수명 주기가 시작될 때 저장된 준비 상태를 무효화한다.
    # 반환값: 없음
    def reset(self) -> None:
        self._expires_at = 0.0
        self._is_ready = False


def _verify_database_revision(connection: object) -> None:
    alembic_config = Config(str(_BACKEND_ROOT / "alembic.ini"))
    script = ScriptDirectory.from_config(alembic_config)
    expected_heads = set(script.get_heads())
    current_heads = set(MigrationContext.configure(connection).get_current_heads())
    if current_heads != expected_heads:
        raise RuntimeError("Database migration revision does not match Alembic head.")


def _verify_catalog_seed(connection: object) -> None:
    required_tables = (
        "drug_basic_infos",
        "drug_approval_infos",
        "pill_identification_references",
        "pharmacy_catalog_records",
    )
    for table_name in required_tables:
        has_rows = connection.execute(
            text(f"SELECT EXISTS (SELECT 1 FROM {table_name} LIMIT 1)")
        ).scalar_one()
        if not has_rows:
            raise RuntimeError("The shared medication catalog is not seeded.")


def _verify_database_dependencies() -> None:
    with engine.connect() as connection:
        connection.execute(text("SELECT 1"))
        if settings.APP_ENV == "production":
            _verify_database_revision(connection)
            _verify_catalog_seed(connection)


async def _ping_required_redis() -> None:
    redis = Redis.from_url(
        settings.REDIS_URL,
        socket_connect_timeout=0.3,
        socket_timeout=0.3,
    )
    try:
        if not await redis.ping():
            raise RuntimeError("Redis readiness ping was rejected.")
    finally:
        await redis.aclose()


# 함수이름: _verify_runtime_dependencies
# 함수역할: 데이터베이스, Firebase, App Check와 Redis의 준비 상태를 검사한다.
# 반환값: 모든 설정된 의존성이 준비되면 없음
async def _verify_runtime_dependencies() -> None:
    await run_in_threadpool(_verify_database_dependencies)
    if settings.AUTH_MODE == "firebase":
        await run_in_threadpool(
            verify_firebase_admin_credentials,
            settings.FIREBASE_PROJECT_ID,
        )
        get_oidc_token_verifier()
    if settings.FIREBASE_APP_CHECK_REQUIRED:
        get_app_check_token_verifier()
    if settings.RATE_LIMIT_REQUIRE_REDIS:
        await _ping_required_redis()


# 함수이름: configure_logging
# 함수역할: 애플리케이션 시작 계층에서 로그 형식과 수준을 구성한다.
# 반환값: 없음
def configure_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)


@asynccontextmanager
async def application_lifespan(app: FastAPI) -> AsyncIterator[None]:
    maintenance_runner: PeriodicDataMaintenanceRunner | None = None
    alert_outbox_worker = CaregiverAlertOutboxWorker(
        SessionLocal,
        get_push_notification_boundary,
        settings.CAREGIVER_ALERT_OUTBOX_POLL_SECONDS,
    )
    alert_outbox_worker.start()
    app.state.caregiver_alert_outbox_worker = alert_outbox_worker
    app.state.readiness_probe_cache.reset()
    if settings.PERIODIC_MAINTENANCE_ENABLED:
        maintenance_runner = PeriodicDataMaintenanceRunner(SessionLocal)
        maintenance_runner.start()
        app.state.data_maintenance_runner = maintenance_runner
    try:
        yield
    finally:
        await alert_outbox_worker.stop()
        if maintenance_runner is not None:
            await maintenance_runner.stop()
        await app.state.request_rate_limit_store.close()
        await close_pill_identification_boundaries()
        await close_medication_detail_cache()
        await close_public_drug_boundaries()
        await close_pharmacy_boundary()


# 함수이름: create_app
# 함수역할:
# - 환경 설정을 적용하고 필요한 로컬 스키마를 확인한다.
# - 복약, 연동 채팅과 근처 약국 API 라우터를 등록한다.
# 반환값: 구성된 FastAPI 애플리케이션
def create_app() -> FastAPI:
    configure_logging()
    if settings.AUTO_CREATE_SCHEMA:
        Base.metadata.create_all(bind=engine)
        if engine.dialect.name == "sqlite":
            ensure_saved_medication_schema(engine)
            ensure_medication_completion_schema(engine)
            ensure_medication_alarm_schema(engine)
            ensure_caregiver_notification_schema(engine)
            ensure_user_setting_schema(engine)
    app = FastAPI(
        title="MedBuddy API",
        version="0.1.0-beta",
        lifespan=application_lifespan,
        docs_url=None if settings.APP_ENV == "production" else "/docs",
        redoc_url=None if settings.APP_ENV == "production" else "/redoc",
        openapi_url=None if settings.APP_ENV == "production" else "/openapi.json",
    )
    rate_limit_store = RequestRateLimitStore(
        redis_url=settings.REDIS_URL,
        require_redis=settings.RATE_LIMIT_REQUIRE_REDIS,
    )
    app.state.request_rate_limit_store = rate_limit_store
    app.state.chat_connection_manager = ChatConnectionManager()
    app.state.readiness_probe_cache = _ReadinessProbeCache(
        _READINESS_CACHE_TTL_SECONDS
    )
    multipart_overhead_bytes = 512 * 1024
    app.add_middleware(
        RequestBodyLimitMiddleware,
        limits={
            "/api/v1/medication/pill-identification/candidates": (
                2 * MAX_PILL_IMAGE_BYTES + multipart_overhead_bytes
            ),
        },
        default_limit=1024 * 1024,
    )
    app.add_middleware(
        ApiContractMiddleware,
        contract_version=settings.API_CONTRACT_VERSION,
    )
    app.add_middleware(
        RequestRateLimitMiddleware,
        store=rate_limit_store,
        rules=DEFAULT_RATE_LIMIT_RULES,
        enabled=settings.RATE_LIMIT_ENABLED,
    )
    if settings.APP_ENV == "production":
        app.add_middleware(
            TrustedHostMiddleware,
            allowed_hosts=settings.trusted_host_list,
        )
    app.include_router(
        medication_router,
        prefix="/api/v1/medication",
        tags=["Medication"],
    )
    app.include_router(
        pharmacy_router,
        prefix="/api/v1/pharmacy",
        tags=["Pharmacy"],
    )
    app.include_router(
        chat_router,
        prefix="/api/v1/chat",
        tags=["Chat"],
    )
    app.include_router(auth_router)

    @app.get("/health", include_in_schema=False)
    def health_check() -> dict[str, str]:
        return {
            "status": "ok",
            "api_contract": settings.API_CONTRACT_VERSION,
        }

    @app.get("/ready", include_in_schema=False)
    async def readiness_check() -> dict[str, str]:
        is_ready = await app.state.readiness_probe_cache.request_readiness(
            _verify_runtime_dependencies
        )
        if not is_ready:
            raise HTTPException(
                status_code=503,
                detail="MedBuddy dependencies are not ready.",
            )
        return {
            "status": "ready",
            "api_contract": settings.API_CONTRACT_VERSION,
        }

    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=True)
