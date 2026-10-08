# File Name: test_async_pharmacy_catalog.py
# Role: Verify pharmacy catalogue workers do not block requests or retain ORM sessions.

import asyncio
from datetime import date, datetime
from pathlib import Path
from threading import Event, get_ident
from unittest.mock import AsyncMock, patch
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, sessionmaker

from controls.check_nearby_pharmacy_control import CheckNearbyPharmacy, PharmacySearchMode
from entities.pharmacy_catalog_entity import (
    PharmacyCatalogEntry, PharmacyCatalogRecord, PharmacyHolidayFetchRecord,
    PharmacyHolidayScheduleRecord, PharmacyHolidaySchedule, PharmacySearchCacheRecord,
)
from repositories.async_pharmacy_catalog import AsyncPharmacyCatalog
from repositories.pharmacy_catalog_repository import PharmacyCatalogRepository


# Function Name: test_catalogue_read_runs_off_event_loop
# Description: A stalled SQL operation leaves the async caller responsive.
# Parameters: tmp_path: Directory for an isolated file-backed database.
# Returns: None; fails when the catalogue runs on the event-loop thread.
@pytest.mark.anyio
async def test_catalogue_read_runs_off_event_loop(tmp_path: Path) -> None:
    engine = create_engine(f"sqlite:///{tmp_path / 'catalog-worker.db'}")
    PharmacyCatalogRecord.__table__.create(engine)
    started, release = Event(), Event()
    loop_thread = get_ident()
    worker_threads: list[int] = []

    # Function Name: stalled_search
    # Description: Holds the worker until the async test confirms it can still run.
    # Parameters: repository: Real repository instance supplied by the adapter;
    #   bounds: Search coordinates and radius, unused.
    # Returns: No candidates, after release.
    def stalled_search(
        repository: PharmacyCatalogRepository, **bounds: float,
    ) -> list[PharmacyCatalogEntry]:
        worker_threads.append(get_ident())
        started.set()
        release.wait(timeout=2)
        assert repository.db.query(PharmacyCatalogRecord).count() == 0
        return []

    adapter = AsyncPharmacyCatalog(sessionmaker(bind=engine))
    with patch.object(PharmacyCatalogRepository, "search_nearby_candidates", stalled_search):
        task = asyncio.create_task(adapter.search_nearby_candidates(
            latitude=37.5665, longitude=126.978, max_distance_km=1.0,
        ))
        try:
            async with asyncio.timeout(3):
                while not started.is_set():
                    await asyncio.sleep(0.001)
            assert len(worker_threads) == 1
            assert worker_threads[0] != loop_thread
            assert not task.done()
        finally:
            release.set()
            await task
            engine.dispose()


# Function Name: test_catalogue_sessions_close_before_holiday_provider
# Description: Every catalogue read and write closes its DB session before provider I/O.
# Parameters: tmp_path: Directory for an isolated file-backed database.
# Returns: None; verifies a holiday roster is persisted with no checked-out connection.
@pytest.mark.anyio
async def test_catalogue_sessions_close_before_holiday_provider(tmp_path: Path) -> None:
    engine = create_engine(f"sqlite:///{tmp_path / 'catalog-lifetime.db'}")
    for table in (
        PharmacyCatalogRecord.__table__,
        PharmacyHolidayFetchRecord.__table__,
        PharmacyHolidayScheduleRecord.__table__,
    ):
        table.create(engine)
    with Session(engine) as db:
        db.add(PharmacyCatalogRecord(
            pharmacy_id="A", name="Pharmacy", address="Seoul", telephone="",
            latitude=37.5665, longitude=126.978,
            weekly_hours={"8": ["0900", "1800"]},
        ))
        db.commit()

    # Function Name: fetch_schedules
    # Description: Checks that no catalogue transaction survives into external I/O.
    # Parameters: value: Requested holiday date.
    # Returns: Verified empty roster.
    async def fetch_schedules(value: date) -> list[PharmacyHolidaySchedule]:
        assert isinstance(value, date)
        assert engine.pool.checkedout() == 0
        await asyncio.sleep(0)
        return []

    calendar = AsyncMock()
    calendar.isHoliday.return_value = True
    emergency = AsyncMock()
    emergency.fetchSchedules.side_effect = fetch_schedules
    control = CheckNearbyPharmacy(
        pharmacy_repository=AsyncPharmacyCatalog(sessionmaker(bind=engine)),
        holiday_boundary=calendar,
        holiday_emergency_boundary=emergency,
        now_provider=lambda: datetime(2026, 9, 30, 12, tzinfo=ZoneInfo("Asia/Seoul")),
    )
    try:
        result = await control.requestNearbyPharmacySearch(
            latitude=37.5665, longitude=126.978, search_mode=PharmacySearchMode.ALL,
        )
        assert [item.pharmacy_id for item in result.data] == ["A"]
        assert emergency.fetchSchedules.await_count == 2
        assert engine.pool.checkedout() == 0
        with Session(engine) as db:
            assert db.query(PharmacyHolidayFetchRecord).count() == 2
    finally:
        engine.dispose()


