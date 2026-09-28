"""근처 병원 조회의 필터와 공통 지도 표시 계약."""

from datetime import date, datetime
from enum import StrEnum

from pydantic import BaseModel, Field


class HospitalSearchMode(StrEnum):
    ALL = "all"
    OPEN_AT_TIME = "open_at_time"
    LATE_HOURS = "late_hours"
    WEEKEND_HOLIDAY = "weekend_holiday"


class NearbyHospitalItem(BaseModel):
    hospital_id: str
    name: str
    address: str
    telephone: str
    latitude: float
    longitude: float
    distance_km: float = Field(ge=0)
    departments: list[str] = Field(default_factory=list)
    institution_type: str | None = None
    operating_notes: str | None = None
    status_basis: str = "registered_weekly_hours"
    today_open_time: str | None = None
    today_close_time: str | None = None
    is_open_now: bool | None = None
    is_24_hours: bool = False
    is_open_late: bool = False
    has_weekend_or_holiday_hours: bool = False
    is_public_holiday: bool = False
    schedule_date: date | None = None
    schedule_source: str = "unknown"
    schedule_is_date_specific: bool = False
    minutes_until_close: int | None = None
    next_open_at: str | None = None
    source_updated_at: str | None = None
    source_name: str = "National Emergency Medical Center"


class NearbyHospitalResponse(BaseModel):
    data: list[NearbyHospitalItem]
    open_only: bool
    search_mode: HospitalSearchMode
    target_datetime: datetime
    department: str | None = None
    max_distance_km: float
    catalog_updated_at: datetime | None = None
    catalog_is_stale: bool = False
    holiday_schedule_status: str = "unknown"
    search_truncated: bool = False
