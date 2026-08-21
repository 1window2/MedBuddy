# File Name: main.py
# Role: Creates and configures the MedBuddy FastAPI application.

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

from api.router import auth_router, router as medication_router
from api.dependencies import (
    close_medication_detail_cache,
    close_pill_identification_boundaries,
    close_public_drug_boundaries,
    get_app_check_token_verifier,
    get_oidc_token_verifier,
)
from boundaries.firebase_admin_boundary import verify_firebase_admin_credentials
from boundaries.pill_identification_boundary import MAX_PILL_IMAGE_BYTES
from controls.input_prescription_control import MAX_PRESCRIPTION_IMAGE_BYTES
from core.config import settings
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
from entities import device_push_token_entity  # noqa: F401
from entities import patient_caregiver_link_entity  # noqa: F401
from entities import pill_identification_entity  # noqa: F401
from entities import saved_medication_entity  # noqa: F401
from entities import user_setting_entity  # noqa: F401
from entities import user_account_entity  # noqa: F401
from entities.caregiver_notification_entity import ensure_caregiver_notification_schema
from entities.medication_completion_entity import ensure_medication_completion_schema
from entities.medication_alarm_entity import ensure_medication_alarm_schema
from entities.saved_medication_entity import ensure_saved_medication_schema
from entities.user_setting_entity import ensure_user_setting_schema
from services.data_maintenance import PeriodicDataMaintenanceRunner


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


# Class Name: _ReadinessProbeCache
# Role: Bounds repeated public readiness checks against production dependencies.
# Responsibilities:
#   - Coalesce concurrent readiness probes behind one dependency check.
#   - Cache only the generic ready/not-ready result for a short interval.
#   - Avoid retaining exception details or dependency response data.
# Attributes:
#   - ttl_seconds: Number of seconds before the cached result expires.
class _ReadinessProbeCache:
    def __init__(self, ttl_seconds: float) -> None:
        self.ttl_seconds = ttl_seconds
        self._lock = asyncio.Lock()
        self._expires_at = 0.0
        self._is_ready = False

    # Function Name: request_readiness
    # Description:
    # - Returns a short-lived readiness result and performs at most one
    #   dependency check when the cached result has expired.
    # Parameters:
    # - check: Awaitable dependency check that raises on unavailable services.
    # Returns:
    # - True when dependencies are ready; otherwise False.
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

    # Function Name: reset
    # Description:
    # - Invalidates the cached result when an application lifespan starts.
    # Returns:
    # - None.
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


# Function Name: _verify_runtime_dependencies
# Description:
# - Performs the database, Firebase, App Check, and Redis readiness checks.
# Returns:
# - None when every configured dependency is ready.
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


# Function Name: configure_logging
# Description:
# - Configures application logging in the bootstrap layer.
# Returns:
# - None.
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
    app.state.readiness_probe_cache.reset()
    if settings.PERIODIC_MAINTENANCE_ENABLED:
        maintenance_runner = PeriodicDataMaintenanceRunner(SessionLocal)
        maintenance_runner.start()
        app.state.data_maintenance_runner = maintenance_runner
    try:
        yield
    finally:
        if maintenance_runner is not None:
            await maintenance_runner.stop()
        await app.state.request_rate_limit_store.close()
        await close_pill_identification_boundaries()
        await close_medication_detail_cache()
        await close_public_drug_boundaries()


# Function Name: create_app
# Description:
# - Loads environment variables.
# - Creates database tables for currently implemented models.
# - Registers medication API routes.
# Returns:
# - Configured FastAPI application.
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
    app.state.readiness_probe_cache = _ReadinessProbeCache(
        _READINESS_CACHE_TTL_SECONDS
    )
    multipart_overhead_bytes = 512 * 1024
    app.add_middleware(
        RequestBodyLimitMiddleware,
        limits={
            "/api/v1/medication/upload-prescription": (
                MAX_PRESCRIPTION_IMAGE_BYTES + multipart_overhead_bytes
            ),
            "/api/v1/medication/pill-identification/candidates": (
                2 * MAX_PILL_IMAGE_BYTES + multipart_overhead_bytes
            ),
        },
        default_limit=1024 * 1024,
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
