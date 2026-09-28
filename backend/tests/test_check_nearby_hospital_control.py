"""병원 시간표의 미확인 상태·진료과·검색 예산을 검증한다."""

import asyncio
from dataclasses import replace
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
import sys
from zoneinfo import ZoneInfo

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from boundaries.hospital_api_boundary import HospitalApiResponseError, HospitalApiUnavailableError
from boundaries.pharmacy_api_boundary import PharmacyApiUnavailableError
from controls.check_nearby_hospital_control import CheckNearbyHospital
from core.config import settings
from entities.nearby_hospital_entity import HospitalDetails, HospitalLocationPage, HospitalLocationRecord
from schemas.hospital import HospitalSearchMode

KST = ZoneInfo("Asia/Seoul")
MONDAY = datetime(2026, 9, 28, 10, tzinfo=KST)


@pytest.fixture
def anyio_backend():
    """asyncio 제어 흐름을 검증한다."""
    return "asyncio"


class Calendar:
    # 필요한 날짜만 공휴일로 취급하거나 제공자 실패를 재현한다.
    def __init__(self, *holidays, unavailable=False):
        self.holidays, self.unavailable = holidays, unavailable

    async def isHoliday(self, value):
        """명시된 공휴일만 반환한다."""
        if self.unavailable:
            raise PharmacyApiUnavailableError("calendar unavailable")
        return value in self.holidays


class Boundary:
    # 페이지 크기 축소와 상세 캐시 적중을 재현한다.
    def __init__(self, details, *, size=30, records=None):
        self.details, self.size = details, size
        self.records = records or [record(identifier) for identifier in details]
        self.pages, self.loads, self.cached = [], [], set()

    async def fetchNearbyPage(self, *, page_no, page_size, **_):
        """제공자 페이지 크기에 맞춰 다음 구간을 반환한다."""
        self.pages.append((page_no, page_size))
        size = min(page_size, self.size)
        rows = self.records[(page_no - 1) * size:page_no * size]
        return HospitalLocationPage(tuple(rows), len(self.records), len(rows), size)

    def hasCachedDetails(self, hospital_id):
        """이미 확인한 ID는 새 상세 예산을 쓰지 않는다."""
        return hospital_id in self.cached

    async def fetchDetails(self, hospital_id):
        """상세 결과 또는 지정한 오류를 반환한다."""
        self.loads.append(hospital_id)
        self.cached.add(hospital_id)
        result = self.details[hospital_id]
        if isinstance(result, Exception):
            raise result
        return result


def record(identifier="A1", *, latitude=37.5665):
    """공유 지도 표시용 위치를 만든다."""
    return HospitalLocationRecord(identifier, "Test clinic", "Seoul", "", latitude, 126.978, "의원")


def detail(identifier="A1", *, departments=("내과",), hours=None):
    """요일별 상세 운영표를 구성한다."""
    return HospitalDetails(identifier, departments=departments,
                           weekly_hours=tuple((day, *times) for day, times in (hours or {}).items()))


async def search(boundary, *, calendar=None, **kwargs):
    """명시적 달력과 기준일로 결과를 계산한다."""
    control = CheckNearbyHospital(boundary, holiday_boundary=calendar or Calendar())
    return await control.requestNearbyHospitalSearch(latitude=37.5665, longitude=126.978,
                                                     target_datetime=kwargs.pop("target_datetime", MONDAY), **kwargs)


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
async def test_schedule_intervals_unknown_and_24_hours(start, end, hour, opened, late, full):
    """불완전·모호한 시각을 영업 또는 휴무로 단정하지 않는다."""
    result = await search(Boundary({"A1": detail(hours={"1": (start, end)})}),
                          target_datetime=MONDAY.replace(hour=hour))
    item = result.data[0]
    assert item.is_open_now is opened and item.is_open_late is late and item.is_24_hours is full
    assert item.institution_type == "의원"
    assert item.schedule_is_date_specific is False
    assert "pharmacy_id" not in item.model_dump() and "is_official_late_night" not in item.model_dump()


@pytest.mark.anyio
async def test_yesterday_holiday_carryover_and_close_countdown():
    """전날 공휴일의 자정 이후 운영 구간도 휴일 표에서 계산한다."""
    result = await search(Boundary({"A1": detail(hours={"8": ("2200", "0200")})}),
                          calendar=Calendar(date(2026, 9, 27)), target_datetime=MONDAY.replace(hour=1))
    assert result.data[0].is_open_now is True
    assert result.data[0].minutes_until_close == 60


