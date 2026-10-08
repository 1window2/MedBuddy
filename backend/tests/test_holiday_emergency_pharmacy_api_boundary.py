# File Name: test_holiday_emergency_pharmacy_api_boundary.py
# Role: Regression coverage for date-specific emergency pharmacy roster parsing and request
#   filters.
"""Tests for the exact-date NEMC holiday pharmacy roster boundary."""

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

from boundaries import holiday_emergency_pharmacy_api_boundary  # noqa: E402
from boundaries.holiday_emergency_pharmacy_api_boundary import (  # noqa: E402
    HolidayEmergencyPharmacyAPI,
)
from boundaries.pharmacy_api_boundary import PharmacyApiUnavailableError  # noqa: E402
from core.config import settings  # noqa: E402

_EMPTY_ROSTER_XML = (
    b"<response><header><resultCode>00</resultCode></header>"
    b"<body><totalCount>0</totalCount><items></items></body></response>"
)


# Function Name: test_exact_date_schedule_is_parsed_and_non_pharmacies_are_ignored
# Description:
# - Parses only the pharmacy entry for the exact date and retains its 09:00-17:30 opening range.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_exact_date_schedule_is_parsed_and_non_pharmacies_are_ignored() -> None:
    # Function Name: respond
    # Description:
    # - Checks the exact-date and 20,000-row query without a weekday filter, then serves a
    #   roster containing pharmacy and non-pharmacy entries.
    # Parameters:
    # - request (httpx.Request): Intercepted HTTP request used to select or validate the
    #   mock response.
    # Returns:
    # - httpx.Response: Synthetic HTTP 200 response containing the scenario XML.
    def respond(request: httpx.Request) -> httpx.Response:
        # The upstream service currently returns no rows for QD=H even though
        # the unfiltered payload contains dutyDiv=H pharmacy records. Fetch the
        # date roster and enforce the pharmacy classification locally.
        assert "QD" not in request.url.params
        assert request.url.params["QT"] == "20260925"
        assert request.url.params["numOfRows"] == "20000"
        return httpx.Response(
            200,
            content=b"""
            <response><header><resultCode>00</resultCode></header><body>
              <totalCount>2</totalCount><items><item>
                <hpid>C1234</hpid>
                <dutyDiv>H</dutyDiv>
                <dutyDay1>2026-09-25</dutyDay1>
                <dutyDaytime1>09:00~17:30</dutyDaytime1>
                <dutyDayEtc>Call before visiting</dutyDayEtc>
              </item><item>
                <hpid>A5678</hpid>
                <dutyDiv>A</dutyDiv>
                <dutyDay1>2026-09-25</dutyDay1>
                <dutyDaytime1>09:00~18:00</dutyDaytime1>
              </item></items>
            </body></response>
            """,
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(respond))
    boundary = HolidayEmergencyPharmacyAPI(client=client)
    try:
        result = await boundary.fetchSchedules(date(2026, 9, 25))
    finally:
        await client.aclose()

    assert len(result) == 1
    assert result[0].pharmacy_id == "C1234"
    assert result[0].start_time == "0900"
    assert result[0].end_time == "1730"


# Function Name: test_invalid_time_range_is_not_claimed_as_date_specific
# Description:
# - Discards an invalid time range instead of claiming it as a date-specific pharmacy schedule.
# Parameters:
# - None.
# Returns:
# - None.
def test_invalid_time_range_is_not_claimed_as_date_specific() -> None:
    import xml.etree.ElementTree as ElementTree

    item = ElementTree.fromstring(
        "<item><hpid>C1234</hpid><dutyDay1>2026-09-25</dutyDay1>"
        "<dutyDaytime1>contact pharmacy</dutyDaytime1></item>"
    )

    assert (
        HolidayEmergencyPharmacyAPI._parse_item(item, date(2026, 9, 25))
        is None
    )


# Class Name: _ManualClock
# Role: Stands in for the `time` module inside the roster boundary so a test can move past the
#   cool-down.
# Attributes:
# - now (float): Current monotonic reading returned to the boundary.
class _ManualClock:
    # Function Name: __init__
    # Description:
    # - Starts the clock at an arbitrary positive reading.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.now = 1000.0

    # Function Name: monotonic
    # Description:
    # - Returns the current reading, standing in for time.monotonic.
    # Parameters:
    # - None.
    # Returns:
    # - float: Current manual reading in seconds.
    def monotonic(self) -> float:
        return self.now


