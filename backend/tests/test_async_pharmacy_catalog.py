# File Name: test_async_pharmacy_catalog.py
# Role: Verify pharmacy catalogue workers do not block requests or retain ORM sessions.

import asyncio
from datetime import date, datetime
from pathlib import Path
from threading import Event, get_ident
from unittest.mock import AsyncMock, patch
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from controls.check_nearby_pharmacy_control import CheckNearbyPharmacy, PharmacySearchMode
from entities.pharmacy_catalog_entity import (
    PharmacyCatalogRecord, PharmacyHolidayFetchRecord, PharmacyHolidayScheduleRecord,
    PharmacyHolidaySchedule,
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

    # Function Name: stalled_count
    # Description: Holds the worker until the async test confirms it can still run.
    # Parameters: repository: Real repository instance supplied by the adapter.
    # Returns: Catalogue row count after release.
    def stalled_count(repository: PharmacyCatalogRepository) -> int:
        worker_threads.append(get_ident())
        started.set()
        release.wait(timeout=2)
        return repository.db.query(PharmacyCatalogRecord).count()

    adapter = AsyncPharmacyCatalog(sessionmaker(bind=engine))
    with patch.object(PharmacyCatalogRepository, "count", stalled_count):
        task = asyncio.create_task(adapter.count())
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
