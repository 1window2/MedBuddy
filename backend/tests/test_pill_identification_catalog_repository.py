import os
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from boundaries.pill_identification_boundary import (
    MFDSPillCatalogBoundary,
    PillCatalogUnavailableError,
)
from core.database import Base
from entities.pill_identification_entity import (
    PillCatalogEntry,
    PillIdentificationReference,
)
from repositories.pill_identification_catalog_repository import (
    PillIdentificationCatalogRepository,
)


def _entry(item_seq: str, item_name: str) -> PillCatalogEntry:
    return PillCatalogEntry(
        item_seq=item_seq,
        item_name=item_name,
        shape="원형",
        color_primary="노랑",
        print_front="YH",
        print_back="LT",
    )


@pytest.fixture
def db() -> Session:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    PillIdentificationReference.__table__.create(bind=engine)
    session = sessionmaker(bind=engine)()
    try:
        yield session
    finally:
        session.close()


def test_repository_replaces_and_reads_complete_catalog(db: Session) -> None:
    repository = PillIdentificationCatalogRepository(db)

    repository.replace_all([_entry("1", "첫번째정"), _entry("2", "두번째정")])

    assert [entry.item_seq for entry in repository.list_all()] == ["1", "2"]
    assert repository.is_fresh(
        minimum_rows=2,
        max_age=timedelta(minutes=1),
    )


def test_reference_entity_is_isolated_from_core_medication_metadata() -> None:
    assert PillIdentificationReference.metadata is not Base.metadata


def test_repository_rolls_back_failed_replacement(
    db: Session,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = PillIdentificationCatalogRepository(db)
    repository.replace_all([_entry("1", "기존정")])

    def fail_insert(*_args: object, **_kwargs: object) -> None:
        raise RuntimeError("insert failed")

    monkeypatch.setattr(db, "bulk_insert_mappings", fail_insert)

    with pytest.raises(RuntimeError, match="insert failed"):
        repository.replace_all([_entry("2", "새정")])

    assert [entry.item_seq for entry in repository.list_all()] == ["1"]


@pytest.mark.anyio
async def test_catalog_boundary_uses_stale_cache_during_outage(db: Session) -> None:
    PillIdentificationCatalogRepository(db).replace_all([_entry("1", "기존정")])

    db.query(PillIdentificationReference).update(
        {
            PillIdentificationReference.updated_at: datetime.now(UTC).replace(
                tzinfo=None
            )
            - timedelta(days=2)
        }
    )
    db.commit()

    class _UnavailableCatalogAPI:
        minimum_catalog_rows = 1

        def __init__(self) -> None:
            self.refresh_attempts = 0

        async def requestCatalog(self) -> list[PillCatalogEntry]:
            self.refresh_attempts += 1
            raise ConnectionError("upstream unavailable")

    catalog_api = _UnavailableCatalogAPI()
    boundary = MFDSPillCatalogBoundary(
        catalog_api=catalog_api,  # type: ignore[arg-type]
        cache_ttl=timedelta(hours=1),
        session_factory=sessionmaker(bind=db.get_bind()),
    )

    catalog = await boundary.getCatalog()

    assert [entry.item_seq for entry in catalog] == ["1"]
    assert catalog_api.refresh_attempts == 1

    assert await boundary.getCatalog() == catalog
    assert catalog_api.refresh_attempts == 1

    boundary._catalog_loaded_at -= 301
    assert await boundary.getCatalog() == catalog
    assert catalog_api.refresh_attempts == 2


@pytest.mark.anyio
async def test_catalog_boundary_rejects_incomplete_stale_cache(db: Session) -> None:
    PillIdentificationCatalogRepository(db).replace_all([_entry("1", "partial")])

    class _UnavailableCatalogAPI:
        minimum_catalog_rows = 2

        async def requestCatalog(self) -> list[PillCatalogEntry]:
            raise ConnectionError("upstream unavailable")

    boundary = MFDSPillCatalogBoundary(
        catalog_api=_UnavailableCatalogAPI(),  # type: ignore[arg-type]
        session_factory=sessionmaker(bind=db.get_bind()),
    )

    with pytest.raises(PillCatalogUnavailableError):
        await boundary.getCatalog()


@pytest.mark.anyio
async def test_catalog_boundary_serves_remote_data_when_cache_io_fails(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _AvailableCatalogAPI:
        minimum_catalog_rows = 1

        async def requestCatalog(self) -> list[PillCatalogEntry]:
            return [_entry("1", "remote")]

    boundary = MFDSPillCatalogBoundary(
        catalog_api=_AvailableCatalogAPI(),  # type: ignore[arg-type]
    )

    def fail_cache(*_args: object, **_kwargs: object) -> None:
        raise RuntimeError("cache unavailable")

    monkeypatch.setattr(boundary, "_load_persisted_catalog", fail_cache)
    monkeypatch.setattr(boundary, "_replace_persisted_catalog", fail_cache)

    catalog = await boundary.getCatalog()

    assert [entry.item_seq for entry in catalog] == ["1"]


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
