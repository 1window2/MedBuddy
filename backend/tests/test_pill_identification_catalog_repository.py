# File Name: test_pill_identification_catalog_repository.py
# Role: Regression coverage for persistent pill catalogs, transaction ownership, refresh
#   serialization, and outage fallback.
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


# Function Name: _entry
# Description:
# - Builds a yellow round-pill catalog entry with selected identity and fixed two-sided
#   imprints.
# Parameters:
# - item_seq (str): Authoritative product code identifying the medication.
# - item_name (str): Product name in the authoritative or saved medication record.
# Returns:
# - PillCatalogEntry: Synthetic authoritative catalog record with the requested identity and
#   matching fields.
def _entry(item_seq: str, item_name: str) -> PillCatalogEntry:
    return PillCatalogEntry(
        item_seq=item_seq,
        item_name=item_name,
        shape="원형",
        color_primary="노랑",
        print_front="YH",
        print_back="LT",
    )


# Function Name: db
# Description:
# - Yields a shared-connection in-memory pill-reference session and closes that session after
#   each test.
# Parameters:
# - None.
# Returns:
# - Yields the pill-reference Session and closes it during fixture cleanup.
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


# Function Name: test_repository_replaces_and_reads_complete_catalog
# Description:
# - Replaces the complete catalog, reads codes in order, and reports freshness only when the
#   minimum row count is met.
# Parameters:
# - db (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
def test_repository_replaces_and_reads_complete_catalog(db: Session) -> None:
    repository = PillIdentificationCatalogRepository(db)

    repository.replace_all([_entry("1", "첫번째정"), _entry("2", "두번째정")])

    assert [entry.item_seq for entry in repository.list_all()] == ["1", "2"]
    assert repository.list_item_sequences() == {"1", "2"}
    assert repository.is_fresh(
        minimum_rows=2,
        max_age=timedelta(minutes=1),
    )


# Function Name: test_repository_requires_every_catalog_row_to_be_fresh
# Description:
# - Marks a catalog stale when any required row is older than the freshness allowance.
# Parameters:
# - db (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
def test_repository_requires_every_catalog_row_to_be_fresh(db: Session) -> None:
    repository = PillIdentificationCatalogRepository(db)
    repository.replace_all([_entry("1", "old"), _entry("2", "new")])
    stale_timestamp = datetime.now(UTC).replace(tzinfo=None) - timedelta(days=2)
    db.query(PillIdentificationReference).filter(
        PillIdentificationReference.item_seq == "1"
    ).update({PillIdentificationReference.updated_at: stale_timestamp})
    db.commit()

    assert not repository.is_fresh(
        minimum_rows=2,
        max_age=timedelta(hours=1),
    )


# Function Name: test_reference_entity_is_isolated_from_core_medication_metadata
# Description:
# - Requires the pill reference entity to participate in the application's shared SQLAlchemy
#   metadata.
# Parameters:
# - None.
# Returns:
# - None.
def test_reference_entity_is_isolated_from_core_medication_metadata() -> None:
    assert PillIdentificationReference.metadata is Base.metadata


