# 파일명: test_hospital_department_search.py
# 역할: 진료과 선조회, 지역 경계, 페이지 완료 후 거리 정렬과 부분 검색 표시를 검증한다.

"""진료과 선조회, 지역 경계, 전 페이지 정렬과 부분 결과 표시를 검증한다."""

import asyncio
from datetime import datetime
from pathlib import Path
import sys
from zoneinfo import ZoneInfo

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from boundaries.hospital_api_boundary import HospitalApiUnavailableError
from controls.check_nearby_hospital_control import CheckNearbyHospital
from controls.hospital_department_search import DepartmentCandidates, _PROVINCE_ALIASES, _region, find_department_candidates
from core.config import settings
from entities.nearby_hospital_entity import HospitalDetails, HospitalLocationPage, HospitalLocationRecord


# 함수이름: anyio_backend
# 함수역할:
# - 호출 예산과 취소 동작을 asyncio에서 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - str; asyncio.
@pytest.fixture
def anyio_backend() -> str:
    """호출 예산과 취소 동작을 asyncio에서 검증한다."""
    return "asyncio"


# 함수이름: record
# 함수역할:
# - 가까운 순서와 행정구역을 독립적으로 조절하는 위치 자료.
# 매개변수:
# - identifier: str; 합성 병원 식별자.
# - district: str; 조회 지역의 시군구.
# - lat: float; 기준 위도.
# 반환값:
# - HospitalLocationRecord; 지정 지역과 위도의 합성 병원.
def record(identifier: str, district: str = "마포구", lat: float = 37.55) -> HospitalLocationRecord:
    """가까운 순서와 행정구역을 독립적으로 조절하는 위치 자료."""
    return HospitalLocationRecord(identifier, identifier, f"서울특별시 {district} 테스트로", "", lat, 126.92)


# 클래스명: Boundary
# 역할: 지역 탐색 목록과 진료과별 후보 목록을 분리하는 병원 제공자.
# 주요 책임:
# - 페이지·지역별 실패와 상세 호출을 기록하여 선조회 순서를 검증한다.
# 속성:
# - regions/lists: 지역·후보 자료; page_size: 행 제한; location_calls/department_calls/details: 조회 기록; fail_region/fail_page/incomplete_regions: 오류·불완전 응답 설정.
class Boundary:
    """좌표 목록에는 타 과목을, 진료과 목록에는 선택 과목만 담는 제공자 대역."""
    # 함수이름: __init__
    # 함수역할:
    # - 가까운 병원과 먼 병원의 기본 자료, 한 행 페이지와 빈 호출 기록을 준비한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - None.
    def __init__(self) -> None:
        self.regions = [record("Other")]
        self.lists = {"마포구": [record("Far", lat=37.558), record("Near", lat=37.55)]}
        self.page_size = 1
        self.location_calls, self.department_calls, self.details = [], [], []
        self.fail_region = None
        self.fail_page = None
        self.incomplete_regions = False

    # 함수이름: fetchNearbyPage
    # 함수역할:
    # - 지역 파악만 제공하며 상세 조회에 이 ID를 사용해서는 안 된다.
    # 매개변수:
    # - kwargs: dict; 위치 좌표 또는 진료과 페이지 조건.
    # 반환값:
    # - HospitalLocationPage; 지역 탐색용 위치. 북쪽 실패 대역은 HospitalApiUnavailableError.
    async def fetchNearbyPage(self, **kwargs: float) -> HospitalLocationPage:
        """지역 파악만 제공하며 상세 조회에 이 ID를 사용해서는 안 된다."""
        self.location_calls.append(kwargs)
        return HospitalLocationPage(tuple(self.regions), 999 if self.incomplete_regions else len(self.regions),
                                    len(self.regions), 30)

    # 함수이름: fetchDepartmentPage
    # 함수역할:
    # - QD 전달과 지역별 페이지 진행을 기록한다.
    # 매개변수:
    # - province: str; 정규화된 시도.
    # - district: str; 조회 지역의 시군구.
    # - department: str; 공식 진료과 코드.
    # - page_no: int; 1부터 시작하는 페이지.
    # - page_size: int; 요청할 행 수.
    # 반환값:
    # - HospitalLocationPage; 해당 지역 페이지. 지정 실패에는 HospitalApiUnavailableError 또는 TimeoutError.
    async def fetchDepartmentPage(self, *, province: str, district: str, department: str, page_no: int, page_size: int) -> HospitalLocationPage:
        """QD 전달과 지역별 페이지 진행을 기록한다."""
        self.department_calls.append((province, district, department, page_no, page_size))
        if district == self.fail_region or page_no == self.fail_page:
            raise HospitalApiUnavailableError("test failure")
        rows = self.lists.get(district, [])
        size = min(page_size, self.page_size)
        selected = rows[(page_no - 1) * size:page_no * size]
        return HospitalLocationPage(tuple(selected), len(rows), len(selected), size)

    # 함수이름: hasCachedDetails
    # 함수역할:
    # - 첫 검색의 신규 상세 예산만 검사한다.
    # 매개변수:
    # - identifier: str; 합성 병원 식별자.
    # 반환값:
    # - bool; 항상 False로 신규 상세 예산 사용.
    def hasCachedDetails(self, identifier: str) -> bool:
        """첫 검색의 신규 상세 예산만 검사한다."""
        return False

    # 함수이름: fetchDetails
    # 함수역할:
    # - 진료과 목록 밖의 상세가 요청되면 테스트를 실패시킨다.
    # 매개변수:
    # - identifier: str; 합성 병원 식별자.
    # 반환값:
    # - HospitalDetails; 내과·월요일 운영표. 타 과목 탐색 ID는 AssertionError.
    async def fetchDetails(self, identifier: str) -> HospitalDetails:
        """진료과 목록 밖의 상세가 요청되면 테스트를 실패시킨다."""
        assert identifier != "Other"
        self.details.append(identifier)
        return HospitalDetails(identifier, departments=("내과",), weekly_hours=(("1", "0900", "1800"),))


