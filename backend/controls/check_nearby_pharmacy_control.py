# 파일명: check_nearby_pharmacy_control.py
# 역할: 현재 위치를 기준으로 가까운 운영 약국을 계산한다.

"""현재 위치를 기준으로 가까운 약국을 조회하는 사용 사례."""

import math
from collections.abc import Callable
from datetime import datetime
from zoneinfo import ZoneInfo

from boundaries.pharmacy_api_boundary import PharmacyLookupBoundary
from core.config import settings
from entities.nearby_pharmacy_entity import NearbyPharmacy, PharmacyLocationRecord

_MAX_RESULT_LIMIT = 30
_MAX_SEARCH_DISTANCE_KM = 50.0


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
        pharmacy_boundary: PharmacyLookupBoundary,
        *,
        now_provider: Callable[[], datetime] | None = None,
    ) -> None:
        self._pharmacy_boundary = pharmacy_boundary
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
        fetch_limit = min(_MAX_RESULT_LIMIT, max(limit * 2, limit))
        records = await self._pharmacy_boundary.searchNearby(
            latitude=latitude,
            longitude=longitude,
            limit=fetch_limit,
        )

        now = self._now_provider()
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
    ) -> NearbyPharmacy:
        start_minutes = cls._parse_minutes(record.start_time)
        end_minutes = cls._parse_minutes(record.end_time, allow_24=True)
        is_open_now = cls._is_open_now(
            now=now,
            start_minutes=start_minutes,
            end_minutes=end_minutes,
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
        )

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
    ) -> bool | None:
        if start_minutes is None or end_minutes is None:
            return None
        current_minutes = now.hour * 60 + now.minute
        if end_minutes > start_minutes:
            return start_minutes <= current_minutes < end_minutes
        if end_minutes < start_minutes:
            return current_minutes >= start_minutes or current_minutes < end_minutes
        return True if start_minutes == 0 else None

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
