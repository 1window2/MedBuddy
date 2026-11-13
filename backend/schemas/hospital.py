# 파일명: hospital.py
# 역할: 병원 지도 검색의 필터·결과·불확실성 응답 구조를 정의한다.
"""근처 병원 조회의 필터와 공통 지도 표시 계약."""

from datetime import date, datetime
from enum import StrEnum

from pydantic import BaseModel, Field


# 클래스명: HospitalSearchMode
# 역할: 병원 검색에서 허용하는 운영시간 필터를 문자열로 표현한다.
# 주요 책임: 전체·선택 시각 진료·저녁·주말 및 공휴일 모드를 제한한다.
# 속성: ALL, OPEN_AT_TIME, LATE_HOURS, WEEKEND_HOLIDAY는 API에 전달하는 str 값이다.
class HospitalSearchMode(StrEnum):
    ALL = "all"
    OPEN_AT_TIME = "open_at_time"
    LATE_HOURS = "late_hours"
    WEEKEND_HOLIDAY = "weekend_holiday"


# 클래스명: NearbyHospitalItem
# 역할: 한 병원의 위치·진료과·선택일 운영 근거를 지도 응답에 담는다.
# 주요 책임: 거리 음수를 거절하고 미확인 시간·현재 진료 여부를 None으로 구분한다.
# 속성: hospital_id·name·address·telephone은 str, latitude·longitude·distance_km은 float, departments는 list[str]이다.
#   today_open_time·today_close_time 등은 선택적 시각, is_open_now는 bool | None, schedule/source 필드는 근거와 날짜를 나타낸다.
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


# 클래스명: NearbyHospitalResponse
# 역할: 검색 결과와 적용 조건·확인 한계를 함께 전달한다.
# 주요 책임: 실제 조회 제한과 주소 표본으로 추정한 지역 불확실성을 분리한다.
# 속성: data는 병원 목록, search_mode·target_datetime·department·max_distance_km은 조건이다.
#   search_truncated·region_scope_uncertain·catalog_is_stale은 bool, holiday_schedule_status는 달력 근거 str이다.
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
    # 주소 표본의 지역 불확실성은 실제 진료과·상세 조회 제한과 별개다.
    region_scope_uncertain: bool = False
