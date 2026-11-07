# 파일명: test_check_nearby_hospital_control.py
# 역할: 병원 시간표의 불확실성, 진료과 필터, 페이지·상세 조회 예산과 장애 시 부분 결과를 검증한다.

"""병원 시간표의 미확인 상태·진료과·검색 예산을 검증한다."""

import asyncio
from collections.abc import Callable, Mapping
from dataclasses import replace
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
import sys
from typing import Any, NoReturn
from zoneinfo import ZoneInfo

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from boundaries.holiday_lookup_boundary import HolidayLookupBoundary
from boundaries.hospital_api_boundary import HospitalApiResponseError, HospitalApiUnavailableError
from boundaries.pharmacy_api_boundary import PharmacyApiUnavailableError
from controls.check_nearby_hospital_control import CheckNearbyHospital
from core.config import settings
from entities.nearby_hospital_entity import HospitalDetails, HospitalLocationPage, HospitalLocationRecord
from schemas.hospital import HospitalSearchMode, NearbyHospitalResponse

KST = ZoneInfo("Asia/Seoul")
MONDAY = datetime(2026, 9, 28, 10, tzinfo=KST)


# 함수이름: anyio_backend
# 함수역할:
# - asyncio 제어 흐름을 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - str; 비동기 테스트 실행기 asyncio.
@pytest.fixture
def anyio_backend() -> str:
    """asyncio 제어 흐름을 검증한다."""
    return "asyncio"


# 클래스명: Calendar
# 역할: 날짜별 공휴일과 달력 장애를 재현하는 대체 제공자.
# 주요 책임:
# - 등록된 날짜를 공휴일로 반환하거나 조회 오류를 발생시킨다.
# 속성:
# - holidays (tuple[date, ...]): 공휴일; unavailable (bool): 장애 여부.
class Calendar:
    # 필요한 날짜만 공휴일로 취급하거나 제공자 실패를 재현한다.
    # 함수이름: __init__
    # 함수역할:
    # - 공휴일 날짜와 장애 발생 여부를 저장한다.
    # 매개변수:
    # - unavailable: bool; 달력 서비스 오류를 발생시킬지 지정한다.
    # - holidays: tuple[date, ...]; 공휴일로 취급할 날짜.
    # 반환값:
    # - None.
    def __init__(self, *holidays: date, unavailable: bool = False) -> None:
        self.holidays, self.unavailable = holidays, unavailable

    # 함수이름: isHoliday
    # 함수역할:
    # - 명시된 공휴일만 반환한다.
    # 매개변수:
    # - value: date; 공휴일 여부를 조회할 날짜.
    # 반환값:
    # - bool; 등록 날짜이면 True. 달력 장애 시 PharmacyApiUnavailableError.
    async def isHoliday(self, value: date) -> bool:
        """명시된 공휴일만 반환한다."""
        if self.unavailable:
            raise PharmacyApiUnavailableError("calendar unavailable")
        return value in self.holidays


# 클래스명: Boundary
# 역할: 병원 위치 페이지와 상세 캐시를 기록하는 대체 제공자.
# 주요 책임:
# - 제공자 페이지 제한, 상세 예산 및 실패 경로를 재현한다.
# 속성:
# - details/records: 상세·위치 자료; size: 페이지 제한; pages/loads/cached: 조회 기록·캐시 ID.
class Boundary:
    # 페이지 크기 축소와 상세 캐시 적중을 재현한다.
    # 함수이름: __init__
    # 함수역할:
    # - 상세·위치 자료와 페이지 크기를 저장하고 조회 기록·캐시를 비운다.
    # 매개변수:
    # - details: dict[str, HospitalDetails | Exception]; 식별자별 상세 또는 오류.
    # - size: int; 제공자가 허용하는 최대 페이지 크기.
    # - records: list[HospitalLocationRecord] | None; 위치 목록, 생략하면 상세 ID에서 생성.
    # 반환값:
    # - None.
    def __init__(self, details: Mapping[str, HospitalDetails | Exception], *, size: int = 30, records: list[HospitalLocationRecord] | None = None) -> None:
        self.details, self.size = details, size
        self.records = records or [record(identifier) for identifier in details]
        self.pages, self.loads, self.cached = [], [], set()

    # 함수이름: fetchNearbyPage
    # 함수역할:
    # - 제공자 페이지 크기에 맞춰 다음 구간을 반환한다.
    # 매개변수:
    # - page_no: int; 1부터 시작하는 요청 페이지.
    # - page_size: int; 요청한 페이지당 행 수.
    # - _: dict; 사용하지 않는 검색 조건.
    # 반환값:
    # - HospitalLocationPage; 요청 구간과 원본 행 수.
    async def fetchNearbyPage(self, *, page_no: int, page_size: int, **_: object) -> HospitalLocationPage:
        """제공자 페이지 크기에 맞춰 다음 구간을 반환한다."""
        self.pages.append((page_no, page_size))
        size = min(page_size, self.size)
        rows = self.records[(page_no - 1) * size:page_no * size]
        return HospitalLocationPage(tuple(rows), len(self.records), len(rows), size)

    # 함수이름: fetchDepartmentPage
    # 함수역할:
    # - 상세와 목록의 진료과가 불일치하는 기존 방어 테스트도 재현한다.
    # 매개변수:
    # - page_no: int; 1부터 시작하는 요청 페이지.
    # - page_size: int; 요청한 페이지당 행 수.
    # - _: dict; 사용하지 않는 검색 조건.
    # 반환값:
    # - HospitalLocationPage; 요청 구간의 진료과 후보.
    async def fetchDepartmentPage(self, *, page_no: int, page_size: int, **_: object) -> HospitalLocationPage:
        """상세와 목록의 진료과가 불일치하는 기존 방어 테스트도 재현한다."""
        size = min(page_size, self.size)
        rows = self.records[(page_no - 1) * size:page_no * size]
        return HospitalLocationPage(tuple(rows), len(self.records), len(rows), size)

    # 함수이름: hasCachedDetails
    # 함수역할:
    # - 이미 확인한 ID는 새 상세 예산을 쓰지 않는다.
    # 매개변수:
    # - hospital_id: str; 상세를 조회할 병원 식별자.
    # 반환값:
    # - bool; 이미 상세를 조회한 ID이면 True.
    def hasCachedDetails(self, hospital_id: str) -> bool:
        """이미 확인한 ID는 새 상세 예산을 쓰지 않는다."""
        return hospital_id in self.cached

    # 함수이름: fetchDetails
    # 함수역할:
    # - 상세 결과 또는 지정한 오류를 반환한다.
    # 매개변수:
    # - hospital_id: str; 상세를 조회할 병원 식별자.
    # 반환값:
    # - HospitalDetails; 지정된 오류가 있으면 해당 예외 발생.
    async def fetchDetails(self, hospital_id: str) -> HospitalDetails:
        """상세 결과 또는 지정한 오류를 반환한다."""
        self.loads.append(hospital_id)
        self.cached.add(hospital_id)
        result = self.details[hospital_id]
        if isinstance(result, Exception):
            raise result
        return result