@pytest.mark.anyio
async def test_registered_holiday_hours_only_and_no_actual_date_claim():
    """평일 공휴일에도 공휴일 전용 표만 선택한다."""
    boundary = Boundary({"A1": detail(hours={"1": ("0900", "1800"), "8": ("1000", "1300")}),
                         "A2": detail("A2", hours={"1": ("0900", "1800")})})
    result = await search(boundary, calendar=Calendar(MONDAY.date()), search_mode=HospitalSearchMode.WEEKEND_HOLIDAY)
    assert [item.hospital_id for item in result.data] == ["A1"]
    assert result.data[0].today_close_time == "13:00"
    assert result.data[0].schedule_source == "nemc_hospital_weekly_report"
    assert result.holiday_schedule_status == "weekly_report"
    assert not result.data[0].schedule_is_date_specific


@pytest.mark.anyio
async def test_calendar_outage_unknown_and_excluded_from_operating_modes():
    """공휴일 여부를 모르면 평일표를 대신 사용하지 않는다."""
    boundary = Boundary({"A1": detail(hours={"1": ("0900", "2300"), "8": ("0900", "2300")})})
    result = await search(boundary, calendar=Calendar(unavailable=True))
    assert result.data[0].is_open_now is None and result.data[0].today_open_time is None
    assert result.holiday_schedule_status == "unknown"
    for mode in (HospitalSearchMode.OPEN_AT_TIME, HospitalSearchMode.LATE_HOURS, HospitalSearchMode.WEEKEND_HOLIDAY):
        assert not (await search(boundary, calendar=Calendar(unavailable=True), search_mode=mode)).data


@pytest.mark.anyio
async def test_selected_weekend_and_timezone_normalization():
    """주말 검색은 선택한 날짜를 사용하고 UTC는 한국 시각으로 변환한다."""
    boundary = Boundary({"A1": detail(hours={"6": ("0900", "1300"), "1": ("0900", "1800")})})
    assert not (await search(boundary, search_mode=HospitalSearchMode.WEEKEND_HOLIDAY)).data
    weekend = await search(boundary, target_datetime=datetime(2026, 10, 3, 10), search_mode=HospitalSearchMode.WEEKEND_HOLIDAY)
    assert len(weekend.data) == 1
    normalized = await search(boundary, target_datetime=MONDAY.astimezone(timezone.utc))
    assert normalized.target_datetime == MONDAY and normalized.data[0].is_open_now is True


@pytest.mark.parametrize("code,names,match", [
    ("D001", ("내과",), True), ("D001", ("한방내과",), False),
    ("D022", ("가정의학과",), True), ("D016", ("재활의학과",), True),
    ("D026", ("치과보존과", "치과보철과"), True),
    ("D020", ("진단검사의학과",), True), ("D034", ("구강악안면외과",), True),
])
@pytest.mark.anyio
async def test_verified_department_names_and_aliases(code, names, match):
    """진료과명은 정확히 비교하고 공식 코드·명칭 변경만 연결한다."""
    result = await search(Boundary({"A1": detail(departments=names)}), department=code)
    assert bool(result.data) is match


@pytest.mark.anyio
async def test_capped_pagination_filter_before_limit_and_deduplication():
    """줄어든 페이지 크기로 다음 페이지를 읽고 중복을 제거한 후 제한한다."""
    boundary = Boundary({"A1": detail(departments=("한방내과",)), "A2": detail("A2")},
                        size=1, records=[record("A1"), record("A1"), record("A2")])
    result = await search(boundary, department="D001", limit=1)
    assert [item.hospital_id for item in result.data] == ["A2"]
    assert boundary.pages == [(1, 30), (2, 1), (3, 1)] and boundary.loads == ["A1", "A2"]


@pytest.mark.anyio
async def test_detail_budget_partial_and_filter_cache_reuse(monkeypatch):
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


@pytest.mark.anyio
async def test_partial_detail_failure_versus_complete_failure():
    """일부 상세 실패는 표시하고 모든 상세 실패는 서비스 오류로 반환한다."""
    boundary = Boundary({"A1": detail(), "A2": HospitalApiUnavailableError("failed")})
    result = await search(boundary)
    assert result.search_truncated and len(result.data) == 2
    for error in (HospitalApiUnavailableError, HospitalApiResponseError):
        with pytest.raises(error):
            await search(Boundary({"A1": error("failed")}))


