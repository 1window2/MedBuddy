"""병원 API의 실제 XML 형태, 호출 예산과 캐시를 검증한다."""

import asyncio
from datetime import date
from pathlib import Path
import sys

import httpx
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from boundaries.hospital_api_boundary import (
    HospitalApiResponseError, HospitalApiUnavailableError,
    NationalEmergencyMedicalCenterHospitalAPI,
)
from core.config import settings


@pytest.fixture
def anyio_backend():
    """공유 비동기 경계는 asyncio에서 실행한다."""
    return "asyncio"


@pytest.fixture(autouse=True)
def credentials(monkeypatch):
    """실제 로컬 인증키를 테스트 요청에 사용하지 않는다."""
    monkeypatch.setattr(settings, "PUBLIC_DATA_API_KEY", "fallback-test-key")
    monkeypatch.setattr(settings, "HOSPITAL_API_KEY", "")


def envelope(items="", *, page=1, size=30, total=1, code="00"):
    """제공자의 대소문자와 페이지 구조를 재현한다."""
    return f"""<response><header><resultCode>{code}</resultCode></header><body>
    <items>{items}</items><pageNo>{page}</pageNo><numOfRows>{size}</numOfRows>
    <totalCount>{total}</totalCount></body></response>""".encode()


def location(identifier="A1", *, lat="37.5665", lon="126.978"):
    """위치 응답에는 기관 유형만 있고 진료과는 없다."""
    return f"""<item><hpid>{identifier}</hpid><dutyName>Test clinic</dutyName>
    <latitude>{lat}</latitude><longitude>{lon}</longitude><dutyDivName>의원</dutyDivName>
    <cnt>999999</cnt><startTime>0900</startTime><endTime>1800</endTime></item>"""


def detail(identifier="A1"):
    """실제 상세의 진료과 CSV와 생략된 요일을 재현한다."""
    return f"""<item><hpid>{identifier}</hpid><dgidIdName>내과, 피부과,내과</dgidIdName>
    <dutyTime1s>0900</dutyTime1s><dutyTime1c>1800</dutyTime1c>
    <dutyEryn>1</dutyEryn></item>"""


@pytest.mark.anyio
async def test_location_capped_pages_and_actual_fields():
    """서버가 줄인 페이지 크기와 totalCount를 신뢰하고 cnt는 무시한다."""
    requests = []

    def handle(request):
        requests.append(request)
        return httpx.Response(200, content=envelope(location(), size=10, total=41))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        api = NationalEmergencyMedicalCenterHospitalAPI(client=client)
        result = await api.fetchNearbyPage(latitude=37.5, longitude=127, page_no=1, page_size=30)
        assert result.total_count == 41 and result.page_size == 10 and result.row_count == 1
        assert result.records[0].institution_type == "의원"
        assert requests[0].url.path.endswith("/getHsptlMdcncLcinfoInqire")
        assert requests[0].url.params["serviceKey"] == "fallback-test-key"
        assert requests[0].url.params["WGS84_LAT"] == "37.5000000"
        assert "QD" not in requests[0].url.params
        await api.close()
        assert not client.is_closed


@pytest.mark.anyio
async def test_details_key_override_and_department_parsing(monkeypatch):
    """별도 키를 우선하고 상세 진료과를 정리하며 누락 시간을 보존한다."""
    monkeypatch.setattr(settings, "HOSPITAL_API_KEY", "hospital%2Bkey%3D")

    def handle(request):
        assert request.url.params["serviceKey"] == "hospital+key="
        assert request.url.params["HPID"] == "A1"
        assert request.url.path.endswith("/getHsptlBassInfoInqire")
        return httpx.Response(200, content=envelope(detail()))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        result = await NationalEmergencyMedicalCenterHospitalAPI(client=client).fetchDetails("A1")
    assert result.departments == ("내과", "피부과")
    assert result.department_codes == () and result.institution_type is None
    assert result.weekly_hours[-1] == ("8", "", "")


@pytest.mark.anyio
async def test_department_page_filters_provider_and_separates_cache():
    """진료과·지역은 요청과 캐시 키에 포함되고 좌표 조회와 혼합되지 않는다."""
    calls = []

    def handle(request):
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


