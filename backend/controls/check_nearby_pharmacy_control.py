# 파일명: check_nearby_pharmacy_control.py
# 역할: 현재 위치를 기준으로 가까운 운영 약국을 계산한다.

"""현재 위치를 기준으로 가까운 약국을 조회하는 사용 사례."""

import math
from collections.abc import Callable
from datetime import date, datetime, timedelta
from typing import Protocol
from zoneinfo import ZoneInfo

from boundaries.pharmacy_api_boundary import (
    PharmacyApiUnavailableError,
    PharmacyLookupBoundary,
)
from core.config import settings
from entities.nearby_pharmacy_entity import NearbyPharmacy, PharmacyLocationRecord
from entities.pharmacy_catalog_entity import PharmacyCatalogEntry

_MAX_RESULT_LIMIT = 30
_MAX_SEARCH_DISTANCE_KM = 50.0


class PharmacyCatalogLookup(Protocol):
    def count(self) -> int: ...

    def search_nearby_candidates(
        self,
        *,
        latitude: float,
        longitude: float,
        max_distance_km: float,
    ) -> list[PharmacyCatalogEntry]: ...


class HolidayLookupBoundary(Protocol):
    async def isHoliday(self, value: date) -> bool: ...


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
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        if pharmacy_boundary is None and pharmacy_repository is None:
            raise ValueError("A pharmacy data source is required.")
        self._pharmacy_boundary = pharmacy_boundary
        self._pharmacy_repository = pharmacy_repository
        self._holiday_boundary = holiday_boundary
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
        self._validate_request(
            latitude=latitude,
            longitude=longitude,
            limit=limit,
            max_distance_km=max_distance_km,
        )
        now = self._now_provider()
        is_public_holiday = False
        was_public_holiday = False
        if self._holiday_boundary is not None:
            is_public_holiday = await self._holiday_boundary.isHoliday(now.date())
            was_public_holiday = await self._holiday_boundary.isHoliday(
                now.date() - timedelta(days=1)
            )

        repository = self._pharmacy_repository
        if repository is not None:
            if repository.count() == 0:
                raise PharmacyApiUnavailableError(
                    "The synchronized pharmacy catalogue is empty."
                )
            catalog_entries = repository.search_nearby_candidates(
                latitude=latitude,
                longitude=longitude,
                max_distance_km=max_distance_km,
            )
            records = [
                self._catalog_entry_to_location_record(
                    entry,
                    day_of_week=now.isoweekday(),
                    is_public_holiday=is_public_holiday,
                    previous_day_of_week=(now.date() - timedelta(days=1)).isoweekday(),
                    was_public_holiday=was_public_holiday,
                )
                for entry in catalog_entries
            ]
            weekend_or_holiday_ids = {
                entry.pharmacy_id
                for entry in catalog_entries
                if entry.has_weekend_or_holiday_hours
            }
        else:
            assert self._pharmacy_boundary is not None
            fetch_limit = min(_MAX_RESULT_LIMIT, max(limit * 2, limit))
            records = await self._pharmacy_boundary.searchNearby(
                latitude=latitude,
                longitude=longitude,
                limit=fetch_limit,
            )
            weekend_or_holiday_ids = set()

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
            if open_only and pharmacy.is_open_now is not True:
                continue
            pharmacies.append(pharmacy)

        pharmacies.sort(
            key=lambda item: (
                item.is_open_now is not True,
                item.distance_km,
                item.name,
            )
        )
        return pharmacies[:limit]

    @staticmethod
    def _catalog_entry_to_location_record(
        entry: PharmacyCatalogEntry,
        *,
        day_of_week: int,
        is_public_holiday: bool,
        previous_day_of_week: int,
        was_public_holiday: bool,
    ) -> PharmacyLocationRecord:
        start_time, end_time = entry.hours_for(
            day_of_week=day_of_week,
            is_public_holiday=is_public_holiday,
        )
        previous_start_time, previous_end_time = entry.hours_for(
            day_of_week=previous_day_of_week,
            is_public_holiday=was_public_holiday,
        )
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
        )

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
