# 파일명: test_check_nearby_pharmacy_control.py
# 역할: 주변 약국의 영업시간·공휴일·심야 지정·캐시 대체 및 정렬 조건을 검증한다.

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


# 클래스명: _FakePharmacyBoundary
# 역할: 조회 좌표와 요청 상한을 확인하고 고정 주변 약국 목록을 제공하는 대체 API다.
# 주요 책임:
# - 서울 기준 좌표를 확인하고 요청 상한을 기록한 뒤 준비된 약국 목록을 반환한다.
# 속성:
# - records (list[PharmacyLocationRecord]): API 대체 객체가 제공할 주변 약국 레코드.
# - requested_limit (int): 최근 요청한 주변 약국 결과 상한.
class _FakePharmacyBoundary:
    # 함수이름: __init__
    # 함수역할:
    # - 반환할 약국 목록을 보관하고 아직 요청되지 않은 결과 상한을 0으로 표시한다.
    # 매개변수:
    # - records (list[PharmacyLocationRecord]): 주변 약국 API 응답으로 제공할 레코드 목록.
    # 반환값:
    # - 없음 (None).
    def __init__(self, records: list[PharmacyLocationRecord]) -> None:
        self.records = records
        self.requested_limit = 0

    # 함수이름: searchNearby
    # 함수역할:
    # - 서울 기준 좌표를 확인하고 요청 상한을 기록한 뒤 준비된 약국 목록을 반환한다.
    # 매개변수:
    # - latitude (float): WGS84 도 단위 검색 위도.
    # - longitude (float): WGS84 도 단위 검색 경도.
    # - limit (int): 요청할 약국 후보 수 상한.
    # 반환값:
    # - list[PharmacyLocationRecord]: 설정된 주변 약국 위치 레코드 목록.
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


# Class Name: _FakePharmacyRepository
# Role: Local pharmacy repository double with fixed candidates, catalog age, and holiday-cache
#   misses.
# Responsibilities:
# - Reports the number of configured local pharmacy entries for catalog availability checks.
# - Supplies a fixed catalog-update timestamp for freshness reporting.
# - Accepts holiday-schedule replacement without persisting data in this repository double.
# Attributes:
# - entries (list[PharmacyCatalogEntry]): Catalog references supplied without an external fetch.
class _FakePharmacyRepository:
    # Function Name: __init__
    # Description:
    # - Stores the catalog entries to expose through count and nearby-candidate queries.
    # Parameters:
    # - entries (list[PharmacyCatalogEntry]): Configured catalog records returned by the
    #   double.
    # Returns:
    # - None.
    def __init__(self, entries: list[PharmacyCatalogEntry]) -> None:
        self.entries = entries

    # Function Name: count
    # Description:
    # - Reports the number of configured local pharmacy entries for catalog availability
    #   checks.
    # Parameters:
    # - None.
    # Returns:
    # - int: Number of configured local catalog entries.
    def count(self) -> int:
        return len(self.entries)

    # Function Name: search_nearby_candidates
    # Description:
    # - Returns every configured nearby candidate without applying an artificial result
    #   limit.
    # Parameters:
    # - **_ (object): Interface argument ignored by this fixed-response double. Unused by
    #   this double.
    # Returns:
    # - list[PharmacyCatalogEntry]: All configured local pharmacy candidates.
    def search_nearby_candidates(self, **_: object) -> list[PharmacyCatalogEntry]:
        return self.entries

    # Function Name: latest_updated_at
    # Description:
    # - Supplies a fixed catalog-update timestamp for freshness reporting.
    # Parameters:
    # - None.
    # Returns:
    # - datetime: Fixed catalog timestamp: 2026-08-24 at midnight.
    def latest_updated_at(self) -> datetime:
        return datetime(2026, 8, 24)

    # Function Name: get_cached_holiday_schedules
    # Description:
    # - Simulates a holiday-schedule cache miss regardless of date or permitted age.
    # Parameters:
    # - value (date): Calendar date whose holiday pharmacy roster is requested or replaced.
    # - max_age (timedelta): Maximum allowed age of the cached calendar or roster.
    # Returns:
    # - None.
    def get_cached_holiday_schedules(
        self,
        value: date,
        *,
        max_age: timedelta,
    ) -> dict[str, PharmacyHolidaySchedule] | None:
        del value, max_age
        return None

    # Function Name: replace_holiday_schedules
    # Description:
    # - Accepts holiday-schedule replacement without persisting data in this repository
    #   double.
    # Parameters:
    # - value (date): Calendar date whose holiday pharmacy roster is requested or replaced.
    # - schedules (list[PharmacyHolidaySchedule]): Date-specific pharmacy opening schedules
    #   offered by the boundary.
    # Returns:
    # - None.
    def replace_holiday_schedules(
        self,
        value: date,
        schedules: list[PharmacyHolidaySchedule],
    ) -> None:
        del value, schedules