# 함수이름: record
# 함수역할:
# - 공유 지도 표시용 위치를 만든다.
# 매개변수:
# - identifier: str; 병원 식별자.
# - latitude: float; 지도 위도.
# 반환값:
# - HospitalLocationRecord; 지정 ID와 위도의 합성 병원 위치.
def record(identifier: str = "A1", *, latitude: float = 37.5665) -> HospitalLocationRecord:
    """공유 지도 표시용 위치를 만든다."""
    return HospitalLocationRecord(identifier, "Test clinic", "서울특별시 중구", "", latitude, 126.978, "의원")


# 함수이름: detail
# 함수역할:
# - 요일별 상세 운영표를 구성한다.
# 매개변수:
# - identifier: str; 병원 식별자.
# - departments: tuple[str, ...]; 제공자 진료과명.
# - hours: dict | None; 요일 코드별 시작·종료 시각.
# 반환값:
# - HospitalDetails; 진료과와 요일별 시간표.
def detail(identifier: str = "A1", *, departments: tuple[str, ...] = ("내과",), hours: dict[str, tuple[str, str]] | None = None) -> HospitalDetails:
    """요일별 상세 운영표를 구성한다."""
    return HospitalDetails(identifier, departments=departments,
                           weekly_hours=tuple((day, *times) for day, times in (hours or {}).items()))


# Function Name: search
# Description:
# - Runs a hospital search at a fixed location using the supplied provider, calendar and clock; propagates validation/provider errors.
# Parameters:
# - boundary: Boundary; hospital provider double.
# - calendar: Calendar | None; holiday provider, defaults to no holidays.
# - clock: Callable | None; application clock, defaults to MONDAY.
# - kwargs: dict; target datetime and search filters.
# Returns:
# - Hospital search response with results and completeness metadata.
async def search(boundary: Boundary, *, calendar: HolidayLookupBoundary | None = None, clock: Callable[[], datetime] | None = None, **kwargs: Any) -> NearbyHospitalResponse:
    """명시적 달력과 기준일로 결과를 계산한다. 조회 허용 범위는 고정 시계(기본 MONDAY) 기준이다."""
    control = CheckNearbyHospital(boundary, holiday_boundary=calendar or Calendar(),
                                  clock=clock or (lambda: MONDAY))
    return await control.requestNearbyHospitalSearch(latitude=37.5665, longitude=126.978,
                                                     target_datetime=kwargs.pop("target_datetime", MONDAY), **kwargs)


