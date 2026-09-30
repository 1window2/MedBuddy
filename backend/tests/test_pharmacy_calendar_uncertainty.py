# File Name: test_pharmacy_calendar_uncertainty.py
# Role: Prevent unverified calendar data from claiming pharmacy opening or closing status.

import asyncio
from datetime import date, datetime
from unittest.mock import AsyncMock
from zoneinfo import ZoneInfo

import pytest

from boundaries.pharmacy_api_boundary import PharmacyApiUnavailableError
from controls.check_nearby_pharmacy_control import CheckNearbyPharmacy, PharmacySearchMode
from core.config import settings
from entities.nearby_pharmacy_entity import PharmacyLocationRecord
from entities.pharmacy_catalog_entity import PharmacyCatalogEntry

TODAY = date(2026, 9, 30)


# Function Name: control_for
# Description: Supply weekday hours that would appear open if a failed calendar became False.
# Parameters: unknown: Dates whose calendar fails; hour: Search hour; live: Use location fallback.
# Returns: Search control with isolated provider doubles.
def control_for(unknown: set[date], *, hour: int = 12, live: bool = False) -> CheckNearbyPharmacy:
    calendar = AsyncMock()

    # Function Name: classify
    # Description: Reproduce a per-date calendar outage while other dates remain verified weekdays.
    # Parameters: value: Date to classify.
    # Returns: False for verified weekdays; raises availability error for unknown dates.
    async def classify(value: date) -> bool:
        if value in unknown:
            raise PharmacyApiUnavailableError("calendar unavailable")
        return False

    calendar.isHoliday.side_effect = classify
    repository = AsyncMock()
    repository.latest_updated_at.return_value = datetime(2026, 9, 30)
    repository.count.return_value = 0 if live else 1
    repository.search_nearby_candidates.return_value = [PharmacyCatalogEntry(
        pharmacy_id="A", name="Pharmacy", address="Seoul", telephone="",
        latitude=37.5665, longitude=126.978,
        weekly_hours={"3": ("0900", "1800"), "2": ("2200", "0200")},
    )]
    boundary = AsyncMock()
    boundary.searchNearby.return_value = [PharmacyLocationRecord(
        "A", "Pharmacy", "Seoul", "", 37.5665, 126.978, 0, "0900", "1800",
    )]
    return CheckNearbyPharmacy(
        pharmacy_repository=repository, pharmacy_boundary=boundary,
        holiday_boundary=calendar,
        now_provider=lambda: datetime(2026, 9, 30, hour, tzinfo=ZoneInfo("Asia/Seoul")),
    )


# Function Name: test_unknown_calendar_preserves_locations_without_claiming_opening
# Description: Unrestricted search remains useful, but weekday times cannot imply verified opening.
# Parameters: live: Catalog or API location path.
# Returns: None.
@pytest.mark.parametrize("live", [False, True])
@pytest.mark.anyio
async def test_unknown_calendar_preserves_locations_without_claiming_opening(live: bool) -> None:
    result = await control_for({TODAY}, live=live).requestNearbyPharmacySearch(
        latitude=37.5665, longitude=126.978, search_mode=PharmacySearchMode.ALL,
    )
    assert result.holiday_schedule_status == "unknown"
    assert len(result.data) == 1
    item = result.data[0]
    assert item.is_open_now is None
    assert item.today_open_time is None and item.today_close_time is None
    assert item.minutes_until_close is None and item.next_open_at is None
    assert item.schedule_source == "unknown"


# Function Name: test_unknown_today_cannot_satisfy_open_or_weekly_hours_filters
# Description: Missing calendar verification must not produce open, late-hours or weekend matches.
# Parameters: mode: Time-dependent query mode.
# Returns: None.
@pytest.mark.parametrize("mode", [
    PharmacySearchMode.OPEN_AT_TIME, PharmacySearchMode.LATE_HOURS,
    PharmacySearchMode.WEEKEND_HOLIDAY,
])
@pytest.mark.anyio
async def test_unknown_today_cannot_satisfy_open_or_weekly_hours_filters(mode: PharmacySearchMode) -> None:
    result = await control_for({TODAY}).requestNearbyPharmacySearch(
        latitude=37.5665, longitude=126.978, search_mode=mode,
    )
    assert result.data == [] and result.holiday_schedule_status == "unknown"


# Function Name: test_calendar_dates_are_verified_independently
# Description: Verified current hours and verified previous overnight hours survive the other day's outage.
# Parameters: unknown: Failed date; hour: Time inside the surviving interval.
# Returns: None.
@pytest.mark.parametrize("unknown,hour", [({date(2026, 9, 29)}, 12), ({TODAY}, 1)])
@pytest.mark.anyio
async def test_calendar_dates_are_verified_independently(unknown: set[date], hour: int) -> None:
    result = await control_for(unknown, hour=hour).requestNearbyPharmacySearch(
        latitude=37.5665, longitude=126.978,
    )
    assert len(result.data) == 1 and result.data[0].is_open_now is True
    assert result.holiday_schedule_status == "unknown"


# Function Name: test_unknown_previous_day_cannot_claim_closed_before_today_opens
# Description: An unknown previous holiday interval could carry overnight; regular hours cannot prove closure.
# Parameters: None. Returns: None.
@pytest.mark.anyio
async def test_unknown_previous_day_cannot_claim_closed_before_today_opens() -> None:
    result = await control_for({date(2026, 9, 29)}, hour=1).requestNearbyPharmacySearch(
        latitude=37.5665, longitude=126.978, search_mode=PharmacySearchMode.ALL,
    )
    assert result.data[0].is_open_now is None
    assert result.data[0].minutes_until_close is None


# Function Name: test_calendar_timeout_keeps_search_responsive
# Description: A hung calendar cannot indefinitely prevent location results from returning.
# Parameters: monkeypatch: Shortens the configured lookup budget.
# Returns: None.
@pytest.mark.anyio
async def test_calendar_timeout_keeps_search_responsive(monkeypatch: pytest.MonkeyPatch) -> None:
    control = control_for(set())

    # Function Name: hang
    # Description: Remain pending until the lookup deadline cancels this provider operation.
    # Parameters: value: Unused calendar date.
    # Returns: Never completes normally.
    async def hang(value: date) -> bool:
        await asyncio.Event().wait()
        return False

    control._holiday_boundary.isHoliday.side_effect = hang
    monkeypatch.setattr(settings, "PHARMACY_API_TIMEOUT_SECONDS", 0.01)
    async with asyncio.timeout(1):
        result = await control.requestNearbyPharmacySearch(
            latitude=37.5665, longitude=126.978, search_mode=PharmacySearchMode.ALL,
        )
    assert len(result.data) == 1 and result.holiday_schedule_status == "unknown"