# Class Name: _FakeHolidayBoundary
# Role: Holiday-service double that supplies a selected holiday classification for any date.
# Responsibilities:
# - Returns the configured holiday status without querying a calendar service.
# Attributes:
# - is_holiday (bool): Fixed holiday classification returned by the calendar double.
class _FakeHolidayBoundary:
    # Function Name: __init__
    # Description:
    # - Stores the holiday classification to return during pharmacy schedule selection.
    # Parameters:
    # - is_holiday (bool): Holiday classification returned for any requested date.
    # Returns:
    # - None.
    def __init__(self, is_holiday: bool) -> None:
        self.is_holiday = is_holiday

    # Function Name: isHoliday
    # Description:
    # - Returns the configured holiday status without querying a calendar service.
    # Parameters:
    # - _ (object): Interface argument ignored by this fixed-response double. Unused by this
    #   double.
    # Returns:
    # - bool: Configured holiday classification.
    async def isHoliday(self, _: object) -> bool:
        return self.is_holiday


# Class Name: _FakeHolidayEmergencyBoundary
# Role: Date-specific emergency-pharmacy roster double backed by supplied schedules.
# Responsibilities:
# - Returns the configured emergency roster without contacting the public API.
# Attributes:
# - schedules (list[PharmacyHolidaySchedule]): Configured date-specific emergency pharmacy
#   roster.
class _FakeHolidayEmergencyBoundary:
    # Function Name: __init__
    # Description:
    # - Stores the emergency opening schedules to return to pharmacy queries.
    # Parameters:
    # - schedules (list[PharmacyHolidaySchedule]): Date-specific pharmacy opening schedules
    #   offered by the boundary.
    # Returns:
    # - None.
    def __init__(self, schedules: list[PharmacyHolidaySchedule]) -> None:
        self.schedules = schedules

    # Function Name: fetchSchedules
    # Description:
    # - Returns the configured emergency roster without contacting the public API.
    # Parameters:
    # - _ (date): Interface argument ignored by this fixed-response double. Unused by this
    #   double.
    # Returns:
    # - list[PharmacyHolidaySchedule]: Configured date-specific emergency pharmacy
    #   schedules.
    async def fetchSchedules(self, _: date) -> list[PharmacyHolidaySchedule]:
        return self.schedules


# Class Name: _MalformedHolidayEmergencyBoundary
# Role: Emergency-pharmacy roster double that injects malformed-response failures.
# Responsibilities:
# - Raises PharmacyApiResponseError to force the bounded stale-roster fallback.
class _MalformedHolidayEmergencyBoundary:
    # Function Name: fetchSchedules
    # Description:
    # - Raises PharmacyApiResponseError to force the bounded stale-roster fallback.
    # Parameters:
    # - _ (date): Interface argument ignored by this fixed-response double. Unused by this
    #   double.
    # Returns:
    # - No normal result; raises the configured failure described above.
    async def fetchSchedules(self, _: date) -> list[PharmacyHolidaySchedule]:
        raise PharmacyApiResponseError("Malformed holiday roster response.")