# 함수이름: test_schedule_intervals_unknown_and_24_hours
# 함수역할:
# - 불완전·모호한 시각을 영업 또는 휴무로 단정하지 않는다.
# 매개변수:
# - start: str; 제공자 영업 시작 시각.
# - end: str; 제공자 영업 종료 시각.
# - hour: int; 조회할 한국 시간의 시.
# - opened: bool | None; 예상 현재 진료 여부.
# - late: bool; 예상 야간 운영 여부.
# - full: bool; 예상 24시간 운영 여부.
# 반환값:
# - None.
@pytest.mark.parametrize("start,end,hour,opened,late,full", [
    ("0900", "1800", 10, True, False, False),
    ("0900", "1800", 18, False, False, False),
    ("0900", "1801", 10, True, True, False),
    ("0900", "1900", 10, True, True, False),
    ("0000", "0200", 1, True, False, False),
    ("2200", "0200", 23, True, True, False),
    ("2200", "0200", 1, False, True, False),
    ("0000", "2400", 12, True, True, True),
    ("0000", "0000", 12, None, False, False),
    ("0900", "0900", 12, None, False, False),
    ("0900", "", 12, None, False, False),
    ("2500", "1800", 12, None, False, False),
    ("09xx00", "1800", 12, None, False, False),
])
@pytest.mark.anyio
async def test_schedule_intervals_unknown_and_24_hours(start: str, end: str, hour: int, opened: bool | None, late: bool, full: bool) -> None:
    """불완전·모호한 시각을 영업 또는 휴무로 단정하지 않는다."""
    result = await search(Boundary({"A1": detail(hours={"1": (start, end)})}),
                          target_datetime=MONDAY.replace(hour=hour))
    item = result.data[0]
    assert item.is_open_now is opened and item.is_open_late is late and item.is_24_hours is full
    assert item.institution_type == "의원"
    assert item.schedule_is_date_specific is False
    assert "pharmacy_id" not in item.model_dump() and "is_official_late_night" not in item.model_dump()


# 함수이름: test_yesterday_holiday_carryover_and_close_countdown
# 함수역할:
# - 전날 공휴일의 자정 이후 운영 구간도 휴일 표에서 계산한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_yesterday_holiday_carryover_and_close_countdown() -> None:
    """전날 공휴일의 자정 이후 운영 구간도 휴일 표에서 계산한다."""
    result = await search(Boundary({"A1": detail(hours={"8": ("2200", "0200")})}),
                          calendar=Calendar(date(2026, 9, 27)), target_datetime=MONDAY.replace(hour=1))
    assert result.data[0].is_open_now is True
    assert result.data[0].minutes_until_close == 60


# 함수이름: test_registered_holiday_hours_only_and_no_actual_date_claim
# 함수역할:
# - 평일 공휴일에도 공휴일 전용 표만 선택한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_registered_holiday_hours_only_and_no_actual_date_claim() -> None:
    """평일 공휴일에도 공휴일 전용 표만 선택한다."""
    boundary = Boundary({"A1": detail(hours={"1": ("0900", "1800"), "8": ("1000", "1300")}),
                         "A2": detail("A2", hours={"1": ("0900", "1800")})})
    result = await search(boundary, calendar=Calendar(MONDAY.date()), search_mode=HospitalSearchMode.WEEKEND_HOLIDAY)
    assert [item.hospital_id for item in result.data] == ["A1"]
    assert result.data[0].today_close_time == "13:00"
    assert result.data[0].schedule_source == "nemc_hospital_weekly_report"
    assert result.holiday_schedule_status == "weekly_report"
    assert not result.data[0].schedule_is_date_specific


# 함수이름: test_calendar_outage_unknown_and_excluded_from_operating_modes
# 함수역할:
# - 공휴일 여부를 모르면 평일표를 대신 사용하지 않는다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_calendar_outage_unknown_and_excluded_from_operating_modes() -> None:
    """공휴일 여부를 모르면 평일표를 대신 사용하지 않는다."""
    boundary = Boundary({"A1": detail(hours={"1": ("0900", "2300"), "8": ("0900", "2300")})})
    result = await search(boundary, calendar=Calendar(unavailable=True))
    assert result.data[0].is_open_now is None and result.data[0].today_open_time is None
    assert result.holiday_schedule_status == "unknown"
    for mode in (HospitalSearchMode.OPEN_AT_TIME, HospitalSearchMode.LATE_HOURS, HospitalSearchMode.WEEKEND_HOLIDAY):
        assert not (await search(boundary, calendar=Calendar(unavailable=True), search_mode=mode)).data


# 함수이름: test_selected_weekend_and_timezone_normalization
# 함수역할:
# - 주말 검색은 선택한 날짜를 사용하고 UTC는 한국 시각으로 변환한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_selected_weekend_and_timezone_normalization() -> None:
    """주말 검색은 선택한 날짜를 사용하고 UTC는 한국 시각으로 변환한다."""
    boundary = Boundary({"A1": detail(hours={"6": ("0900", "1300"), "1": ("0900", "1800")})})
    assert not (await search(boundary, search_mode=HospitalSearchMode.WEEKEND_HOLIDAY)).data
    weekend = await search(boundary, target_datetime=datetime(2026, 10, 3, 10), search_mode=HospitalSearchMode.WEEKEND_HOLIDAY)
    assert len(weekend.data) == 1
    normalized = await search(boundary, target_datetime=MONDAY.astimezone(timezone.utc))
    assert normalized.target_datetime == MONDAY and normalized.data[0].is_open_now is True


