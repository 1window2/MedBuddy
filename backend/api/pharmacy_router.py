# 파일명: pharmacy_router.py
# 역할: 현재 위치 기반 약국 조회 HTTP 엔드포인트를 제공한다.

"""현재 위치 기반 약국 조회 HTTP 엔드포인트."""

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
from controls.check_nearby_pharmacy_control import CheckNearbyPharmacy
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
    open_only: bool = Query(default=True),
    limit: int = Query(default=20, ge=1, le=30),
    max_distance_km: float = Query(default=20.0, ge=0.1, le=50.0),
    control: CheckNearbyPharmacy = Depends(get_check_nearby_pharmacy),
) -> NearbyPharmacyResponse:
    try:
        pharmacies = await control.requestNearbyPharmacies(
            latitude=latitude,
            longitude=longitude,
            open_only=open_only,
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
        data=[NearbyPharmacyItem.model_validate(item) for item in pharmacies],
        open_only=open_only,
        max_distance_km=max_distance_km,
    )