# Class Name: _StaleHolidayRepository
# Role: Pharmacy repository double that exposes an old holiday roster only to the stale-cache
#   policy.
# Responsibilities:
# - Returns no fresh roster below a 45-day allowance, otherwise supplying the requested day's
#   18:00-23:00 schedule.
class _StaleHolidayRepository(_FakePharmacyRepository):
    # Function Name: get_cached_holiday_schedules
    # Description:
    # - Returns no fresh roster below a 45-day allowance, otherwise supplying the requested
    #   day's 18:00-23:00 schedule.
    # Parameters:
    # - value (date): Calendar date whose holiday pharmacy roster is requested or replaced.
    # - max_age (timedelta): Maximum allowed age of the cached calendar or roster.
    # Returns:
    # - dict[str, PharmacyHolidaySchedule] | None: None on a cache miss; the stale-roster
    #   double returns date-specific hours only under its allowed age.
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


# 클래스명: _UnavailableHolidayBoundary
# 역할: 공휴일 조회 장애를 발생시켜 약국 결과의 선택적 부가조회 실패를 재현하는 객체다.
# 주요 책임:
# - 공휴일 서비스 사용 불가 오류를 발생시켜 로컬 약국 응답 유지 여부를 검증하게 한다.
class _UnavailableHolidayBoundary:
    # 함수이름: isHoliday
    # 함수역할:
    # - 공휴일 서비스 사용 불가 오류를 발생시켜 로컬 약국 응답 유지 여부를 검증하게 한다.
    # 매개변수:
    # - _ (object): 고정 응답 대체 객체에서 사용하지 않는 인터페이스 인자. 이 대체 객체에서는 사용하지 않음.
    # 반환값:
    # - 정상 반환 없음. 위에 명시한 실패를 예외로 전달함.
    async def isHoliday(self, _: object) -> bool:
        raise PharmacyApiUnavailableError("Holiday service unavailable.")


# 함수이름: _record
# 함수역할:
# - 선택한 식별자·거리·영업시간과 고정 서울 좌표를 가진 약국 레코드를 만든다.
# 매개변수:
# - pharmacy_id (str): 공공 카탈로그 약국 식별자.
# - distance_km (float | None): API가 제공한 km 거리 또는 좌표 계산을 시험할 None.
# - start_time (str): HHMM 형식의 약국 개점 시각.
# - end_time (str): HHMM 형식의 약국 폐점 시각.
# 반환값:
# - PharmacyLocationRecord: 선택한 거리와 영업시간 범위가 있는 약국 위치 레코드.
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


