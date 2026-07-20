import asyncio
import os
import sys
import threading
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
    boundary._last_refresh_failure_at -= 16
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
async def test_catalog_boundary_bounds_concurrent_failed_refresh_waiters(
    db: Session,
) -> None:
    class _SlowUnavailableCatalogAPI:
        minimum_catalog_rows = 1

        def __init__(self) -> None:
            self.refresh_attempts = 0

        async def requestCatalog(self) -> list[PillCatalogEntry]:
            self.refresh_attempts += 1
            await asyncio.sleep(1)
            return []

    catalog_api = _SlowUnavailableCatalogAPI()
    boundary = MFDSPillCatalogBoundary(
        catalog_api=catalog_api,  # type: ignore[arg-type]
        # Long enough for SQLite cache inspection even on a loaded CI runner,
        # but shorter than the simulated upstream request.
        refresh_timeout_seconds=0.5,
        session_factory=sessionmaker(bind=db.get_bind()),
    )

    results = await asyncio.gather(
        boundary.getCatalog(),
        boundary.getCatalog(),
        return_exceptions=True,
    )

    assert all(isinstance(result, PillCatalogUnavailableError) for result in results)
    assert catalog_api.refresh_attempts == 1


@pytest.mark.anyio
async def test_catalog_boundary_serves_stale_cache_on_refresh_timeout(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    stale_catalog = [_entry("1", "stale")]

    class _SlowCatalogAPI:
        minimum_catalog_rows = 1

        async def requestCatalog(self) -> list[PillCatalogEntry]:
            await asyncio.sleep(1)
            return [_entry("2", "remote")]

    boundary = MFDSPillCatalogBoundary(
        catalog_api=_SlowCatalogAPI(),  # type: ignore[arg-type]
        refresh_timeout_seconds=0.05,
    )
    monkeypatch.setattr(
        boundary,
        "_load_persisted_catalog",
        lambda: (False, stale_catalog),
    )

    catalog = await boundary.getCatalog()

    assert catalog == tuple(stale_catalog)
    assert boundary._catalog_is_stale is True


@pytest.mark.anyio
async def test_catalog_boundary_cancellation_does_not_trigger_refresh_backoff(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    refresh_started = asyncio.Event()

    class _WaitingCatalogAPI:
        minimum_catalog_rows = 1

        async def requestCatalog(self) -> list[PillCatalogEntry]:
            refresh_started.set()
            await asyncio.Event().wait()
            return []

    boundary = MFDSPillCatalogBoundary(
        catalog_api=_WaitingCatalogAPI(),  # type: ignore[arg-type]
    )
    monkeypatch.setattr(
        boundary,
        "_load_persisted_catalog",
        lambda: (False, []),
    )
    request = asyncio.create_task(boundary.getCatalog())
    await refresh_started.wait()

    request.cancel()
    with pytest.raises(asyncio.CancelledError):
        await request

    assert boundary._last_refresh_failure_at == 0.0


@pytest.mark.anyio
async def test_catalog_boundary_retains_cache_io_capacity_after_timeout(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    worker_started = threading.Event()
    release_worker = threading.Event()
    load_attempts = 0

    class _UnusedCatalogAPI:
        minimum_catalog_rows = 1

        async def requestCatalog(self) -> list[PillCatalogEntry]:
            raise AssertionError("catalog refresh must wait for cache inspection")

    boundary = MFDSPillCatalogBoundary(
        catalog_api=_UnusedCatalogAPI(),  # type: ignore[arg-type]
        refresh_timeout_seconds=0.05,
    )

    def slow_load() -> tuple[bool, list[PillCatalogEntry]]:
        nonlocal load_attempts
        load_attempts += 1
        worker_started.set()
        release_worker.wait(timeout=2)
        return True, [_entry("recovered", "recovered")]

    monkeypatch.setattr(boundary, "_load_persisted_catalog", slow_load)
    try:
        with pytest.raises(PillCatalogUnavailableError):
            await boundary.getCatalog()
        assert worker_started.is_set()

        with pytest.raises(PillCatalogUnavailableError):
            await boundary.getCatalog()

        assert load_attempts == 1
    finally:
        release_worker.set()
        await asyncio.sleep(0.05)

    recovered = await boundary.getCatalog()

    assert [entry.item_seq for entry in recovered] == ["recovered"]
    assert load_attempts == 2


@pytest.mark.anyio
async def test_catalog_boundary_backs_off_after_failed_refresh(db: Session) -> None:
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
        session_factory=sessionmaker(bind=db.get_bind()),
    )

    with pytest.raises(PillCatalogUnavailableError):
        await boundary.getCatalog()
    with pytest.raises(PillCatalogUnavailableError):
        await boundary.getCatalog()

    assert catalog_api.refresh_attempts == 1


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
