"""인증된 사용자의 위치 기반 병원 검색 API."""

import asyncio
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query

from api.dependencies import (
    get_check_nearby_hospital,
    get_registered_principal,
    verify_app_check_token,
)
from boundaries.hospital_api_boundary import (
    HospitalApiBudgetExhaustedError,
    HospitalApiResponseError,
    HospitalApiUnavailableError,
)
from core.application_clock import seconds_until_next_application_day
from controls.check_nearby_hospital_control import CheckNearbyHospital
from core.config import settings
from schemas.hospital import HospitalSearchMode, NearbyHospitalResponse


# 모든 사용자가 함께 쓰는 병원 API 하루 예산이 바닥났을 때의 안내. 채팅의 병원 공유도 같은 문구를 쓴다.
HOSPITAL_BUDGET_EXHAUSTED_DETAIL = "오늘 병원 정보를 조회할 수 있는 횟수를 모두 사용했습니다. 내일 다시 시도해주세요."

router = APIRouter(dependencies=[Depends(verify_app_check_token), Depends(get_registered_principal)])


# 기존 인증·앱 검증을 유지하고 외부 장애는 키가 없는 고정 문구로 응답한다.
@router.get("/nearby", response_model=NearbyHospitalResponse)
async def get_nearby_hospitals(
    latitude: float = Query(ge=-90, le=90),
    longitude: float = Query(ge=-180, le=180),
    search_mode: HospitalSearchMode = Query(default=HospitalSearchMode.ALL),
    target_datetime: datetime | None = Query(default=None),
    department: str | None = Query(default=None, pattern=r"^D[0-9]{3}$"),
    limit: int = Query(default=20, ge=1, le=30),
    max_distance_km: float = Query(default=20.0, ge=0.1, le=50.0),
    control: CheckNearbyHospital = Depends(get_check_nearby_hospital),
) -> NearbyHospitalResponse:
    try:
        async with asyncio.timeout(settings.HOSPITAL_SEARCH_TIMEOUT_SECONDS):
            return await control.requestNearbyHospitalSearch(
                latitude=latitude, longitude=longitude, search_mode=search_mode,
                target_datetime=target_datetime, department=department,
                limit=limit, max_distance_km=max_distance_km,
            )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from None
    except HospitalApiBudgetExhaustedError:
        # 모든 사용자가 함께 쓰는 하루 조회 예산이 바닥났다. 몇 초 뒤 다시 시도해도 소용없으므로
        # 일시 장애와 다른 안내와 자정까지의 대기 시간을 준다.
        raise HTTPException(
            status_code=503, detail=HOSPITAL_BUDGET_EXHAUSTED_DETAIL,
            headers={"Retry-After": str(seconds_until_next_application_day())},
        ) from None
    except (HospitalApiUnavailableError, TimeoutError):
        raise HTTPException(
            status_code=503, detail="병원 정보 서비스가 일시적으로 응답하지 않습니다.",
            headers={"Retry-After": "5"},
        ) from None
    except HospitalApiResponseError:
        raise HTTPException(status_code=502, detail="병원 정보 응답을 처리할 수 없습니다.") from None
