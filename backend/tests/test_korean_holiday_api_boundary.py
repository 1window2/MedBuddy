# File Name: test_korean_holiday_api_boundary.py
# Role: Regression coverage for monthly Korean-holiday caching, service errors, and bounded
#   stale persistence.
"""Tests for legal-holiday lookup and fail-closed behavior."""

import asyncio
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


@pytest.mark.anyio
async def test_gateway_error_never_becomes_cached_nonholiday() -> None:
    """HTTP 200 인증 오류를 공휴일 없음으로 캐시하지 않고 재시도도 제한한다."""
    requests = []

    def respond(request):
        requests.append(request)
        return httpx.Response(200, content=b"<OpenAPI_ServiceResponse><cmmMsgHeader><returnReasonCode>30</returnReasonCode></cmmMsgHeader></OpenAPI_ServiceResponse>")

    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        boundary = KoreanHolidayAPI(client=client)
        for day in (17, 18):
            with pytest.raises(PharmacyApiUnavailableError):
                await boundary.isHoliday(date(2026, 8, day))
        assert not boundary._cache and len(requests) == 1


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


_AUGUST_HOLIDAY_XML = (
    b"<response><header><resultCode>00</resultCode></header>"
    b"<body><items><item><locdate>20260817</locdate></item>"
    b"</items></body></response>"
)


# Function Name: test_slow_provider_fills_the_cache_after_the_caller_timed_out
# Description:
# - A provider that answers correctly but slower than the caller's budget must still populate
#   the month: the first caller times out, the fill keeps running, and the next lookup is served
#   from the cache without a second provider request.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_slow_provider_fills_the_cache_after_the_caller_timed_out() -> None:
    request_count = 0

    # Function Name: respond
    # Description:
    # - Counts the calendar request and answers correctly after 0.2 seconds, longer than the
    #   first caller waits.
    # Parameters:
    # - _ (httpx.Request): Interface argument ignored by this fixed-response double.
    # Returns:
    # - httpx.Response: Synthetic HTTP 200 response containing the August 17 holiday.
    async def respond(_: httpx.Request) -> httpx.Response:
        nonlocal request_count
        request_count += 1
        await asyncio.sleep(0.2)
        return httpx.Response(200, content=_AUGUST_HOLIDAY_XML)

    client = httpx.AsyncClient(transport=httpx.MockTransport(respond))
    boundary = KoreanHolidayAPI(client=client)
    try:
        with pytest.raises(TimeoutError):
            async with asyncio.timeout(0.05):
                await boundary.isHoliday(date(2026, 8, 17))
        assert (2026, 8) not in boundary._failures

        await asyncio.sleep(0.3)
        assert await boundary.isHoliday(date(2026, 8, 17)) is True
        assert await boundary.isHoliday(date(2026, 8, 18)) is False
    finally:
        await boundary.close()
        await client.aclose()

    assert request_count == 1
    assert not boundary._inflight


# Function Name: test_concurrent_callers_share_one_fill_and_a_failed_fill_starts_the_cooldown
# Description:
# - Callers of the same month wait on one provider request. When that request fails after every
#   caller has given up, the failure cool-down is still recorded, so the next lookup is refused
#   without another provider request.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_concurrent_callers_share_one_fill_and_a_failed_fill_starts_the_cooldown() -> None:
    request_count = 0

    # Function Name: respond
    # Description:
    # - Counts the calendar request and fails after 0.1 seconds.
    # Parameters:
    # - _ (httpx.Request): Interface argument ignored by this fixed-response double.
    # Returns:
    # - httpx.Response: Synthetic HTTP 503 response.
    async def respond(_: httpx.Request) -> httpx.Response:
        nonlocal request_count
        request_count += 1
        await asyncio.sleep(0.1)
        return httpx.Response(503)

    # Function Name: impatient_lookup
    # Description:
    # - Looks one day up and gives up after 0.02 seconds, like a control with a short budget.
    # Parameters:
    # - day (int): Day of August 2026 to classify.
    # Returns:
    # - None; the timeout is expected.
    async def impatient_lookup(day: int) -> None:
        with pytest.raises(TimeoutError):
            async with asyncio.timeout(0.02):
                await boundary.isHoliday(date(2026, 8, day))

    client = httpx.AsyncClient(transport=httpx.MockTransport(respond))
    boundary = KoreanHolidayAPI(client=client)
    try:
        await asyncio.gather(impatient_lookup(17), impatient_lookup(18))
        assert request_count == 1 and (2026, 8) in boundary._inflight

        await asyncio.sleep(0.2)
        assert not boundary._inflight and not boundary._cache
        with pytest.raises(PharmacyApiUnavailableError):
            await boundary.isHoliday(date(2026, 8, 17))
    finally:
        await boundary.close()
        await client.aclose()

    assert request_count == 1


# Function Name: test_close_cancels_a_running_fill
# Description:
# - Shutdown must not leave a provider request running: close() cancels the in-flight fill and
#   nothing is cached or marked as failed for that month.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_close_cancels_a_running_fill() -> None:
    started = asyncio.Event()

    # Function Name: respond
    # Description:
    # - Signals that the request started and then never answers.
    # Parameters:
    # - _ (httpx.Request): Interface argument ignored by this fixed-response double.
    # Returns:
    # - Never completes normally.
    async def respond(_: httpx.Request) -> httpx.Response:
        started.set()
        await asyncio.Event().wait()
        return httpx.Response(200, content=_AUGUST_HOLIDAY_XML)

    client = httpx.AsyncClient(transport=httpx.MockTransport(respond))
    boundary = KoreanHolidayAPI(client=client)
    lookup = asyncio.create_task(boundary.isHoliday(date(2026, 8, 17)))
    try:
        async with asyncio.timeout(1):
            await started.wait()
            fill = boundary._inflight[(2026, 8)]
            await boundary.close()
        assert fill.cancelled()
        with pytest.raises(asyncio.CancelledError):
            await lookup
        assert not boundary._inflight
        assert not boundary._cache and not boundary._failures
    finally:
        lookup.cancel()
        await client.aclose()
