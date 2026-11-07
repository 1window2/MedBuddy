# File Name: conftest.py
# Role: Keeps every backend test run away from the developer database and provides the
#   suite-wide fixtures.
#
# Isolation, applied when pytest loads this file and therefore before any test module imports
# core.config:
# - DATABASE_URL is replaced by a SQLite file in a temporary directory created for this run
#   and removed at the end. The application engine (core.database.engine / SessionLocal, used
#   by main.app, its schema preparation and its lifespan workers) is bound to that file, so
#   backend/medbuddy.db is never opened. A file is used instead of an in-memory database
#   because the readiness tests reach the engine from several threads.
# - PERIODIC_MAINTENANCE_ENABLED=false, so TestClient(main.app) does not start the
#   maintenance runner, whose first pass deletes link codes, caches and old chat.
# - GEMINI_API_KEY and PUBLIC_DATA_API_KEY get the CI placeholder when unset.
# - Exception: with MEDBUDDY_RUN_POSTGRES_INTEGRATION=1 an explicitly configured database is
#   kept, because the PostgreSQL CI job points the suite at its own service container.
# - The backend root and the tests directory are put on sys.path, so new test files need no
#   sys.path.insert and can import the helpers in tests/support.
#
# Fixtures:
# - anyio_backend: runs `@pytest.mark.anyio` tests on asyncio; no per-file copy is needed.
# - fk_engine: in-memory SQLite engine with foreign keys enforced and the ORM schema created.
# - fk_session_factory: session factory on fk_engine, configured like SessionLocal.
# - fk_db: one open session from fk_session_factory, closed after the test.
#
# Helpers for new tests (see the header of each file):
#   from support.db import make_engine, make_session, make_session_factory
#   from support.db import seed_account, seed_medication
#   from support.fakes import FakeGeminiClient, FakeRedis, RecordingPushBoundary

import os
import shutil
import sys
import tempfile
from collections.abc import Iterator
from pathlib import Path

import pytest
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.orm import Session, sessionmaker

_TESTS_ROOT = Path(__file__).resolve().parent
_BACKEND_ROOT = _TESTS_ROOT.parent
_DEVELOPER_DATABASE_PATH = _BACKEND_ROOT / "medbuddy.db"
_POSTGRES_INTEGRATION_FLAG = "MEDBUDDY_RUN_POSTGRES_INTEGRATION"
_PLACEHOLDER_API_KEY = "test-key-for-ci"

# Redis address no test run can reach; see _isolate_test_environment.
_UNREACHABLE_REDIS_URL = "redis://127.0.0.1:1/0"
# Set by _isolate_test_environment when this run owns a temporary database directory.
_run_directory: Path | None = None


# Function Name: _uses_external_database
# Description:
# - Decides whether the caller deliberately pointed the suite at its own database: the
#   PostgreSQL integration flag is on and a URL or structured host is configured.
# Parameters:
# - None.
# Returns:
# - True when the configured database must be kept.
def _uses_external_database() -> bool:
    if os.environ.get(_POSTGRES_INTEGRATION_FLAG) != "1":
        return False
    return any(
        os.environ.get(name, "").strip() for name in ("DATABASE_URL", "DATABASE_HOST")
    )


# 함수이름: _isolate_test_environment
# 함수역할:
# - 백엔드와 테스트 경로 및 격리 환경 변수를 설정하고, 개발자 DB 설정이 이미 로드되었으면 실행을 거부한다.
# 매개변수:
# - 없음.
# 반환값:
# - None; 격리할 수 없으면 pytest.UsageError를 발생시킨다.
def _isolate_test_environment() -> None:
    global _run_directory

    for import_root in (_TESTS_ROOT, _BACKEND_ROOT):
        if str(import_root) not in sys.path:
            sys.path.insert(0, str(import_root))

    os.environ["PERIODIC_MAINTENANCE_ENABLED"] = "false"
    # A closed local port: the rate-limit store falls back to its in-memory counters at once
    # instead of writing test keys into a developer's running Redis.
    os.environ["REDIS_URL"] = _UNREACHABLE_REDIS_URL
    os.environ["RATE_LIMIT_REDIS_URL"] = _UNREACHABLE_REDIS_URL
    os.environ.setdefault("GEMINI_API_KEY", _PLACEHOLDER_API_KEY)
    os.environ.setdefault("PUBLIC_DATA_API_KEY", _PLACEHOLDER_API_KEY)
    if _uses_external_database():
        return

    loaded_config = sys.modules.get("core.config")
    if loaded_config is not None:
        loaded_database = make_url(loaded_config.settings.DATABASE_URL).database or ""
        if Path(loaded_database).resolve() == _DEVELOPER_DATABASE_PATH:
            raise pytest.UsageError(
                "core.config was imported before tests/conftest.py and is bound to the "
                "developer database backend/medbuddy.db; run pytest in a fresh process."
            )

    _run_directory = Path(tempfile.mkdtemp(prefix="medbuddy-tests-"))
    os.environ["DATABASE_URL"] = (
        f"sqlite:///{(_run_directory / 'medbuddy-test.db').as_posix()}"
    )


_isolate_test_environment()