# 함수이름: test_verified_department_names_and_aliases
# 함수역할:
# - 진료과명은 정확히 비교하고 공식 코드·명칭 변경만 연결한다.
# 매개변수:
# - code: str; 필터로 요청할 공식 진료과 코드.
# - names: tuple[str, ...]; 상세 응답의 진료과명.
# - match: bool; 진료과 필터의 예상 통과 여부.
# 반환값:
# - None.
@pytest.mark.parametrize("code,names,match", [
    ("D001", ("내과",), True), ("D001", ("한방내과",), False),
    ("D022", ("가정의학과",), True), ("D016", ("재활의학과",), True),
    ("D026", ("치과보존과", "치과보철과"), True),
    ("D020", ("진단검사의학과",), True), ("D034", ("구강악안면외과",), True),
])
@pytest.mark.anyio
async def test_verified_department_names_and_aliases(code: str, names: tuple[str, ...], match: bool) -> None:
    """진료과명은 정확히 비교하고 공식 코드·명칭 변경만 연결한다."""
    result = await search(Boundary({"A1": detail(departments=names)}), department=code)
    assert bool(result.data) is match


# 함수이름: test_capped_pagination_filter_before_limit_and_deduplication
# 함수역할:
# - 줄어든 페이지 크기로 다음 페이지를 읽고 중복을 제거한 후 제한한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_capped_pagination_filter_before_limit_and_deduplication() -> None:
    """줄어든 페이지 크기로 다음 페이지를 읽고 중복을 제거한 후 제한한다."""
    boundary = Boundary({"A1": detail(departments=("한방내과",)), "A2": detail("A2")},
                        size=1, records=[record("A1"), record("A1"), record("A2")])
    result = await search(boundary, department="D001", limit=1)
    assert [item.hospital_id for item in result.data] == ["A2"]
    assert boundary.pages == [(1, 30)] * 5 and boundary.loads == ["A1", "A2"]


# 함수이름: test_detail_budget_partial_and_filter_cache_reuse
# 함수역할:
# - 상세 신규 호출 상한을 지키고 필터 변경에 기존 상세를 재사용한다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_detail_budget_partial_and_filter_cache_reuse(monkeypatch: pytest.MonkeyPatch) -> None:
    """상세 신규 호출 상한을 지키고 필터 변경에 기존 상세를 재사용한다."""
    monkeypatch.setattr(settings, "HOSPITAL_DETAIL_REQUEST_BUDGET", 1)
    boundary = Boundary({"A1": detail(), "A2": detail("A2")})
    first = await search(boundary)
    assert len(boundary.loads) == 1 and first.search_truncated and len(first.data) == 2
    assert first.data[1].is_open_now is None and not first.data[1].departments
    second = await search(boundary, department="D001")
    assert len(second.data) == 2 and not second.search_truncated
    capped = Boundary({"A1": detail(departments=("한방내과",)), "A2": detail("A2")})
    empty = await search(capped, department="D001")
    assert not empty.data and empty.search_truncated


# 함수이름: test_partial_detail_failure_versus_complete_failure
# 함수역할:
# - 일부 상세 실패는 표시하고 모든 상세 실패는 서비스 오류로 반환한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_partial_detail_failure_versus_complete_failure() -> None:
    """일부 상세 실패는 표시하고 모든 상세 실패는 서비스 오류로 반환한다."""
    boundary = Boundary({"A1": detail(), "A2": HospitalApiUnavailableError("failed")})
    result = await search(boundary)
    assert result.search_truncated and len(result.data) == 2
    for error in (HospitalApiUnavailableError, HospitalApiResponseError):
        with pytest.raises(error):
            await search(Boundary({"A1": error("failed")}))


# 함수이름: test_radius_before_rounding_and_no_distant_detail_requests
# 함수역할:
# - 반경 밖 병원은 상세 호출 전 제외한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_radius_before_rounding_and_no_distant_detail_requests() -> None:
    """반경 밖 병원은 상세 호출 전 제외한다."""
    boundary = Boundary({"A1": detail(), "A2": detail("A2")},
                        records=[record("A2", latitude=38), record("A1")])
    result = await search(boundary, max_distance_km=0.1)
    assert [item.hospital_id for item in result.data] == ["A1"] and boundary.loads == ["A1"]


# 함수이름: test_invalid_requests_rejected_before_network
# 함수역할:
# - 미지원 진료과와 잘못된 범위는 빈 성공 응답이 아닌 검증 오류다.
# 매개변수:
# - kwargs: dict; 검색에 전달할 옵션.
# 반환값:
# - None.
@pytest.mark.parametrize("kwargs", [{"department": "D999"}, {"limit": 31}, {"max_distance_km": float("nan")},
                                        {"search_mode": "official_late_night"}])
@pytest.mark.anyio
async def test_invalid_requests_rejected_before_network(kwargs: dict[str, str | int | float]) -> None:
    """미지원 진료과와 잘못된 범위는 빈 성공 응답이 아닌 검증 오류다."""
    boundary = Boundary({"A1": detail()})
    with pytest.raises(ValueError):
        await search(boundary, **kwargs)
    assert not boundary.pages


