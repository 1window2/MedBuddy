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


# Function Name: _isolate_test_environment
# Description:
# - Puts the backend root and the tests directory on sys.path, then sets the environment
#   (including a Redis address that cannot be reached, so no test touches a local Redis)
#   described in the file header before core.config reads it.
# - Refuses to continue when the settings were already loaded with the developer database,
#   because the environment set here could no longer take effect.
# Parameters:
# - None.
# Returns:
# - None; raises pytest.UsageError in the refused case.
def _isolate_test_environment() -> None:
    global _run_directory

    for import_root in (_TESTS_ROOT, _BACKEND_ROOT):
        if str(import_root) not in sys.path:
            sys.path.insert(0, str(import_root))

    os.environ["PERIODIC_MAINTENANCE_ENABLED"] = "false"
    # A closed local port: the rate-limit store falls back to its in-memory counters at once
    # instead of writing test keys into a developer's running Redis.
    os.environ["REDIS_URL"] = _UNREACHABLE_REDIS_URL
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
