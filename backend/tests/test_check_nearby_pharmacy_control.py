# 파일명: test_check_nearby_pharmacy_control.py
# 역할: 근처 약국의 거리, 영업 상태, 필터와 입력 검증을 확인한다.

import os
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from controls.check_nearby_pharmacy_control import (  # noqa: E402
    CheckNearbyPharmacy,
)
from entities.nearby_pharmacy_entity import PharmacyLocationRecord  # noqa: E402


class _FakePharmacyBoundary:
    def __init__(self, records: list[PharmacyLocationRecord]) -> None:
        self.records = records
        self.requested_limit = 0

    async def searchNearby(
        self,
        *,
        latitude: float,
        longitude: float,
        limit: int,
    ) -> list[PharmacyLocationRecord]:
        assert latitude == 37.5665
        assert longitude == 126.9780
        self.requested_limit = limit
        return self.records


def _record(
    pharmacy_id: str,
    *,
    distance_km: float | None,
    start_time: str,
    end_time: str,
) -> PharmacyLocationRecord:
    return PharmacyLocationRecord(
        pharmacy_id=pharmacy_id,
        name=f"Pharmacy {pharmacy_id}",
        address="Seoul",
        telephone="02-123-4567",
        latitude=37.5665,
        longitude=126.9780,
        distance_km=distance_km,
        start_time=start_time,
        end_time=end_time,
    )


@pytest.mark.anyio
async def test_open_only_filters_closed_pharmacies_and_formats_hours() -> None:
    boundary = _FakePharmacyBoundary(
        [
            _record("open", distance_km=0.3, start_time="0900", end_time="2400"),
            _record("closed", distance_km=0.1, start_time="0900", end_time="1000"),
        ]
    )
    control = CheckNearbyPharmacy(
        boundary,
        now_provider=lambda: datetime(
            2026,
            8,
            22,
            12,
            0,
            tzinfo=ZoneInfo("Asia/Seoul"),
        ),
    )

    result = await control.requestNearbyPharmacies(
        latitude=37.5665,
        longitude=126.9780,
        open_only=True,
        limit=10,
    )

    assert [item.pharmacy_id for item in result] == ["open"]
    assert result[0].today_open_time == "09:00"
    assert result[0].today_close_time == "24:00"
    assert boundary.requested_limit == 20


@pytest.mark.anyio
async def test_all_results_put_open_pharmacies_before_nearer_closed_ones() -> None:
    boundary = _FakePharmacyBoundary(
        [
            _record("closed", distance_km=0.1, start_time="0900", end_time="1000"),
            _record("open", distance_km=0.8, start_time="0000", end_time="2400"),
        ]
    )
    control = CheckNearbyPharmacy(
        boundary,
        now_provider=lambda: datetime(
            2026,
            8,
            22,
            12,
            0,
            tzinfo=ZoneInfo("Asia/Seoul"),
        ),
    )

    result = await control.requestNearbyPharmacies(
        latitude=37.5665,
        longitude=126.9780,
        open_only=False,
        limit=10,
    )

    assert [item.pharmacy_id for item in result] == ["open", "closed"]
    assert result[0].is_24_hours is True


@pytest.mark.anyio
async def test_missing_api_distance_uses_coordinate_distance() -> None:
    boundary = _FakePharmacyBoundary(
        [_record("same", distance_km=None, start_time="0000", end_time="2400")]
    )
    control = CheckNearbyPharmacy(boundary)

    result = await control.requestNearbyPharmacies(
        latitude=37.5665,
        longitude=126.9780,
        open_only=False,
    )

    assert result[0].distance_km == 0


@pytest.mark.anyio
async def test_invalid_coordinate_is_rejected_before_api_call() -> None:
    boundary = _FakePharmacyBoundary([])
    control = CheckNearbyPharmacy(boundary)

    with pytest.raises(ValueError):
        await control.requestNearbyPharmacies(
            latitude=91,
            longitude=126.9780,
        )

    assert boundary.requested_limit == 0
