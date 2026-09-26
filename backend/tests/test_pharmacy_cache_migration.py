# File Name: test_pharmacy_cache_migration.py
# Role: Rehearses the pharmacy-cache rollout and rollback without touching deployed data.

import os
from collections.abc import Iterator
from datetime import datetime
from pathlib import Path
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import MetaData, Table, create_engine, inspect, select
from sqlalchemy.engine import Connection

from core.schema_initialization import verify_database_revision
from entities.pharmacy_catalog_entity import PharmacySearchCacheRecord

PREVIOUS_REVISION = "f8a2c6d901be"
CACHE_REVISION = "6d4f8a2c9301"
CACHE_INDEX = "ix_pharmacy_search_cache_fetched_at"


# Function Name: migration_database
# Description: Create an isolated SQLite DB or transaction-scoped PostgreSQL schema.
# Parameters: request - selected dialect; tmp_path - disposable SQLite directory.
# Returns: Connection and migration configuration; rolls back PostgreSQL DDL on exit.
@pytest.fixture(params=["sqlite"] + (
    ["postgresql"] if os.getenv("MEDBUDDY_RUN_POSTGRES_INTEGRATION") == "1" else []
))
def migration_database(
    request: pytest.FixtureRequest, tmp_path: Path,
) -> Iterator[tuple[Connection, Config]]:
    url = (
        os.environ["DATABASE_URL"] if request.param == "postgresql"
        else f"sqlite:///{(tmp_path / 'cache-migration.db').as_posix()}"
    )
    engine = create_engine(url)
    try:
        with engine.connect() as connection:
            transaction = connection.begin()
            try:
                if request.param == "postgresql":
                    assert engine.dialect.name == "postgresql"
                    if engine.dialect.server_version_info < (16,):
                        pytest.skip("requires PostgreSQL 16+ to match production/CI")
                    schema = f"migration_test_{uuid4().hex}"
                    connection.exec_driver_sql(f'CREATE SCHEMA "{schema}"')
                    connection.exec_driver_sql(f'SET LOCAL search_path TO "{schema}"')
                config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
                config.attributes.update(connection=connection, database_url=url)
                command.upgrade(config, PREVIOUS_REVISION)
                yield connection, config
            finally:
                transaction.rollback()
    finally:
        engine.dispose()


# Function Name: test_cache_migration_preserves_existing_records_through_rollback
# Description: Preserve catalog, linked chat and dose records while only cache data is disposable.
# Parameters: migration_database - isolated connection and Alembic configuration.
# Returns: None; fails on data loss, missing index, incorrect revision or nonrepeatable upgrade.
def test_cache_migration_preserves_existing_records_through_rollback(
    migration_database: tuple[Connection, Config],
) -> None:
    connection, config = migration_database
    metadata = MetaData()
    metadata.reflect(bind=connection)
    tables = metadata.tables
    now = datetime(2026, 9, 26, 8)
    connection.execute(tables["user_accounts"].insert(), [
        dict(user_hash=user, created_at=now, updated_at=now)
        for user in ("patient", "caregiver")
    ])
    connection.execute(tables["patient_caregiver_links"].insert().values(
        id=1, patient_hash="patient", caregiver_hash="caregiver", linked=True,
        patient_alias="Patient", created_at=now,
    ))
    connection.execute(tables["saved_medications"].insert().values(
        id=1, patient_hash="patient", item_name="Test medicine",
        created_date=now.date(), deduplication_key="preserved-dose",
        schedule_slot_keys='["morning"]', medication_status=True,
    ))
    connection.execute(tables["medication_completions"].insert().values(
        id=1, saved_medication_id=1, patient_hash="patient",
        schedule_date=now.date(), slot_key="morning", completed=True,
        completed_at=now,
    ))
    connection.execute(tables["chat_messages"].insert().values(
        id=1, link_id=1, sender_hash="patient", client_message_id="preserved-chat",
        body="Preserve this pharmacy snapshot", message_kind="pharmacy_share",
        context_payload={"pharmacy_id": "CACHE", "name": "Shared pharmacy"},
        created_at=now,
    ))
    connection.execute(tables["pharmacy_catalog_records"].insert().values(
        pharmacy_id="CATALOG", name="Catalog pharmacy", address="Test address",
        telephone="000", latitude=37.5, longitude=127.0, weekly_hours={},
        official_designations={}, source_updated_at=now,
    ))
    preserved = {
        name: connection.execute(select(table)).mappings().all()
        for name, table in tables.items() if name != "alembic_version"
    }
    with pytest.raises(RuntimeError, match="alembic upgrade head"):
        verify_database_revision(connection)
    for _ in range(2):
        command.upgrade(config, CACHE_REVISION)
        command.upgrade(config, CACHE_REVISION)
        verify_database_revision(connection)
        assert CACHE_INDEX in {
            index["name"] for index in inspect(connection).get_indexes("pharmacy_search_cache")
        }
        cache = Table("pharmacy_search_cache", MetaData(), autoload_with=connection)
        connection.execute(cache.insert().values(
            pharmacy_id="CACHE", name="Shared pharmacy", address="Test address",
            telephone="000", latitude=37.5, longitude=127.0, fetched_at=now,
        ))
        command.downgrade(config, PREVIOUS_REVISION)
        assert not inspect(connection).has_table("pharmacy_search_cache")
        for name, rows in preserved.items():
            assert connection.execute(select(tables[name])).mappings().all() == rows
    command.upgrade(config, "head")
    verify_database_revision(connection)


# Function Name: test_cache_migration_adopts_existing_rows_and_repairs_missing_index
# Description: Adopt locally created cache data, both with and without its expiry index.
# Parameters: migration_database - isolated database; has_index - existing index state.
# Returns: None; fails if migration replaces cache data or misses the required index.
@pytest.mark.parametrize("has_index", [False, True])
def test_cache_migration_adopts_existing_rows_and_repairs_missing_index(
    migration_database: tuple[Connection, Config], has_index: bool,
) -> None:
    connection, config = migration_database
    table = PharmacySearchCacheRecord.__table__
    table.create(connection)
    if not has_index:
        connection.exec_driver_sql(f"DROP INDEX {CACHE_INDEX}")
    connection.execute(table.insert().values(
        pharmacy_id="EXISTING", name="Existing pharmacy", address="Test address",
        telephone="000", latitude=37.5, longitude=127.0,
        fetched_at=datetime(2026, 9, 26),
    ))
    before = connection.execute(select(table)).mappings().all()
    command.upgrade(config, CACHE_REVISION)
    command.upgrade(config, CACHE_REVISION)
    verify_database_revision(connection)
    assert connection.execute(select(table)).mappings().all() == before
    indexes = inspect(connection).get_indexes(table.name)
    assert [index["column_names"] for index in indexes if index["name"] == CACHE_INDEX] == [["fetched_at"]]