# Function Name: test_target_date_window_is_counted_in_calendar_days
# Description:
# - Accepts both calendar-day window boundaries regardless of the clock hour and rejects outside dates before provider work.
# Parameters:
# - hour: int; application clock hour at the same reference date.
# Returns:
# - None.
@pytest.mark.parametrize("hour", [9, 14])
@pytest.mark.anyio
async def test_target_date_window_is_counted_in_calendar_days(hour: int) -> None:
    """앱 달력이 제공하는 첫날·마지막 날은 현재 시각과 무관하게 허용하고 범위 밖 날짜는 달력·병원 조회 전에 거절한다."""
    now = datetime(2026, 10, 8, hour, tzinfo=KST)
    calendar = Calendar()
    calendar.seen = []
    lookup = calendar.isHoliday

    # Function Name: recording
    # Description:
    # - Records each calendar date requested before delegating to the original holiday lookup.
    # Parameters:
    # - value: date; holiday query date.
    # Returns:
    # - bool returned by the original calendar.
    async def recording(value: date) -> bool:
        calendar.seen.append(value)
        return await lookup(value)

    calendar.isHoliday = recording
    boundary = Boundary({"A1": detail()})
    for picked in (datetime(2026, 10, 1, 12), datetime(2027, 10, 9, 12)):
        result = await search(boundary, calendar=calendar, clock=lambda: now, target_datetime=picked)
        assert result.target_datetime == picked.replace(tzinfo=KST) and len(result.data) == 1
    pages, seen = list(boundary.pages), list(calendar.seen)
    for outside in (datetime(2026, 9, 30, 23, 59), datetime(2027, 10, 10), datetime(1990, 5, 5, 12),
                    datetime.max.replace(tzinfo=timezone.utc)):
        with pytest.raises(ValueError, match="^Target date"):
            await search(boundary, calendar=calendar, clock=lambda: now, target_datetime=outside)
    assert boundary.pages == pages and calendar.seen == seen


# 함수이름: test_unknown_department_and_hours_are_incomplete_not_exhaustive
# 함수역할:
# - 필터 판단 근거가 누락되면 결과 없음도 부분 검색으로 표시한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_unknown_department_and_hours_are_incomplete_not_exhaustive() -> None:
    """필터 판단 근거가 누락되면 결과 없음도 부분 검색으로 표시한다."""
    boundary = Boundary({"A1": detail(departments=())})
    for filters in ({"department": "D001"}, {"search_mode": HospitalSearchMode.OPEN_AT_TIME}):
        result = await search(boundary, **filters)
        assert not result.data and result.search_truncated


# 함수이름: test_small_all_limit_hydrates_only_visible_result
# 함수역할:
# - 전체 목록의 한 건 요청은 나머지 후보의 상세를 조회하지 않는다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_small_all_limit_hydrates_only_visible_result() -> None:
    """전체 목록의 한 건 요청은 나머지 후보의 상세를 조회하지 않는다."""
    boundary = Boundary({f"A{index}": detail(f"A{index}") for index in range(30)})
    result = await search(boundary, limit=1)
    assert len(result.data) == 1 and len(boundary.loads) == 1


# 함수이름: test_calendar_deadline_preserves_basic_list
# 함수역할:
# - 달력이 지연되어도 기본 병원 목록은 미확인 시간으로 반환한다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_calendar_deadline_preserves_basic_list(monkeypatch: pytest.MonkeyPatch) -> None:
    """달력이 지연되어도 기본 병원 목록은 미확인 시간으로 반환한다."""
    monkeypatch.setattr(settings, "HOSPITAL_CALENDAR_TIMEOUT_SECONDS", 0.01)

    # 클래스명: SlowCalendar
    # 역할: 응답하지 않는 달력 제공자.
    # 주요 책임:
    # - 달력 조회 제한 시간이 목록 응답을 보호하는지 재현한다.
    # 속성:
    # - 없음.
    class SlowCalendar:
        # 함수이름: isHoliday
        # 함수역할:
        # - 달력 조회를 완료하지 않아 호출자의 시간 제한과 취소를 유도한다.
        # 매개변수:
        # - value: date; 공휴일 여부를 조회할 날짜.
        # 반환값:
        # - 정상 반환 없음; 호출자가 취소할 때까지 대기.
        async def isHoliday(self, value: date) -> NoReturn:
            await asyncio.Event().wait()

    async with asyncio.timeout(0.5):
        result = await search(Boundary({"A1": detail(hours={"1": ("0900", "1800")})}), calendar=SlowCalendar())
    assert len(result.data) == 1 and result.data[0].is_open_now is None