# 함수이름: candidates
# 함수역할:
# - 1km 지역의 선조회 후보를 실시간 달력 없이 검사한다.
# 매개변수:
# - boundary: Boundary; 기록용 병원 제공자.
# - radius: float; 검색 반경(km).
# 반환값:
# - 진료과 후보 결과; 정렬된 위치와 불완전·지역 불확실성 상태.
async def candidates(boundary: Boundary, *, radius: float = 1) -> DepartmentCandidates:
    """1km 지역의 선조회 후보를 실시간 달력 없이 검사한다."""
    return await find_department_candidates(boundary, latitude=37.55, longitude=126.92,
        radius_km=radius, department="D001", deadline=asyncio.get_running_loop().time() + 2)


# Function Name: test_department_before_detail_and_all_pages_before_distance_limit
# Description:
# - Requires department pagination to finish before distance sorting and the one-detail budget select the nearest matching hospital.
# Parameters:
# - monkeypatch: pytest.MonkeyPatch; restores temporary dependency replacements.
# Returns:
# - None.
@pytest.mark.anyio
async def test_department_before_detail_and_all_pages_before_distance_limit(monkeypatch: pytest.MonkeyPatch) -> None:
    """마지막 페이지의 가까운 병원이 앞 페이지의 먼 병원·타 과목에 밀리지 않는다."""
    monkeypatch.setattr(settings, "HOSPITAL_DETAIL_REQUEST_BUDGET", 1)
    boundary = Boundary()
    # 조회일 허용 범위가 실제 오늘이 아닌 고정 기준일로 계산되도록 시계를 함께 고정한다.
    monday = datetime(2026, 9, 28, 10, tzinfo=ZoneInfo("Asia/Seoul"))
    result = await CheckNearbyHospital(boundary, clock=lambda: monday).requestNearbyHospitalSearch(
        latitude=37.55, longitude=126.92, max_distance_km=1, department="D001", limit=1,
        target_datetime=datetime(2026, 9, 28, 10),
    )
    assert [item.hospital_id for item in result.data] == ["Near"]
    assert boundary.details == ["Near"]
    assert boundary.department_calls == [("서울특별시", "마포구", "D001", 1, 100),
                                         ("서울특별시", "마포구", "D001", 2, 1)]


