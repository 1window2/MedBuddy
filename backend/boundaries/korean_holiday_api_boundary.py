# File Name: korean_holiday_api_boundary.py
# Role: Resolves Korean legal holidays through the government special-day API.

import asyncio
from collections import OrderedDict
from datetime import date, timedelta
import logging
import time
from typing import Protocol
import xml.etree.ElementTree as ElementTree

import httpx
from starlette.concurrency import run_in_threadpool

from boundaries.pharmacy_api_boundary import PharmacyApiUnavailableError
from core.config import settings


logger = logging.getLogger(__name__)


# Class Name: KoreanHolidayAPI
# Role:
# - Retrieves Korean legal holiday dates with an in-process monthly cache.
# Responsibilities:
# - Share one cache fill per month, parse government XML dates and classify upstream failures.
# Attributes:
# - _cache (dict[tuple[int, int], frozenset[date]]): Holidays by year and month.
# - _client (AsyncClient | None): Borrowed or owned HTTP transport.
# - _inflight (dict[tuple[int, int], asyncio.Task]): Running cache fill per month; every caller
#   of that month waits on the same task, and a caller's timeout does not cancel it.
class KoreanHolidayAPI:
    """Month-cached boundary for Korean legal holiday dates."""

    _BASE_URL = (
        "https://apis.data.go.kr/B090041/openapi/service/"
        "SpcdeInfoService/getRestDeInfo"
    )

    # Function Name: __init__
    # Description:
    # - Set up the monthly cache and the in-flight fill table while recording whether this boundary owns its HTTP client.
    # Parameters:
    # - client (httpx.AsyncClient | None): Optional borrowed HTTP client; omitted to create an owned client.
    # Returns:
    # - None; the client is created lazily when not injected.
    def __init__(self, *, client: httpx.AsyncClient | None = None) -> None:
        self._client = client
        self._owns_client = client is None
        self._cache: OrderedDict[tuple[int, int], frozenset[date]] = OrderedDict()
        self._expires: dict[tuple[int, int], float] = {}
        self._failures: OrderedDict[tuple[int, int], float] = OrderedDict()
        self._inflight: dict[tuple[int, int], asyncio.Task[frozenset[date]]] = {}

    # Function Name: isHoliday
    # Description:
    # - Check whether a date belongs to the holiday set for its month.
    # Parameters:
    # - value (date): Calendar date to check.
    # Returns:
    # - True when the date appears in the fetched or cached holiday set.
    async def isHoliday(self, value: date) -> bool:
        dates = await self.fetchMonth(value.year, value.month)
        return value in dates

    # Function Name: fetchMonth
    # Description:
    # - Return the monthly holiday set from the cache, or wait for the single fill task of that month.
    # - The fill runs as its own task behind asyncio.shield: a caller that gives up (the nearby-care
    #   controls allow 2-3 seconds) stops waiting, while the provider request finishes and stores its
    #   answer for the next lookup. Cancelling the fill with the caller meant a provider slower than
    #   that budget could never populate the cache.
    # Parameters:
    # - year (int): Calendar year of the requested holiday month.
    # - month (int): Calendar month, from 1 through 12.
    # Returns:
    # - Immutable holiday dates for the requested month; raises PharmacyApiUnavailableError when the
    #   fill fails or the month is inside its failure cool-down.
    async def fetchMonth(self, year: int, month: int) -> frozenset[date]:
        cache_key = (year, month)
        if self._expires.get(cache_key, 0) <= time.monotonic():
            self._cache.pop(cache_key, None)
            self._expires.pop(cache_key, None)
        dates = self._cache.get(cache_key)
        if dates is not None:
            return dates
        # No await separates this lookup from the registration below, so one task per month exists.
        fill = self._inflight.get(cache_key)
        if fill is None:
            if self._failures.get(cache_key, 0) > time.monotonic():
                raise PharmacyApiUnavailableError("Holiday lookup is temporarily unavailable.")
            fill = asyncio.create_task(self._fill_month(cache_key))
            self._inflight[cache_key] = fill
            fill.add_done_callback(self._retrieve_fill_outcome)
        return await asyncio.shield(fill)

    # Function Name: _fill_month
    # Description:
    # - Fetch one month and record the outcome itself, so the result is kept even when no caller is
    #   still waiting: the cache entry on success, a 30-second failure mark on provider failure.
    # Parameters:
    # - cache_key (tuple[int, int]): Year and month being filled.
    # Returns:
    # - Immutable holiday dates; re-raises PharmacyApiUnavailableError after marking the failure.
    async def _fill_month(self, cache_key: tuple[int, int]) -> frozenset[date]:
        try:
            dates = await self._fetch_month(*cache_key)
        except PharmacyApiUnavailableError:
            # Prevent repeated failures and queued requests from amplifying calls for the same month.
            self._failures[cache_key] = time.monotonic() + 30
            self._failures.move_to_end(cache_key)
            while len(self._failures) > 48:
                self._failures.popitem(last=False)
            raise
        finally:
            self._inflight.pop(cache_key, None)
        self._cache[cache_key] = dates
        self._expires[cache_key] = time.monotonic() + 86400
        self._failures.pop(cache_key, None)
        while len(self._cache) > 48:
            removed, _ = self._cache.popitem(last=False)
            self._expires.pop(removed, None)
        return dates

    # Function Name: _retrieve_fill_outcome
    # Description:
    # - Mark a finished fill's exception as retrieved. Every waiting caller may have timed out, and
    #   an unretrieved task exception would be reported by the event loop as an error.
    # - A provider failure is an expected outcome that _fill_month recorded as the cool-down; any
    #   other exception is logged here because no caller may be left to receive it.
    # Parameters:
    # - fill (asyncio.Task[frozenset[date]]): Finished cache-fill task.
    # Returns:
    # - None.
    @staticmethod
    def _retrieve_fill_outcome(fill: asyncio.Task[frozenset[date]]) -> None:
        if fill.cancelled():
            return
        error = fill.exception()
        if error is not None and not isinstance(error, PharmacyApiUnavailableError):
            logger.error(
                "Korean holiday cache fill failed unexpectedly: %s",
                type(error).__name__,
            )

    # Function Name: close
    # Description:
    # - Cancel and await any running cache fill, then close and release an internally created HTTP
    #   client without closing a borrowed client.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def close(self) -> None:
        fills = list(self._inflight.values())
        for fill in fills:
            fill.cancel()
        if fills:
            await asyncio.gather(*fills, return_exceptions=True)
        if self._owns_client and self._client is not None:
            await self._client.aclose()
            self._client = None

    # Function Name: _fetch_month
    # Description:
    # - Read the government special-day XML response, reject provider failures and parse eight-digit dates.
    # Parameters:
    # - year (int): Calendar year of the requested holiday month.
    # - month (int): Calendar month, from 1 through 12.
    # Returns:
    # - Immutable holiday dates; raises PharmacyApiUnavailableError on transport or provider failure.
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
        except (httpx.HTTPError, OSError, ElementTree.ParseError, ValueError, LookupError) as exc:
            logger.warning("Korean holiday lookup failed: %s", type(exc).__name__)
            raise PharmacyApiUnavailableError(
                "The Korean holiday data service is temporarily unavailable."
            ) from exc

        result_code = (root.findtext(".//resultCode") or "").strip()
        if (
            root.tag != "response" or root.find("body") is None
            or root.find(".//cmmMsgHeader") is not None
            or result_code not in {"00", "0000"}
        ):
            raise PharmacyApiUnavailableError(
                "The Korean holiday data service rejected the request."
            )
        holidays: set[date] = set()
        for element in root.findall(".//locdate"):
            raw_value = (element.text or "").strip()
            if len(raw_value) != 8 or not raw_value.isdigit():
                raise PharmacyApiUnavailableError("Invalid holiday date response.")
            try:
                holidays.add(date(int(raw_value[:4]), int(raw_value[4:6]), int(raw_value[6:])))
            except ValueError:
                raise PharmacyApiUnavailableError("Invalid holiday date response.") from None
        return frozenset(holidays)