# 함수이름: test_unknown_previous_holiday_does_not_imply_closed
# 함수역할:
# - 전날 공휴일 여부가 불명확하면 야간 이월 가능성을 닫힘으로 숨기지 않는다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_unknown_previous_holiday_does_not_imply_closed() -> None:
    """전날 공휴일 여부가 불명확하면 야간 이월 가능성을 닫힘으로 숨기지 않는다."""
    # 클래스명: PartialCalendar
    # 역할: 전날의 공휴일 여부만 조회할 수 없는 달력.
    # 주요 책임:
    # - 전날 조회에는 오류를 발생시키고 나머지 날짜는 평일로 반환한다.
    # 속성:
    # - 없음.
    class PartialCalendar:
        # 함수이름: isHoliday
        # 함수역할:
        # - 전날 조회에만 서비스 오류를 내고 나머지 날짜에는 False를 반환한다.
        # 매개변수:
        # - value: date; 공휴일 여부를 조회할 날짜.
        # 반환값:
        # - bool; 전날에는 PharmacyApiUnavailableError 발생.
        async def isHoliday(self, value: date) -> bool:
            if value == MONDAY.date() - timedelta(days=1):
                raise PharmacyApiUnavailableError("previous month unavailable")
            return False

    result = await search(Boundary({"A1": detail(hours={"1": ("0900", "1800"), "8": ("2200", "0200")})}),
                          calendar=PartialCalendar(), target_datetime=MONDAY.replace(hour=1))
    assert result.data[0].is_open_now is None


# 함수이름: test_operating_notes_are_preserved_and_not_ignored
# 함수역할:
# - 비정형 휴게시간 안내가 있으면 진료 중을 단정하지 않는다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_operating_notes_are_preserved_and_not_ignored() -> None:
    """비정형 휴게시간 안내가 있으면 진료 중을 단정하지 않는다."""
    with_notes = replace(detail(hours={"1": ("0900", "1800")}), operating_notes="점심시간 전화 확인")
    result = await search(Boundary({"A1": with_notes}))
    assert result.data[0].operating_notes == with_notes.operating_notes
    assert result.data[0].is_open_now is None and result.data[0].minutes_until_close is None


# 함수이름: test_skipped_location_rows_mark_empty_or_populated_results_partial
# 함수역할:
# - 유효하지 않은 위치 행을 제외하면 빈 결과도 완전한 검색으로 표시하지 않는다.
# 매개변수:
# - include_valid: bool; 잘못된 위치 행 외 정상 병원도 포함할지 지정한다.
# 반환값:
# - None.
@pytest.mark.parametrize("include_valid", [False, True])
@pytest.mark.anyio
async def test_skipped_location_rows_mark_empty_or_populated_results_partial(include_valid: bool) -> None:
    """유효하지 않은 위치 행을 제외하면 빈 결과도 완전한 검색으로 표시하지 않는다."""
    # 클래스명: SkippedRowsBoundary
    # 역할: 잘못된 위치 행이 제거된 페이지 제공자.
    # 주요 책임:
    # - 유효 행과 원본 행 수의 차이를 재현한다.
    # 속성:
    # - Boundary 속성 상속; include_valid는 외부 테스트 인수.
    class SkippedRowsBoundary(Boundary):
        # 함수이름: fetchNearbyPage
        # 함수역할:
        # - 원본 행 하나가 검증 중 제외된 페이지를 반환한다.
        # 매개변수:
        # - _: dict; 사용하지 않는 검색 조건.
        # 반환값:
        # - HospitalLocationPage; 요청 구간과 원본 행 수.
        async def fetchNearbyPage(self, **_: object) -> HospitalLocationPage:
            """원본 행 하나가 검증 중 제외된 페이지를 반환한다."""
            records = (record(),) if include_valid else ()
            raw_count = len(records) + 1
            return HospitalLocationPage(records, raw_count, raw_count, 30)

    result = await search(SkippedRowsBoundary({"A1": detail()}))
    assert [item.hospital_id for item in result.data] == (["A1"] if include_valid else [])
    assert result.search_truncated


# 클래스명: PageFailureBoundary
# 역할: 특정 위치 페이지에서만 오류를 발생시키는 제공자.
# 주요 책임:
# - 정상 선행 페이지를 유지하고 실패 페이지 요청도 기록한다.
# 속성:
# - failed_page (int): 실패 페이지; error (Exception): 주입 오류; 나머지는 Boundary 상속.
class PageFailureBoundary(Boundary):
    # 지정 페이지에서만 오류를 내고 앞선 페이지의 정상 처리는 유지한다.
    # 함수이름: __init__
    # 함수역할:
    # - 한 행씩 반환하는 기본 제공자에 실패 페이지와 오류를 지정한다.
    # 매개변수:
    # - details: dict[str, HospitalDetails | Exception]; 식별자별 상세 또는 오류.
    # - failed_page: int; 오류를 주입할 페이지 번호.
    # - error: Exception; 지정 페이지에서 발생시킬 오류.
    # 반환값:
    # - None.
    def __init__(self, details: Mapping[str, HospitalDetails | Exception], *, failed_page: int, error: Exception) -> None:
        super().__init__(details, size=1)
        self.failed_page, self.error = failed_page, error

    # 함수이름: fetchNearbyPage
    # 함수역할:
    # - 오류 페이지 이후의 추가 조회가 없는지 확인할 수 있게 기록한다.
    # 매개변수:
    # - page_no: int; 1부터 시작하는 요청 페이지.
    # - page_size: int; 요청한 페이지당 행 수.
    # - kwargs: dict; 검색에 전달할 옵션.
    # 반환값:
    # - HospitalLocationPage; 요청 구간과 원본 행 수.
    async def fetchNearbyPage(self, *, page_no: int, page_size: int, **kwargs: object) -> HospitalLocationPage:
        """오류 페이지 이후의 추가 조회가 없는지 확인할 수 있게 기록한다."""
        if page_no == self.failed_page:
            self.pages.append((page_no, page_size))
            raise self.error
        return await super().fetchNearbyPage(page_no=page_no, page_size=page_size, **kwargs)


