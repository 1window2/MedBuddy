# File Name: check_nearby_pharmacy_control.py
# Role: Ranks nearby pharmacies using distance, operating hours, holiday rosters, official designations and source freshness.

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


# Class Name: PharmacySearchMode
# Role:
# - Enumerates unrestricted, open-at-time, late-hours, designated-night and weekend/holiday pharmacy searches.
# Responsibilities:
# - Keep public search-mode values stable across the API and pharmacy filtering logic.
class PharmacySearchMode(StrEnum):
    ALL = "all"
    OPEN_AT_TIME = "open_at_time"
    LATE_HOURS = "late_hours"
    OFFICIAL_LATE_NIGHT = "official_late_night"
    WEEKEND_HOLIDAY = "weekend_holiday"


# Class Name: PharmacyCatalogLookup
# Role:
# - Defines persisted pharmacy lookup and date-specific holiday-roster caching required by nearby search.
# Responsibilities:
# - Supply geographic candidates and catalog timestamps and manage dated holiday-roster replacement and cache age.
class PharmacyCatalogLookup(Protocol):
    # Function Name: count
    # Description:
    # - Reports whether the persisted pharmacy catalog has usable seed rows.
    # Parameters:
    # - None.
    # Returns:
    # - Number of catalog entries.
    def count(self) -> int: ...

    # Function Name: search_nearby_candidates
    # Description:
    # - Selects catalog entries near the search coordinates for exact distance and hours filtering.
    # Parameters:
    # - latitude (float): Search-origin latitude in degrees.
    # - longitude (float): Search-origin longitude in degrees.
    # - max_distance_km (float): Maximum accepted search radius in kilometers.
    # Returns:
    # - Candidate pharmacy catalog entries within the repository's geographic search bounds.
    def search_nearby_candidates(
        self,
        *,
        latitude: float,
        longitude: float,
        max_distance_km: float,
    ) -> list[PharmacyCatalogEntry]: ...

    # Function Name: latest_updated_at
    # Description:
    # - Exposes the newest catalog update for search-result freshness reporting.
    # Parameters:
    # - None.
    # Returns:
    # - Latest catalog timestamp, or None when no update is available.
    def latest_updated_at(self) -> datetime | None: ...

    # Function Name: get_cached_holiday_schedules
    # Description:
    # - Retrieves one date's pharmacy roster only within the accepted cache age.
    # Parameters:
    # - value (date): Calendar date for the requested schedule or validation.
    # - max_age (timedelta): Maximum acceptable age of the cached holiday roster.
    # Returns:
    # - Roster keyed by pharmacy ID, or None for an absent or expired cache.
    def get_cached_holiday_schedules(
        self,
        value: date,
        *,
        max_age: timedelta,
    ) -> dict[str, PharmacyHolidaySchedule] | None: ...

    # Function Name: replace_holiday_schedules
    # Description:
    # - Replaces the persisted holiday pharmacy roster for one calendar date.
    # Parameters:
    # - value (date): Calendar date for the requested schedule or validation.
    # - schedules (list[PharmacyHolidaySchedule]): Complete date-specific pharmacy roster replacing the cached entries.
    # Returns:
    # - None.
    def replace_holiday_schedules(
        self,
        value: date,
        schedules: list[PharmacyHolidaySchedule],
    ) -> None: ...


# Class Name: HolidayLookupBoundary
# Role:
# - Defines asynchronous public-holiday classification for pharmacy schedule selection.
# Responsibilities:
# - Let nearby search select holiday hours without depending on a particular calendar provider.
class HolidayLookupBoundary(Protocol):
    # Function Name: isHoliday
    # Description:
    # - Checks whether the requested date is an official public holiday.
    # Parameters:
    # - value (date): Calendar date for the requested schedule or validation.
    # Returns:
    # - True for a recognized public holiday.
    async def isHoliday(self, value: date) -> bool: ...


# Class Name: HolidayEmergencyPharmacyBoundary
# Role:
# - Defines date-specific emergency pharmacy roster retrieval independently of weekly hours.
# Responsibilities:
# - Supply dated opening intervals that take precedence over regular weekly hours.
class HolidayEmergencyPharmacyBoundary(Protocol):
    # Function Name: fetchSchedules
    # Description:
    # - Retrieves the official emergency pharmacy opening roster for one date.
    # Parameters:
    # - value (date): Calendar date for the requested schedule or validation.
    # Returns:
    # - Date-specific pharmacy schedules.
    async def fetchSchedules(self, value: date) -> list[PharmacyHolidaySchedule]: ...


