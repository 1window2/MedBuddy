# File Name: test_public_drug_api_boundary.py
# Role: Regression coverage for basic/approval drug API contracts and catalog retry isolation
#   from interactive failure caching.
import os
import sys
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from boundaries.public_drug_api_boundary import (  # noqa: E402
    PublicDrugLargeAPI,
    PublicDrugSmallAPI,
    _PublicDrugTransport,
)
from core.config import settings  # noqa: E402


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


# Function Name: test_small_api_search_medication_degrades_to_empty_result
# Description:
# - Degrades an unavailable interactive basic-drug search to an empty result.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
@pytest.mark.anyio
async def test_small_api_search_medication_degrades_to_empty_result(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    transport = _PublicDrugTransport()
    api = PublicDrugSmallAPI(transport=transport)

    # Function Name: failing_request_items
    # Description:
    # - Raises an upstream availability error to exercise interactive search fallback.
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

    assert await api.searchMedication("sample tablet") == []


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