# 함수이름: test_cross_district_candidates_merge_deduplicate_then_sort
# 함수역할:
# - 양쪽 구의 결과를 합쳐 가까운 순으로 정렬하고 중복 ID는 한 번만 사용한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_cross_district_candidates_merge_deduplicate_then_sort() -> None:
    """양쪽 구의 결과를 합쳐 가까운 순으로 정렬하고 중복 ID는 한 번만 사용한다."""
    boundary = Boundary()
    boundary.regions.append(record("Border", "서대문구"))
    boundary.lists["서대문구"] = [record("Near", "서대문구"), record("Across", "서대문구", 37.551)]
    result = await candidates(boundary)
    assert [row.hospital_id for row in result.records] == ["Near", "Across", "Far"]
    assert not result.partial
    assert {call[1] for call in boundary.department_calls[:2]} == {"마포구", "서대문구"}


# 함수이름: test_radius_filter_before_detail_and_complete_empty_result
# 함수역할:
# - 지역 전체 목록 중 반경 밖 병원은 상세 조회 후보에서 제외한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_radius_filter_before_detail_and_complete_empty_result() -> None:
    """지역 전체 목록 중 반경 밖 병원은 상세 조회 후보에서 제외한다."""
    boundary = Boundary()
    boundary.lists["마포구"] = [record("Outside", lat=38)]
    result = await candidates(boundary)
    assert not result.records and not result.partial and not boundary.details


# 함수이름: test_page_budget_does_not_claim_complete_empty_result
# 함수역할:
# - 선택 진료과만 조회해도 마지막 페이지를 못 읽었으면 부분 결과다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_page_budget_does_not_claim_complete_empty_result(monkeypatch: pytest.MonkeyPatch) -> None:
    """선택 진료과만 조회해도 마지막 페이지를 못 읽었으면 부분 결과다."""
    monkeypatch.setattr(settings, "HOSPITAL_DEPARTMENT_MAX_PAGES", 1)
    boundary = Boundary()
    boundary.lists["마포구"] = [record("Outside", lat=38), record("Near")]
    result = await candidates(boundary)
    assert not result.records and result.partial
    assert len(boundary.department_calls) == 1


# 함수이름: test_discovery_sample_is_not_a_department_pagination_limit
# 함수역할:
# - 보조 주소 목록이 길어도 진료과 목록을 다 받으면 실제 조회 제한은 아니다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_discovery_sample_is_not_a_department_pagination_limit() -> None:
    """보조 주소 목록이 길어도 진료과 목록을 다 받으면 실제 조회 제한은 아니다."""
    boundary = Boundary()
    boundary.incomplete_regions = True
    result = await candidates(boundary)
    assert not result.partial and result.region_scope_uncertain
    assert len(boundary.location_calls) == 5
    assert len({(call['latitude'], call['longitude']) for call in boundary.location_calls}) == 5


# 함수이름: test_sampled_region_with_one_or_no_matches_is_not_truncated
# 함수역할:
# - 한 건·빈 결과 모두 지역 표본의 한계만 전달하고 조회 제한을 만들지 않는다.
# 매개변수:
# - inside: bool; 유일 후보가 검색 반경 안에 있는지 지정한다.
# 반환값:
# - None.
@pytest.mark.parametrize("inside", [True, False])
@pytest.mark.anyio
async def test_sampled_region_with_one_or_no_matches_is_not_truncated(inside: bool) -> None:
    """한 건·빈 결과 모두 지역 표본의 한계만 전달하고 조회 제한을 만들지 않는다."""
    boundary = Boundary()
    boundary.incomplete_regions = True
    boundary.lists["마포구"] = [record("Only", lat=37.55 if inside else 38)]
    result = await CheckNearbyHospital(boundary).requestNearbyHospitalSearch(
        latitude=37.55, longitude=126.92, max_distance_km=.5, department="D001",
    )
    assert len(result.data) == int(inside)
    assert not result.search_truncated and result.region_scope_uncertain


