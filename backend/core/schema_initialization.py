# File Name: schema_initialization.py
# Role: Bootstraps only empty development databases and verifies migration heads and required ORM columns.
"""Bootstrap empty development databases with Alembic; never guess a legacy revision."""

from functools import lru_cache
import logging
from pathlib import Path

from alembic import command
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import inspect
from sqlalchemy.engine import Connection, Engine

from core.database import Base

_migration_logger = logging.getLogger("alembic.runtime.migration")


# Function Name: migration_config
# Description: Resolves Alembic configuration relative to this backend, independent of the working directory.
# Parameters: None.
# Returns: Config for backend/alembic.ini; loading/validation is left to Alembic consumers.
def migration_config() -> Config:
    return Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))


# Function Name: _expected_heads
# Description: Reads and caches the repository migration heads for the process lifetime.
# Parameters: None.
# Returns: frozenset[str] of head revision IDs; invalid migration configuration propagates.
@lru_cache(maxsize=1)
def _expected_heads() -> frozenset[str]:
    """Reads the migration scripts once; they do not change while the process runs."""
    return frozenset(ScriptDirectory.from_config(migration_config()).get_heads())


# Function Name: _current_heads
# Description: Reads applied revisions while temporarily suppressing repetitive Alembic INFO logging, restoring the prior level even on failure.
# Parameters: connection (Connection) is the caller's open database connection.
# Returns: set[str] of current heads, empty for an unstamped database; database errors propagate.
def _current_heads(connection: Connection) -> set[str]:
    """Reads the applied revisions without Alembic's two INFO lines per call.

    The readiness probe verifies the revision every few seconds; at INFO those lines made up
    nearly the whole backend log and buried every other message.
    """
    previous_level = _migration_logger.level
    _migration_logger.setLevel(logging.WARNING)
    try:
        return set(MigrationContext.configure(connection).get_current_heads())
    finally:
        _migration_logger.setLevel(previous_level)


# Function Name: verify_database_revision
# Description: Requires the applied revision set to equal the shipped heads without stamping or modifying the database.
# Parameters: connection (Connection) is the database to inspect.
# Returns: None on agreement; raises RuntimeError with recovery guidance for missing or mismatched revisions.
def verify_database_revision(connection: Connection) -> None:
    expected = set(_expected_heads())
    current = _current_heads(connection)
    if current != expected:
        if not current:
            raise RuntimeError(
                "Database has no Alembic revision. Stop the backend and back up the "
                "database. For an existing database, audit its schema before adopting "
                "a matching baseline; do not blindly stamp head. See README Backend Setup."
            )
        raise RuntimeError(
            f"Database migration revision {sorted(current)} does not match Alembic "
            f"head {sorted(expected)}. Stop the backend, back up the database, and run "
            "python -m alembic upgrade head from backend/."
        )


# Function Name: prepare_database_schema
# Description: Migrates only an empty unstamped database when enabled, then checks exact heads and required ORM tables/columns.
# Parameters: db_engine (Engine) supplies the transaction; auto_create (bool) permits empty-database bootstrap, never repair of existing schemas.
# Returns: None on success; migration/connection errors propagate and RuntimeError rejects revision or column mismatches.
def prepare_database_schema(db_engine: Engine, *, auto_create: bool) -> None:
    """Only empty databases may be initialized automatically; existing ones are read-only."""
    with db_engine.begin() as connection:
        tables = set(inspect(connection).get_table_names()) - {"alembic_version"}
        revisions = MigrationContext.configure(connection).get_current_heads()
        if auto_create and not tables and not revisions:
            config = migration_config()
            config.attributes["connection"] = connection
            # Reuse the configured connection, including in-memory SQLite databases.
            config.attributes["database_url"] = db_engine.url.render_as_string(hide_password=False)
            command.upgrade(config, "head")
        verify_database_revision(connection)
        inspector = inspect(connection)
        missing = []
        for table in Base.metadata.sorted_tables:
            columns = (
                {column["name"] for column in inspector.get_columns(table.name)}
                if inspector.has_table(table.name) else set()
            )
            missing.extend(f"{table.name}.{name}" for name in set(table.columns.keys()) - columns)
        if missing:
            raise RuntimeError(
                "Database schema does not match ORM despite its revision: "
                + ", ".join(sorted(missing))
                + ". Stop the backend and audit migrations; create_all cannot repair existing tables."
            )
