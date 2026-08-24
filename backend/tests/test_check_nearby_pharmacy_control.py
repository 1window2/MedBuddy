# 파일명: test_check_nearby_pharmacy_control.py
# 역할: 근처 약국의 거리, 영업 상태, 필터와 입력 검증을 확인한다.

import os
import sys
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from boundaries.pharmacy_api_boundary import (  # noqa: E402
    PharmacyApiResponseError,
    PharmacyApiUnavailableError,
)
from controls.check_nearby_pharmacy_control import (  # noqa: E402
    CheckNearbyPharmacy,
    PharmacySearchMode,
)
from entities.nearby_pharmacy_entity import PharmacyLocationRecord  # noqa: E402
from entities.pharmacy_catalog_entity import (  # noqa: E402
    PharmacyCatalogEntry,
    PharmacyHolidaySchedule,
)


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


class _FakePharmacyRepository:
    def __init__(self, entries: list[PharmacyCatalogEntry]) -> None:
        self.entries = entries

    def count(self) -> int:
        return len(self.entries)

    def search_nearby_candidates(self, **_: object) -> list[PharmacyCatalogEntry]:
        return self.entries

    def latest_updated_at(self) -> datetime:
        return datetime(2026, 8, 24)

    def get_cached_holiday_schedules(
        self,
        value: date,
        *,
        max_age: timedelta,
    ) -> dict[str, PharmacyHolidaySchedule] | None:
        del value, max_age
        return None

    def replace_holiday_schedules(
        self,
        value: date,
        schedules: list[PharmacyHolidaySchedule],
    ) -> None:
        del value, schedules


class _FakeHolidayBoundary:
    def __init__(self, is_holiday: bool) -> None:
        self.is_holiday = is_holiday

    async def isHoliday(self, _: object) -> bool:
        return self.is_holiday


class _FakeHolidayEmergencyBoundary:
    def __init__(self, schedules: list[PharmacyHolidaySchedule]) -> None:
        self.schedules = schedules

    async def fetchSchedules(self, _: date) -> list[PharmacyHolidaySchedule]:
        return self.schedules


class _MalformedHolidayEmergencyBoundary:
    async def fetchSchedules(self, _: date) -> list[PharmacyHolidaySchedule]:
        raise PharmacyApiResponseError("Malformed holiday roster response.")


class _StaleHolidayRepository(_FakePharmacyRepository):
    def get_cached_holiday_schedules(
        self,
        value: date,
        *,
        max_age: timedelta,
    ) -> dict[str, PharmacyHolidaySchedule] | None:
        if max_age < timedelta(days=45):
            return None
        return {
            "holiday-roster": PharmacyHolidaySchedule(
                pharmacy_id="holiday-roster",
                schedule_date=value,
                start_time="1800",
                end_time="2300",
            )
        }


class _UnavailableHolidayBoundary:
    async def isHoliday(self, _: object) -> bool:
        raise PharmacyApiUnavailableError("Holiday service unavailable.")


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


@pytest.mark.anyio
async def test_empty_catalog_falls_back_to_location_api() -> None:
    """동기화 전의 빈 로컬 DB에서도 공공 위치 API로 약국을 조회한다."""
    boundary = _FakePharmacyBoundary(
        [_record("fallback", distance_km=0.2, start_time="0900", end_time="1800")]
    )
    control = CheckNearbyPharmacy(
        boundary,
        pharmacy_repository=_FakePharmacyRepository([]),
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
        limit=5,
    )

    assert [item.pharmacy_id for item in result] == ["fallback"]
    assert boundary.requested_limit == 10


@pytest.mark.anyio
async def test_holiday_lookup_failure_does_not_block_pharmacy_results() -> None:
    """공휴일 부가 조회가 실패해도 로컬 약국 결과는 반환한다."""
    entry = PharmacyCatalogEntry(
        pharmacy_id="available",
        name="Available pharmacy",
        address="Seoul",
        telephone="",
        latitude=37.5665,
        longitude=126.9780,
        weekly_hours={"6": ("0900", "1800")},
    )
    control = CheckNearbyPharmacy(
        pharmacy_repository=_FakePharmacyRepository([entry]),
        holiday_boundary=_UnavailableHolidayBoundary(),
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
        limit=5,
    )

    assert [item.pharmacy_id for item in result] == ["available"]