# 함수이름: test_actual_department_limit_still_warns_with_sampled_regions
# 함수역할:
# - 지역 표본을 구별해도 실제 진료과 목록 페이지 제한은 숨기지 않는다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_actual_department_limit_still_warns_with_sampled_regions(monkeypatch: pytest.MonkeyPatch) -> None:
    """지역 표본을 구별해도 실제 진료과 목록 페이지 제한은 숨기지 않는다."""
    monkeypatch.setattr(settings, "HOSPITAL_DEPARTMENT_MAX_PAGES", 1)
    boundary = Boundary()
    boundary.incomplete_regions = True
    result = await CheckNearbyHospital(boundary).requestNearbyHospitalSearch(
        latitude=37.55, longitude=126.92, max_distance_km=1, department="D001",
    )
    assert len(result.data) == 1
    assert result.search_truncated and result.region_scope_uncertain


# 함수이름: test_failed_region_probe_keeps_partial_warning
# 함수역할:
# - 주소 탐색 자체가 실패한 경우는 단순히 표본을 사용한 경우와 구분한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_failed_region_probe_keeps_partial_warning() -> None:
    """주소 탐색 자체가 실패한 경우는 단순히 표본을 사용한 경우와 구분한다."""
    # 클래스명: FailedProbe
    # 역할: 북쪽 지역 탐색만 실패시키는 제공자.
    # 주요 책임:
    # - 다른 탐색 결과를 보존한 부분 검색을 재현한다.
    # 속성:
    # - Boundary 속성 상속.
    class FailedProbe(Boundary):
        # 함수이름: fetchNearbyPage
        # 함수역할:
        # - 중심 북쪽의 한 탐색만 실패시킨다.
        # 매개변수:
        # - kwargs: dict; 위치 좌표 또는 진료과 페이지 조건.
        # 반환값:
        # - HospitalLocationPage; 지역 탐색용 위치. 북쪽 실패 대역은 HospitalApiUnavailableError.
        async def fetchNearbyPage(self, **kwargs: float) -> HospitalLocationPage:
            """중심 북쪽의 한 탐색만 실패시킨다."""
            if kwargs["latitude"] > 37.55:
                raise HospitalApiUnavailableError("test failure")
            return await super().fetchNearbyPage(**kwargs)

    result = await candidates(FailedProbe())
    assert result.partial and result.records


# 함수이름: test_short_and_full_seoul_addresses_share_one_region_without_warning
# 함수역할:
# - 실제 홍대 주소의 '서울 마포구' 축약명을 오류나 별개 지역으로 처리하지 않는다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_short_and_full_seoul_addresses_share_one_region_without_warning() -> None:
    """실제 홍대 주소의 '서울 마포구' 축약명을 오류나 별개 지역으로 처리하지 않는다."""
    boundary = Boundary()
    boundary.regions.append(HospitalLocationRecord(
        "Short", "Short", "서울 마포구 서강로 106", "", 37.55, 126.92,
    ))
    boundary.incomplete_regions = True
    boundary.page_size = 100
    result = await candidates(boundary)
    assert not result.partial and result.region_scope_uncertain
    assert boundary.department_calls == [("서울특별시", "마포구", "D001", 1, 100)]


# 함수이름: test_provider_short_province_names_use_explicit_aliases
# 함수역할:
# - 시도 축약명만 정규화하고 시군구나 병원명에서 지역을 추측하지 않는다.
# 매개변수:
# - short: str; 제공자 주소의 시도 축약명.
# - full: str; 대응하는 공식 시도명.
# 반환값:
# - None.
@pytest.mark.parametrize("short,full", _PROVINCE_ALIASES.items())
def test_provider_short_province_names_use_explicit_aliases(short: str, full: str) -> None:
    """시도 축약명만 정규화하고 시군구나 병원명에서 지역을 추측하지 않는다."""
    district = "" if full == "세종특별자치시" else "테스트구"
    assert _region(f"{short} {district} 테스트로") == (full, district)