# Class Name: KoreanHolidayCache
# Role:
# - Defines persistent monthly holiday snapshot storage.
# Responsibilities:
# - Distinguish a cached empty month from a missing or expired snapshot and replace complete monthly data.
class KoreanHolidayCache(Protocol):
    # Function Name: get_cached_korean_holidays
    # Description:
    # - Look up a monthly holiday snapshot within the caller's allowed cache age.
    # Parameters:
    # - year (int): Calendar year of the requested holiday month.
    # - month (int): Calendar month, from 1 through 12.
    # - max_age (timedelta): Maximum permitted age of the cached snapshot.
    # Returns:
    # - Cached dates, including an empty set for a known empty month, or None if unavailable or stale.
    def get_cached_korean_holidays(
        self,
        year: int,
        month: int,
        *,
        max_age: timedelta,
    ) -> frozenset[date] | None: ...

    # Function Name: replace_korean_holidays
    # Description:
    # - Replace the persisted snapshot for one calendar month, including months with no holidays.
    # Parameters:
    # - year (int): Calendar year of the requested holiday month.
    # - month (int): Calendar month, from 1 through 12.
    # - holidays (frozenset[date]): Complete set of legal holiday dates for the month.
    # Returns:
    # - None; the monthly snapshot is stored.
    def replace_korean_holidays(
        self,
        year: int,
        month: int,
        holidays: frozenset[date],
    ) -> None: ...