@pytest.mark.anyio
async def test_catalog_search_filters_after_all_nearby_candidates() -> None:
    entries = [
        PharmacyCatalogEntry(
            pharmacy_id=f"closed-{index}",
            name=f"Closed {index}",
            address="Seoul",
            telephone="",
            latitude=37.5665,
            longitude=126.9780,
            weekly_hours={"6": ("0900", "1000")},
        )
        for index in range(31)
    ]
    entries.append(
        PharmacyCatalogEntry(
            pharmacy_id="open-after-thirty",
            name="Open after thirty",
            address="Seoul",
            telephone="02-123-4567",
            latitude=37.5666,
            longitude=126.9781,
            weekly_hours={"6": ("0000", "2400"), "8": ("2200", "0100")},
        )
    )
    control = CheckNearbyPharmacy(
        pharmacy_repository=_FakePharmacyRepository(entries),
        holiday_boundary=_FakeHolidayBoundary(False),
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
        limit=30,
    )

    assert [item.pharmacy_id for item in result] == ["open-after-thirty"]
    assert result[0].has_weekend_or_holiday_hours is True
    assert result[0].is_24_hours is True


@pytest.mark.anyio
async def test_public_holiday_uses_eighth_schedule() -> None:
    entry = PharmacyCatalogEntry(
        pharmacy_id="holiday",
        name="Holiday Pharmacy",
        address="Seoul",
        telephone="",
        latitude=37.5665,
        longitude=126.9780,
        weekly_hours={"1": ("0900", "1800"), "8": ("2200", "0100")},
    )
    control = CheckNearbyPharmacy(
        pharmacy_repository=_FakePharmacyRepository([entry]),
        holiday_boundary=_FakeHolidayBoundary(True),
        now_provider=lambda: datetime(
            2026,
            8,
            17,
            23,
            0,
            tzinfo=ZoneInfo("Asia/Seoul"),
        ),
    )

    result = await control.requestNearbyPharmacies(
        latitude=37.5665,
        longitude=126.9780,
        open_only=True,
    )

    assert result[0].is_public_holiday is True
    assert result[0].is_open_late is True
    assert result[0].today_open_time == "22:00"
    assert result[0].today_close_time == "01:00"


@pytest.mark.anyio
async def test_after_midnight_uses_previous_days_overnight_schedule() -> None:
    entries = [
        PharmacyCatalogEntry(
            pharmacy_id="previous-day",
            name="Previous-day overnight pharmacy",
            address="Seoul",
            telephone="",
            latitude=37.5665,
            longitude=126.9780,
            weekly_hours={"1": ("2200", "0100")},
        ),
        PharmacyCatalogEntry(
            pharmacy_id="later-today",
            name="Later today pharmacy",
            address="Seoul",
            telephone="",
            latitude=37.5665,
            longitude=126.9780,
            weekly_hours={"2": ("2200", "0100")},
        ),
    ]
    control = CheckNearbyPharmacy(
        pharmacy_repository=_FakePharmacyRepository(entries),
        holiday_boundary=_FakeHolidayBoundary(False),
        now_provider=lambda: datetime(
            2026,
            8,
            18,
            0,
            30,
            tzinfo=ZoneInfo("Asia/Seoul"),
        ),
    )

    result = await control.requestNearbyPharmacies(
        latitude=37.5665,
        longitude=126.9780,
        open_only=True,
    )

    assert [item.pharmacy_id for item in result] == ["previous-day"]
    assert result[0].minutes_until_close == 30