@pytest.mark.anyio
async def test_radius_before_rounding_and_no_distant_detail_requests():
    """반경 밖 병원은 상세 호출 전 제외한다."""
    boundary = Boundary({"A1": detail(), "A2": detail("A2")},
                        records=[record("A2", latitude=38), record("A1")])
    result = await search(boundary, max_distance_km=0.1)
    assert [item.hospital_id for item in result.data] == ["A1"] and boundary.loads == ["A1"]


@pytest.mark.parametrize("kwargs", [{"department": "D999"}, {"limit": 31}, {"max_distance_km": float("nan")},
                                        {"search_mode": "official_late_night"}])
@pytest.mark.anyio
async def test_invalid_requests_rejected_before_network(kwargs):
    """미지원 진료과와 잘못된 범위는 빈 성공 응답이 아닌 검증 오류다."""
    boundary = Boundary({"A1": detail()})
    with pytest.raises(ValueError):
        await search(boundary, **kwargs)
    assert not boundary.pages


@pytest.mark.anyio
async def test_unknown_department_and_hours_are_incomplete_not_exhaustive():
    """필터 판단 근거가 누락되면 결과 없음도 부분 검색으로 표시한다."""
    boundary = Boundary({"A1": detail(departments=())})
    for filters in ({"department": "D001"}, {"search_mode": HospitalSearchMode.OPEN_AT_TIME}):
        result = await search(boundary, **filters)
        assert not result.data and result.search_truncated


@pytest.mark.anyio
async def test_small_all_limit_hydrates_only_visible_result():
    """전체 목록의 한 건 요청은 나머지 후보의 상세를 조회하지 않는다."""
    boundary = Boundary({f"A{index}": detail(f"A{index}") for index in range(30)})
    result = await search(boundary, limit=1)
    assert len(result.data) == 1 and len(boundary.loads) == 1


@pytest.mark.anyio
async def test_calendar_deadline_preserves_basic_list(monkeypatch):
    """달력이 지연되어도 기본 병원 목록은 미확인 시간으로 반환한다."""
    monkeypatch.setattr(settings, "HOSPITAL_CALENDAR_TIMEOUT_SECONDS", 0.01)

    class SlowCalendar:
        async def isHoliday(self, value):
            await asyncio.Event().wait()

    async with asyncio.timeout(0.5):
        result = await search(Boundary({"A1": detail(hours={"1": ("0900", "1800")})}), calendar=SlowCalendar())
    assert len(result.data) == 1 and result.data[0].is_open_now is None


@pytest.mark.anyio
async def test_unknown_previous_holiday_does_not_imply_closed():
    """전날 공휴일 여부가 불명확하면 야간 이월 가능성을 닫힘으로 숨기지 않는다."""
    class PartialCalendar:
        async def isHoliday(self, value):
            if value == MONDAY.date() - timedelta(days=1):
                raise PharmacyApiUnavailableError("previous month unavailable")
            return False

    result = await search(Boundary({"A1": detail(hours={"1": ("0900", "1800"), "8": ("2200", "0200")})}),
                          calendar=PartialCalendar(), target_datetime=MONDAY.replace(hour=1))
    assert result.data[0].is_open_now is None


@pytest.mark.anyio
async def test_operating_notes_are_preserved_and_not_ignored():
    """비정형 휴게시간 안내가 있으면 진료 중을 단정하지 않는다."""
    with_notes = replace(detail(hours={"1": ("0900", "1800")}), operating_notes="점심시간 전화 확인")
    result = await search(Boundary({"A1": with_notes}))
    assert result.data[0].operating_notes == with_notes.operating_notes
    assert result.data[0].is_open_now is None and result.data[0].minutes_until_close is None


@pytest.mark.parametrize("include_valid", [False, True])
@pytest.mark.anyio
async def test_skipped_location_rows_mark_empty_or_populated_results_partial(include_valid):
    """유효하지 않은 위치 행을 제외하면 빈 결과도 완전한 검색으로 표시하지 않는다."""
    class SkippedRowsBoundary(Boundary):
        async def fetchNearbyPage(self, **_):
            """원본 행 하나가 검증 중 제외된 페이지를 반환한다."""
            records = (record(),) if include_valid else ()
            raw_count = len(records) + 1
            return HospitalLocationPage(records, raw_count, raw_count, 30)

    result = await search(SkippedRowsBoundary({"A1": detail()}))
    assert [item.hospital_id for item in result.data] == (["A1"] if include_valid else [])
    assert result.search_truncated


