# 파일명: test_hospital_api_boundary.py
# 역할: 병원 API의 XML 검증, 키 선택, 캐시·동시 조회 및 호출 예산을 검증한다.

"""병원 API의 실제 XML 형태, 호출 예산과 캐시를 검증한다."""

import asyncio
from datetime import date
from pathlib import Path
import sys
from typing import NoReturn

import httpx
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from boundaries.hospital_api_boundary import (
    HospitalApiBudgetExhaustedError, HospitalApiResponseError, HospitalApiUnavailableError,
    NationalEmergencyMedicalCenterHospitalAPI,
)
from core.config import settings


# 함수이름: anyio_backend
# 함수역할:
# - 공유 비동기 경계는 asyncio에서 실행한다.
# 매개변수:
# - 없음.
# 반환값:
# - str; asyncio.
@pytest.fixture
def anyio_backend() -> str:
    """공유 비동기 경계는 asyncio에서 실행한다."""
    return "asyncio"


# 함수이름: credentials
# 함수역할:
# - 실제 로컬 인증키를 테스트 요청에 사용하지 않는다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.fixture(autouse=True)
def credentials(monkeypatch: pytest.MonkeyPatch) -> None:
    """실제 로컬 인증키를 테스트 요청에 사용하지 않는다."""
    monkeypatch.setattr(settings, "PUBLIC_DATA_API_KEY", "fallback-test-key")
    monkeypatch.setattr(settings, "HOSPITAL_API_KEY", "")


# 함수이름: envelope
# 함수역할:
# - 제공자의 대소문자와 페이지 구조를 재현한다.
# 매개변수:
# - items: str; XML items 안에 넣을 행.
# - page: int; 응답 페이지 번호.
# - size: int; 제공자가 보고한 페이지 크기.
# - total: int; 전체 원본 행 수.
# - code: str; 제공자 결과 코드.
# 반환값:
# - bytes; 페이지 메타데이터를 포함한 XML 응답.
def envelope(items: str = "", *, page: int = 1, size: int = 30, total: int = 1, code: str = "00") -> bytes:
    """제공자의 대소문자와 페이지 구조를 재현한다."""
    return f"""<response><header><resultCode>{code}</resultCode></header><body>
    <items>{items}</items><pageNo>{page}</pageNo><numOfRows>{size}</numOfRows>
    <totalCount>{total}</totalCount></body></response>""".encode()


# 함수이름: location
# 함수역할:
# - 위치 응답에는 기관 유형만 있고 진료과는 없다.
# 매개변수:
# - identifier: str; 응답 병원 식별자.
# - lat: str; XML 위도 필드.
# - lon: str; XML 경도 필드.
# 반환값:
# - str; 기관 유형과 좌표를 담은 위치 XML 행.
def location(identifier: str = "A1", *, lat: str = "37.5665", lon: str = "126.978") -> str:
    """위치 응답에는 기관 유형만 있고 진료과는 없다."""
    return f"""<item><hpid>{identifier}</hpid><dutyName>Test clinic</dutyName>
    <latitude>{lat}</latitude><longitude>{lon}</longitude><dutyDivName>의원</dutyDivName>
    <cnt>999999</cnt><startTime>0900</startTime><endTime>1800</endTime></item>"""


# 함수이름: detail
# 함수역할:
# - 실제 상세의 진료과 CSV와 생략된 요일을 재현한다.
# 매개변수:
# - identifier: str; 응답 병원 식별자.
# 반환값:
# - str; 중복 진료과와 일부 시간표를 담은 상세 XML 행.
def detail(identifier: str = "A1") -> str:
    """실제 상세의 진료과 CSV와 생략된 요일을 재현한다."""
    return f"""<item><hpid>{identifier}</hpid><dgidIdName>내과, 피부과,내과</dgidIdName>
    <dutyTime1s>0900</dutyTime1s><dutyTime1c>1800</dutyTime1c>
    <dutyEryn>1</dutyEryn></item>"""


