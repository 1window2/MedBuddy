# File Name: korean_holiday_api_boundary.py
# Role: Resolves Korean legal holidays through the government special-day API.

import asyncio
from datetime import date, timedelta
import logging
from typing import Protocol
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
        dates = await self.fetchMonth(value.year, value.month)
        return value in dates

    async def fetchMonth(self, year: int, month: int) -> frozenset[date]:
        cache_key = (year, month)
        dates = self._cache.get(cache_key)
        if dates is None:
            async with self._lock:
                dates = self._cache.get(cache_key)
                if dates is None:
                    dates = await self._fetch_month(*cache_key)
                    self._cache[cache_key] = dates
        return dates

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


class KoreanHolidayCache(Protocol):
    def get_cached_korean_holidays(
        self,
        year: int,
        month: int,
        *,
        max_age: timedelta,
    ) -> frozenset[date] | None: ...

    def replace_korean_holidays(
        self,
        year: int,
        month: int,
        holidays: frozenset[date],
    ) -> None: ...


class PersistentKoreanHolidayLookup:
    """Database-backed calendar lookup with a bounded stale fallback."""

    _FRESH_MAX_AGE = timedelta(days=30)
    _STALE_MAX_AGE = timedelta(days=730)

    def __init__(
        self,
        *,
        cache: KoreanHolidayCache,
        upstream: KoreanHolidayAPI,
    ) -> None:
        self._cache = cache
        self._upstream = upstream

    async def isHoliday(self, value: date) -> bool:
        cached = self._cache.get_cached_korean_holidays(
            value.year,
            value.month,
            max_age=self._FRESH_MAX_AGE,
        )
        if cached is not None:
            return value in cached
        try:
            holidays = await self._upstream.fetchMonth(value.year, value.month)
            self._cache.replace_korean_holidays(
                value.year,
                value.month,
                holidays,
            )
            return value in holidays
        except PharmacyApiUnavailableError:
            stale = self._cache.get_cached_korean_holidays(
                value.year,
                value.month,
                max_age=self._STALE_MAX_AGE,
            )
            if stale is not None:
                logger.warning(
                    "Using stale Korean holiday cache for %04d-%02d.",
                    value.year,
                    value.month,
                )
                return value in stale
            raise
