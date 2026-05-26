# File Name: public_drug_api_client.py
# Role: Encapsulates calls to Korean public drug data APIs.

import httpx
from fastapi import HTTPException

from core.config import settings


# Class Name: PublicDrugApiClient
# Role: Boundary adapter for public medication data APIs.
# Responsibilities:
#   - Query the basic e-yak-eun-yo drug API.
#   - Query the advanced drug approval information API.
# Attributes:
#   - api_key: Public API service key.
#   - basic_url: Basic drug API endpoint.
#   - advanced_url: Advanced drug approval API endpoint.
#   - timeout_seconds: HTTP request timeout.
class PublicDrugApiClient:
    def __init__(
        self,
        api_key: str = settings.PUBLIC_DATA_API_KEY,
        basic_url: str = settings.BASIC_DRUG_API_BASE_URL,
        advanced_url: str = settings.ADVANCED_DRUG_API_BASE_URL,
        timeout_seconds: float = 15.0,
    ) -> None:
        self.api_key = api_key
        self.basic_url = basic_url
        self.advanced_url = advanced_url
        self.timeout_seconds = timeout_seconds

    # Function Name: search_basic
    # Description:
    # - Searches the easy public drug API by item name.
    # Parameters:
    # - drug_name: Search keyword.
    # Returns:
    # - Raw API item list. Empty list on no result or non-200 response.
    async def search_basic(self, drug_name: str) -> list[dict]:
        params = {
            "serviceKey": self.api_key,
            "itemName": drug_name,
            "type": "json",
            "numOfRows": 3,
        }

        async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
            response = await client.get(self.basic_url, params=params)

        if response.status_code != 200:
            return []

        data = response.json()
        return data.get("body", {}).get("items") or []

    # Function Name: search_advanced
    # Description:
    # - Searches the advanced drug approval API by item name.
    # Parameters:
    # - drug_name: Search keyword.
    # Returns:
    # - Raw API item list.
    async def search_advanced(self, drug_name: str) -> list[dict]:
        params = {
            "serviceKey": self.api_key,
            "item_name": drug_name,
            "type": "json",
            "numOfRows": 1,
        }

        async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
            response = await client.get(self.advanced_url, params=params)

        if response.status_code != 200:
            raise HTTPException(
                status_code=502,
                detail="공공데이터 API 서버와 통신할 수 없습니다.",
            )

        data = response.json()
        return data.get("body", {}).get("items") or []
