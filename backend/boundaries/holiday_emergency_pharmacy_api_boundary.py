"""Date-specific pharmacy schedules from the official NEMC holiday roster."""

import asyncio
from datetime import UTC, date, datetime, timedelta
import logging
import re
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


class HolidayEmergencyPharmacyAPI:
    """Queries the nationwide, exact-date NEMC holiday pharmacy roster."""

    _BASE_URL = (
        "https://apis.data.go.kr/B552657/"
        "HolidyEmgncClnicInsttInfoInqireService/"
        "getHolidyClnicPosblEgytInfoInqire"
    )

    def __init__(self, *, client: httpx.AsyncClient | None = None) -> None:
        self._client = client
        self._owns_client = client is None
        self._lock = asyncio.Lock()
        self._cache: dict[
            date,
            tuple[datetime, tuple[PharmacyHolidaySchedule, ...]],
        ] = {}

    async def fetchSchedules(self, value: date) -> list[PharmacyHolidaySchedule]:
        """Fetches every pharmacy schedule published for one holiday date."""

        cached = self._cache.get(value)
        if (
            cached is not None
            and cached[0] >= datetime.now(UTC) - timedelta(hours=12)
        ):
            return list(cached[1])
        async with self._lock:
            cached = self._cache.get(value)
            if (
                cached is not None
                and cached[0] >= datetime.now(UTC) - timedelta(hours=12)
            ):
                return list(cached[1])
            if not settings.PUBLIC_DATA_API_KEY.strip():
                raise PharmacyApiUnavailableError(
                    "Public holiday pharmacy credentials are unavailable."
                )
            page_no = 1
            schedules_by_id: dict[str, PharmacyHolidaySchedule] = {}
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
                if page_no * 1000 >= total_count or not items:
                    break
                page_no += 1
            schedules = tuple(schedules_by_id.values())
            self._cache[value] = (datetime.now(UTC), schedules)
            return list(schedules)

    async def close(self) -> None:
        if self._owns_client and self._client is not None:
            await self._client.aclose()
            self._client = None

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
                    "QD": "H",
                    "QT": value.strftime("%Y%m%d"),
                    "pageNo": page_no,
                    "numOfRows": 1000,
                },
            )
            response.raise_for_status()
            root = ElementTree.fromstring(response.content)
        except (httpx.HTTPError, OSError, ElementTree.ParseError) as exc:
            logger.warning(
                "Holiday emergency pharmacy lookup failed: %s",
                type(exc).__name__,
            )
            raise PharmacyApiUnavailableError(
                "The NEMC holiday pharmacy roster is temporarily unavailable."
            ) from exc

        result_code = (root.findtext(".//resultCode") or "").strip()
        if result_code not in {"", "00", "0000"}:
            raise PharmacyApiUnavailableError(
                "The NEMC holiday pharmacy roster rejected the request."
            )
        return root

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
