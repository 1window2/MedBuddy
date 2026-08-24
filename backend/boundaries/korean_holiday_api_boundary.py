# File Name: korean_holiday_api_boundary.py
# Role: Resolves Korean legal holidays through the government special-day API.

import asyncio
from datetime import date
import logging
import xml.etree.ElementTree as ElementTree

import httpx

from boundaries.pharmacy_api_boundary import PharmacyApiUnavailableError
from core.config import settings


logger = logging.getLogger(__name__)


class KoreanHolidayAPI:
    """Month-cached boundary for Korean legal holiday dates."""

    _BASE_URL = (
        "https://apis.data.go.kr/B090041/openapi/service/"
        "SpcdeInfoService/getRestDeInfo"
    )

    def __init__(self, *, client: httpx.AsyncClient | None = None) -> None:
        self._client = client
        self._owns_client = client is None
        self._lock = asyncio.Lock()
        self._cache: dict[tuple[int, int], frozenset[date]] = {}

    async def isHoliday(self, value: date) -> bool:
        cache_key = (value.year, value.month)
        dates = self._cache.get(cache_key)
        if dates is None:
            async with self._lock:
                dates = self._cache.get(cache_key)
                if dates is None:
                    dates = await self._fetch_month(*cache_key)
                    self._cache[cache_key] = dates
        return value in dates

    async def close(self) -> None:
        if self._owns_client and self._client is not None:
            await self._client.aclose()
            self._client = None

    async def _fetch_month(self, year: int, month: int) -> frozenset[date]:
        client = self._client
        if client is None:
            client = httpx.AsyncClient(
                timeout=settings.PHARMACY_API_TIMEOUT_SECONDS,
                follow_redirects=False,
            )
            self._client = client
        try:
            response = await client.get(
                self._BASE_URL,
                params={
                    "ServiceKey": settings.PUBLIC_DATA_API_KEY,
                    "solYear": str(year),
                    "solMonth": f"{month:02d}",
                    "numOfRows": 100,
                },
            )
            response.raise_for_status()
            root = ElementTree.fromstring(response.content)
        except (httpx.HTTPError, OSError, ElementTree.ParseError) as exc:
            logger.warning("Korean holiday lookup failed: %s", type(exc).__name__)
            raise PharmacyApiUnavailableError(
                "The Korean holiday data service is temporarily unavailable."
            ) from exc

        result_code = (root.findtext(".//resultCode") or "").strip()
        if result_code not in {"", "00", "0000"}:
            raise PharmacyApiUnavailableError(
                "The Korean holiday data service rejected the request."
            )
        holidays: set[date] = set()
        for element in root.findall(".//locdate"):
            raw_value = (element.text or "").strip()
            if len(raw_value) != 8 or not raw_value.isdigit():
                continue
            holidays.add(
                date(int(raw_value[:4]), int(raw_value[4:6]), int(raw_value[6:]))
            )
        return frozenset(holidays)
