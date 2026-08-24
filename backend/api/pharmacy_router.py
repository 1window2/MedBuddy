# 파일명: pharmacy_router.py
# 역할: 현재 위치 기반 약국 조회 HTTP 엔드포인트를 제공한다.

"""현재 위치 기반 약국 조회 HTTP 엔드포인트."""

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query

from api.dependencies import (
    get_check_nearby_pharmacy,
    get_registered_principal,
    verify_app_check_token,
)
from boundaries.pharmacy_api_boundary import (
    PharmacyApiResponseError,
    PharmacyApiUnavailableError,
)
from controls.check_nearby_pharmacy_control import (
    CheckNearbyPharmacy,
    PharmacySearchMode,
)
from schemas.pharmacy import NearbyPharmacyItem, NearbyPharmacyResponse

router = APIRouter(
    dependencies=[
        Depends(verify_app_check_token),
        Depends(get_registered_principal),
    ]
)


# 함수명: get_nearby_pharmacies
# 역할:
# - 사용자 좌표 주변 약국을 조회해 영업 상태와 거리순 목록을 반환한다.
@router.get("/nearby", response_model=NearbyPharmacyResponse)
async def get_nearby_pharmacies(
    latitude: float = Query(ge=-90, le=90),
    longitude: float = Query(ge=-180, le=180),
    search_mode: PharmacySearchMode | None = Query(default=None),
    target_datetime: datetime | None = Query(default=None),
    open_only: bool | None = Query(
        default=None,
        deprecated=True,
        description="Compatibility alias; use search_mode instead.",
    ),
    limit: int = Query(default=20, ge=1, le=30),
    max_distance_km: float = Query(default=20.0, ge=0.1, le=50.0),
    control: CheckNearbyPharmacy = Depends(get_check_nearby_pharmacy),
) -> NearbyPharmacyResponse:
    try:
        effective_mode = search_mode
        if effective_mode is None:
            effective_mode = (
                PharmacySearchMode.ALL
                if open_only is False
                else PharmacySearchMode.OPEN_AT_TIME
            )
        result = await control.requestNearbyPharmacySearch(
            latitude=latitude,
            longitude=longitude,
            search_mode=effective_mode,
            target_datetime=target_datetime,
            limit=limit,
            max_distance_km=max_distance_km,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except PharmacyApiUnavailableError as exc:
        raise HTTPException(
            status_code=503,
            detail="약국 정보 서비스가 일시적으로 응답하지 않습니다.",
            headers={"Retry-After": "5"},
        ) from exc
    except PharmacyApiResponseError as exc:
        raise HTTPException(
            status_code=502,
            detail="약국 정보 응답을 처리할 수 없습니다.",
        ) from exc

    return NearbyPharmacyResponse(
        data=[NearbyPharmacyItem.model_validate(item) for item in result.data],
        open_only=result.search_mode == PharmacySearchMode.OPEN_AT_TIME.value,
        search_mode=result.search_mode,
        target_datetime=result.target_datetime,
        max_distance_km=max_distance_km,
        catalog_updated_at=result.catalog_updated_at,
        catalog_is_stale=result.catalog_is_stale,
        holiday_schedule_status=result.holiday_schedule_status,
    )
