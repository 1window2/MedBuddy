# File Name: test_pharmacy_router.py
# Role: Regression coverage for pharmacy search mode and schedule provenance in router
#   responses.
"""Tests for the nearby-pharmacy HTTP response contract."""

import os
import sys
from datetime import UTC, datetime
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from api.pharmacy_router import get_nearby_pharmacies  # noqa: E402
from controls.check_nearby_pharmacy_control import PharmacySearchMode  # noqa: E402
from entities.nearby_pharmacy_entity import (  # noqa: E402
    NearbyPharmacy,
    NearbyPharmacySearchResult,
)


# Class Name: _FakeControl
# Role: Pharmacy control double returning a fresh, officially designated late-night result with
#   date-specific hours.
# Responsibilities:
# - Supplies an official-late-night search result carrying catalog freshness and holiday-roster
#   provenance.
class _FakeControl:
    # Function Name: requestNearbyPharmacySearch
    # Description:
    # - Supplies an official-late-night search result carrying catalog freshness and
    #   holiday-roster provenance.
    # Parameters:
    # - **_ (object): Interface argument ignored by this fixed-response double. Unused by
    #   this double.
    # Returns:
    # - NearbyPharmacySearchResult: Fresh official-late-night result with holiday-roster
    #   provenance.
    async def requestNearbyPharmacySearch(self, **_: object) -> NearbyPharmacySearchResult:
        target = datetime(2026, 8, 24, 22, 0, tzinfo=UTC)
        return NearbyPharmacySearchResult(
            data=[
                NearbyPharmacy(
                    pharmacy_id="C1234",
                    name="MedBuddy Pharmacy",
                    address="Seoul",
                    telephone="02-123-4567",
                    latitude=37.5665,
                    longitude=126.9780,
                    distance_km=0.2,
                    today_open_time="22:00",
                    today_close_time="01:00",
                    is_open_now=True,
                    is_24_hours=False,
                    is_open_late=True,
                    is_official_late_night=True,
                    schedule_date=target.date(),
                    schedule_source="nemc_holiday_roster",
                    schedule_is_date_specific=True,
                )
            ],
            search_mode=PharmacySearchMode.OFFICIAL_LATE_NIGHT.value,
            target_datetime=target,
            catalog_updated_at=target,
            catalog_is_stale=False,
            holiday_schedule_status="fresh",
        )


# Function Name: test_response_exposes_filter_provenance_and_compatibility_flag
# Description:
# - Preserves official-late-night mode, the compatibility open_only flag, fresh holiday status,
#   and date-specific schedule metadata.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_response_exposes_filter_provenance_and_compatibility_flag() -> None:
    response = await get_nearby_pharmacies(
        latitude=37.5665,
        longitude=126.9780,
        search_mode=PharmacySearchMode.OFFICIAL_LATE_NIGHT,
        target_datetime=datetime(2026, 8, 24, 22, 0, tzinfo=UTC),
        open_only=None,
        limit=20,
        max_distance_km=20,
        control=_FakeControl(),
    )

    assert response.search_mode == "official_late_night"
    assert response.open_only is False
    assert response.holiday_schedule_status == "fresh"
    assert response.data[0].schedule_is_date_specific is True
