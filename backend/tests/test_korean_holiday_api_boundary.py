# File Name: test_korean_holiday_api_boundary.py
# Role: Regression coverage for monthly Korean-holiday caching, service errors, and bounded
#   stale persistence.
"""Tests for legal-holiday lookup and fail-closed behavior."""

import os
import sys
from datetime import date, timedelta
from pathlib import Path

import httpx
import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from boundaries.korean_holiday_api_boundary import (  # noqa: E402
    KoreanHolidayAPI,
    PersistentKoreanHolidayLookup,
)
from boundaries.pharmacy_api_boundary import (  # noqa: E402
    PharmacyApiUnavailableError,
)


# Function Name: test_holiday_month_is_parsed_and_cached
# Description:
# - Caches one parsed holiday month so holiday and ordinary dates require only one HTTP request.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_holiday_month_is_parsed_and_cached() -> None:
    request_count = 0

    # Function Name: respond
    # Description:
    # - Counts the calendar request and serves a month containing the fixed August 17
    #   holiday.
    # Parameters:
    # - _ (httpx.Request): Interface argument ignored by this fixed-response double. Unused
    #   by this double.
    # Returns:
    # - httpx.Response: Synthetic HTTP 200 response containing the scenario XML.
    def respond(_: httpx.Request) -> httpx.Response:
        nonlocal request_count
        request_count += 1
        return httpx.Response(
            200,
            content=(
                b"<response><header><resultCode>00</resultCode></header>"
                b"<body><items><item><locdate>20260817</locdate></item>"
                b"</items></body></response>"
            ),
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(respond))
    boundary = KoreanHolidayAPI(client=client)
    try:
        assert await boundary.isHoliday(date(2026, 8, 17)) is True
        assert await boundary.isHoliday(date(2026, 8, 18)) is False
    finally:
        await client.aclose()

    assert request_count == 1


# Function Name: test_holiday_lookup_fails_closed_on_service_error
# Description:
# - Raises an availability error on an unsuccessful holiday service response rather than
#   silently declaring a normal day.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_holiday_lookup_fails_closed_on_service_error() -> None:
    client = httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _: httpx.Response(503))
    )
    boundary = KoreanHolidayAPI(client=client)
    try:
        with pytest.raises(PharmacyApiUnavailableError):
            await boundary.isHoliday(date(2026, 8, 17))
    finally:
        await client.aclose()


# Class Name: _StaleHolidayCache
# Role: Persistent holiday-cache double with data available only under the bounded stale-age
#   policy.
# Responsibilities:
# - Returns the fixed holiday set only when a 730-day stale allowance is requested; otherwise
#   reports a cache miss.
# - Accepts a holiday cache replacement without persisting it in the stale-cache double.
class _StaleHolidayCache:
    # Function Name: get_cached_korean_holidays
    # Description:
    # - Returns the fixed holiday set only when a 730-day stale allowance is requested;
    #   otherwise reports a cache miss.
    # Parameters:
    # - year (int): Calendar year requested or cached.
    # - month (int): Calendar month requested or cached.
    # - max_age (timedelta): Maximum allowed age of the cached calendar or roster.
    # Returns:
    # - frozenset[date] | None: Holiday set under a 730-day stale allowance, otherwise None.
    def get_cached_korean_holidays(
        self,
        year: int,
        month: int,
        *,
        max_age: timedelta,
    ) -> frozenset[date] | None:
        del year, month
        if max_age >= timedelta(days=730):
            return frozenset({date(2026, 8, 17)})
        return None

    # Function Name: replace_korean_holidays
    # Description:
    # - Accepts a holiday cache replacement without persisting it in the stale-cache double.
    # Parameters:
    # - year (int): Calendar year requested or cached.
    # - month (int): Calendar month requested or cached.
    # - holidays (frozenset[date]): Holiday dates offered for persistent caching.
    # Returns:
    # - None.
    def replace_korean_holidays(
        self,
        year: int,
        month: int,
        holidays: frozenset[date],
    ) -> None:
        del year, month, holidays


# Function Name: test_persistent_lookup_uses_bounded_stale_cache_during_outage
# Description:
# - Uses the bounded stale persistent holiday set to answer accurately during an upstream
#   outage.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_persistent_lookup_uses_bounded_stale_cache_during_outage() -> None:
    client = httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _: httpx.Response(503))
    )
    upstream = KoreanHolidayAPI(client=client)
    lookup = PersistentKoreanHolidayLookup(
        cache=_StaleHolidayCache(),
        upstream=upstream,
    )
    try:
        assert await lookup.isHoliday(date(2026, 8, 17)) is True
    finally:
        await client.aclose()
