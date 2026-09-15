# 파일명: pharmacy.py
# 역할: 근처 약국 API 요청·응답 계약을 정의한다.

"""근처 약국 API 요청·응답 계약."""

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field


# 클래스명: NearbyPharmacyItem
# 역할:
# - 모바일 앱에 전달할 근처 약국 한 건의 응답 계약을 정의한다.
# 주요 책임:
# - 위치, 거리, 영업 시간과 현재 영업 상태를 직렬화한다.
# 속성:
# - pharmacy_id (str): 공공 약국 식별자.
# - name (str): 공공 약국 표시 이름.
# - address (str): 약국 도로명·소재지 주소.
# - telephone (str): 약국 문의 전화번호.
# - latitude (float): 약국 위치의 위도(도).
# - longitude (float): 약국 위치의 경도(도).
class NearbyPharmacyItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    pharmacy_id: str
    name: str
    address: str
    telephone: str
    latitude: float
    longitude: float
    distance_km: float = Field(ge=0)
    today_open_time: str | None
    today_close_time: str | None
    is_open_now: bool | None
    is_24_hours: bool
    is_open_late: bool
    has_weekend_or_holiday_hours: bool
    is_public_holiday: bool
    is_official_late_night: bool
    designation_source_name: str | None
    designation_source_url: str | None
    designation_verified_at: date | None
    designation_is_stale: bool
    schedule_date: date | None
    schedule_source: str
    schedule_is_date_specific: bool
    minutes_until_close: int | None
    next_open_at: str | None
    source_updated_at: str | None
    source_name: str


# Class Name: NearbyPharmacyResponse
# Role:
# - Carries nearby pharmacy results with the effective search mode, target time, radius and catalog/holiday freshness indicators.
# Responsibilities:
# - Preserve the effective filters and source freshness alongside the pharmacy list so fallback data remains identifiable.
# Attributes:
# - open_only (bool): Whether results must be open at the reference time.
# - search_mode (str): Requested pharmacy opening-hours or official-designation filter.
# - target_datetime (datetime): Resolved opening-hours reference time in the application time zone.
# - max_distance_km (float): Maximum accepted search radius in kilometers.
class NearbyPharmacyResponse(BaseModel):
    data: list[NearbyPharmacyItem]
    open_only: bool
    search_mode: str
    target_datetime: datetime
    max_distance_km: float
    catalog_updated_at: datetime | None
    catalog_is_stale: bool
    holiday_schedule_status: str