# Function Name: test_location_capped_pages_and_actual_fields
# Description:
# - Checks provider page-size and totalCount parsing, institution fields, nearby-coordinate cache reuse and ownership of the injected client.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_location_capped_pages_and_actual_fields() -> None:
    """서버가 줄인 페이지 크기와 totalCount를 신뢰하고 cnt는 무시한다."""
    requests = []

    # 함수이름: handle
    # 함수역할:
    # - 요청을 기록하고 제공자가 페이지 크기를 10으로 줄인 위치 XML을 반환한다.
    # 매개변수:
    # - request: httpx.Request; 대체 전송기가 받은 요청.
    # 반환값:
    # - httpx.Response; 지정 XML 또는 오류 본문을 담은 HTTP 200 응답.
    def handle(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, content=envelope(location(), size=10, total=41))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        api = NationalEmergencyMedicalCenterHospitalAPI(client=client)
        result = await api.fetchNearbyPage(latitude=37.5, longitude=127, page_no=1, page_size=30)
        assert result.total_count == 41 and result.page_size == 10 and result.row_count == 1
        assert result.records[0].institution_type == "의원"
        assert requests[0].url.path.endswith("/getHsptlMdcncLcinfoInqire")
        assert requests[0].url.params["serviceKey"] == "fallback-test-key"
        assert requests[0].url.params["WGS84_LAT"] == "37.500"
        assert "QD" not in requests[0].url.params
        # 약 100 m 격자 안에서 좌표만 조금 바꾼 검색은 제공자를 다시 부르지 않는다.
        await api.fetchNearbyPage(
            latitude=37.5001234, longitude=127.0003456, page_no=1, page_size=30,
        )
        assert len(requests) == 1
        await api.close()
        assert not client.is_closed


# 함수이름: test_details_key_override_and_department_parsing
# 함수역할:
# - 별도 키를 우선하고 상세 진료과를 정리하며 누락 시간을 보존한다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_details_key_override_and_department_parsing(monkeypatch: pytest.MonkeyPatch) -> None:
    """별도 키를 우선하고 상세 진료과를 정리하며 누락 시간을 보존한다."""
    monkeypatch.setattr(settings, "HOSPITAL_API_KEY", "hospital%2Bkey%3D")

    # 함수이름: handle
    # 함수역할:
    # - 병원 전용 키·상세 경로·병원 ID를 검증한 뒤 상세 XML을 반환한다.
    # 매개변수:
    # - request: httpx.Request; 대체 전송기가 받은 요청.
    # 반환값:
    # - httpx.Response; 지정 XML 또는 오류 본문을 담은 HTTP 200 응답.
    def handle(request: httpx.Request) -> httpx.Response:
        assert request.url.params["serviceKey"] == "hospital+key="
        assert request.url.params["HPID"] == "A1"
        assert request.url.path.endswith("/getHsptlBassInfoInqire")
        return httpx.Response(200, content=envelope(detail()))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        result = await NationalEmergencyMedicalCenterHospitalAPI(client=client).fetchDetails("A1")
    assert result.departments == ("내과", "피부과")
    assert result.department_codes == () and result.institution_type is None
    assert result.weekly_hours[-1] == ("8", "", "")


