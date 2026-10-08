# File Name: test_korean_holiday_cache.py
# Role: Regression coverage for calendar worker isolation and session lifetime.

import asyncio
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from threading import Event, get_ident
from unittest.mock import AsyncMock, MagicMock

import pytest
from sqlalchemy import create_engine
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session, sessionmaker

from boundaries.korean_holiday_api_boundary import PersistentKoreanHolidayLookup
from boundaries.pharmacy_api_boundary import PharmacyApiUnavailableError
from repositories.korean_holiday_cache import SessionScopedKoreanHolidayCache
from repositories.pharmacy_catalog_repository import (
    KoreanHolidayMonthFetchRecord,
    KoreanHolidayRecord,
)


# Function Name: test_blocked_calendar_cache_does_not_block_event_loop
# Description: A stalled synchronous read must leave the async caller responsive.
# Parameters: None.
# Returns: None; fails if cache work executes on the event-loop thread.
@pytest.mark.anyio
async def test_blocked_calendar_cache_does_not_block_event_loop() -> None:
    started, release = Event(), Event()
    loop_thread = get_ident()
    worker_threads: list[int] = []

    # Function Name: read
    # Description: Holds the worker until the async test releases it, with a safety timeout.
    # Parameters: args, kwargs: Unused cache protocol arguments.
    # Returns: A verified empty month.
    def read(*args: object, **kwargs: object) -> frozenset[date]:
        worker_threads.append(get_ident())
        started.set()
        release.wait(timeout=2)
        return frozenset()

    cache = MagicMock()
    cache.get_cached_korean_holidays.side_effect = read
    lookup = PersistentKoreanHolidayLookup(cache=cache, upstream=AsyncMock())
    task = asyncio.create_task(lookup.isHoliday(date(2026, 9, 29)))
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


# Function Name: test_calendar_sessions_close_before_upstream_and_paired_lookup_reuses_month
# Description: Real database sessions are released before network I/O; paired reads share a snapshot.
# Parameters: tmp_path: Isolated file database directory.
# Returns: None.
@pytest.mark.anyio
async def test_calendar_sessions_close_before_upstream_and_paired_lookup_reuses_month(
    tmp_path: Path,
) -> None:
    engine = create_engine(f"sqlite:///{tmp_path / 'calendar.db'}")
    KoreanHolidayRecord.__table__.create(engine)
    KoreanHolidayMonthFetchRecord.__table__.create(engine)
    cache = SessionScopedKoreanHolidayCache(sessionmaker(bind=engine))

    # Function Name: fetch_month
    # Description: Ensures no calendar connection remains checked out during provider I/O.
    # Parameters: year, month: Requested calendar month.
    # Returns: Verified holiday dates.
    async def fetch_month(year: int, month: int) -> frozenset[date]:
        assert engine.pool.checkedout() == 0
        await asyncio.sleep(0)
        return frozenset({date(year, month, 29)})

    upstream = AsyncMock()
    upstream.fetchMonth.side_effect = fetch_month
    lookup = PersistentKoreanHolidayLookup(cache=cache, upstream=upstream)
    try:
        assert await asyncio.gather(
            lookup.isHoliday(date(2026, 9, 29)),
            lookup.isHoliday(date(2026, 9, 28)),
        ) == [True, False]
        upstream.fetchMonth.assert_awaited_once_with(2026, 9)
        assert engine.pool.checkedout() == 0
    finally:
        engine.dispose()


# Function Name: test_calendar_database_failure_is_sanitized_and_session_closed
# Description: Both cache operations close their session and suppress database details on failure.
# Parameters: operation: Read or write cache path.
# Returns: None.
@pytest.mark.parametrize("operation", ["read", "write"])
def test_calendar_database_failure_is_sanitized_and_session_closed(operation: str) -> None:
    db = MagicMock()
    db.__enter__.return_value = db
    db.query.side_effect = OperationalError("private SQL", {}, Exception("private host"))
    db.get.side_effect = OperationalError("private SQL", {}, Exception("private host"))
    cache = SessionScopedKoreanHolidayCache(lambda: db)
    with pytest.raises(PharmacyApiUnavailableError, match="^Calendar cache is unavailable.$"):
        if operation == "read":
            cache.get_cached_korean_holidays(2026, 9, max_age=timedelta(days=30))
        else:
            cache.replace_korean_holidays(2026, 9, frozenset())
    db.__exit__.assert_called_once()


# Function Name: test_month_snapshot_is_served_only_within_the_accepted_age
# Description: A stored month is returned while its fetch marker is younger than the caller's
#   limit and reported as missing once it is older, so the 30-day fresh read refreshes it while
#   the 730-day outage fallback can still use it. A verified empty month is not a missing one.
# Parameters: tmp_path: Isolated file database directory.
# Returns: None.
def test_month_snapshot_is_served_only_within_the_accepted_age(tmp_path: Path) -> None:
    engine = create_engine(f"sqlite:///{tmp_path / 'calendar-age.db'}")
    KoreanHolidayRecord.__table__.create(engine)
    KoreanHolidayMonthFetchRecord.__table__.create(engine)
    cache = SessionScopedKoreanHolidayCache(sessionmaker(bind=engine))
    try:
        cache.replace_korean_holidays(2026, 10, frozenset({date(2026, 10, 9)}))
        cache.replace_korean_holidays(2026, 11, frozenset())
        fetched_at = datetime.now(UTC).replace(tzinfo=None) - timedelta(days=31)
        with Session(engine) as db:
            db.get(KoreanHolidayMonthFetchRecord, "2026-10").fetched_at = fetched_at
            db.commit()

        assert cache.get_cached_korean_holidays(
            2026, 10, max_age=timedelta(days=30),
        ) is None
        assert cache.get_cached_korean_holidays(
            2026, 10, max_age=timedelta(days=730),
        ) == frozenset({date(2026, 10, 9)})
        assert cache.get_cached_korean_holidays(
            2026, 11, max_age=timedelta(days=30),
        ) == frozenset()
        assert cache.get_cached_korean_holidays(
            2026, 12, max_age=timedelta(days=730),
        ) is None
    finally:
        engine.dispose()