# 함수이름: test_later_location_failure_retains_earlier_valid_matches
# 함수역할:
# - 후속 페이지 장애는 이전 정상 결과를 부분 결과로 보존한다.
# 매개변수:
# - error_type: type[Exception]; 재현할 제공자 장애 유형.
# 반환값:
# - None.
@pytest.mark.parametrize("error_type", [HospitalApiUnavailableError, HospitalApiResponseError])
@pytest.mark.anyio
async def test_later_location_failure_retains_earlier_valid_matches(error_type: type[Exception]) -> None:
    """후속 페이지 장애는 이전 정상 결과를 부분 결과로 보존한다."""
    boundary = PageFailureBoundary(
        {identifier: detail(identifier) for identifier in ("A1", "A2", "A3")},
        failed_page=3, error=error_type("provider failed"),
    )
    result = await search(boundary)
    assert [item.hospital_id for item in result.data] == ["A1", "A2"]
    assert result.search_truncated
    assert boundary.pages == [(1, 30), (2, 1), (3, 1)]
    assert boundary.loads == ["A1", "A2"]


# 함수이름: test_later_location_failure_keeps_empty_unknown_results_partial
# 함수역할:
# - 이전 후보의 진료과·시간이 불명확해도 후속 장애를 확정적인 결과 없음으로 숨기지 않는다.
# 매개변수:
# - error_type: type[Exception]; 재현할 제공자 장애 유형.
# - filters: dict; 운영 중 여부 검색 조건.
# 반환값:
# - None.
@pytest.mark.parametrize("error_type", [HospitalApiUnavailableError, HospitalApiResponseError])
@pytest.mark.parametrize("filters", [
    {"search_mode": HospitalSearchMode.OPEN_AT_TIME},
])
@pytest.mark.anyio
async def test_later_location_failure_keeps_empty_unknown_results_partial(error_type: type[Exception], filters: dict[str, HospitalSearchMode]) -> None:
    """이전 후보의 진료과·시간이 불명확해도 후속 장애를 확정적인 결과 없음으로 숨기지 않는다."""
    boundary = PageFailureBoundary(
        {"A1": detail(departments=()), "A2": detail("A2")},
        failed_page=2, error=error_type("provider failed"),
    )
    result = await search(boundary, **filters)
    assert result.data == [] and result.search_truncated
    assert boundary.pages == [(1, 30), (2, 1)] and boundary.loads == ["A1"]


# 함수이름: test_first_location_failure_still_propagates_to_http_error
# 함수역할:
# - 첫 페이지 장애는 부분 성공으로 바꾸지 않고 기존 503·502 매핑으로 전달한다.
# 매개변수:
# - error_type: type[Exception]; 재현할 제공자 장애 유형.
# 반환값:
# - None.
@pytest.mark.parametrize("error_type", [HospitalApiUnavailableError, HospitalApiResponseError])
@pytest.mark.anyio
async def test_first_location_failure_still_propagates_to_http_error(error_type: type[Exception]) -> None:
    """첫 페이지 장애는 부분 성공으로 바꾸지 않고 기존 503·502 매핑으로 전달한다."""
    error = error_type("provider failed")
    boundary = PageFailureBoundary({"A1": detail()}, failed_page=1, error=error)
    with pytest.raises(error_type) as caught:
        await search(boundary)
    assert caught.value is error
    assert boundary.pages == [(1, 30)] and not boundary.loads


# 함수이름: test_weekday_holiday_filter_does_not_call_hospital_provider
# 함수역할:
# - 공휴일이 아닌 평일은 병원 API 장애와 무관하게 날짜 변경 대상으로 응답한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_weekday_holiday_filter_does_not_call_hospital_provider() -> None:
    """공휴일이 아닌 평일은 병원 API 장애와 무관하게 날짜 변경 대상으로 응답한다."""
    boundary = PageFailureBoundary(
        {"A1": detail()}, failed_page=1, error=HospitalApiUnavailableError("offline"),
    )
    result = await search(boundary, search_mode=HospitalSearchMode.WEEKEND_HOLIDAY)
    assert result.data == [] and not result.search_truncated
    assert result.holiday_schedule_status == "not_applicable"
    assert not boundary.pages and not boundary.loads