# Class Name: PersistentKoreanHolidayLookup
# Role:
# - Resolves holidays through persistent cache with bounded stale fallback.
# Responsibilities:
# - Prefer data at most 30 days old; refresh upstream and allow a 730-day snapshot during provider outages.
# Attributes:
# - _cache (KoreanHolidayCache): Persistent monthly snapshots.
# - _upstream (KoreanHolidayAPI): Government holiday fetcher.
class PersistentKoreanHolidayLookup:
    """Database-backed calendar lookup with a bounded stale fallback."""

    _FRESH_MAX_AGE = timedelta(days=30)
    _STALE_MAX_AGE = timedelta(days=730)

    # Function Name: __init__
    # Description:
    # - Bind persistent storage and the upstream holiday boundary for cache-first lookups.
    # Parameters:
    # - cache (KoreanHolidayCache): Persistent monthly holiday cache.
    # - upstream (KoreanHolidayAPI): Government holiday API used on a cache miss.
    # Returns:
    # - None; dependencies are retained without fetching data.
    def __init__(
        self,
        *,
        cache: KoreanHolidayCache,
        upstream: KoreanHolidayAPI,
    ) -> None:
        self._cache = cache
        self._upstream = upstream
        self._lookup_lock = asyncio.Lock()

    # Function Name: isHoliday
    # Description:
    # - Check a fresh snapshot, refresh and persist on a miss, or use bounded stale data when the provider is unavailable.
    # Parameters:
    # - value (date): Calendar date whose legal-holiday status is needed.
    # Returns:
    # - Whether the date is a holiday; propagates unavailability when no acceptable snapshot exists.
    async def isHoliday(self, value: date) -> bool:
        # Serialize paired same-month lookups without holding a database session.
        async with self._lookup_lock:
            return await self._lookup_holiday(value)

    # Function Name: _lookup_holiday
    # Description: Keeps blocking cache work off the event loop and provider I/O outside DB sessions.
    # Parameters: value: Date being checked.
    # Returns: Verified holiday status or an availability error.
    async def _lookup_holiday(self, value: date) -> bool:
        cached = await run_in_threadpool(
            self._cache.get_cached_korean_holidays,
            value.year,
            value.month,
            max_age=self._FRESH_MAX_AGE,
        )
        if cached is not None:
            return value in cached
        try:
            holidays = await self._upstream.fetchMonth(value.year, value.month)
            await run_in_threadpool(
                self._cache.replace_korean_holidays,
                value.year,
                value.month,
                holidays,
            )
            return value in holidays
        except PharmacyApiUnavailableError:
            stale = await run_in_threadpool(
                self._cache.get_cached_korean_holidays,
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
