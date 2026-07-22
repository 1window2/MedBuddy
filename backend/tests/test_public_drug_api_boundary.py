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


@pytest.mark.anyio
async def test_small_api_search_medication_uses_basic_catalog_contract(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    transport = _PublicDrugTransport()
    api = PublicDrugSmallAPI(transport=transport)

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


@pytest.mark.anyio
async def test_small_api_search_medication_degrades_to_empty_result(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    transport = _PublicDrugTransport()
    api = PublicDrugSmallAPI(transport=transport)

    async def failing_request_items(
        url: str,
        params: dict[str, object],
    ) -> tuple[list[dict[str, object]], int]:
        raise RuntimeError("unavailable")

    monkeypatch.setattr(transport, "request_items", failing_request_items)

    assert await api.searchMedication("sample tablet") == []


@pytest.mark.anyio
async def test_large_api_search_medication_uses_approval_catalog_contract(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    transport = _PublicDrugTransport()
    api = PublicDrugLargeAPI(transport=transport)

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


@pytest.mark.anyio
async def test_catalog_page_fetches_stay_owned_by_their_api_boundaries(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    transport = _PublicDrugTransport()
    small_api = PublicDrugSmallAPI(transport=transport)
    large_api = PublicDrugLargeAPI(transport=transport)
    requested_urls: list[str] = []

    async def fake_request_items(
        url: str,
        params: dict[str, object],
    ) -> tuple[list[dict[str, object]], int]:
        requested_urls.append(url)
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