# Function Name: test_repository_rolls_back_failed_replacement
# Description:
# - Rolls back a repository-owned replacement failure and preserves the previous catalog.
# Parameters:
# - db (Session): Isolated SQLAlchemy session supplied by the test fixture.
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
def test_repository_rolls_back_failed_replacement(
    db: Session,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = PillIdentificationCatalogRepository(db)
    repository.replace_all([_entry("1", "기존정")])

    # Function Name: fail_insert
    # Description:
    # - Raises an insert failure to exercise repository-owned transaction rollback.
    # Parameters:
    # - *_args (object): Positional interface arguments; ignored by this test double.
    # - **_kwargs (object): Keyword arguments accepted by the substituted service interface.
    # Returns:
    # - No normal result; raises the configured failure described above.
    def fail_insert(*_args: object, **_kwargs: object) -> None:
        raise RuntimeError("insert failed")

    monkeypatch.setattr(db, "bulk_insert_mappings", fail_insert)

    with pytest.raises(RuntimeError, match="insert failed"):
        repository.replace_all([_entry("2", "새정")])

    assert [entry.item_seq for entry in repository.list_all()] == ["1"]


# Function Name: test_repository_leaves_caller_owned_transaction_for_caller_rollback
# Description:
# - Leaves a caller-owned transaction unrolled back after replacement failure so the caller can
#   restore the previous catalog.
# Parameters:
# - db (Session): Isolated SQLAlchemy session supplied by the test fixture.
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
def test_repository_leaves_caller_owned_transaction_for_caller_rollback(
    db: Session,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = PillIdentificationCatalogRepository(db)
    repository.replace_all([_entry("1", "existing")])
    original_rollback = db.rollback
    rollback_calls = 0

    # Function Name: count_rollback
    # Description:
    # - Counts rollback calls and forwards them to the original session rollback
    #   implementation.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def count_rollback() -> None:
        nonlocal rollback_calls
        rollback_calls += 1
        original_rollback()

    # Function Name: fail_insert
    # Description:
    # - Raises an insert failure while the caller owns the surrounding transaction.
    # Parameters:
    # - *_args (object): Positional interface arguments; ignored by this test double.
    # - **_kwargs (object): Keyword arguments accepted by the substituted service interface.
    # Returns:
    # - No normal result; raises the configured failure described above.
    def fail_insert(*_args: object, **_kwargs: object) -> None:
        raise RuntimeError("insert failed")

    monkeypatch.setattr(db, "rollback", count_rollback)
    monkeypatch.setattr(db, "bulk_insert_mappings", fail_insert)

    with pytest.raises(RuntimeError, match="insert failed"):
        repository.replace_all([_entry("2", "replacement")], commit=False)

    assert rollback_calls == 0
    original_rollback()
    assert [entry.item_seq for entry in repository.list_all()] == ["1"]


# Function Name: test_catalog_boundary_uses_stale_cache_during_outage
# Description:
# - Serves a complete stale catalog during an outage, suppresses retries during backoff, and
#   retries after the delay expires.
# Parameters:
# - db (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
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

    # Class Name: _UnavailableCatalogAPI
    # Role: Catalog API double that counts refresh attempts and always fails upstream
    #   access.
    # Responsibilities:
    # - Counts the refresh and raises an upstream connection error.
    # Attributes:
    # - minimum_catalog_rows (int): Minimum catalog size advertised to the refresh
    #   completeness guard.
    # - refresh_attempts (int): Number of remote catalog refreshes actually attempted.
    class _UnavailableCatalogAPI:
        minimum_catalog_rows = 1

        # Function Name: __init__
        # Description:
        # - Starts the failed-refresh attempt counter at zero.
        # Parameters:
        # - None.
        # Returns:
        # - None.
        def __init__(self) -> None:
            self.refresh_attempts = 0

        # Function Name: requestCatalog
        # Description:
        # - Counts the refresh and raises an upstream connection error.
        # Parameters:
        # - None.
        # Returns:
        # - No normal result; raises the configured failure described above.
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


# Function Name: test_catalog_boundary_rejects_incomplete_stale_cache
# Description:
# - Rejects an incomplete stale catalog when the upstream API is also unavailable.
# Parameters:
# - db (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
@pytest.mark.anyio
async def test_catalog_boundary_rejects_incomplete_stale_cache(db: Session) -> None:
    PillIdentificationCatalogRepository(db).replace_all([_entry("1", "partial")])

    # Class Name: _UnavailableCatalogAPI
    # Role: Unavailable catalog API double used to test minimum-row requirements for stale
    #   fallback.
    # Responsibilities:
    # - Raises an upstream connection error so incomplete cached data cannot be
    #   supplemented.
    # Attributes:
    # - minimum_catalog_rows (int): Minimum catalog size advertised to the refresh
    #   completeness guard.
    class _UnavailableCatalogAPI:
        minimum_catalog_rows = 2

        # Function Name: requestCatalog
        # Description:
        # - Raises an upstream connection error so incomplete cached data cannot be
        #   supplemented.
        # Parameters:
        # - None.
        # Returns:
        # - No normal result; raises the configured failure described above.
        async def requestCatalog(self) -> list[PillCatalogEntry]:
            raise ConnectionError("upstream unavailable")

    boundary = MFDSPillCatalogBoundary(
        catalog_api=_UnavailableCatalogAPI(),  # type: ignore[arg-type]
        session_factory=sessionmaker(bind=db.get_bind()),
    )

    with pytest.raises(PillCatalogUnavailableError):
        await boundary.getCatalog()


# Function Name: test_production_catalog_boundary_never_refreshes_inline
# Description:
# - Serves the production shared catalog without attempting an inline remote refresh.
# Parameters:
# - db (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
@pytest.mark.anyio
async def test_production_catalog_boundary_never_refreshes_inline(db: Session) -> None:
    PillIdentificationCatalogRepository(db).replace_all([_entry("1", "shared")])

    # Class Name: _UnexpectedCatalogAPI
    # Role: Catalog API double that fails the test if production code attempts an inline
    #   refresh.
    # Responsibilities:
    # - Raises AssertionError on remote refresh to enforce the production cache-only path.
    # Attributes:
    # - minimum_catalog_rows (int): Minimum catalog size advertised to the refresh
    #   completeness guard.
    class _UnexpectedCatalogAPI:
        minimum_catalog_rows = 1

        # Function Name: requestCatalog
        # Description:
        # - Raises AssertionError on remote refresh to enforce the production cache-only
        #   path.
        # Parameters:
        # - None.
        # Returns:
        # - No normal result; raises the configured failure described above.
        async def requestCatalog(self) -> list[PillCatalogEntry]:
            raise AssertionError("production API must not refresh the shared catalog")

    boundary = MFDSPillCatalogBoundary(
        catalog_api=_UnexpectedCatalogAPI(),  # type: ignore[arg-type]
        cache_ttl=timedelta(seconds=0.001),
        allow_inline_refresh=False,
        session_factory=sessionmaker(bind=db.get_bind()),
    )

    catalog = await boundary.getCatalog()

    assert [entry.item_seq for entry in catalog] == ["1"]


# Function Name: test_catalog_boundary_bounds_concurrent_failed_refresh_waiters
# Description:
# - Bounds concurrent refresh waiters, returns catalog-unavailable errors to all, and starts
#   only one slow refresh.
# Parameters:
# - db (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
@pytest.mark.anyio
async def test_catalog_boundary_bounds_concurrent_failed_refresh_waiters(
    db: Session,
) -> None:
    # Class Name: _SlowUnavailableCatalogAPI
    # Role: Slow catalog API double measuring coalesced refresh attempts under a short
    #   deadline.
    # Responsibilities:
    # - Counts the refresh and waits before returning an empty catalog, allowing the
    #   boundary timeout to fire.
    # Attributes:
    # - minimum_catalog_rows (int): Minimum catalog size advertised to the refresh
    #   completeness guard.
    # - refresh_attempts (int): Number of remote catalog refreshes actually attempted.
    class _SlowUnavailableCatalogAPI:
        minimum_catalog_rows = 1

        # Function Name: __init__
        # Description:
        # - Initializes the slow-refresh attempt counter.
        # Parameters:
        # - None.
        # Returns:
        # - None.
        def __init__(self) -> None:
            self.refresh_attempts = 0

        # Function Name: requestCatalog
        # Description:
        # - Counts the refresh and waits before returning an empty catalog, allowing the
        #   boundary timeout to fire.
        # Parameters:
        # - None.
        # Returns:
        # - list[PillCatalogEntry]: Configured replacement pill entries; empty or
        #   delayed in the corresponding failure scenarios.
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


# Function Name: test_catalog_boundary_serves_stale_cache_on_refresh_timeout
# Description:
# - Serves an existing stale in-memory catalog when a remote refresh times out and marks the
#   result stale.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
@pytest.mark.anyio
async def test_catalog_boundary_serves_stale_cache_on_refresh_timeout(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    stale_catalog = [_entry("1", "stale")]

    # Class Name: _SlowCatalogAPI
    # Role: Catalog API double that returns remote data only after a delay beyond the
    #   boundary deadline.
    # Responsibilities:
    # - Waits before supplying a replacement entry to exercise stale fallback on refresh
    #   timeout.
    # Attributes:
    # - minimum_catalog_rows (int): Minimum catalog size advertised to the refresh
    #   completeness guard.
    class _SlowCatalogAPI:
        minimum_catalog_rows = 1

        # Function Name: requestCatalog
        # Description:
        # - Waits before supplying a replacement entry to exercise stale fallback on
        #   refresh timeout.
        # Parameters:
        # - None.
        # Returns:
        # - list[PillCatalogEntry]: Configured replacement pill entries; empty or
        #   delayed in the corresponding failure scenarios.
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


# Function Name: test_catalog_boundary_cancellation_does_not_trigger_refresh_backoff
# Description:
# - Propagates caller cancellation without recording a refresh failure or activating retry
#   backoff.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
@pytest.mark.anyio
async def test_catalog_boundary_cancellation_does_not_trigger_refresh_backoff(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    refresh_started = asyncio.Event()

    # Class Name: _WaitingCatalogAPI
    # Role: Catalog API double that signals refresh start and waits indefinitely for
    #   cancellation.
    # Responsibilities:
    # - Signals the active refresh, then waits without completing so the caller can cancel
    #   it.
    # Attributes:
    # - minimum_catalog_rows (int): Minimum catalog size advertised to the refresh
    #   completeness guard.
    class _WaitingCatalogAPI:
        minimum_catalog_rows = 1

        # Function Name: requestCatalog
        # Description:
        # - Signals the active refresh, then waits without completing so the caller can
        #   cancel it.
        # Parameters:
        # - None.
        # Returns:
        # - list[PillCatalogEntry]: Configured replacement pill entries; empty or
        #   delayed in the corresponding failure scenarios.
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


# Function Name: test_catalog_boundary_serializes_cache_io_before_remote_refresh
# Description:
# - Serializes slow persistent-cache inspection across concurrent requests and reuses recovered
#   data without remote refresh.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
@pytest.mark.anyio
async def test_catalog_boundary_serializes_cache_io_before_remote_refresh(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    worker_started = threading.Event()
    release_worker = threading.Event()
    load_attempts = 0

    # Class Name: _UnusedCatalogAPI
    # Role: Catalog API double that fails if refresh bypasses an unfinished persistent-cache
    #   read.
    # Responsibilities:
    # - Raises AssertionError if remote refresh starts before cache inspection has resolved.
    # Attributes:
    # - minimum_catalog_rows (int): Minimum catalog size advertised to the refresh
    #   completeness guard.
    class _UnusedCatalogAPI:
        minimum_catalog_rows = 1

        # Function Name: requestCatalog
        # Description:
        # - Raises AssertionError if remote refresh starts before cache inspection has
        #   resolved.
        # Parameters:
        # - None.
        # Returns:
        # - No normal result; raises the configured failure described above.
        async def requestCatalog(self) -> list[PillCatalogEntry]:
            raise AssertionError("catalog refresh must wait for cache inspection")

    boundary = MFDSPillCatalogBoundary(
        catalog_api=_UnusedCatalogAPI(),  # type: ignore[arg-type]
        refresh_timeout_seconds=0.05,
    )

    # Function Name: slow_load
    # Description:
    # - Counts cache loads, signals worker start, and waits for release before returning a
    #   recovered fresh catalog.
    # Parameters:
    # - None.
    # Returns:
    # - tuple[bool, list[PillCatalogEntry]]: (True, entries): a fresh recovered catalog
    #   after the worker is released.
    def slow_load() -> tuple[bool, list[PillCatalogEntry]]:
        nonlocal load_attempts
        load_attempts += 1
        worker_started.set()
        release_worker.wait(timeout=2)
        return True, [_entry("recovered", "recovered")]

    monkeypatch.setattr(boundary, "_load_persisted_catalog", slow_load)
    try:
        first_request = asyncio.create_task(boundary.getCatalog())
        assert await asyncio.to_thread(worker_started.wait, 1)
        second_request = asyncio.create_task(boundary.getCatalog())
        await asyncio.sleep(0.05)
        assert load_attempts == 1
    finally:
        release_worker.set()
    first_result, second_result = await asyncio.gather(
        first_request,
        second_request,
    )

    assert [entry.item_seq for entry in first_result] == ["recovered"]
    assert second_result == first_result
    assert load_attempts == 1


# Function Name: test_catalog_boundary_backs_off_after_failed_refresh
# Description:
# - Suppresses repeated remote refresh attempts after failure while continuing to report catalog
#   unavailability.
# Parameters:
# - db (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
@pytest.mark.anyio
async def test_catalog_boundary_backs_off_after_failed_refresh(db: Session) -> None:
    # Class Name: _UnavailableCatalogAPI
    # Role: Catalog API double counting failures for retry-backoff assertions.
    # Responsibilities:
    # - Counts and fails each actual upstream refresh attempt.
    # Attributes:
    # - minimum_catalog_rows (int): Minimum catalog size advertised to the refresh
    #   completeness guard.
    # - refresh_attempts (int): Number of remote catalog refreshes actually attempted.
    class _UnavailableCatalogAPI:
        minimum_catalog_rows = 1

        # Function Name: __init__
        # Description:
        # - Starts the refresh-failure counter at zero for the backoff test.
        # Parameters:
        # - None.
        # Returns:
        # - None.
        def __init__(self) -> None:
            self.refresh_attempts = 0

        # Function Name: requestCatalog
        # Description:
        # - Counts and fails each actual upstream refresh attempt.
        # Parameters:
        # - None.
        # Returns:
        # - No normal result; raises the configured failure described above.
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


# Function Name: test_catalog_boundary_serves_remote_data_when_cache_io_fails
# Description:
# - Returns available remote catalog data even when persistent-cache I/O fails.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
@pytest.mark.anyio
async def test_catalog_boundary_serves_remote_data_when_cache_io_fails(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Class Name: _AvailableCatalogAPI
    # Role: Available catalog API double supplying a complete remote fallback entry.
    # Responsibilities:
    # - Returns one remote pill reference to keep identification available despite cache
    #   failure.
    # Attributes:
    # - minimum_catalog_rows (int): Minimum catalog size advertised to the refresh
    #   completeness guard.
    class _AvailableCatalogAPI:
        minimum_catalog_rows = 1

        # Function Name: requestCatalog
        # Description:
        # - Returns one remote pill reference to keep identification available despite
        #   cache failure.
        # Parameters:
        # - None.
        # Returns:
        # - list[PillCatalogEntry]: Configured replacement pill entries; empty or
        #   delayed in the corresponding failure scenarios.
        async def requestCatalog(self) -> list[PillCatalogEntry]:
            return [_entry("1", "remote")]

    boundary = MFDSPillCatalogBoundary(
        catalog_api=_AvailableCatalogAPI(),  # type: ignore[arg-type]
    )

    # Function Name: fail_cache
    # Description:
    # - Raises a cache I/O error to exercise the independent remote-data path.
    # Parameters:
    # - *_args (object): Positional interface arguments; ignored by this test double.
    # - **_kwargs (object): Keyword arguments accepted by the substituted service interface.
    # Returns:
    # - No normal result; raises the configured failure described above.
    def fail_cache(*_args: object, **_kwargs: object) -> None:
        raise RuntimeError("cache unavailable")

    monkeypatch.setattr(boundary, "_load_persisted_catalog", fail_cache)
    monkeypatch.setattr(boundary, "_replace_persisted_catalog", fail_cache)

    catalog = await boundary.getCatalog()

    assert [entry.item_seq for entry in catalog] == ["1"]


# Function Name: anyio_backend
# Description:
# - Selects asyncio for repository-backed asynchronous catalog tests.
# Parameters:
# - None.
# Returns:
# - str: 'asyncio', the event loop backend selected for the test.
@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