@pytest.mark.anyio
async def test_department_page_sejong_omits_district_and_rejects_bad_query():
    """시군구가 없는 세종시와 잘못된 조회 조건을 구별한다."""
    def handle(request):
        assert 'Q1' not in request.url.params
        return httpx.Response(200, content=envelope('', size=100, total=0))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        api = NationalEmergencyMedicalCenterHospitalAPI(client=client)
        query = dict(province='세종특별자치시', district='', department='D001', page_no=1, page_size=100)
        assert not (await api.fetchDepartmentPage(**query)).records
        for changes in ({'department':'내과'}, {'page_size':101}, {'page_no':0}, {'province':''}):
            with pytest.raises(ValueError):
                await api.fetchDepartmentPage(**dict(query, **changes))


@pytest.mark.anyio
async def test_cache_coalescing_ttl_and_cancelled_waiter(monkeypatch):
    """동시 요청·취소·만료가 호출 증폭이나 캐시 손상을 만들지 않는다."""
    tick = [0.0]
    gate = asyncio.Event()
    calls = []

    async def handle(request):
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


@pytest.mark.anyio
async def test_lru_size_and_inflight_capacity_are_bounded(monkeypatch):
    """좌표·ID를 바꾼 반복 호출도 메모리와 진행 작업 수를 제한한다."""
    monkeypatch.setattr(settings, "HOSPITAL_CACHE_MAX_ENTRIES", 2)

    def handle(request):
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


@pytest.mark.anyio
async def test_daily_budget_cache_reuse_and_reset(monkeypatch):
    """캐시 적중은 일일 예산을 소모하지 않고 날짜 변경 시에만 초기화한다."""
    monkeypatch.setattr(settings, "HOSPITAL_API_DAILY_REQUEST_BUDGET", 1)
    day, tick, calls = [date(2026, 9, 28)], [0.0], []

    def handle(request):
        calls.append(request)
        return httpx.Response(200, content=envelope(detail(request.url.params["HPID"])))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        api = NationalEmergencyMedicalCenterHospitalAPI(client=client, clock=lambda: tick[0], date_clock=lambda: day[0])
        await api.fetchDetails("A1")
        await api.fetchDetails("A1")
        with pytest.raises(HospitalApiUnavailableError):
            await api.fetchDetails("A2")
        assert len(calls) == 1
        day[0] = date(2026, 9, 29)
        tick[0] += settings.PUBLIC_API_FAILURE_CACHE_SECONDS + 1
        await api.fetchDetails("A2")
        assert len(calls) == 2


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
async def test_response_failures_are_sanitized_and_cached(payload, error):
    """인증·형식·크기 오류를 구분하고 실패 반복 호출을 막는다."""
    calls = []

    def handle(request):
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


@pytest.mark.anyio
async def test_invalid_coordinates_are_skipped_without_shortening_page():
    """잘못된 좌표를 제외해도 원본 페이지 행 수는 유지한다."""
    items = location("A1", lat="NaN") + location("A2", lat="91") + location("A3")
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, content=envelope(items, total=3)))) as client:
        api = NationalEmergencyMedicalCenterHospitalAPI(client=client)
        result = await api.fetchNearbyPage(latitude=37.5, longitude=127, page_no=1, page_size=30)
        assert result.row_count == 3 and [r.hospital_id for r in result.records] == ["A3"]


@pytest.mark.parametrize("status", [302, 403, 429, 500])
@pytest.mark.anyio
async def test_http_failures_do_not_redirect_or_leak(status):
    """실패 상태나 리다이렉트는 서비스 장애로 처리한다."""
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(status))) as client:
        with pytest.raises(HospitalApiUnavailableError):
            await NationalEmergencyMedicalCenterHospitalAPI(client=client).fetchDetails("A1")


@pytest.mark.anyio
async def test_missing_key_and_network_timeout(monkeypatch):
    """키 부재와 통신 오류에 원본 URL이 노출되지 않는다."""
    calls = []

    def handle(request):
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
