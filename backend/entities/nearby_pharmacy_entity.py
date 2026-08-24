# 파일명: nearby_pharmacy_entity.py
# 역할: 근처 약국 조회 과정에서 사용하는 비영속 도메인 모델을 정의한다.

"""근처 약국 조회 과정에서 사용하는 비영속 도메인 모델."""

from dataclasses import dataclass, field
from datetime import date, datetime


# 클래스명: PharmacyLocationRecord
# 역할:
# - 공공데이터 약국 API 응답에서 필요한 위치·영업 정보만 보관한다.
@dataclass(frozen=True, slots=True)
class PharmacyLocationRecord:
    pharmacy_id: str
    name: str
    address: str
    telephone: str
    latitude: float
    longitude: float
    distance_km: float | None
    start_time: str
    end_time: str
    previous_start_time: str = ""
    previous_end_time: str = ""
    schedule_source: str = "nemc_weekly_report"
    schedule_is_date_specific: bool = False
    official_designations: dict[str, object] = field(default_factory=dict)


# 클래스명: NearbyPharmacy
# 역할:
# - 사용자에게 보여줄 거리와 현재 영업 상태가 계산된 약국 정보를 표현한다.
@dataclass(frozen=True, slots=True)
class NearbyPharmacy:
    pharmacy_id: str
    name: str
    address: str
    telephone: str
    latitude: float
    longitude: float
    distance_km: float
    today_open_time: str | None
    today_close_time: str | None
    is_open_now: bool | None
    is_24_hours: bool
    is_open_late: bool = False
    has_weekend_or_holiday_hours: bool = False
    is_public_holiday: bool = False
    is_official_late_night: bool = False
    designation_source_name: str | None = None
    designation_source_url: str | None = None
    designation_verified_at: date | None = None
    designation_is_stale: bool = False
    schedule_date: date | None = None
    schedule_source: str = "nemc_weekly_report"
    schedule_is_date_specific: bool = False
    source_name: str = "National Emergency Medical Center"


@dataclass(frozen=True, slots=True)
class NearbyPharmacySearchResult:
    """Pharmacy matches plus the freshness and fallback state used to build them."""

    data: list[NearbyPharmacy]
    search_mode: str
    target_datetime: datetime
    catalog_updated_at: datetime | None
    catalog_is_stale: bool
    holiday_schedule_status: str