# 함수이름: test_department_page_filters_provider_and_separates_cache
# 함수역할:
# - 진료과·지역은 요청과 캐시 키에 포함되고 좌표 조회와 혼합되지 않는다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_department_page_filters_provider_and_separates_cache() -> None:
    """진료과·지역은 요청과 캐시 키에 포함되고 좌표 조회와 혼합되지 않는다."""
    calls = []

    # 함수이름: handle
    # 함수역할:
    # - 진료과 전용 경로와 지역 조건을 검증·기록하고 위치 XML을 반환한다.
    # 매개변수:
    # - request: httpx.Request; 대체 전송기가 받은 요청.
    # 반환값:
    # - httpx.Response; 지정 XML 또는 오류 본문을 담은 HTTP 200 응답.
    def handle(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        assert request.url.path.endswith('/getHsptlMdcncListInfoInqire')
        assert request.url.params['Q0'] == '서울특별시'
        assert request.url.params['Q1'] == '마포구'
        assert 'WGS84_LAT' not in request.url.params
        return httpx.Response(200, content=envelope(location(), size=100))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        api = NationalEmergencyMedicalCenterHospitalAPI(client=client)
        for code in ('D001', 'D001', 'D013'):
            page = await api.fetchDepartmentPage(province='서울특별시', district='마포구',
                department=code, page_no=1, page_size=100)
            assert page.records[0].hospital_id == 'A1'
        assert len(calls) == 2
        assert [call.url.params['QD'] for call in calls] == ['D001', 'D013']


# 함수이름: test_department_page_sejong_omits_district_and_rejects_bad_query
# 함수역할:
# - 시군구가 없는 세종시와 잘못된 조회 조건을 구별한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_department_page_sejong_omits_district_and_rejects_bad_query() -> None:
    """시군구가 없는 세종시와 잘못된 조회 조건을 구별한다."""
    # 함수이름: handle
    # 함수역할:
    # - 세종 조회에 시군구 조건이 없음을 확인하고 빈 목록 XML을 반환한다.
    # 매개변수:
    # - request: httpx.Request; 대체 전송기가 받은 요청.
    # 반환값:
    # - httpx.Response; 지정 XML 또는 오류 본문을 담은 HTTP 200 응답.
    def handle(request: httpx.Request) -> httpx.Response:
        assert 'Q1' not in request.url.params
        return httpx.Response(200, content=envelope('', size=100, total=0))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        api = NationalEmergencyMedicalCenterHospitalAPI(client=client)
        query = dict(province='세종특별자치시', district='', department='D001', page_no=1, page_size=100)
        assert not (await api.fetchDepartmentPage(**query)).records
        for changes in ({'department':'내과'}, {'page_size':101}, {'page_no':0}, {'province':''}):
            with pytest.raises(ValueError):
                await api.fetchDepartmentPage(**dict(query, **changes))


# 함수이름: test_cache_coalescing_ttl_and_cancelled_waiter
# 함수역할:
# - 동시 요청·취소·만료가 호출 증폭이나 캐시 손상을 만들지 않는다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_cache_coalescing_ttl_and_cancelled_waiter(monkeypatch: pytest.MonkeyPatch) -> None:
    """동시 요청·취소·만료가 호출 증폭이나 캐시 손상을 만들지 않는다."""
    tick = [0.0]
    gate = asyncio.Event()
    calls = []

    # 함수이름: handle
    # 함수역할:
    # - 요청을 기록하고 이벤트 해제까지 응답을 지연한 뒤 상세 XML을 반환한다.
    # 매개변수:
    # - request: httpx.Request; 대체 전송기가 받은 요청.
    # 반환값:
    # - httpx.Response; 지정 XML 또는 오류 본문을 담은 HTTP 200 응답.
    async def handle(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        await gate.wait()
        return httpx.Response(200, content=envelope(detail()))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        api = NationalEmergencyMedicalCenterHospitalAPI(client=client, clock=lambda: tick[0])
        first = asyncio.create_task(api.fetchDetails("A1"))
        second = asyncio.create_task(api.fetchDetails("A1"))
        await asyncio.sleep(0)
        await asyncio.sleep(0)
        first.cancel()
        with pytest.raises(asyncio.CancelledError):
            await first
        gate.set()
        await second
        assert len(calls) == 1 and api.hasCachedDetails("A1")
        tick[0] = settings.HOSPITAL_DETAIL_CACHE_SECONDS - 1
        await api.fetchDetails("A1")
        assert len(calls) == 1
        tick[0] += 2
        await api.fetchDetails("A1")
        assert len(calls) == 2 and not api._inflight


# 함수이름: test_lru_size_and_inflight_capacity_are_bounded
# 함수역할:
# - 좌표·ID를 바꾼 반복 호출도 메모리와 진행 작업 수를 제한한다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_lru_size_and_inflight_capacity_are_bounded(monkeypatch: pytest.MonkeyPatch) -> None:
    """좌표·ID를 바꾼 반복 호출도 메모리와 진행 작업 수를 제한한다."""
    monkeypatch.setattr(settings, "HOSPITAL_CACHE_MAX_ENTRIES", 2)

    # 함수이름: handle
    # 함수역할:
    # - 요청 HPID와 일치하는 상세 XML을 반환한다.
    # 매개변수:
    # - request: httpx.Request; 대체 전송기가 받은 요청.
    # 반환값:
    # - httpx.Response; 지정 XML 또는 오류 본문을 담은 HTTP 200 응답.
    def handle(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=envelope(detail(request.url.params["HPID"])))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        api = NationalEmergencyMedicalCenterHospitalAPI(client=client)
        for identifier in ("A1", "A2", "A3"):
            await api.fetchDetails(identifier)
        assert len(api._cache) == 2 and not api.hasCachedDetails("A1")
        api._inflight = {("busy", n): None for n in range(settings.PUBLIC_API_MAX_CONCURRENCY * 8)}
        with pytest.raises(HospitalApiUnavailableError):
            await api.fetchDetails("A4")
        api._inflight.clear()


# Function Name: test_daily_budget_cache_reuse_and_reset
# Description:
# - Requires cached details to consume no daily quota and a new application day to restore the exhausted request budget.
# Parameters:
# - monkeypatch: pytest.MonkeyPatch; restores temporary dependency replacements.
# Returns:
# - None.
@pytest.mark.anyio
async def test_daily_budget_cache_reuse_and_reset(monkeypatch: pytest.MonkeyPatch) -> None:
    """캐시 적중은 일일 예산을 소모하지 않고 날짜 변경 시에만 초기화한다."""
    monkeypatch.setattr(settings, "HOSPITAL_API_DAILY_REQUEST_BUDGET", 1)
    day, tick, calls = [date(2026, 9, 28)], [0.0], []

    # 함수이름: handle
    # 함수역할:
    # - 요청을 기록하고 요청 HPID의 상세 XML을 반환하여 날짜별 호출 횟수를 측정한다.
    # 매개변수:
    # - request: httpx.Request; 대체 전송기가 받은 요청.
    # 반환값:
    # - httpx.Response; 지정 XML 또는 오류 본문을 담은 HTTP 200 응답.
    def handle(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        return httpx.Response(200, content=envelope(detail(request.url.params["HPID"])))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        api = NationalEmergencyMedicalCenterHospitalAPI(client=client, clock=lambda: tick[0], date_clock=lambda: day[0])
        await api.fetchDetails("A1")
        await api.fetchDetails("A1")
        with pytest.raises(HospitalApiBudgetExhaustedError):
            await api.fetchDetails("A2")
        assert len(calls) == 1
        day[0] = date(2026, 9, 29)
        tick[0] += settings.PUBLIC_API_FAILURE_CACHE_SECONDS + 1
        await api.fetchDetails("A2")
        assert len(calls) == 2


# Function Name: test_daily_budget_is_counted_per_provider_operation
# Description:
# - Requires exhausted detail quota to leave location lookup quota available, with each operation enforcing its own limit.
# Parameters:
# - monkeypatch: pytest.MonkeyPatch; restores temporary dependency replacements.
# Returns:
# - None.
@pytest.mark.anyio
async def test_daily_budget_is_counted_per_provider_operation(monkeypatch: pytest.MonkeyPatch) -> None:
    """제공기관 할당량은 오퍼레이션별이므로 상세 조회 예산을 다 써도 위치 조회는 계속된다."""
    monkeypatch.setattr(settings, "HOSPITAL_API_DAILY_REQUEST_BUDGET", 1)

    # Function Name: handle
    # Description:
    # - Returns detail XML for HPID requests and location XML for other operations.
    # Parameters:
    # - request: httpx.Request; provider request being simulated.
    # Returns:
    # - httpx.Response; successful XML for the requested operation.
    def handle(request: httpx.Request) -> httpx.Response:
        if "HPID" in request.url.params:
            return httpx.Response(200, content=envelope(detail(request.url.params["HPID"])))
        return httpx.Response(200, content=envelope(location()))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        api = NationalEmergencyMedicalCenterHospitalAPI(
            client=client, clock=lambda: 0.0, date_clock=lambda: date(2026, 9, 28),
        )
        await api.fetchDetails("A1")
        with pytest.raises(HospitalApiBudgetExhaustedError):
            await api.fetchDetails("A2")
        page = await api.fetchNearbyPage(latitude=37.5, longitude=127, page_no=1, page_size=30)
        assert page is not None
        with pytest.raises(HospitalApiBudgetExhaustedError):
            await api.fetchNearbyPage(latitude=37.6, longitude=127, page_no=1, page_size=30)


# 함수이름: test_response_failures_are_sanitized_and_cached
# 함수역할:
# - 인증·형식·크기 오류를 구분하고 실패 반복 호출을 막는다.
# 매개변수:
# - payload: bytes; 형식·인증·크기 오류를 재현할 응답.
# - error: type[Exception]; 예상 경계 오류 유형.
# 반환값:
# - None.
@pytest.mark.parametrize("payload,error", [
    (b"not XML", HospitalApiResponseError),
    (b"<html/>", HospitalApiResponseError),
    (envelope(code="22"), HospitalApiUnavailableError),
    (b"<OpenAPI_ServiceResponse><cmmMsgHeader><returnAuthMsg>DENIED</returnAuthMsg></cmmMsgHeader></OpenAPI_ServiceResponse>", HospitalApiUnavailableError),
    (envelope(detail("other")), HospitalApiResponseError),
    (b"<!DOCTYPE x><response/>", HospitalApiResponseError),
    (b"x" * (1024 * 1024 + 1), HospitalApiResponseError),
], ids=["invalid-xml", "missing-status", "quota", "gateway", "wrong-id", "doctype", "oversize"])
@pytest.mark.anyio
async def test_response_failures_are_sanitized_and_cached(payload: bytes, error: type[HospitalApiResponseError] | type[HospitalApiUnavailableError]) -> None:
    """인증·형식·크기 오류를 구분하고 실패 반복 호출을 막는다."""
    calls = []

    # 함수이름: handle
    # 함수역할:
    # - 요청을 기록하고 매개변수로 선택된 잘못된 제공자 응답을 반환한다.
    # 매개변수:
    # - request: httpx.Request; 대체 전송기가 받은 요청.
    # 반환값:
    # - httpx.Response; 지정 XML 또는 오류 본문을 담은 HTTP 200 응답.
    def handle(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        return httpx.Response(200, content=payload)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        api = NationalEmergencyMedicalCenterHospitalAPI(client=client)
        for _ in range(2):
            with pytest.raises(error) as caught:
                await api.fetchDetails("A1")
            assert "serviceKey" not in str(caught.value)
            assert "fallback-test-key" not in str(caught.value)
        assert len(calls) == 1


# 함수이름: test_invalid_coordinates_are_skipped_without_shortening_page
# 함수역할:
# - 잘못된 좌표를 제외해도 원본 페이지 행 수는 유지한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_invalid_coordinates_are_skipped_without_shortening_page() -> None:
    """잘못된 좌표를 제외해도 원본 페이지 행 수는 유지한다."""
    items = location("A1", lat="NaN") + location("A2", lat="91") + location("A3")
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, content=envelope(items, total=3)))) as client:
        api = NationalEmergencyMedicalCenterHospitalAPI(client=client)
        result = await api.fetchNearbyPage(latitude=37.5, longitude=127, page_no=1, page_size=30)
        assert result.row_count == 3 and [r.hospital_id for r in result.records] == ["A3"]


# 함수이름: test_http_failures_do_not_redirect_or_leak
# 함수역할:
# - 실패 상태나 리다이렉트는 서비스 장애로 처리한다.
# 매개변수:
# - status: int; 제공자의 HTTP 오류 상태.
# 반환값:
# - None.
@pytest.mark.parametrize("status", [302, 403, 429, 500])
@pytest.mark.anyio
async def test_http_failures_do_not_redirect_or_leak(status: int) -> None:
    """실패 상태나 리다이렉트는 서비스 장애로 처리한다."""
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(status))) as client:
        with pytest.raises(HospitalApiUnavailableError):
            await NationalEmergencyMedicalCenterHospitalAPI(client=client).fetchDetails("A1")