# 함수이름: test_open_only_filters_closed_pharmacies_and_formats_hours
# 함수역할:
# - 영업 중 필터가 닫힌 약국을 제외하고 시간을 09:00·24:00으로 표시하며 충분한 후보 상한을 요청하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_all_results_put_open_pharmacies_before_nearer_closed_ones
# 함수역할:
# - 더 가까운 닫힌 약국보다 영업 중인 약국을 먼저 반환하고 24시간 운영 여부를 표시하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_open_results_put_late_hours_before_regular_hours
# 함수역할:
# - 현재 영업 중인 후보끼리는 일반 약국보다 늦게 닫는 약국을 먼저 반환하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
@pytest.mark.anyio
async def test_open_results_put_late_hours_before_regular_hours() -> None:
    """현재 영업 중인 결과에서는 늦게까지 운영하는 약국을 먼저 반환한다."""
    boundary = _FakePharmacyBoundary(
        [
            _record("regular", distance_km=0.1, start_time="0900", end_time="1800"),
            _record("late", distance_km=0.8, start_time="0900", end_time="2300"),
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

    assert [item.pharmacy_id for item in result] == ["late", "regular"]


# 함수이름: test_missing_api_distance_uses_coordinate_distance
# 함수역할:
# - API 거리가 없을 때 좌표로 계산하여 같은 위치의 거리가 0이 되는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_invalid_coordinate_is_rejected_before_api_call
# 함수역할:
# - 유효하지 않은 좌표를 API 호출 전에 ValueError로 거절하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_empty_catalog_falls_back_to_location_api
# 함수역할:
# - 동기화 전 빈 로컬 목록에서는 위치 API를 호출하여 지정 상한의 대체 결과를 반환하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_holiday_lookup_failure_does_not_block_pharmacy_results
# 함수역할:
# - 공휴일 부가 조회가 실패해도 사용 가능한 로컬 약국 결과를 유지하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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


# Function Name: test_catalog_search_filters_after_all_nearby_candidates
# Description:
# - Filters the full local candidate set before limiting results so an open 24-hour pharmacy
#   beyond the first thirty is retained.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_public_holiday_uses_eighth_schedule
# Description:
# - Selects the eighth schedule on a public holiday and preserves late overnight hours from
#   22:00 to 01:00.
# Parameters:
# - None.
# Returns:
# - None.
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


# 함수이름: test_after_midnight_uses_previous_days_overnight_schedule
# 함수역할:
# - 자정 이후에도 전날 시작한 심야 영업을 적용하고 폐점까지 남은 30분을 반환하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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


# Function Name: test_late_hours_mode_filters_before_result_limit
# Description:
# - Applies the late-hours filter before the result limit so a qualifying pharmacy beyond thirty
#   ordinary candidates is retained.
# Parameters:
# - None.
# Returns:
# - None.
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


# 함수이름: test_late_hours_mode_includes_official_public_late_night_pharmacy
# 함수역할:
# - 공식 지정 심야약국을 사용자용 늦은 영업 검색에 포함하고 지정 상태를 표시하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
@pytest.mark.anyio
async def test_late_hours_mode_includes_official_public_late_night_pharmacy() -> None:
    """행정 지정 심야약국도 사용자용 늦은 영업 조건에 함께 포함한다."""
    entry = PharmacyCatalogEntry(
        pharmacy_id="official-late-night",
        name="Official late-night pharmacy",
        address="Seoul",
        telephone="",
        latitude=37.5665,
        longitude=126.9780,
        weekly_hours={"1": ("0900", "1800")},
        official_designations={
            "public_late_night": {
                "operating_days": [1],
                "source_name": "Seoul Metropolitan Government",
                "verified_at": "2026-08-19",
            }
        },
    )
    control = CheckNearbyPharmacy(
        pharmacy_repository=_FakePharmacyRepository([entry]),
        holiday_boundary=_FakeHolidayBoundary(False),
        now_provider=lambda: datetime(
            2026, 8, 24, 12, 0, tzinfo=ZoneInfo("Asia/Seoul")
        ),
    )

    result = await control.requestNearbyPharmacySearch(
        latitude=37.5665,
        longitude=126.9780,
        search_mode=PharmacySearchMode.LATE_HOURS,
    )

    assert [item.pharmacy_id for item in result.data] == ["official-late-night"]
    assert result.data[0].is_official_late_night is True


# Function Name: test_holiday_roster_overrides_generic_weekly_schedule
# Description:
# - Requires a date-specific emergency roster to override weekly hours and report its source and
#   date-specific status.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_malformed_holiday_roster_uses_bounded_stale_cache
# Description:
# - Uses a bounded stale holiday roster after malformed upstream data and labels the response
#   stale_fallback.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_official_designation_respects_operating_weekday
# Description:
# - Requires official late-night designation to respect its operating weekday and retain the
#   government source name.
# Parameters:
# - None.
# Returns:
# - None.
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


# 함수이름: test_open_pharmacy_reports_minutes_until_close
# 함수역할:
# - 영업 중인 약국에 폐점까지 남은 15분을 표시하고 다음 개점 시각은 비워두는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_closed_pharmacy_reports_next_regular_opening
# 함수역할:
# - 닫힌 약국에는 다음 정규 개점 시각을 서울 시간대 ISO 문자열로 안내하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_holiday_next_opening_uses_holiday_schedule
# 함수역할:
# - 공휴일의 다음 개점 안내가 평일 영업표 대신 공휴일 오전 10시를 사용하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_aware_catalog_timestamp_is_converted_without_relabeling
# 함수역할:
# - 시간대가 있는 카탈로그 갱신 시각을 동일한 순간의 서울 시간으로 변환하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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