# Function Name: test_roster_failure_is_not_requested_again_during_the_cooldown
# Description:
# - After one provider failure for a date, further lookups of that date fail immediately without
#   a provider request until PUBLIC_API_FAILURE_CACHE_SECONDS have passed; another date is still
#   requested. Once the cool-down is over the roster is fetched, and that success removes the mark.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Replaces the boundary's monotonic clock.
# Returns:
# - None.
@pytest.mark.anyio
async def test_roster_failure_is_not_requested_again_during_the_cooldown(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    clock = _ManualClock()
    # Only the boundary module's view of `time` is replaced; the event loop keeps the real clock.
    monkeypatch.setattr(holiday_emergency_pharmacy_api_boundary, "time", clock)
    requested_dates: list[str] = []
    provider_available = False

    # Function Name: respond
    # Description:
    # - Records the requested roster date and answers 503 until the provider is switched on.
    # Parameters:
    # - request (httpx.Request): Intercepted roster request.
    # Returns:
    # - httpx.Response: HTTP 503, or an empty verified roster once available.
    def respond(request: httpx.Request) -> httpx.Response:
        requested_dates.append(request.url.params["QT"])
        if not provider_available:
            return httpx.Response(503)
        return httpx.Response(200, content=_EMPTY_ROSTER_XML)

    holiday = date(2026, 9, 25)
    client = httpx.AsyncClient(transport=httpx.MockTransport(respond))
    boundary = HolidayEmergencyPharmacyAPI(client=client)
    try:
        with pytest.raises(PharmacyApiUnavailableError):
            await boundary.fetchSchedules(holiday)
        assert requested_dates == ["20260925"]

        for _ in range(5):
            with pytest.raises(PharmacyApiUnavailableError):
                await boundary.fetchSchedules(holiday)
        assert requested_dates == ["20260925"]

        # The mark belongs to one date; the day before is still looked up.
        with pytest.raises(PharmacyApiUnavailableError):
            await boundary.fetchSchedules(holiday - timedelta(days=1))
        assert requested_dates == ["20260925", "20260924"]

        provider_available = True
        clock.now += settings.PUBLIC_API_FAILURE_CACHE_SECONDS - 1
        with pytest.raises(PharmacyApiUnavailableError):
            await boundary.fetchSchedules(holiday)
        assert requested_dates == ["20260925", "20260924"]

        clock.now += 2
        assert await boundary.fetchSchedules(holiday) == []
        assert requested_dates == ["20260925", "20260924", "20260925"]
        assert holiday not in boundary._failed_until
    finally:
        await client.aclose()


# Function Name: test_roster_tables_keep_only_the_newest_dates
# Description:
# - The per-date cache and the failure table are bounded: after more dates than the limit were
#   requested, only the most recent ones remain and the oldest is fetched again when asked.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_roster_tables_keep_only_the_newest_dates() -> None:
    limit = holiday_emergency_pharmacy_api_boundary._MAX_TRACKED_DATES
    request_count = 0
    provider_available = True

    # Function Name: respond
    # Description:
    # - Counts the request and serves an empty verified roster, or 503 when switched off.
    # Parameters:
    # - _ (httpx.Request): Interface argument ignored by this fixed-response double.
    # Returns:
    # - httpx.Response: Empty roster or HTTP 503.
    def respond(_: httpx.Request) -> httpx.Response:
        nonlocal request_count
        request_count += 1
        if not provider_available:
            return httpx.Response(503)
        return httpx.Response(200, content=_EMPTY_ROSTER_XML)

    first = date(2026, 9, 1)
    dates = [first + timedelta(days=offset) for offset in range(limit + 2)]
    client = httpx.AsyncClient(transport=httpx.MockTransport(respond))
    boundary = HolidayEmergencyPharmacyAPI(client=client)
    try:
        for value in dates:
            await boundary.fetchSchedules(value)
        assert list(boundary._cache) == dates[2:]

        await boundary.fetchSchedules(dates[-1])
        assert request_count == limit + 2
        await boundary.fetchSchedules(dates[0])
        assert request_count == limit + 3

        provider_available = False
        failing = [date(2027, 1, 1) + timedelta(days=offset) for offset in range(limit + 2)]
        for value in failing:
            with pytest.raises(PharmacyApiUnavailableError):
                await boundary.fetchSchedules(value)
        assert list(boundary._failed_until) == failing[2:]
    finally:
        await client.aclose()