# 클래스명: CheckNearbyPharmacy
# 역할:
# - 공공 약국 위치 데이터를 사용자용 거리·영업 상태 정보로 가공한다.
# 주요 책임:
# - 좌표와 검색 옵션을 검증한다.
# - API 거리 누락 시 두 좌표의 직선거리를 계산한다.
# - 현재 시각 기준 영업 중 여부를 계산하고 가까운 순으로 정렬한다.
# 속성:
# - _pharmacy_boundary (PharmacyLookupBoundary | None): 선택적 실시간 약국 위치·운영 시간 제공 경계.
# - _pharmacy_repository (PharmacyCatalogLookup | None): 약국 카탈로그와 공휴일 당번표 저장소.
# - _holiday_boundary (HolidayLookupBoundary | None): 선택적 법정 공휴일 판정 경계.
# - _holiday_emergency_boundary (HolidayEmergencyPharmacyBoundary | None): 선택적 날짜별 당번 약국 명단 제공 경계.
# - _now_provider (Callable[[], datetime]): 검색 기준 시각을 제공하는 주입 가능한 시계 함수.
class CheckNearbyPharmacy:
    # Function Name: __init__
    # Description:
    # - Requires at least one pharmacy data source and binds optional holiday lookups and the application-zone clock.
    # Parameters:
    # - pharmacy_boundary (PharmacyLookupBoundary | None): Optional live pharmacy location and hours provider.
    # - pharmacy_repository (PharmacyCatalogLookup | None): Repository for pharmacy catalog entries and holiday rosters.
    # - holiday_boundary (HolidayLookupBoundary | None): Optional official public-holiday classifier.
    # - holiday_emergency_boundary (HolidayEmergencyPharmacyBoundary | None): Optional date-specific emergency pharmacy roster provider.
    # - now_provider (Callable[[], datetime] | None): Injectable clock returning the search reference time.
    # Returns:
    # - None.
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

    # Function Name: requestNearbyPharmacies
    # Description:
    # - Adapts the legacy open-only flag to the richer pharmacy search modes.
    # Parameters:
    # - latitude (float): Search-origin latitude in degrees.
    # - longitude (float): Search-origin longitude in degrees.
    # - open_only (bool): Whether results must be open at the reference time.
    # - limit (int): Maximum number of results to return.
    # - max_distance_km (float): Maximum accepted search radius in kilometers.
    # Returns:
    # - Ranked nearby pharmacies without the search metadata envelope.
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

    # 함수이름: requestNearbyPharmacySearch
    # 함수역할:
    # - 좌표·시간을 검증하고 카탈로그 또는 실시간 API에서 영업·거리 조건에 맞는 약국과 자료 최신성을 조회한다.
    # 매개변수:
    # - latitude (float): 검색 기준 위치의 위도(도).
    # - longitude (float): 검색 기준 위치의 경도(도).
    # - search_mode (PharmacySearchMode): 요청한 약국 영업 시간·공식 지정 필터.
    # - target_datetime (datetime | None): 선택적 약국 영업 여부 조회 기준 시각.
    # - limit (int): 반환할 최대 결과 수.
    # - max_distance_km (float): 허용할 최대 검색 반경(km).
    # 반환값:
    # - 필터링된 약국 목록, 기준 시각과 카탈로그·공휴일 자료 상태.
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
                not (
                    item.is_open_late
                    or item.is_24_hours
                    or item.is_official_late_night
                ),
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

    # 함수이름: _catalog_entry_to_location_record
    # 함수역할:
    # - 오늘·전날의 주간 운영 시간에 날짜별 공휴일 당번표를 우선 적용한다.
    # 매개변수:
    # - entry (PharmacyCatalogEntry): 저장된 약국 식별·위치·운영 시간 정보.
    # - day_of_week (int): 월요일 1부터 일요일 7까지의 ISO 요일.
    # - is_public_holiday (bool): 조회 날짜가 법정 공휴일인지 여부.
    # - previous_day_of_week (int): 이전 날짜의 ISO 요일.
    # - was_public_holiday (bool): 이전 날짜가 법정 공휴일이었는지 여부.
    # - holiday_schedule (PharmacyHolidaySchedule | None): 오늘 주간 운영 시간보다 우선할 날짜별 당번표.
    # - previous_holiday_schedule (PharmacyHolidaySchedule | None): 전날 야간 이월 판정에 사용할 날짜별 당번표.
    # 반환값:
    # - 야간 이월 판정과 운영 근거를 포함한 약국 위치 레코드.
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

    # 함수이름: _validate_request
    # 함수역할:
    # - 좌표가 유한한 지리 범위인지 확인하고 결과 수와 반경을 지원 한도 내로 제한한다.
    # 매개변수:
    # - latitude (float): 검색 기준 위치의 위도(도).
    # - longitude (float): 검색 기준 위치의 경도(도).
    # - limit (int): 반환할 최대 결과 수.
    # - max_distance_km (float): 허용할 최대 검색 반경(km).
    # 반환값:
    # - 없음.
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

    # Function Name: _normalize_target_datetime
    # Description:
    # - Applies the application time zone and rejects dates outside the seven-day past and 366-day future window.
    # Parameters:
    # - value (datetime | None): Requested search time; naive values use APPLICATION_TIME_ZONE, and None selects the current application time.
    # Returns:
    # - Aware target datetime, or the current application time when omitted.
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

    # Function Name: _resolve_holiday_schedules
    # Description:
    # - Uses a fresh holiday roster, fetches a replacement, or falls back to stale cache and weekly hours on service errors.
    # Parameters:
    # - value (date): Calendar date for the requested schedule or validation.
    # - is_public_holiday (bool): Whether the target date is an official public holiday.
    # Returns:
    # - Pharmacy-ID roster and its freshness/fallback status.
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

    # Function Name: _weaker_schedule_status
    # Description:
    # - Reports the less reliable of two roster sources so an overnight fallback remains visible.
    # Parameters:
    # - first (str): First roster freshness/fallback status.
    # - second (str): Second roster freshness/fallback status.
    # Returns:
    # - Status with the higher fallback severity.
    @staticmethod
    def _weaker_schedule_status(first: str, second: str) -> str:
        rank = {
            "not_applicable": 0,
            "fresh": 1,
            "stale_fallback": 2,
            "weekly_fallback": 3,
        }
        return max((first, second), key=lambda value: rank.get(value, 3))

    # Function Name: _is_catalog_stale
    # Description:
    # - Compares the catalog timestamp in UTC with the configured freshness interval.
    # Parameters:
    # - updated_at (datetime | None): Most recent source update timestamp, if known.
    # Returns:
    # - True when the timestamp is absent or older than the allowed age.
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

    # 함수이름: _matches_search_mode
    # 함수역할:
    # - 영업 여부·심야 지정·주말과 공휴일 조건에 따라 약국의 검색 모드 적합성을 판정한다.
    # 매개변수:
    # - pharmacy (NearbyPharmacy): 계산된 거리와 영업 상태를 포함한 약국 결과.
    # - search_mode (PharmacySearchMode): 요청한 약국 영업 시간·공식 지정 필터.
    # - target_datetime (datetime): 선택적 약국 영업 여부 조회 기준 시각.
    # 반환값:
    # - 해당 검색 모드에 포함할 약국이면 True.
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
            return (
                pharmacy.is_open_late
                or pharmacy.is_24_hours
                or pharmacy.is_official_late_night
            )
        if search_mode is PharmacySearchMode.OFFICIAL_LATE_NIGHT:
            return pharmacy.is_official_late_night
        return (
            target_datetime.isoweekday() in {6, 7}
            or pharmacy.is_public_holiday
        ) and pharmacy.today_open_time is not None

    # 함수이름: _to_nearby_pharmacy
    # 함수역할:
    # - 운영 시각과 전날 야간 이월을 해석하고 거리·심야 지정·마감 및 다음 개점 정보를 계산한다.
    # 매개변수:
    # - record (PharmacyLocationRecord): 약국 좌표와 오늘·전날 신고 운영 시간.
    # - latitude (float): 검색 기준 위치의 위도(도).
    # - longitude (float): 검색 기준 위치의 경도(도).
    # - now (datetime): 상태·만료 판정에 사용할 기준 시각.
    # - is_public_holiday (bool): 조회 날짜가 법정 공휴일인지 여부.
    # - has_weekend_or_holiday_hours (bool): 주말 또는 공휴일 개점 시간이 등록되어 있는지 여부.
    # 반환값:
    # - 영업 상태와 자료 출처·최신성을 담은 주변 약국 엔티티.
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

    # 함수이름: _minutes_until_close
    # 함수역할:
    # - 현재 영업 중일 때 폐점까지 남은 분을 계산한다.
    # 매개변수:
    # - now (datetime): 상태·만료 판정에 사용할 기준 시각.
    # - is_open_now (bool | None): 알려진 영업 여부; 운영 시간이 없으면 None.
    # - start_minutes (int | None): 확인된 경우 자정 이후 분 단위의 오늘 개점 시각.
    # - end_minutes (int | None): 확인된 경우 자정 이후 분 단위의 오늘 폐점 시각.
    # - previous_start_minutes (int | None): 야간 이월 판정에 사용할 전날 개점 시각(분).
    # - previous_end_minutes (int | None): 야간 이월 판정에 사용할 전날 폐점 시각(분).
    # 반환값:
    # - 현재 영업 구간이 끝날 때까지의 분 수; 24시간 영업이거나 영업 중이 아니거나 시각을 계산할 수 없으면 None.
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

    # 함수이름: _next_open_at
    # 함수역할:
    # - 문을 닫은 약국의 다음 정규 영업 시작 시각을 최대 일주일 탐색한다.
    # 매개변수:
    # - now (datetime): 상태·만료 판정에 사용할 기준 시각.
    # - is_open_now (bool | None): 알려진 영업 여부; 운영 시간이 없으면 None.
    # - weekly_hours (dict[str, tuple[str, str]] | None): ISO 요일별 개점·폐점 문자열; 8은 공휴일.
    # - is_public_holiday (bool): 조회 날짜가 법정 공휴일인지 여부.
    # 반환값:
    # - 주간 운영표에서 찾은 다음 개점 ISO 시각; 이미 영업 중이거나 찾을 수 없으면 None.
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

    # 함수이름: _source_updated_at_iso
    # 함수역할:
    # - 카탈로그 갱신 시각을 현재 화면 시간대로 안전하게 변환한다.
    # 매개변수:
    # - value (datetime | None): 카탈로그 갱신 시각. 시간대 정보가 없으면 UTC로 간주하고, None은 그대로 반환한다.
    # - target_timezone (tzinfo | None): 자료 갱신 시각 표시에 사용할 시간대.
    # 반환값:
    # - 조회 시간대로 표시한 자료 갱신 ISO 시각 또는 값이 없을 때 None.
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

    # Function Name: _is_late_schedule
    # Description:
    # - Recognizes overnight hours, midnight-to-midnight operation and closing times at or after 22:00.
    # Parameters:
    # - start_minutes (int | None): Today's opening time as minutes since midnight, if known.
    # - end_minutes (int | None): Today's closing time as minutes since midnight, if known.
    # Returns:
    # - True for a known late-night or all-day schedule; False for missing hours.
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

    # 함수이름: _parse_minutes
    # 함수역할:
    # - 시각에서 숫자를 추출해 시·분 범위를 확인하고 허용된 경우 24:00도 처리한다.
    # 매개변수:
    # - value (str): 공공 약국 API의 시·분 문자열.
    # - allow_24 (bool): 폐점 시각으로 정확히 24:00을 허용할지 여부.
    # 반환값:
    # - 자정 이후 분 수; 잘못된 시각은 None.
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

    # Function Name: _is_open_now
    # Description:
    # - Checks today's interval and yesterday's overnight carryover, treating midnight-to-midnight as all-day operation.
    # Parameters:
    # - now (datetime): Reference datetime for time-sensitive status or expiration checks.
    # - start_minutes (int | None): Today's opening time as minutes since midnight, if known.
    # - end_minutes (int | None): Today's closing time as minutes since midnight, if known.
    # - previous_start_minutes (int | None): Previous day's opening time for overnight checks.
    # - previous_end_minutes (int | None): Previous day's closing time for overnight checks.
    # Returns:
    # - True when open, False when closed with known hours, or None when today's hours are unknown.
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

    # 함수이름: _format_time
    # 함수역할:
    # - 자정 이후 분 수를 HH:MM 표시로 변환하고 1440분은 24:00으로 보존한다.
    # 매개변수:
    # - minutes (int | None): 시각 표시로 변환할 자정 이후 분 수.
    # 반환값:
    # - 표시용 시각 또는 입력이 없을 때 None.
    @staticmethod
    def _format_time(minutes: int | None) -> str | None:
        if minutes is None:
            return None
        if minutes == 24 * 60:
            return "24:00"
        return f"{minutes // 60:02d}:{minutes % 60:02d}"

    # 함수이름: _haversine_distance
    # 함수역할:
    # - 두 위도·경도의 대권 거리를 평균 지구 반지름으로 계산한다.
    # 매개변수:
    # - start_latitude (float): 출발 위치의 위도(도).
    # - start_longitude (float): 출발 위치의 경도(도).
    # - end_latitude (float): 도착 위치의 위도(도).
    # - end_longitude (float): 도착 위치의 경도(도).
    # 반환값:
    # - 두 위치 사이의 거리(km).
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