# 함수이름: test_missing_key_and_network_timeout
# 함수역할:
# - 키 부재와 통신 오류에 원본 URL이 노출되지 않는다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_missing_key_and_network_timeout(monkeypatch: pytest.MonkeyPatch) -> None:
    """키 부재와 통신 오류에 원본 URL이 노출되지 않는다."""
    calls = []

    # 함수이름: handle
    # 함수역할:
    # - 요청을 기록한 뒤 민감한 URL 문구가 포함된 ReadTimeout을 발생시킨다.
    # 매개변수:
    # - request: httpx.Request; 대체 전송기가 받은 요청.
    # 반환값:
    # - 반환하지 않음; httpx.ReadTimeout 발생.
    def handle(request: httpx.Request) -> NoReturn:
        calls.append(request)
        raise httpx.ReadTimeout("sensitive serviceKey URL", request=request)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        monkeypatch.setattr(settings, "PUBLIC_DATA_API_KEY", "")
        with pytest.raises(HospitalApiUnavailableError):
            await NationalEmergencyMedicalCenterHospitalAPI(client=client).fetchDetails("A1")
        assert not calls
        monkeypatch.setattr(settings, "PUBLIC_DATA_API_KEY", "fake")
        with pytest.raises(HospitalApiUnavailableError) as caught:
            await NationalEmergencyMedicalCenterHospitalAPI(client=client).fetchDetails("A1")
        assert "sensitive" not in str(caught.value)
