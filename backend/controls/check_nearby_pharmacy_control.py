# 파일명: check_nearby_pharmacy_control.py
# 역할: 현재 위치를 기준으로 가까운 운영 약국을 계산한다.

"""현재 위치를 기준으로 가까운 약국을 조회하는 사용 사례."""

import logging
import math
from collections.abc import Callable
from datetime import UTC, date, datetime, timedelta, tzinfo
from enum import StrEnum
from typing import Protocol
from zoneinfo import ZoneInfo

from boundaries.pharmacy_api_boundary import (
    PharmacyApiResponseError,
    PharmacyApiUnavailableError,
    PharmacyLookupBoundary,
)
from core.config import settings
from entities.nearby_pharmacy_entity import (
    NearbyPharmacy,
    NearbyPharmacySearchResult,
    PharmacyLocationRecord,
)
from entities.pharmacy_catalog_entity import (
    PharmacyCatalogEntry,
    PharmacyHolidaySchedule,
)

_MAX_RESULT_LIMIT = 30
_MAX_SEARCH_DISTANCE_KM = 50.0
_CATALOG_STALE_AFTER = timedelta(days=14)
_HOLIDAY_CACHE_MAX_AGE = timedelta(hours=12)
_HOLIDAY_STALE_FALLBACK_MAX_AGE = timedelta(days=45)
logger = logging.getLogger(__name__)


class PharmacySearchMode(StrEnum):
    ALL = "all"
    OPEN_AT_TIME = "open_at_time"
    LATE_HOURS = "late_hours"
    OFFICIAL_LATE_NIGHT = "official_late_night"
    WEEKEND_HOLIDAY = "weekend_holiday"


class PharmacyCatalogLookup(Protocol):
    def count(self) -> int: ...

    def search_nearby_candidates(
        self,
        *,
        latitude: float,
        longitude: float,
        max_distance_km: float,
    ) -> list[PharmacyCatalogEntry]: ...

    def latest_updated_at(self) -> datetime | None: ...

    def get_cached_holiday_schedules(
        self,
        value: date,
        *,
        max_age: timedelta,
    ) -> dict[str, PharmacyHolidaySchedule] | None: ...

    def replace_holiday_schedules(
        self,
        value: date,
        schedules: list[PharmacyHolidaySchedule],
    ) -> None: ...


class HolidayLookupBoundary(Protocol):
    async def isHoliday(self, value: date) -> bool: ...


class HolidayEmergencyPharmacyBoundary(Protocol):
    async def fetchSchedules(self, value: date) -> list[PharmacyHolidaySchedule]: ...


