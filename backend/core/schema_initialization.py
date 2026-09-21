"""Bootstrap empty development databases with Alembic; never guess a legacy revision."""

from pathlib import Path

from alembic import command
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import inspect
from sqlalchemy.engine import Connection, Engine

from core.database import Base


def migration_config() -> Config:
    return Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))


def verify_database_revision(connection: Connection) -> None:
    expected = set(ScriptDirectory.from_config(migration_config()).get_heads())
    current = set(MigrationContext.configure(connection).get_current_heads())
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
