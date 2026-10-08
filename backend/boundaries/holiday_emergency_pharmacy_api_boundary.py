# File Name: holiday_emergency_pharmacy_api_boundary.py
# Role: Fetches and caches exact-date holiday pharmacy schedules from the official NEMC roster.
"""Date-specific pharmacy schedules from the official NEMC holiday roster."""

import asyncio
from datetime import UTC, date, datetime, timedelta
import logging
import re
import time
import xml.etree.ElementTree as ElementTree

import httpx

from boundaries.pharmacy_api_boundary import (
    PharmacyApiResponseError,
    PharmacyApiUnavailableError,
)
from core.config import settings
from entities.pharmacy_catalog_entity import PharmacyHolidaySchedule


logger = logging.getLogger(__name__)
_TIME_RANGE_PATTERN = re.compile(
    r"(?P<start>\d{1,2})\s*:\s*(?P<start_minute>\d{2})"
    r"\s*[~\-–]\s*"
    r"(?P<end>\d{1,2})\s*:\s*(?P<end_minute>\d{2})"
)
_PAGE_SIZE = 20_000
# A search needs the roster of the target day and the day before; 16 dates cover the dates in
# use at one time and keep both per-date tables from growing with every date ever requested.
_MAX_TRACKED_DATES = 16


# Class Name: HolidayEmergencyPharmacyAPI
# Role:
# - Provides nationwide pharmacy opening hours for one holiday date.
# Responsibilities:
# - Page through the official roster, validate hours and retain a 12-hour per-date cache.
# - Answer a date whose roster just failed from a short failure mark instead of the provider.
# Attributes:
# - _client (AsyncClient | None): Borrowed or lazily created HTTP client.
# - _cache (dict): Fetch timestamps and immutable schedules indexed by date; newest 16 dates.
# - _failed_until (dict[date, float]): Monotonic time until which a date is not requested again
#   after the provider was unavailable; newest 16 dates.
# - _lock (asyncio.Lock): Serializes cache fills.
class HolidayEmergencyPharmacyAPI:
    """Queries the nationwide, exact-date NEMC holiday pharmacy roster."""

    _BASE_URL = (
        "https://apis.data.go.kr/B552657/"
        "HolidyEmgncClnicInsttInfoInqireService/"
        "getHolidyClnicPosblEgytInfoInqire"
    )

    # Function Name: __init__
    # Description:
    # - Initialize an empty schedule cache, synchronization lock and HTTP-client ownership state.
    # Parameters:
    # - client (httpx.AsyncClient | None): Optional borrowed HTTP client; omitted to create an owned client.
    # Returns:
    # - None; no upstream request is made.
    def __init__(self, *, client: httpx.AsyncClient | None = None) -> None:
        self._client = client
        self._owns_client = client is None
        self._lock = asyncio.Lock()
        self._cache: dict[
            date,
            tuple[datetime, tuple[PharmacyHolidaySchedule, ...]],
        ] = {}
        self._failed_until: dict[date, float] = {}

    # Function Name: fetchSchedules
    # Description:
    # - Load every roster page for the requested date, deduplicate pharmacy IDs and reuse fresh cached results.
    # - After the provider was unavailable for a date, fail that date immediately for
    #   PUBLIC_API_FAILURE_CACHE_SECONDS: without the mark every search on a holiday waited a full
    #   provider timeout, one after another behind the fill lock.
    # Parameters:
    # - value (date): Exact holiday date to query.
    # Returns:
    # - Pharmacy holiday schedules; raises an availability or response error when retrieval fails.
    async def fetchSchedules(self, value: date) -> list[PharmacyHolidaySchedule]:
        """Fetches every pharmacy schedule published for one holiday date."""

        cached = self._cache.get(value)
        if (
            cached is not None
            and cached[0] >= datetime.now(UTC) - timedelta(hours=12)
        ):
            return list(cached[1])
        self._raise_if_recently_failed(value)
        async with self._lock:
            cached = self._cache.get(value)
            if (
                cached is not None
                and cached[0] >= datetime.now(UTC) - timedelta(hours=12)
            ):
                return list(cached[1])
            # Requests that queued behind a failing fill must not repeat it.
            self._raise_if_recently_failed(value)
            if not settings.PUBLIC_DATA_API_KEY.strip():
                raise PharmacyApiUnavailableError(
                    "Public holiday pharmacy credentials are unavailable."
                )
            page_no = 1
            schedules_by_id: dict[str, PharmacyHolidaySchedule] = {}
            try:
                while True:
                    root = await self._fetch_page(value, page_no=page_no)
                    total_count = self._parse_nonnegative_int(
                        root.findtext(".//totalCount"),
                        field_name="totalCount",
                    )
                    items = root.findall(".//item")
                    for item in items:
                        schedule = self._parse_item(item, value)
                        if schedule is not None:
                            schedules_by_id[schedule.pharmacy_id] = schedule
                    if page_no * _PAGE_SIZE >= total_count or not items:
                        break
                    page_no += 1
            except PharmacyApiUnavailableError:
                self._failed_until[value] = (
                    time.monotonic() + settings.PUBLIC_API_FAILURE_CACHE_SECONDS
                )
                self._keep_newest_dates(self._failed_until)
                raise
            schedules = tuple(schedules_by_id.values())
            # Re-insert so a refreshed date counts as the newest entry.
            self._cache.pop(value, None)
            self._cache[value] = (datetime.now(UTC), schedules)
            self._keep_newest_dates(self._cache)
            return list(schedules)

    # Function Name: _raise_if_recently_failed
    # Description:
    # - Reject a date whose failure mark is still in the future and drop a mark that has expired,
    #   so a date is only ever requested without a mark and a success leaves none behind.
    # Parameters:
    # - value (date): Roster date about to be requested.
    # Returns:
    # - None; raises PharmacyApiUnavailableError during the cool-down.
    def _raise_if_recently_failed(self, value: date) -> None:
        failed_until = self._failed_until.get(value)
        if failed_until is None:
            return
        if failed_until > time.monotonic():
            raise PharmacyApiUnavailableError(
                "The NEMC holiday pharmacy roster is temporarily unavailable."
            )
        del self._failed_until[value]

    # Function Name: _keep_newest_dates
    # Description:
    # - Bound a per-date table to the most recently written dates. A date is absent when it is
    #   written (failure marks) or re-inserted (cache), so dict order is write order and the first
    #   keys are the oldest.
    # Parameters:
    # - table (dict[date, object]): Per-date cache or failure table to trim in place.
    # Returns:
    # - None.
    @staticmethod
    def _keep_newest_dates(table: dict[date, object]) -> None:
        while len(table) > _MAX_TRACKED_DATES:
            del table[next(iter(table))]

    # Function Name: close
    # Description:
    # - Close only the HTTP client created by this boundary and clear its reference.
    # Parameters:
    # - None.
    # Returns:
    # - None; a borrowed client remains open.
    async def close(self) -> None:
        if self._owns_client and self._client is not None:
            await self._client.aclose()
            self._client = None

    # Function Name: _fetch_page
    # Description:
    # - Fetch and parse one NEMC XML page, mapping transport, XML and provider-status failures to unavailability.
    # Parameters:
    # - value (date): Exact holiday date encoded as YYYYMMDD for the roster query.
    # - page_no (int): One-based upstream result page number.
    # Returns:
    # - Validated XML document root.
    async def _fetch_page(self, value: date, *, page_no: int) -> ElementTree.Element:
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
                    "serviceKey": settings.PUBLIC_DATA_API_KEY,
                    "QT": value.strftime("%Y%m%d"),
                    "pageNo": page_no,
                    "numOfRows": _PAGE_SIZE,
                },
            )
            response.raise_for_status()
            root = ElementTree.fromstring(response.content)
        except (httpx.HTTPError, OSError, ElementTree.ParseError, ValueError, LookupError) as exc:
            logger.warning(
                "Holiday emergency pharmacy lookup failed: %s",
                type(exc).__name__,
            )
            raise PharmacyApiUnavailableError(
                "The NEMC holiday pharmacy roster is temporarily unavailable."
            ) from exc

        result_code = (root.findtext(".//resultCode") or "").strip()
        # A gateway error envelope must not be stored as an empty holiday roster.
        if root.find(".//cmmMsgHeader") is not None or result_code not in {"", "00", "0000"}:
            raise PharmacyApiUnavailableError(
                "The NEMC holiday pharmacy roster rejected the request."
            )
        return root

    # Function Name: _parse_item
    # Description:
    # - Select a pharmacy's matching duty date and validate its opening-time range; ignore non-pharmacy or incomplete rows.
    # Parameters:
    # - item (ElementTree.Element): One NEMC institution XML element.
    # - value (date): Holiday date whose duty-day slot should be selected.
    # Returns:
    # - A dated schedule, or None when the row cannot supply one.
    @classmethod
    def _parse_item(
        cls,
        item: ElementTree.Element,
        value: date,
    ) -> PharmacyHolidaySchedule | None:
        pharmacy_id = (item.findtext("hpid") or "").strip()
        if not pharmacy_id:
            return None
        institution_type = (item.findtext("dutyDiv") or "").strip()
        if institution_type and institution_type != "H":
            return None
        expected_dates = {
            value.strftime("%Y%m%d"),
            value.strftime("%Y-%m-%d"),
        }
        for index in range(1, 11):
            raw_date = (item.findtext(f"dutyDay{index}") or "").strip()
            if raw_date not in expected_dates:
                continue
            raw_time = (item.findtext(f"dutyDaytime{index}") or "").strip()
            time_range = cls._parse_time_range(raw_time)
            if time_range is None:
                return None
            return PharmacyHolidaySchedule(
                pharmacy_id=pharmacy_id,
                schedule_date=value,
                start_time=time_range[0],
                end_time=time_range[1],
                note=(item.findtext("dutyDayEtc") or "").strip(),
            )
        return None

    # Function Name: _parse_time_range
    # Description:
    # - Parse a clock range and allow 24:00 only as a closing time.
    # Parameters:
    # - value (str): Roster text containing start and end times.
    # Returns:
    # - Zero-padded HHMM opening and closing times, or None for an invalid range.
    @staticmethod
    def _parse_time_range(value: str) -> tuple[str, str] | None:
        match = _TIME_RANGE_PATTERN.search(value)
        if match is None:
            return None
        start_hour = int(match.group("start"))
        start_minute = int(match.group("start_minute"))
        end_hour = int(match.group("end"))
        end_minute = int(match.group("end_minute"))
        if (
            start_hour > 23
            or start_minute > 59
            or end_hour > 24
            or end_minute > 59
            or (end_hour == 24 and end_minute != 0)
        ):
            return None
        return (
            f"{start_hour:02d}{start_minute:02d}",
            f"{end_hour:02d}{end_minute:02d}",
        )

    # Function Name: _parse_nonnegative_int
    # Description:
    # - Read a nonnegative roster count, defaulting absent text to zero and rejecting malformed or negative values.
    # Parameters:
    # - value (str | None): Raw numeric text from the XML response, or None.
    # - field_name (str): Response field name to include in validation errors.
    # Returns:
    # - Validated integer; raises PharmacyApiResponseError on invalid input.
    @staticmethod
    def _parse_nonnegative_int(value: str | None, *, field_name: str) -> int:
        try:
            parsed = int((value or "0").strip())
        except ValueError as exc:
            raise PharmacyApiResponseError(
                f"Invalid {field_name} in holiday pharmacy response."
            ) from exc
        if parsed < 0:
            raise PharmacyApiResponseError(
                f"Invalid {field_name} in holiday pharmacy response."
            )
        return parsed