@pytest.mark.anyio
async def test_late_hours_mode_filters_before_result_limit() -> None:
    entries = [
        PharmacyCatalogEntry(
            pharmacy_id=f"day-{index}",
            name=f"Day {index}",
            address="Seoul",
            telephone="",
            latitude=37.5665,
            longitude=126.9780,
            weekly_hours={"1": ("0900", "1800")},
        )
        for index in range(35)
    ]
    entries.append(
        PharmacyCatalogEntry(
            pharmacy_id="late-after-thirty",
            name="Late after thirty",
            address="Seoul",
            telephone="",
            latitude=37.5666,
            longitude=126.9781,
            weekly_hours={"1": ("0900", "2300")},
        )
    )
    control = CheckNearbyPharmacy(
        pharmacy_repository=_FakePharmacyRepository(entries),
        holiday_boundary=_FakeHolidayBoundary(False),
        now_provider=lambda: datetime(
            2026, 8, 24, 12, 0, tzinfo=ZoneInfo("Asia/Seoul")
        ),
    )

    result = await control.requestNearbyPharmacySearch(
        latitude=37.5665,
        longitude=126.9780,
        search_mode=PharmacySearchMode.LATE_HOURS,
        limit=30,
    )

    assert [item.pharmacy_id for item in result.data] == ["late-after-thirty"]


@pytest.mark.anyio
async def test_holiday_roster_overrides_generic_weekly_schedule() -> None:
    target_date = date(2026, 9, 25)
    entry = PharmacyCatalogEntry(
        pharmacy_id="holiday-roster",
        name="Holiday roster pharmacy",
        address="Seoul",
        telephone="",
        latitude=37.5665,
        longitude=126.9780,
        weekly_hours={"8": ("0900", "1200")},
    )
    control = CheckNearbyPharmacy(
        pharmacy_repository=_FakePharmacyRepository([entry]),
        holiday_boundary=_FakeHolidayBoundary(True),
        holiday_emergency_boundary=_FakeHolidayEmergencyBoundary(
            [
                PharmacyHolidaySchedule(
                    pharmacy_id="holiday-roster",
                    schedule_date=target_date,
                    start_time="1800",
                    end_time="2300",
                )
            ]
        ),
        now_provider=lambda: datetime(
            2026, 9, 25, 20, 0, tzinfo=ZoneInfo("Asia/Seoul")
        ),
    )

    result = await control.requestNearbyPharmacySearch(
        latitude=37.5665,
        longitude=126.9780,
        search_mode=PharmacySearchMode.OPEN_AT_TIME,
    )

    assert result.data[0].today_open_time == "18:00"
    assert result.data[0].today_close_time == "23:00"
    assert result.data[0].schedule_is_date_specific is True
    assert result.data[0].schedule_source == "nemc_holiday_roster"


@pytest.mark.anyio
async def test_malformed_holiday_roster_uses_bounded_stale_cache() -> None:
    entry = PharmacyCatalogEntry(
        pharmacy_id="holiday-roster",
        name="Holiday roster pharmacy",
        address="Seoul",
        telephone="",
        latitude=37.5665,
        longitude=126.9780,
        weekly_hours={"8": ("0900", "1200")},
    )
    control = CheckNearbyPharmacy(
        pharmacy_repository=_StaleHolidayRepository([entry]),
        holiday_boundary=_FakeHolidayBoundary(True),
        holiday_emergency_boundary=_MalformedHolidayEmergencyBoundary(),
        now_provider=lambda: datetime(
            2026, 9, 25, 20, 0, tzinfo=ZoneInfo("Asia/Seoul")
        ),
    )

    result = await control.requestNearbyPharmacySearch(
        latitude=37.5665,
        longitude=126.9780,
        search_mode=PharmacySearchMode.OPEN_AT_TIME,
    )

    assert result.holiday_schedule_status == "stale_fallback"
    assert result.data[0].today_open_time == "18:00"
    assert result.data[0].schedule_is_date_specific is True


@pytest.mark.anyio
async def test_official_designation_respects_operating_weekday() -> None:
    entry = PharmacyCatalogEntry(
        pharmacy_id="official",
        name="Official pharmacy",
        address="Seoul",
        telephone="",
        latitude=37.5665,
        longitude=126.9780,
        weekly_hours={"1": ("0900", "2300")},
        official_designations={
            "public_late_night": {
                "operating_days": [1],
                "source_name": "Seoul Metropolitan Government",
                "source_url": "https://news.seoul.go.kr/welfare/archives/567003",
                "verified_at": "2026-08-19",
            }
        },
    )
    control = CheckNearbyPharmacy(
        pharmacy_repository=_FakePharmacyRepository([entry]),
        holiday_boundary=_FakeHolidayBoundary(False),
        now_provider=lambda: datetime(
            2026, 8, 24, 22, 30, tzinfo=ZoneInfo("Asia/Seoul")
        ),
    )

    result = await control.requestNearbyPharmacySearch(
        latitude=37.5665,
        longitude=126.9780,
        search_mode=PharmacySearchMode.OFFICIAL_LATE_NIGHT,
    )

    assert result.data[0].is_official_late_night is True
    assert result.data[0].designation_source_name == "Seoul Metropolitan Government"