# 함수이름: test_later_page_error_keeps_known_candidates
# 함수역할:
# - 후속 진료과 페이지 장애가 앞에서 찾은 병원을 지우지 않는다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_later_page_error_keeps_known_candidates() -> None:
    """후속 진료과 페이지 장애가 앞에서 찾은 병원을 지우지 않는다."""
    boundary = Boundary()
    boundary.fail_page = 2
    result = await candidates(boundary)
    assert result.partial and [r.hospital_id for r in result.records] == ["Far"]


# 함수이름: test_regional_search_preserves_department_and_radius
# 함수역할:
# - 다른 시도·일반구·구 없는 시·읍 지역에서도 지역 코드와 반경을 유지한다.
# 매개변수:
# - address: str; 제공자 주소 문자열.
# - province: str; 정규화된 시도.
# - district: str; 조회 지역의 시군구.
# - lat: float; 기준 위도.
# - lon: float; 기준 경도.
# 반환값:
# - None.
@pytest.mark.parametrize("address,province,district,lat,lon", [
    ("경기 수원시 영통구 효원로 397", "경기도", "수원시", 37.2596, 127.0465),
    ("세종 한누리대로 2129", "세종특별자치시", "", 36.4800, 127.2890),
    ("부산 연제구 중앙대로 1033", "부산광역시", "연제구", 35.1796, 129.0756),
    ("제주 제주시 애월읍", "제주특별자치도", "제주시", 33.3600, 126.3560),
])
@pytest.mark.anyio
async def test_regional_search_preserves_department_and_radius(address: str, province: str, district: str, lat: float, lon: float) -> None:
    """다른 시도·일반구·구 없는 시·읍 지역에서도 지역 코드와 반경을 유지한다."""
    boundary = Boundary()
    near = HospitalLocationRecord("Near", "Near", address, "", lat, lon)
    far = HospitalLocationRecord("Far", "Far", address, "", lat + .1, lon)
    boundary.regions = [near]
    boundary.lists = {district: [far, near]}
    result = await find_department_candidates(
        boundary, latitude=lat, longitude=lon, radius_km=.3, department="D026",
        deadline=asyncio.get_running_loop().time() + 2,
    )
    assert [row.hospital_id for row in result.records] == ["Near"]
    assert all(call[:3] == (province, district, "D026") for call in boundary.department_calls)
    assert not result.partial


# 함수이름: test_one_region_failure_preserves_other_region
# 함수역할:
# - 구 하나가 실패해도 다른 구의 결과를 부분 조회로 돌려준다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_one_region_failure_preserves_other_region() -> None:
    """구 하나가 실패해도 다른 구의 결과를 부분 조회로 돌려준다."""
    boundary = Boundary()
    boundary.regions.append(record("OtherRegion", "서대문구"))
    boundary.fail_region = "서대문구"
    result = await candidates(boundary)
    assert len(result.records) == 2 and result.partial


# 함수이름: test_all_region_failure_is_not_successful_empty
# 함수역할:
# - 모든 진료과 조회 실패는 기존 서비스 오류로 전달한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_all_region_failure_is_not_successful_empty() -> None:
    """모든 진료과 조회 실패는 기존 서비스 오류로 전달한다."""
    boundary = Boundary()
    boundary.fail_region = "마포구"
    with pytest.raises(HospitalApiUnavailableError):
        await candidates(boundary)


# 함수이름: test_unknown_address_does_not_guess_region_or_query_all_country
# 함수역할:
# - 지역 주소를 얻지 못하면 전국 전체 조회나 잘못된 빈 결과로 대체하지 않는다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_unknown_address_does_not_guess_region_or_query_all_country() -> None:
    """지역 주소를 얻지 못하면 전국 전체 조회나 잘못된 빈 결과로 대체하지 않는다."""
    boundary = Boundary()
    boundary.regions = []
    with pytest.raises(HospitalApiUnavailableError):
        await candidates(boundary)
    assert not boundary.department_calls