# 함수이름: test_slow_followup_page_preserves_holiday_results
# 함수역할:
# - 후속 위치 조회가 지연돼도 이미 확인한 공휴일 진료 병원은 보존한다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_slow_followup_page_preserves_holiday_results(monkeypatch: pytest.MonkeyPatch) -> None:
    """후속 위치 조회가 지연돼도 이미 확인한 공휴일 진료 병원은 보존한다."""
    monkeypatch.setattr(settings, "HOSPITAL_SEARCH_TIMEOUT_SECONDS", 1.05)

    # 클래스명: SlowPageBoundary
    # 역할: 두 번째 이후 위치 페이지가 끝나지 않는 제공자.
    # 주요 책임:
    # - 첫 페이지 결과를 보존하는 검색 시간 제한을 검증한다.
    # 속성:
    # - Boundary 속성 상속.
    class SlowPageBoundary(Boundary):
        # 함수이름: fetchNearbyPage
        # 함수역할:
        # - 첫 페이지는 정상 반환하고 후속 페이지는 취소될 때까지 대기한다.
        # 매개변수:
        # - page_no: int; 1부터 시작하는 요청 페이지.
        # - page_size: int; 요청한 페이지당 행 수.
        # - kwargs: dict; 검색에 전달할 옵션.
        # 반환값:
        # - HospitalLocationPage; 후속 조회는 정상 반환하지 않음.
        async def fetchNearbyPage(self, *, page_no: int, page_size: int, **kwargs: object) -> HospitalLocationPage:
            if page_no > 1:
                await asyncio.Event().wait()
            return await super().fetchNearbyPage(page_no=page_no, page_size=page_size, **kwargs)

    boundary = SlowPageBoundary({
        "A1": detail(hours={"8": ("0900", "1800")}), "A2": detail("A2"),
    }, size=1)
    async with asyncio.timeout(0.5):
        result = await search(boundary, calendar=Calendar(MONDAY.date()),
                              search_mode=HospitalSearchMode.WEEKEND_HOLIDAY)
    assert [item.hospital_id for item in result.data] == ["A1"]
    assert result.search_truncated and result.data[0].is_public_holiday


# 함수이름: test_slow_detail_preserves_completed_holiday_results
# 함수역할:
# - 한 병원의 상세가 늦어도 완료된 결과는 반환하고 대기 작업은 회수한다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_slow_detail_preserves_completed_holiday_results(monkeypatch: pytest.MonkeyPatch) -> None:
    """한 병원의 상세가 늦어도 완료된 결과는 반환하고 대기 작업은 회수한다."""
    monkeypatch.setattr(settings, "HOSPITAL_SEARCH_TIMEOUT_SECONDS", 1.05)
    cancelled = asyncio.Event()

    # 클래스명: SlowDetailBoundary
    # 역할: A2 병원의 상세 조회만 지연하는 제공자.
    # 주요 책임:
    # - 완료된 상세는 유지하고 대기 중 작업 취소를 기록한다.
    # 속성:
    # - Boundary 속성 상속; 외부 cancelled 이벤트에 취소를 알린다.
    class SlowDetailBoundary(Boundary):
        # 함수이름: fetchDetails
        # 함수역할:
        # - A2 조회를 지연하고 취소 시 이벤트를 설정하며 다른 상세는 기본 제공자에 위임한다.
        # 매개변수:
        # - hospital_id: str; 상세를 조회할 병원 식별자.
        # 반환값:
        # - HospitalDetails; A2는 호출자 취소까지 대기.
        async def fetchDetails(self, hospital_id: str) -> HospitalDetails:
            if hospital_id == "A2":
                try:
                    await asyncio.Event().wait()
                finally:
                    cancelled.set()
            return await super().fetchDetails(hospital_id)

    boundary = SlowDetailBoundary({
        "A1": detail(hours={"8": ("0900", "1800")}), "A2": detail("A2"),
    })
    async with asyncio.timeout(0.5):
        result = await search(boundary, calendar=Calendar(MONDAY.date()),
                              search_mode=HospitalSearchMode.WEEKEND_HOLIDAY)
    assert [item.hospital_id for item in result.data] == ["A1"]
    assert result.search_truncated and cancelled.is_set()


# 함수이름: test_first_page_timeout_is_not_an_empty_success
# 함수역할:
# - 위치 정보조차 받지 못한 시간 초과는 결과 없음으로 바꾸지 않는다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_first_page_timeout_is_not_an_empty_success(monkeypatch: pytest.MonkeyPatch) -> None:
    """위치 정보조차 받지 못한 시간 초과는 결과 없음으로 바꾸지 않는다."""
    monkeypatch.setattr(settings, "HOSPITAL_SEARCH_TIMEOUT_SECONDS", 1.05)

    # 클래스명: SlowBoundary
    # 역할: 첫 위치 페이지부터 응답하지 않는 제공자.
    # 주요 책임:
    # - 후보조차 없는 검색 시간 초과를 재현한다.
    # 속성:
    # - Boundary 속성 상속.
    class SlowBoundary(Boundary):
        # 함수이름: fetchNearbyPage
        # 함수역할:
        # - 위치 조회를 완료하지 않아 첫 페이지 검색 시간 초과를 유도한다.
        # 매개변수:
        # - kwargs: dict; 검색에 전달할 옵션.
        # 반환값:
        # - 정상 반환 없음; 호출자가 취소할 때까지 대기.
        async def fetchNearbyPage(self, **kwargs: object) -> NoReturn:
            await asyncio.Event().wait()

    with pytest.raises(HospitalApiUnavailableError):
        await search(SlowBoundary({"A1": detail()}))