@pytest.mark.anyio
async def test_open_pharmacy_reports_minutes_until_close() -> None:
    """영업 중 약국이 곧 닫는지 화면에서 판단할 남은 분을 반환한다."""
    boundary = _FakePharmacyBoundary(
        [_record("closing-soon", distance_km=0.2, start_time="0900", end_time="1800")]
    )
    control = CheckNearbyPharmacy(
        boundary,
        now_provider=lambda: datetime(
            2026,
            8,
            22,
            17,
            45,
            tzinfo=ZoneInfo("Asia/Seoul"),
        ),
    )

    result = await control.requestNearbyPharmacies(
        latitude=37.5665,
        longitude=126.9780,
        open_only=True,
    )

    assert result[0].minutes_until_close == 15
    assert result[0].next_open_at is None


@pytest.mark.anyio
async def test_closed_pharmacy_reports_next_regular_opening() -> None:
    """문을 닫은 약국은 다음 정규 영업 시작 시각을 반환한다."""
    entry = PharmacyCatalogEntry(
        pharmacy_id="opens-later",
        name="Opens later",
        address="Seoul",
        telephone="",
        latitude=37.5665,
        longitude=126.9780,
        weekly_hours={"6": ("0900", "1800")},
    )
    control = CheckNearbyPharmacy(
        pharmacy_repository=_FakePharmacyRepository([entry]),
        holiday_boundary=_FakeHolidayBoundary(False),
        now_provider=lambda: datetime(
            2026,
            8,
            22,
            8,
            0,
            tzinfo=ZoneInfo("Asia/Seoul"),
        ),
    )

    result = await control.requestNearbyPharmacies(
        latitude=37.5665,
        longitude=126.9780,
        open_only=False,
    )

    assert result[0].is_open_now is False
    assert result[0].next_open_at == "2026-08-22T09:00:00+09:00"


@pytest.mark.anyio
async def test_holiday_next_opening_uses_holiday_schedule() -> None:
    """공휴일 당일에는 평일이 아니라 공휴일 운영 시작 시각을 안내한다."""
    entry = PharmacyCatalogEntry(
        pharmacy_id="holiday-opens-later",
        name="Holiday opens later",
        address="Seoul",
        telephone="",
        latitude=37.5665,
        longitude=126.9780,
        weekly_hours={"1": ("0900", "1800"), "8": ("1000", "1600")},
    )
    control = CheckNearbyPharmacy(
        pharmacy_repository=_FakePharmacyRepository([entry]),
        holiday_boundary=_FakeHolidayBoundary(True),
        now_provider=lambda: datetime(
            2026,
            8,
            17,
            8,
            0,
            tzinfo=ZoneInfo("Asia/Seoul"),
        ),
    )

    result = await control.requestNearbyPharmacies(
        latitude=37.5665,
        longitude=126.9780,
        open_only=False,
    )

    assert result[0].is_open_now is False
    assert result[0].next_open_at == "2026-08-17T10:00:00+09:00"


@pytest.mark.anyio
async def test_aware_catalog_timestamp_is_converted_without_relabeling() -> None:
    """시간대가 있는 갱신 시각은 순간을 바꾸지 않고 서울 시각으로 표시한다."""
    entry = PharmacyCatalogEntry(
        pharmacy_id="timestamped",
        name="Timestamped pharmacy",
        address="Seoul",
        telephone="",
        latitude=37.5665,
        longitude=126.9780,
        weekly_hours={"6": ("0000", "2400")},
        source_updated_at=datetime(2026, 8, 22, 0, 0, tzinfo=ZoneInfo("UTC")),
    )
    control = CheckNearbyPharmacy(
        pharmacy_repository=_FakePharmacyRepository([entry]),
        holiday_boundary=_FakeHolidayBoundary(False),
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
    )

    assert result[0].source_updated_at == "2026-08-22T09:00:00+09:00"