# 함수이름: _block_external_redis
# 함수역할:
# - 모든 Redis 비동기 연결을 차단하고 주입된 대체 객체는 유지하도록 자동 적용한다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.fixture(autouse=True)
def _block_external_redis(monkeypatch: pytest.MonkeyPatch) -> None:
    from redis.asyncio.connection import AbstractConnection
    from redis.exceptions import ConnectionError as RedisConnectionError

    # 직접 생성한 클라이언트도 실제 Redis에 닿지 않으며, 주입한 대체 객체는 유지한다.
    # 함수이름: reject_connection
    # 함수역할:
    # - 실제 Redis 연결 대신 RedisConnectionError를 발생시킨다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 반환하지 않음; RedisConnectionError 발생.
    async def reject_connection(self: object) -> None:
        raise RedisConnectionError("Redis network connections are disabled in backend tests.")

    monkeypatch.setattr(AbstractConnection, "connect", reject_connection)


# 함수이름: _block_external_http
# 함수역할:
# - 실제 HTTP 전송만 차단하여 ASGI·MockTransport 기반 테스트는 계속 허용한다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.fixture(autouse=True)
def _block_external_http(monkeypatch: pytest.MonkeyPatch) -> None:
    import httpx
    import requests
    import urllib.request

    # 인메모리 ASGI·MockTransport는 유지하고 실제 HTTP 전송만 차단한다.
    # 함수이름: reject_request
    # 함수역할:
    # - 동기 HTTP 전송 시도에 AssertionError를 발생시켜 외부 요청을 탐지한다.
    # 매개변수:
    # - args: tuple[object, ...]; 차단할 전송 함수의 위치 인수.
    # - kwargs: dict[str, object]; 차단할 전송 함수의 키워드 인수.
    # 반환값:
    # - 반환하지 않음; AssertionError 발생.
    def reject_request(*args: object, **kwargs: object) -> None:
        raise AssertionError("HTTP network connections are disabled in backend tests.")

    # 함수이름: reject_async_request
    # 함수역할:
    # - 비동기 HTTP 전송에서도 동기 차단 함수와 같은 AssertionError를 발생시킨다.
    # 매개변수:
    # - args: tuple[object, ...]; 차단할 비동기 전송의 위치 인수.
    # - kwargs: dict[str, object]; 차단할 비동기 전송의 키워드 인수.
    # 반환값:
    # - 반환하지 않음; AssertionError 발생.
    async def reject_async_request(*args: object, **kwargs: object) -> None:
        reject_request()

    monkeypatch.setattr(httpx.HTTPTransport, "handle_request", reject_request)
    monkeypatch.setattr(httpx.AsyncHTTPTransport, "handle_async_request", reject_async_request)
    monkeypatch.setattr(requests.adapters.HTTPAdapter, "send", reject_request)
    monkeypatch.setattr(urllib.request.OpenerDirector, "open", reject_request)


# Function Name: pytest_sessionfinish
# Description:
# - Releases the application engine's connections, if the run imported it, and removes the
#   temporary database directory of this run.
# Parameters:
# - session (pytest.Session): Finished test session; unused.
# - exitstatus (int): Session exit status; unused.
# Returns:
# - None.
def pytest_sessionfinish(session: pytest.Session, exitstatus: int) -> None:
    if _run_directory is None:
        return
    database_module = sys.modules.get("core.database")
    if database_module is not None:
        database_module.engine.dispose()
    shutil.rmtree(_run_directory, ignore_errors=True)


# Function Name: anyio_backend
# Description:
# - Selects asyncio for every `@pytest.mark.anyio` test. Session scope lets fixtures of any
#   scope depend on it; a file-level fixture of the same name still takes precedence.
# Parameters:
# - None.
# Returns:
# - The anyio backend name "asyncio".
@pytest.fixture(scope="session")
def anyio_backend() -> str:
    return "asyncio"


# Function Name: fk_engine
# Description:
# - Provides a fresh in-memory SQLite engine with foreign keys enforced and the full ORM
#   schema, and disposes it after the test. For a file-backed engine call
#   support.db.make_engine(tmp_path) directly.
# Parameters:
# - None.
# Returns:
# - Iterator yielding the Engine.
@pytest.fixture
def fk_engine() -> Iterator[Engine]:
    from support.db import make_engine

    engine = make_engine()
    try:
        yield engine
    finally:
        engine.dispose()


# Function Name: fk_session_factory
# Description:
# - Provides a session factory on fk_engine with the options of SessionLocal, for controls and
#   workers that open their own sessions.
# Parameters:
# - fk_engine (Engine): Foreign-key-enforcing test engine.
# Returns:
# - sessionmaker bound to fk_engine.
@pytest.fixture
def fk_session_factory(fk_engine: Engine) -> sessionmaker[Session]:
    from support.db import make_session_factory

    return make_session_factory(fk_engine)


# Function Name: fk_db
# Description:
# - Provides one open session on fk_engine and closes it after the test.
# Parameters:
# - fk_session_factory (sessionmaker[Session]): Factory bound to the test engine.
# Returns:
# - Iterator yielding the Session.
@pytest.fixture
def fk_db(fk_session_factory: sessionmaker[Session]) -> Iterator[Session]:
    db = fk_session_factory()
    try:
        yield db
    finally:
        db.close()
