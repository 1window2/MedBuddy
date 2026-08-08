"""PostgreSQL integration checks for shared catalog publication."""

import os

import pytest
from sqlalchemy import select

from core.database import SessionLocal, engine
from entities.pill_identification_entity import (
    PillCatalogEntry,
    PillIdentificationReference,
)
from repositories.pill_identification_catalog_repository import (
    PillIdentificationCatalogRepository,
)
from scripts.sync_drug_catalog import (
    CatalogSyncAlreadyRunningError,
    _exclusive_catalog_sync_lock,
)


pytestmark = pytest.mark.skipif(
    os.getenv("MEDBUDDY_RUN_POSTGRES_INTEGRATION") != "1"
    or engine.dialect.name != "postgresql",
    reason="requires the opt-in PostgreSQL integration database",
)


def test_postgresql_advisory_lock_excludes_overlapping_catalog_jobs() -> None:
    first_session = SessionLocal()
    second_session = SessionLocal()
    try:
        with _exclusive_catalog_sync_lock(first_session):
            with pytest.raises(CatalogSyncAlreadyRunningError):
                with _exclusive_catalog_sync_lock(second_session):
                    pytest.fail("an overlapping catalog writer acquired the lock")

        with _exclusive_catalog_sync_lock(second_session):
            pass
    finally:
        second_session.close()
        first_session.close()


def test_postgresql_catalog_replacement_becomes_visible_only_after_commit() -> None:
    writer = SessionLocal()
    reader = SessionLocal()
    try:
        writer.query(PillIdentificationReference).delete(synchronize_session=False)
        writer.add(
            PillIdentificationReference(
                item_seq="OLD",
                item_name="old tablet",
            )
        )
        writer.commit()

        PillIdentificationCatalogRepository(writer).replace_all(
            [PillCatalogEntry(item_seq="NEW", item_name="new tablet")],
            commit=False,
        )
        before_commit = reader.execute(
            select(PillIdentificationReference.item_seq)
        ).scalars().all()
        assert before_commit == ["OLD"]

        writer.commit()
        after_commit = reader.execute(
            select(PillIdentificationReference.item_seq)
        ).scalars().all()
        assert after_commit == ["NEW"]
    finally:
        writer.rollback()
        reader.rollback()
        writer.close()
        reader.close()