# 클래스명: CheckNearbyPharmacy
# 역할:
# - 공공 약국 위치 데이터를 사용자용 거리·영업 상태 정보로 가공한다.
# 주요 책임:
# - 좌표와 검색 옵션을 검증한다.
# - API 거리 누락 시 두 좌표의 직선거리를 계산한다.
# - 현재 시각 기준 영업 중 여부를 계산하고 가까운 순으로 정렬한다.
class CheckNearbyPharmacy:
    def __init__(
        self,
        pharmacy_boundary: PharmacyLookupBoundary | None = None,
        *,
        pharmacy_repository: PharmacyCatalogLookup | None = None,
        holiday_boundary: HolidayLookupBoundary | None = None,
        holiday_emergency_boundary: HolidayEmergencyPharmacyBoundary | None = None,
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        if pharmacy_boundary is None and pharmacy_repository is None:
            raise ValueError("A pharmacy data source is required.")
        self._pharmacy_boundary = pharmacy_boundary
        self._pharmacy_repository = pharmacy_repository
        self._holiday_boundary = holiday_boundary
        self._holiday_emergency_boundary = holiday_emergency_boundary
        self._now_provider = now_provider or (
            lambda: datetime.now(ZoneInfo(settings.APPLICATION_TIME_ZONE))
        )

    # 함수명: requestNearbyPharmacies
    # 역할:
    # - 위치 주변 약국을 조회하고 화면에 필요한 형태로 반환한다.
    # 매개변수:
    # - latitude, longitude: 사용자의 WGS84 좌표
    # - open_only: 현재 영업 중인 약국만 반환할지 여부
    # - limit: 반환할 최대 약국 수
    # - max_distance_km: 결과에 포함할 최대 직선거리
    # 반환값:
    # - 영업 상태와 거리가 계산된 NearbyPharmacy 목록
    async def requestNearbyPharmacies(
        self,
        *,
        latitude: float,
        longitude: float,
        open_only: bool = True,
        limit: int = 20,
        max_distance_km: float = 20.0,
    ) -> list[NearbyPharmacy]:
        result = await self.requestNearbyPharmacySearch(
            latitude=latitude,
            longitude=longitude,
            search_mode=(
                PharmacySearchMode.OPEN_AT_TIME
                if open_only
                else PharmacySearchMode.ALL
            ),
            limit=limit,
            max_distance_km=max_distance_km,
        )
        return result.data

    async def requestNearbyPharmacySearch(
        self,
        *,
        latitude: float,
        longitude: float,
        search_mode: PharmacySearchMode = PharmacySearchMode.OPEN_AT_TIME,
        target_datetime: datetime | None = None,
        limit: int = 20,
        max_distance_km: float = 20.0,
    ) -> NearbyPharmacySearchResult:
        self._validate_request(
            latitude=latitude,
            longitude=longitude,
            limit=limit,
            max_distance_km=max_distance_km,
        )
        now = self._normalize_target_datetime(target_datetime)
        is_public_holiday = False
        was_public_holiday = False
        if self._holiday_boundary is not None:
            try:
                is_public_holiday = await self._holiday_boundary.isHoliday(now.date())
                was_public_holiday = await self._holiday_boundary.isHoliday(
                    now.date() - timedelta(days=1)
                )
            except (PharmacyApiUnavailableError, PharmacyApiResponseError):
                # 공휴일 조회 실패가 일반 요일표 기반 약국 검색까지 막지 않게 한다.
                logger.warning(
                    "Holiday lookup unavailable; using regular weekly schedules."
                )

        repository = self._pharmacy_repository
        catalog_updated_at: datetime | None = None
        catalog_is_stale = False
        holiday_schedule_status = "not_applicable"
        catalog_entries: list[PharmacyCatalogEntry] = []
        if repository is not None:
            try:
                latest_updated_at = getattr(repository, "latest_updated_at", None)
                catalog_updated_at = (
                    latest_updated_at() if callable(latest_updated_at) else None
                )
                catalog_is_stale = self._is_catalog_stale(catalog_updated_at)
                if repository.count() > 0:
                    catalog_entries = repository.search_nearby_candidates(
                        latitude=latitude,
                        longitude=longitude,
                        max_distance_km=max_distance_km,
                    )
            except Exception:
                if self._pharmacy_boundary is None:
                    raise
                # 로컬 카탈로그 장애 시에도 공공 위치 조회 API로 검색을 이어간다.
                logger.exception(
                    "Pharmacy catalogue lookup failed; using the live API fallback."
                )

        if catalog_entries:
            holiday_schedules, holiday_schedule_status = (
                await self._resolve_holiday_schedules(
                    now.date(),
                    is_public_holiday=is_public_holiday,
                )
            )
            previous_holiday_schedules, previous_status = (
                await self._resolve_holiday_schedules(
                    now.date() - timedelta(days=1),
                    is_public_holiday=was_public_holiday,
                )
            )
            if previous_status in {"fresh", "stale_fallback", "weekly_fallback"}:
                holiday_schedule_status = self._weaker_schedule_status(
                    holiday_schedule_status,
                    previous_status,
                )
            records = [
                self._catalog_entry_to_location_record(
                    entry,
                    day_of_week=now.isoweekday(),
                    is_public_holiday=is_public_holiday,
                    previous_day_of_week=(now.date() - timedelta(days=1)).isoweekday(),
                    was_public_holiday=was_public_holiday,
                    holiday_schedule=holiday_schedules.get(entry.pharmacy_id),
                    previous_holiday_schedule=previous_holiday_schedules.get(
                        entry.pharmacy_id
                    ),
                )
                for entry in catalog_entries
            ]
            weekend_or_holiday_ids = {
                entry.pharmacy_id
                for entry in catalog_entries
                if entry.has_weekend_or_holiday_hours
            }
        elif self._pharmacy_boundary is not None:
            # 로컬 카탈로그가 준비되지 않았거나 주변 결과가 없으면
            # 위치 조회 API로 보완해 데모와 초기 배포 환경의 공백을 막는다.
            fetch_limit = min(_MAX_RESULT_LIMIT, max(limit * 2, limit))
            records = await self._pharmacy_boundary.searchNearby(
                latitude=latitude,
                longitude=longitude,
                limit=fetch_limit,
            )
            weekend_or_holiday_ids = set()
        else:
            raise PharmacyApiUnavailableError(
                "No pharmacy data source has usable nearby records."
            )

        pharmacies: list[NearbyPharmacy] = []
        seen_ids: set[str] = set()
        for record in records:
            if record.pharmacy_id in seen_ids:
                continue
            seen_ids.add(record.pharmacy_id)
            pharmacy = self._to_nearby_pharmacy(
                record,
                latitude=latitude,
                longitude=longitude,
                now=now,
                is_public_holiday=is_public_holiday,
                has_weekend_or_holiday_hours=(
                    record.pharmacy_id in weekend_or_holiday_ids
                ),
            )
            if pharmacy.distance_km > max_distance_km:
                continue
            if not self._matches_search_mode(
                pharmacy,
                search_mode=search_mode,
                target_datetime=now,
            ):
                continue
            pharmacies.append(pharmacy)

        pharmacies.sort(
            key=lambda item: (
                item.is_open_now is not True,
                item.distance_km,
                item.name,
            )
        )
        return NearbyPharmacySearchResult(
            data=pharmacies[:limit],
            search_mode=search_mode.value,
            target_datetime=now,
            catalog_updated_at=catalog_updated_at,
            catalog_is_stale=catalog_is_stale,
            holiday_schedule_status=holiday_schedule_status,
        )

    @staticmethod
    def _catalog_entry_to_location_record(
        entry: PharmacyCatalogEntry,
        *,
        day_of_week: int,
        is_public_holiday: bool,
        previous_day_of_week: int,
        was_public_holiday: bool,
        holiday_schedule: PharmacyHolidaySchedule | None = None,
        previous_holiday_schedule: PharmacyHolidaySchedule | None = None,
    ) -> PharmacyLocationRecord:
        start_time, end_time = entry.hours_for(
            day_of_week=day_of_week,
            is_public_holiday=is_public_holiday,
        )
        previous_start_time, previous_end_time = entry.hours_for(
            day_of_week=previous_day_of_week,
            is_public_holiday=was_public_holiday,
        )
        if holiday_schedule is not None:
            start_time = holiday_schedule.start_time
            end_time = holiday_schedule.end_time
        if previous_holiday_schedule is not None:
            previous_start_time = previous_holiday_schedule.start_time
            previous_end_time = previous_holiday_schedule.end_time
        return PharmacyLocationRecord(
            pharmacy_id=entry.pharmacy_id,
            name=entry.name,
            address=entry.address,
            telephone=entry.telephone,
            latitude=entry.latitude,
            longitude=entry.longitude,
            distance_km=None,
            start_time=start_time,
            end_time=end_time,
            previous_start_time=previous_start_time,
            previous_end_time=previous_end_time,
            schedule_source=(
                "nemc_holiday_roster"
                if holiday_schedule is not None
                else "nemc_weekly_report"
            ),
            schedule_is_date_specific=holiday_schedule is not None,
            official_designations=entry.official_designations,
            weekly_hours=entry.weekly_hours,
            source_updated_at=entry.source_updated_at,
        )

    @staticmethod
    def _validate_request(
        *,
        latitude: float,
        longitude: float,
        limit: int,
        max_distance_km: float,
    ) -> None:
        if not math.isfinite(latitude) or not -90 <= latitude <= 90:
            raise ValueError("Latitude must be between -90 and 90.")
        if not math.isfinite(longitude) or not -180 <= longitude <= 180:
            raise ValueError("Longitude must be between -180 and 180.")
        if not 1 <= limit <= _MAX_RESULT_LIMIT:
            raise ValueError(f"Limit must be between 1 and {_MAX_RESULT_LIMIT}.")
        if (
            not math.isfinite(max_distance_km)
            or not 0.1 <= max_distance_km <= _MAX_SEARCH_DISTANCE_KM
        ):
            raise ValueError(
                "Maximum distance must be between 0.1 and 50 kilometers."
            )

    def _normalize_target_datetime(self, value: datetime | None) -> datetime:
        timezone = ZoneInfo(settings.APPLICATION_TIME_ZONE)
        current = self._now_provider().astimezone(timezone)
        if value is None:
            return current
        normalized = (
            value.replace(tzinfo=timezone)
            if value.tzinfo is None
            else value.astimezone(timezone)
        )
        if normalized < current - timedelta(days=7):
            raise ValueError("Target date cannot be more than 7 days in the past.")
        if normalized > current + timedelta(days=366):
            raise ValueError("Target date cannot be more than 366 days in the future.")
        return normalized

    async def _resolve_holiday_schedules(
        self,
        value: date,
        *,
        is_public_holiday: bool,
    ) -> tuple[dict[str, PharmacyHolidaySchedule], str]:
        if not is_public_holiday:
            return {}, "not_applicable"
        repository = self._pharmacy_repository
        boundary = self._holiday_emergency_boundary
        if repository is None or boundary is None:
            return {}, "weekly_fallback"
        cached = repository.get_cached_holiday_schedules(
            value,
            max_age=_HOLIDAY_CACHE_MAX_AGE,
        )
        if cached is not None:
            return cached, "fresh" if cached else "weekly_fallback"
        try:
            schedules = await boundary.fetchSchedules(value)
            repository.replace_holiday_schedules(value, schedules)
            return (
                {schedule.pharmacy_id: schedule for schedule in schedules},
                "fresh" if schedules else "weekly_fallback",
            )
        except (PharmacyApiUnavailableError, PharmacyApiResponseError):
            stale = repository.get_cached_holiday_schedules(
                value,
                max_age=_HOLIDAY_STALE_FALLBACK_MAX_AGE,
            )
            if stale is not None:
                return stale, "stale_fallback"
            return {}, "weekly_fallback"

    @staticmethod
    def _weaker_schedule_status(first: str, second: str) -> str:
        rank = {
            "not_applicable": 0,
            "fresh": 1,
            "stale_fallback": 2,
            "weekly_fallback": 3,
        }
        return max((first, second), key=lambda value: rank.get(value, 3))

    @staticmethod
    def _is_catalog_stale(updated_at: datetime | None) -> bool:
        if updated_at is None:
            return True
        aware_updated_at = (
            updated_at.replace(tzinfo=UTC)
            if updated_at.tzinfo is None
            else updated_at.astimezone(UTC)
        )
        return aware_updated_at < datetime.now(UTC) - _CATALOG_STALE_AFTER

    @staticmethod
    def _matches_search_mode(
        pharmacy: NearbyPharmacy,
        *,
        search_mode: PharmacySearchMode,
        target_datetime: datetime,
    ) -> bool:
        if search_mode is PharmacySearchMode.ALL:
            return True
        if search_mode is PharmacySearchMode.OPEN_AT_TIME:
            return pharmacy.is_open_now is True
        if search_mode is PharmacySearchMode.LATE_HOURS:
            return pharmacy.is_open_late or pharmacy.is_24_hours
        if search_mode is PharmacySearchMode.OFFICIAL_LATE_NIGHT:
            return pharmacy.is_official_late_night
        return (
            target_datetime.isoweekday() in {6, 7}
            or pharmacy.is_public_holiday
        ) and pharmacy.today_open_time is not None

    @classmethod
    def _to_nearby_pharmacy(
        cls,
        record: PharmacyLocationRecord,
        *,
        latitude: float,
        longitude: float,
        now: datetime,
        is_public_holiday: bool = False,
        has_weekend_or_holiday_hours: bool = False,
    ) -> NearbyPharmacy:
        start_minutes = cls._parse_minutes(record.start_time)
        end_minutes = cls._parse_minutes(record.end_time, allow_24=True)
        previous_start_minutes = cls._parse_minutes(record.previous_start_time)
        previous_end_minutes = cls._parse_minutes(
            record.previous_end_time,
            allow_24=True,
        )
        is_open_now = cls._is_open_now(
            now=now,
            start_minutes=start_minutes,
            end_minutes=end_minutes,
            previous_start_minutes=previous_start_minutes,
            previous_end_minutes=previous_end_minutes,
        )
        distance_km = record.distance_km
        if distance_km is None or distance_km < 0:
            distance_km = cls._haversine_distance(
                latitude,
                longitude,
                record.latitude,
                record.longitude,
            )
        is_24_hours = (
            start_minutes == 0
            and end_minutes is not None
            and (end_minutes == 0 or end_minutes >= 23 * 60 + 59)
        )
        is_open_late = cls._is_late_schedule(
            start_minutes=start_minutes,
            end_minutes=end_minutes,
        )
        designation = record.official_designations.get("public_late_night")
        if not isinstance(designation, dict):
            designation = {}
        operating_days = designation.get("operating_days", [])
        is_official_late_night = bool(designation) and (
            not isinstance(operating_days, list)
            or not operating_days
            or now.isoweekday() in operating_days
        )
        raw_verified_at = designation.get("verified_at")
        try:
            designation_verified_at = (
                date.fromisoformat(str(raw_verified_at))
                if raw_verified_at
                else None
            )
        except ValueError:
            designation_verified_at = None
        designation_is_stale = (
            designation_verified_at is None
            or designation_verified_at < now.date() - timedelta(days=90)
        )
        minutes_until_close = cls._minutes_until_close(
            now=now,
            is_open_now=is_open_now,
            start_minutes=start_minutes,
            end_minutes=end_minutes,
            previous_start_minutes=previous_start_minutes,
            previous_end_minutes=previous_end_minutes,
        )
        next_open_at = cls._next_open_at(
            now=now,
            is_open_now=is_open_now,
            weekly_hours=record.weekly_hours,
            is_public_holiday=is_public_holiday,
        )
        return NearbyPharmacy(
            pharmacy_id=record.pharmacy_id,
            name=record.name,
            address=record.address,
            telephone=record.telephone,
            latitude=record.latitude,
            longitude=record.longitude,
            distance_km=round(distance_km, 2),
            today_open_time=cls._format_time(start_minutes),
            today_close_time=cls._format_time(end_minutes),
            is_open_now=is_open_now,
            is_24_hours=is_24_hours,
            is_open_late=is_open_late,
            has_weekend_or_holiday_hours=has_weekend_or_holiday_hours,
            is_public_holiday=is_public_holiday,
            is_official_late_night=is_official_late_night,
            designation_source_name=(
                str(designation.get("source_name"))
                if designation.get("source_name")
                else None
            ),
            designation_source_url=(
                str(designation.get("source_url"))
                if designation.get("source_url")
                else None
            ),
            designation_verified_at=designation_verified_at,
            designation_is_stale=designation_is_stale,
            schedule_date=now.date(),
            schedule_source=record.schedule_source,
            schedule_is_date_specific=record.schedule_is_date_specific,
            minutes_until_close=minutes_until_close,
            next_open_at=next_open_at,
            source_updated_at=cls._source_updated_at_iso(
                record.source_updated_at,
                target_timezone=now.tzinfo,
            ),
        )

    @staticmethod
    def _minutes_until_close(
        *,
        now: datetime,
        is_open_now: bool | None,
        start_minutes: int | None,
        end_minutes: int | None,
        previous_start_minutes: int | None,
        previous_end_minutes: int | None,
    ) -> int | None:
        """현재 영업 중일 때 폐점까지 남은 분을 계산한다."""
        if is_open_now is not True:
            return None
        current_minutes = now.hour * 60 + now.minute
        if (
            previous_start_minutes is not None
            and previous_end_minutes is not None
            and previous_end_minutes < previous_start_minutes
            and current_minutes < previous_end_minutes
        ):
            return previous_end_minutes - current_minutes
        if start_minutes is None or end_minutes is None:
            return None
        if start_minutes == 0 and end_minutes in {0, 24 * 60}:
            return None
        if end_minutes > start_minutes:
            return max(end_minutes - current_minutes, 0)
        if end_minutes < start_minutes and current_minutes >= start_minutes:
            return 24 * 60 - current_minutes + end_minutes
        return None

    @classmethod
    def _next_open_at(
        cls,
        *,
        now: datetime,
        is_open_now: bool | None,
        weekly_hours: dict[str, tuple[str, str]] | None,
        is_public_holiday: bool = False,
    ) -> str | None:
        """문을 닫은 약국의 다음 정규 영업 시작 시각을 최대 일주일 탐색한다."""
        if is_open_now is True or not weekly_hours:
            return None
        current_minutes = now.hour * 60 + now.minute
        for day_offset in range(0, 8):
            target_date = now.date() + timedelta(days=day_offset)
            schedule_key = (
                "8"
                if day_offset == 0 and is_public_holiday
                else str(target_date.isoweekday())
            )
            start_value, _ = weekly_hours.get(
                schedule_key,
                ("", ""),
            )
            start_minutes = cls._parse_minutes(start_value)
            if start_minutes is None:
                continue
            if day_offset == 0 and start_minutes <= current_minutes:
                continue
            next_open = datetime(
                target_date.year,
                target_date.month,
                target_date.day,
                start_minutes // 60,
                start_minutes % 60,
                tzinfo=now.tzinfo,
            )
            return next_open.isoformat()
        return None

    @staticmethod
    def _source_updated_at_iso(
        value: datetime | None,
        *,
        target_timezone: tzinfo | None,
    ) -> str | None:
        """카탈로그 갱신 시각을 현재 화면 시간대로 안전하게 변환한다."""
        if value is None:
            return None
        utc_value = value.replace(tzinfo=UTC) if value.tzinfo is None else value
        if target_timezone is None:
            return utc_value.isoformat()
        return utc_value.astimezone(target_timezone).isoformat()

    @staticmethod
    def _is_late_schedule(
        *,
        start_minutes: int | None,
        end_minutes: int | None,
    ) -> bool:
        if start_minutes is None or end_minutes is None:
            return False
        if end_minutes < start_minutes:
            return True
        if end_minutes == start_minutes:
            return start_minutes == 0
        return end_minutes >= 22 * 60

    @staticmethod
    def _parse_minutes(value: str, *, allow_24: bool = False) -> int | None:
        normalized = "".join(character for character in value if character.isdigit())
        if len(normalized) not in {3, 4}:
            return None
        normalized = normalized.zfill(4)
        hour = int(normalized[:2])
        minute = int(normalized[2:])
        if allow_24 and hour == 24 and minute == 0:
            return 24 * 60
        if hour > 23 or minute > 59:
            return None
        return hour * 60 + minute

    @staticmethod
    def _is_open_now(
        *,
        now: datetime,
        start_minutes: int | None,
        end_minutes: int | None,
        previous_start_minutes: int | None = None,
        previous_end_minutes: int | None = None,
    ) -> bool | None:
        current_minutes = now.hour * 60 + now.minute
        if start_minutes is not None and end_minutes is not None:
            if end_minutes > start_minutes:
                if start_minutes <= current_minutes < end_minutes:
                    return True
            elif end_minutes < start_minutes:
                if current_minutes >= start_minutes:
                    return True
            elif start_minutes == 0:
                return True

        if (
            previous_start_minutes is not None
            and previous_end_minutes is not None
            and previous_end_minutes < previous_start_minutes
            and current_minutes < previous_end_minutes
        ):
            return True
        if start_minutes is None or end_minutes is None:
            return None
        return False

    @staticmethod
    def _format_time(minutes: int | None) -> str | None:
        if minutes is None:
            return None
        if minutes == 24 * 60:
            return "24:00"
        return f"{minutes // 60:02d}:{minutes % 60:02d}"

    @staticmethod
    def _haversine_distance(
        start_latitude: float,
        start_longitude: float,
        end_latitude: float,
        end_longitude: float,
    ) -> float:
        earth_radius_km = 6371.0088
        start_latitude_radians = math.radians(start_latitude)
        end_latitude_radians = math.radians(end_latitude)
        latitude_delta = math.radians(end_latitude - start_latitude)
        longitude_delta = math.radians(end_longitude - start_longitude)
        haversine = (
            math.sin(latitude_delta / 2) ** 2
            + math.cos(start_latitude_radians)
            * math.cos(end_latitude_radians)
            * math.sin(longitude_delta / 2) ** 2
        )
        return earth_radius_km * 2 * math.asin(math.sqrt(haversine))
