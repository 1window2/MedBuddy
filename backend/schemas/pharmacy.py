# 파일명: pharmacy.py
# 역할: 근처 약국 API 요청·응답 계약을 정의한다.

"""근처 약국 API 요청·응답 계약."""

from pydantic import BaseModel, ConfigDict, Field


# 클래스명: NearbyPharmacyItem
# 역할: 모바일 앱에 전달할 근처 약국 한 건의 응답 계약을 정의한다.
# 주요 책임: 위치, 거리, 영업 시간과 현재 영업 상태를 직렬화한다.
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


# 클래스명: NearbyPharmacyResponse
# 역할: 근처 약국 목록과 적용된 조회 조건을 반환한다.
# 주요 책임: 약국 목록, 영업 중 필터와 최대 거리 조건을 묶는다.
class NearbyPharmacyResponse(BaseModel):
    data: list[NearbyPharmacyItem]
    open_only: bool
    max_distance_km: float
