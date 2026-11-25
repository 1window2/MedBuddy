# File Name: test_public_drug_api_boundary.py
# Role: Regression coverage for basic/approval drug API contracts and catalog retry isolation
#   from interactive failure caching.
import os
import sys
from datetime import date
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from boundaries.public_drug_api_boundary import (  # noqa: E402
    PillImageAPI,
    PublicDrugApiBudgetExhaustedError,
    PublicDrugLargeAPI,
    PublicDrugSmallAPI,
    _PublicDrugTransport,
)
from core.config import Settings, settings  # noqa: E402


# Function Name: test_small_api_search_medication_uses_basic_catalog_contract
# Description:
# - Uses the basic-drug endpoint's itemName parameter and three-row limit and returns its
#   matching medication payload.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
@pytest.mark.anyio
async def test_small_api_search_medication_uses_basic_catalog_contract(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    transport = _PublicDrugTransport()
    api = PublicDrugSmallAPI(transport=transport)

    # Function Name: fake_request_items
    # Description:
    # - Checks the basic endpoint and search parameters before supplying one matching
    #   medication.
    # Parameters:
    # - url (str): Public API endpoint requested by the boundary.
    # - params (dict[str, object]): Public API query parameters checked by the transport
    #   double.
    # Returns:
    # - tuple[list[dict[str, object]], int]: Configured drug rows and the advertised total
    #   count.
    async def fake_request_items(
        url: str,
        params: dict[str, object],
    ) -> tuple[list[dict[str, object]], int]:
        assert url == settings.BASIC_DRUG_API_BASE_URL
        assert params["itemName"] == "sample tablet"
        assert params["numOfRows"] == 3
        return ([{"itemName": "sample tablet"}], 1)

    monkeypatch.setattr(transport, "request_items", fake_request_items)

    assert await api.searchMedication("sample tablet") == [
        {"itemName": "sample tablet"}
    ]


# 함수이름: test_small_api_search_medication_propagates_failure
# 함수역할:
# - 기본 약품 검색 장애가 성공한 빈 결과로 바뀌지 않고 호출자에게 전파되는지 검증한다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_small_api_search_medication_propagates_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    transport = _PublicDrugTransport()
    api = PublicDrugSmallAPI(transport=transport)

    # Function Name: failing_request_items
    # Description:
    # - Raises an upstream availability error to verify that lookup failures remain visible.
    # Parameters:
    # - url (str): Public API endpoint requested by the boundary.
    # - params (dict[str, object]): Public API query parameters checked by the transport
    #   double.
    # Returns:
    # - No normal result; raises the configured failure described above.
    async def failing_request_items(
        url: str,
        params: dict[str, object],
    ) -> tuple[list[dict[str, object]], int]:
        raise RuntimeError("unavailable")

    monkeypatch.setattr(transport, "request_items", failing_request_items)

    with pytest.raises(RuntimeError, match="unavailable"):
        await api.searchMedication("sample tablet")


# 함수이름: test_large_api_search_medication_uses_approval_catalog_contract
# 함수역할:
# - 허가 약 검색이 고급 API의 item_name 인자와 5건 상한을 사용하고 대문자 필드 응답을 유지하는지 검증한다.
# 매개변수:
# - monkeypatch (pytest.MonkeyPatch): 교체한 의존성을 종료 시 복구하는 pytest fixture.
# 반환값:
# - 없음 (None).
@pytest.mark.anyio
async def test_large_api_search_medication_uses_approval_catalog_contract(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    transport = _PublicDrugTransport()
    api = PublicDrugLargeAPI(transport=transport)

    # 함수이름: fake_request_items
    # 함수역할:
    # - 고급 API 주소와 약명·결과 상한을 확인한 뒤 허가 약 단일 결과를 제공한다.
    # 매개변수:
    # - url (str): 경계가 요청한 공공 API 주소.
    # - params (dict[str, object]): 통신 대체 객체에서 확인할 공공 API 쿼리 인자.
    # 반환값:
    # - tuple[list[dict[str, object]], int]: 설정된 약 레코드 목록과 공시된 전체 건수.
    async def fake_request_items(
        url: str,
        params: dict[str, object],
    ) -> tuple[list[dict[str, object]], int]:
        assert url == settings.ADVANCED_DRUG_API_BASE_URL
        assert params["item_name"] == "sample tablet"
        assert params["numOfRows"] == 5
        return ([{"ITEM_NAME": "sample tablet"}], 1)

    monkeypatch.setattr(transport, "request_items", fake_request_items)

    assert await api.searchMedication("sample tablet") == [
        {"ITEM_NAME": "sample tablet"}
    ]


# Function Name: test_catalog_page_fetches_stay_owned_by_their_api_boundaries
# Description:
# - Keeps basic and approval page retrieval on their respective endpoints and bypasses
#   interactive failure caching.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
@pytest.mark.anyio
async def test_catalog_page_fetches_stay_owned_by_their_api_boundaries(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    transport = _PublicDrugTransport()
    small_api = PublicDrugSmallAPI(transport=transport)
    large_api = PublicDrugLargeAPI(transport=transport)
    requested_urls: list[str] = []

    # Function Name: fake_request_items
    # Description:
    # - Records the selected endpoint and checks page two, fifty rows, and explicit
    #   failure-cache bypass.
    # Parameters:
    # - url (str): Public API endpoint requested by the boundary.
    # - params (dict[str, object]): Public API query parameters checked by the transport
    #   double.
    # - bypass_failure_cache (bool): Whether catalog refresh must bypass interactive failure
    #   backoff.
    # Returns:
    # - tuple[list[dict[str, object]], int]: Configured drug rows and the advertised total
    #   count.
    async def fake_request_items(
        url: str,
        params: dict[str, object],
        *,
        bypass_failure_cache: bool = False,
    ) -> tuple[list[dict[str, object]], int]:
        requested_urls.append(url)
        assert bypass_failure_cache is True
        assert params["pageNo"] == 2
        assert params["numOfRows"] == 50
        return ([], 0)

    monkeypatch.setattr(transport, "request_items", fake_request_items)

    await small_api.fetchPage(2, 50)
    await large_api.fetchPage(2, 50)

    assert requested_urls == [
        settings.BASIC_DRUG_API_BASE_URL,
        settings.ADVANCED_DRUG_API_BASE_URL,
    ]


# Function Name: test_catalog_retry_bypasses_interactive_failure_cache
# Description:
# - Suppresses repeated interactive failures but permits a catalog retry to bypass the failure
#   cache and recover valid items.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
@pytest.mark.anyio
async def test_catalog_retry_bypasses_interactive_failure_cache(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    transport = _PublicDrugTransport()
    request_count = 0

    # Class Name: _Response
    # Role: HTTP response double carrying a selected status and fixed public-drug result
    #   payload.
    # Responsibilities:
    # - Returns one sample medication and its advertised total in public API response
    #   format.
    # Attributes:
    # - status_code (int): HTTP status returned by the simulated response.
    class _Response:
        # Function Name: __init__
        # Description:
        # - Stores the HTTP status used to distinguish the failed first request from the
        #   successful retry.
        # Parameters:
        # - status_code (int): HTTP response status supplied by the transport double.
        # Returns:
        # - None.
        def __init__(self, status_code: int) -> None:
            self.status_code = status_code

        # Function Name: json
        # Description:
        # - Returns one sample medication and its advertised total in public API
        #   response format.
        # Parameters:
        # - None.
        # Returns:
        # - dict[str, object]: Public API body containing one sample item and
        #   totalCount=1.
        def json(self) -> dict[str, object]:
            return {"body": {"items": [{"itemName": "sample"}], "totalCount": 1}}

    # Class Name: _Client
    # Role: HTTP client double that fails its first page request and succeeds on the next
    #   actual request.
    # Responsibilities:
    # - Checks the first-page request, counts attempts, and returns 503 once followed by
    #   200.
    # Attributes:
    # - None.
    class _Client:
        # Function Name: get
        # Description:
        # - Checks the first-page request, counts attempts, and returns 503 once
        #   followed by 200.
        # Parameters:
        # - _url (str): Public API endpoint requested by the boundary. Unused by this
        #   double.
        # - params (dict[str, object]): Public API query parameters checked by the
        #   transport double.
        # Returns:
        # - _Response: 503 response for the first actual request, then a 200 response.
        async def get(
            self,
            _url: str,
            *,
            params: dict[str, object],
        ) -> _Response:
            nonlocal request_count
            request_count += 1
            assert params["pageNo"] == 1
            return _Response(503 if request_count == 1 else 200)

    # Function Name: fake_get_client
    # Description:
    # - Supplies the deterministic retry client without constructing a network client.
    # Parameters:
    # - None.
    # Returns:
    # - _Client: Client double with deterministic failure-then-success behavior.
    async def fake_get_client() -> _Client:
        return _Client()

    monkeypatch.setattr(transport, "_get_client", fake_get_client)
    params: dict[str, object] = {"pageNo": 1, "numOfRows": 50}

    with pytest.raises(RuntimeError):
        await transport.request_items(settings.BASIC_DRUG_API_BASE_URL, params)
    with pytest.raises(RuntimeError):
        await transport.request_items(settings.BASIC_DRUG_API_BASE_URL, params)
    assert request_count == 1

    items, total_count = await transport.request_items(
        settings.BASIC_DRUG_API_BASE_URL,
        params,
        bypass_failure_cache=True,
    )

    assert request_count == 2
    assert items == [{"itemName": "sample"}]
    assert total_count == 1


# Class Name: _CountingClient
# Role: HTTP client double that records requested endpoints and answers one sample row.
# Responsibilities:
# - Count real provider requests so budget refusals can be shown to make none.
# Attributes:
# - urls (list[str]): Endpoints requested so far.
class _CountingClient:
    def __init__(self) -> None:
        self.urls: list[str] = []

    # Function Name: get
    # Description: Records the endpoint and returns a successful one-row public API response.
    # Parameters: url (str) is the endpoint; params (dict[str, object]) is unused.
    # Returns: Response double with status 200.
    async def get(self, url: str, *, params: dict[str, object]) -> object:
        del params
        self.urls.append(url)

        # Class Name: _Response
        # Role: Successful public API response double.
        # Responsibilities: Return one sample item.
        # Attributes: status_code (int): Always 200.
        class _Response:
            status_code = 200

            def json(self) -> dict[str, object]:
                return {"body": {"items": [{"itemName": "sample"}], "totalCount": 1}}

        return _Response()


# Function Name: _transport_with
# Description: Build a transport whose HTTP client and budget day are test doubles.
# Parameters: monkeypatch (pytest.MonkeyPatch); client (_CountingClient); today (list[date]) holds the current day.
# Returns: _PublicDrugTransport using the doubles.
def _transport_with(
    monkeypatch: pytest.MonkeyPatch,
    client: _CountingClient,
    today: list[date],
) -> _PublicDrugTransport:
    transport = _PublicDrugTransport(date_clock=lambda: today[0])

    async def fake_get_client() -> _CountingClient:
        return client

    monkeypatch.setattr(transport, "_get_client", fake_get_client)
    return transport


# Function Name: test_defaults_follow_the_approved_portal_accounts
# Description:
# - Pins the approval endpoint to the 08 operations approved for the operating account and the
#   per-process budgets to 80% of each portal quota.
# Parameters: None.
# Returns: None.
def test_defaults_follow_the_approved_portal_accounts() -> None:
    fields = Settings.model_fields
    assert fields["ADVANCED_DRUG_API_BASE_URL"].default.endswith(
        "/DrugPrdtPrmsnInfoService08/getDrugPrdtPrmsnDtlInq08"
    )
    assert fields["BASIC_DRUG_API_DAILY_REQUEST_BUDGET"].default == 800_000
    assert fields["ADVANCED_DRUG_API_DAILY_REQUEST_BUDGET"].default == 80_000
    assert fields["PILL_IMAGE_API_DAILY_REQUEST_BUDGET"].default == 8_000


# Function Name: test_daily_budget_is_counted_per_endpoint_and_refuses_without_a_request
# Description:
# - Each MFDS endpoint has its own counter; a spent budget refuses before any HTTP request,
#   does not enter the failure cache, and a new application day starts from zero.
# Parameters: monkeypatch (pytest.MonkeyPatch): Restores patched settings afterward.
# Returns: None.
@pytest.mark.anyio
async def test_daily_budget_is_counted_per_endpoint_and_refuses_without_a_request(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "ADVANCED_DRUG_API_DAILY_REQUEST_BUDGET", 2)
    monkeypatch.setattr(settings, "BASIC_DRUG_API_DAILY_REQUEST_BUDGET", 1)
    client = _CountingClient()
    today = [date(2026, 11, 25)]
    transport = _transport_with(monkeypatch, client, today)
    approval = settings.ADVANCED_DRUG_API_BASE_URL
    basic = settings.BASIC_DRUG_API_BASE_URL

    await transport.request_items(approval, {"item_name": "a"})
    await transport.request_items(approval, {"item_name": "b"})
    with pytest.raises(PublicDrugApiBudgetExhaustedError):
        await transport.request_items(approval, {"item_name": "c"})
    with pytest.raises(PublicDrugApiBudgetExhaustedError):
        await transport.request_items(approval, {"pageNo": 1}, bypass_failure_cache=True)
    assert client.urls == [approval, approval]

    await transport.request_items(basic, {"itemName": "a"})
    with pytest.raises(PublicDrugApiBudgetExhaustedError):
        await transport.request_items(basic, {"itemName": "b"})
    assert client.urls == [approval, approval, basic]
    assert transport._failed_until == {}

    today[0] = date(2026, 11, 26)
    await transport.request_items(approval, {"item_name": "c"})
    await transport.request_items(basic, {"itemName": "b"})
    assert client.urls[-2:] == [approval, basic]


# Function Name: test_unbudgeted_url_is_not_counted
# Description: A URL outside the three MFDS endpoints is neither counted nor refused.
# Parameters: monkeypatch (pytest.MonkeyPatch): Restores patched settings afterward.
# Returns: None.
@pytest.mark.anyio
async def test_unbudgeted_url_is_not_counted(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "BASIC_DRUG_API_DAILY_REQUEST_BUDGET", 1)
    client = _CountingClient()
    transport = _transport_with(monkeypatch, client, [date(2026, 11, 25)])
    other = "https://apis.data.go.kr/1471000/OtherService/getList"

    for _ in range(3):
        await transport.request_items(other, {"pageNo": 1}, bypass_failure_cache=True)

    assert client.urls == [other, other, other]
    assert transport._daily_requests == {}


# Function Name: test_pill_image_lookup_returns_no_image_when_its_budget_is_spent
# Description: The optional image enrichment degrades to "no image" once its budget is spent.
# Parameters: monkeypatch (pytest.MonkeyPatch): Restores patched settings afterward.
# Returns: None.
@pytest.mark.anyio
async def test_pill_image_lookup_returns_no_image_when_its_budget_is_spent(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "PILL_IMAGE_API_ENABLED", True)
    monkeypatch.setattr(settings, "PILL_IMAGE_API_DAILY_REQUEST_BUDGET", 1)
    client = _CountingClient()
    transport = _transport_with(monkeypatch, client, [date(2026, 11, 25)])
    api = PillImageAPI(transport=transport)

    await api.searchMedicationImage("first tablet")
    assert await api.searchMedicationImage("second tablet") == ""
    assert client.urls == [settings.PILL_IMAGE_API_BASE_URL]