# 함수이름: test_provider_region_address_contract
# 함수역할:
# - 주소 계약과 특별자치시·일반구의 검색 범위를 명시한다.
# 매개변수:
# - address: str; 제공자 주소 문자열.
# - region: tuple[str, str] | None; 예상 시도·시군구 또는 파싱 실패.
# 반환값:
# - None.
@pytest.mark.parametrize("address,region", [
    ("서울특별시 마포구 월드컵로", ("서울특별시", "마포구")),
    ("경기도 수원시 영통구", ("경기도", "수원시")),
    ("세종특별자치시 한누리대로", ("세종특별자치시", "")),
    ("강원특별자치도 춘천시", ("강원특별자치도", "춘천시")),
    ("서울특별시", None), ("알 수 없는 주소", None),
])
def test_provider_region_address_contract(address: str, region: tuple[str, str] | None) -> None:
    """주소 계약과 특별자치시·일반구의 검색 범위를 명시한다."""
    assert _region(address) == region


# 함수이름: test_expired_deadline_does_not_start_provider_calls
# 함수역할:
# - 이미 소진된 제한 시간에는 위치·진료과 요청을 새로 보내지 않는다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_expired_deadline_does_not_start_provider_calls() -> None:
    """이미 소진된 제한 시간에는 위치·진료과 요청을 새로 보내지 않는다."""
    boundary = Boundary()
    with pytest.raises(HospitalApiUnavailableError):
        await find_department_candidates(boundary, latitude=37.55, longitude=126.92,
            radius_km=1, department="D001", deadline=asyncio.get_running_loop().time() - 1)
    assert not boundary.location_calls and not boundary.department_calls


# 함수이름: test_later_timeout_preserves_results_without_starting_more_pages
# 함수역할:
# - 느린 후속 페이지가 시간을 소진하면 나머지 지역의 호출도 중지한다.
# 매개변수:
# - wait_for_deadline: bool; 시간 제한까지 대기할지 즉시 TimeoutError를 낼지 지정한다.
# 반환값:
# - None.
@pytest.mark.anyio
@pytest.mark.parametrize("wait_for_deadline", [True, False])
async def test_later_timeout_preserves_results_without_starting_more_pages(wait_for_deadline: bool) -> None:
    """느린 후속 페이지가 시간을 소진하면 나머지 지역의 호출도 중지한다."""
    # 클래스명: SlowBoundary
    # 역할: 후속 진료과 페이지에서 시간 초과를 재현하는 제공자.
    # 주요 책임:
    # - 두 번째 페이지를 지연하거나 즉시 TimeoutError를 발생시킨다.
    # 속성:
    # - Boundary 속성 상속; 외부 wait_for_deadline으로 실패 방식을 선택한다.
    class SlowBoundary(Boundary):
        # 함수이름: fetchDepartmentPage
        # 함수역할:
        # - 두 번째 페이지에서만 제한 시간까지 대기한다.
        # 매개변수:
        # - kwargs: dict; 위치 좌표 또는 진료과 페이지 조건.
        # 반환값:
        # - HospitalLocationPage; 해당 지역 페이지. 지정 실패에는 HospitalApiUnavailableError 또는 TimeoutError.
        async def fetchDepartmentPage(self, **kwargs: str | int) -> HospitalLocationPage:
            """두 번째 페이지에서만 제한 시간까지 대기한다."""
            if kwargs["page_no"] == 2:
                self.department_calls.append(tuple(kwargs[key] for key in (
                    "province", "district", "department", "page_no", "page_size")))
                if not wait_for_deadline:
                    raise TimeoutError()
                await asyncio.sleep(60)
            return await super().fetchDepartmentPage(**kwargs)

    boundary = SlowBoundary()
    boundary.regions.append(record("Border", "서대문구"))
    boundary.lists["서대문구"] = [record("Across", "서대문구"), record("Next", "서대문구")]
    result = await find_department_candidates(boundary, latitude=37.55, longitude=126.92,
        radius_km=1, department="D001", deadline=asyncio.get_running_loop().time() + .05)
    assert result.partial
    assert {record.hospital_id for record in result.records} == {"Far", "Across"}
    assert len(boundary.department_calls) == 3