class PageFailureBoundary(Boundary):
    # 지정 페이지에서만 오류를 내고 앞선 페이지의 정상 처리는 유지한다.
    def __init__(self, details, *, failed_page, error):
        super().__init__(details, size=1)
        self.failed_page, self.error = failed_page, error

    async def fetchNearbyPage(self, *, page_no, page_size, **kwargs):
        """오류 페이지 이후의 추가 조회가 없는지 확인할 수 있게 기록한다."""
        if page_no == self.failed_page:
            self.pages.append((page_no, page_size))
            raise self.error
        return await super().fetchNearbyPage(page_no=page_no, page_size=page_size, **kwargs)


@pytest.mark.parametrize("error_type", [HospitalApiUnavailableError, HospitalApiResponseError])
@pytest.mark.anyio
async def test_later_location_failure_retains_earlier_valid_matches(error_type):
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


@pytest.mark.parametrize("error_type", [HospitalApiUnavailableError, HospitalApiResponseError])
@pytest.mark.parametrize("filters", [
    {"department": "D001"},
    {"search_mode": HospitalSearchMode.OPEN_AT_TIME},
])
@pytest.mark.anyio
async def test_later_location_failure_keeps_empty_unknown_results_partial(error_type, filters):
    """이전 후보의 진료과·시간이 불명확해도 후속 장애를 확정적인 결과 없음으로 숨기지 않는다."""
    boundary = PageFailureBoundary(
        {"A1": detail(departments=()), "A2": detail("A2")},
        failed_page=2, error=error_type("provider failed"),
    )
    result = await search(boundary, **filters)
    assert result.data == [] and result.search_truncated
    assert boundary.pages == [(1, 30), (2, 1)] and boundary.loads == ["A1"]


@pytest.mark.parametrize("error_type", [HospitalApiUnavailableError, HospitalApiResponseError])
@pytest.mark.anyio
async def test_first_location_failure_still_propagates_to_http_error(error_type):
    """첫 페이지 장애는 부분 성공으로 바꾸지 않고 기존 503·502 매핑으로 전달한다."""
    error = error_type("provider failed")
    boundary = PageFailureBoundary({"A1": detail()}, failed_page=1, error=error)
    with pytest.raises(error_type) as caught:
        await search(boundary)
    assert caught.value is error
    assert boundary.pages == [(1, 30)] and not boundary.loads


@pytest.mark.anyio
async def test_weekday_holiday_filter_does_not_call_hospital_provider():
    """공휴일이 아닌 평일은 병원 API 장애와 무관하게 날짜 변경 대상으로 응답한다."""
    boundary = PageFailureBoundary(
        {"A1": detail()}, failed_page=1, error=HospitalApiUnavailableError("offline"),
    )
    result = await search(boundary, search_mode=HospitalSearchMode.WEEKEND_HOLIDAY)
    assert result.data == [] and not result.search_truncated
    assert result.holiday_schedule_status == "not_applicable"
    assert not boundary.pages and not boundary.loads


@pytest.mark.anyio
async def test_slow_followup_page_preserves_holiday_results(monkeypatch):
    """후속 위치 조회가 지연돼도 이미 확인한 공휴일 진료 병원은 보존한다."""
    monkeypatch.setattr(settings, "HOSPITAL_SEARCH_TIMEOUT_SECONDS", 1.05)

    class SlowPageBoundary(Boundary):
        async def fetchNearbyPage(self, *, page_no, page_size, **kwargs):
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


@pytest.mark.anyio
async def test_slow_detail_preserves_completed_holiday_results(monkeypatch):
    """한 병원의 상세가 늦어도 완료된 결과는 반환하고 대기 작업은 회수한다."""
    monkeypatch.setattr(settings, "HOSPITAL_SEARCH_TIMEOUT_SECONDS", 1.05)
    cancelled = asyncio.Event()

    class SlowDetailBoundary(Boundary):
        async def fetchDetails(self, hospital_id):
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


@pytest.mark.anyio
async def test_first_page_timeout_is_not_an_empty_success(monkeypatch):
    """위치 정보조차 받지 못한 시간 초과는 결과 없음으로 바꾸지 않는다."""
    monkeypatch.setattr(settings, "HOSPITAL_SEARCH_TIMEOUT_SECONDS", 1.05)

    class SlowBoundary(Boundary):
        async def fetchNearbyPage(self, **kwargs):
            await asyncio.Event().wait()

    with pytest.raises(HospitalApiUnavailableError):
        await search(SlowBoundary({"A1": detail()}))