# Function Name: test_catalogue_search_reads_plain_rows_in_two_statements
# Description: A search asks the catalogue for its newest timestamp and for the candidates in the
#   bounding box, nothing else (no row count), and the plain-row read yields the same entry values
#   as the stored record. A catalogue with rows but none nearby takes the location fallback.
# Parameters: tmp_path: Directory for an isolated file-backed database.
# Returns: None.
@pytest.mark.anyio
async def test_catalogue_search_reads_plain_rows_in_two_statements(tmp_path: Path) -> None:
    engine = create_engine(f"sqlite:///{tmp_path / 'catalog-search.db'}")
    for table in (PharmacyCatalogRecord.__table__, PharmacySearchCacheRecord.__table__):
        table.create(engine)
    updated_at = datetime(2026, 9, 29, 3, 0)
    designation = {"public_late_night": {"operating_days": [3], "verified_at": "2026-09-01"}}
    with Session(engine) as db:
        db.add_all([
            PharmacyCatalogRecord(
                pharmacy_id="near", name="Near", address="Seoul", telephone="02-1",
                latitude=37.5665, longitude=126.978,
                weekly_hours={"3": ["0900", "1800"], "8": ["1000", "1300"], "bad": ["0900"]},
                official_designations=designation, source_updated_at=updated_at,
            ),
            PharmacyCatalogRecord(
                pharmacy_id="busan", name="Busan", address="Busan", telephone="051-1",
                latitude=35.1796, longitude=129.0756, weekly_hours={"3": ["0900", "1800"]},
                source_updated_at=datetime(2026, 9, 1, 3, 0),
            ),
        ])
        db.commit()
    statements: list[str] = []

    # Function Name: record_statement
    # Description: Collects every SQL statement the engine executes during the searches.
    # Parameters: statement: SQL text; the other event arguments are unused.
    # Returns: None.
    @event.listens_for(engine, "before_cursor_execute")
    def record_statement(conn, cursor, statement, parameters, context, executemany) -> None:
        statements.append(" ".join(statement.split()).lower())

    adapter = AsyncPharmacyCatalog(sessionmaker(bind=engine))
    calendar = AsyncMock()
    calendar.isHoliday.return_value = False
    live = AsyncMock()
    live.searchNearby.return_value = []
    control = CheckNearbyPharmacy(
        pharmacy_boundary=live, pharmacy_repository=adapter, holiday_boundary=calendar,
        now_provider=lambda: datetime(2026, 9, 30, 12, tzinfo=ZoneInfo("Asia/Seoul")),
    )
    try:
        candidates = await adapter.search_nearby_candidates(
            latitude=37.5665, longitude=126.978, max_distance_km=5.0,
        )
        assert candidates == [PharmacyCatalogEntry(
            pharmacy_id="near", name="Near", address="Seoul", telephone="02-1",
            latitude=37.5665, longitude=126.978,
            weekly_hours={"3": ("0900", "1800"), "8": ("1000", "1300")},
            official_designations=designation, source_updated_at=updated_at,
        )]

        statements.clear()
        result = await control.requestNearbyPharmacySearch(
            latitude=37.5665, longitude=126.978, search_mode=PharmacySearchMode.ALL,
        )
        assert [item.pharmacy_id for item in result.data] == ["near"]
        assert result.catalog_updated_at == updated_at
        assert len(statements) == 2 and not any("count(" in text for text in statements)
        live.searchNearby.assert_not_awaited()

        # Rows exist, but none within reach of this origin: same fallback as an empty catalogue.
        elsewhere = await control.requestNearbyPharmacySearch(
            latitude=33.4996, longitude=126.5312, search_mode=PharmacySearchMode.ALL,
        )
        assert elsewhere.data == []
        live.searchNearby.assert_awaited_once()
        assert engine.pool.checkedout() == 0
    finally:
        engine.dispose()
