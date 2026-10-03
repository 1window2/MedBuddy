"""병원 경로의 인증, 요청 검증, 오류·응답 계약을 검증한다."""

import asyncio
from datetime import date, datetime
from pathlib import Path
import sys
from unittest.mock import AsyncMock

import httpx
import pytest
from fastapi import FastAPI, HTTPException
from pydantic import ValidationError
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from api.dependencies import get_check_nearby_hospital, get_registered_principal, verify_app_check_token
from api import dependencies
from api.hospital_router import router
from boundaries.hospital_api_boundary import HospitalApiResponseError, HospitalApiUnavailableError
from boundaries.korean_holiday_api_boundary import PersistentKoreanHolidayLookup
from boundaries.pharmacy_api_boundary import PharmacyApiUnavailableError
from core.config import Settings, settings
from core.request_rate_limits import resolve_rate_limit_rule
from entities.pharmacy_catalog_entity import KoreanHolidayMonthFetchRecord, KoreanHolidayRecord
from repositories.pharmacy_catalog_repository import PharmacyCatalogRepository
from schemas.hospital import NearbyHospitalResponse


@pytest.fixture
def anyio_backend():
    """라우터를 asyncio에서 실행한다."""
    return "asyncio"


@pytest.fixture
def app_control():
    """DB·네트워크 없이 인증 의존성을 명시적으로 대체한다."""
    app = FastAPI()
    app.include_router(router, prefix="/api/v1/hospitals")
    control = AsyncMock()
    control.requestNearbyHospitalSearch.return_value = NearbyHospitalResponse(
        data=[], open_only=False, search_mode="all", target_datetime=datetime(2026, 9, 28),
        max_distance_km=20, search_truncated=True,
    )
    app.dependency_overrides[get_check_nearby_hospital] = lambda: control
    app.dependency_overrides[verify_app_check_token] = lambda: None
    app.dependency_overrides[get_registered_principal] = lambda: object()
    return app, control


@pytest.mark.anyio
async def test_envelope_department_and_generic_route_contract(app_control):
    """화면이 사용하는 경로·필터·부분 결과 메타데이터를 보존한다."""
    app, control = app_control
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/api/v1/hospitals/nearby", params={"latitude": 37.5, "longitude": 127, "department": "D026"})
    assert response.status_code == 200 and response.json()["search_truncated"] is True
    assert control.requestNearbyHospitalSearch.call_args.kwargs["department"] == "D026"
    assert resolve_rate_limit_rule("GET", "/api/v1/hospitals/nearby")[0].max_requests == 30


@pytest.mark.anyio
async def test_region_scope_metadata_is_independent_of_search_limit(app_control):
    """응답 직렬화에서도 지역 표본의 한계를 조회 제한으로 합치지 않는다."""
    app, control = app_control
    result = control.requestNearbyHospitalSearch.return_value
    result.search_truncated = False
    result.region_scope_uncertain = True
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/api/v1/hospitals/nearby", params={"latitude": 37.5, "longitude": 127})
    assert response.status_code == 200
    assert response.json()["search_truncated"] is False
    assert response.json()["region_scope_uncertain"] is True


@pytest.mark.parametrize("params", [
    {"latitude": "NaN"}, {"longitude": 181}, {"limit": 31}, {"limit": 0},
    {"max_distance_km": 51}, {"max_distance_km": 0}, {"department": "내과"},
    {"search_mode": "official_late_night"}, {"target_datetime": "bad"},
])
@pytest.mark.anyio
async def test_invalid_query_never_reaches_provider(app_control, params):
    """HTTP 경계에서 잘못된 입력을 차단한다."""
    app, control = app_control
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/api/v1/hospitals/nearby", params={"latitude": 37.5, "longitude": 127, **params})
    assert response.status_code == 422 and not control.requestNearbyHospitalSearch.called


@pytest.mark.parametrize("dependency,status", [(verify_app_check_token, 403), (get_registered_principal, 401)])
@pytest.mark.anyio
async def test_admission_requires_appcheck_and_registered_principal(app_control, dependency, status):
    """앱 검증·등록 사용자 검증이 검색 실행보다 먼저 수행된다."""
    app, control = app_control

    def denied():
        raise HTTPException(status_code=status, detail="denied")

    app.dependency_overrides[dependency] = denied
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/api/v1/hospitals/nearby?latitude=37.5&longitude=127")
    assert response.status_code == status and not control.requestNearbyHospitalSearch.called
    assert {item.dependency for item in router.dependencies} == {verify_app_check_token, get_registered_principal}


@pytest.mark.parametrize("error,status", [(HospitalApiUnavailableError, 503), (HospitalApiResponseError, 502)])
@pytest.mark.anyio
async def test_provider_errors_are_sanitized(app_control, error, status):
    """제공자 오류의 비밀 정보는 HTTP 응답으로 전달하지 않는다."""
    app, control = app_control
    control.requestNearbyHospitalSearch.side_effect = error("secret-key-and-provider-url")
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/api/v1/hospitals/nearby?latitude=37.5&longitude=127")
    assert response.status_code == status and "secret" not in response.text
    if status == 503:
        assert response.headers["retry-after"] == "5"


@pytest.mark.anyio
async def test_whole_search_deadline_precedes_frontend_timeout(app_control, monkeypatch):
    """전체 요청의 지연 한도가 UI의 25초 제한보다 짧다."""
    assert settings.HOSPITAL_SEARCH_TIMEOUT_SECONDS < 25
    monkeypatch.setattr(settings, "HOSPITAL_SEARCH_TIMEOUT_SECONDS", 0.01)
    app, control = app_control

    async def wait(**_):
        await asyncio.Event().wait()

    control.requestNearbyHospitalSearch.side_effect = wait
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/api/v1/hospitals/nearby?latitude=37.5&longitude=127")
    assert response.status_code == 503


def test_settings_validate_hospital_bounds_and_https():
    """병원 기본값은 24시간 상세 캐시와 유한한 요청·저장 상한을 사용한다."""
    defaults = Settings(_env_file=None)
    assert defaults.HOSPITAL_DETAIL_CACHE_SECONDS == 86400
    assert defaults.HOSPITAL_API_KEY == ""
    for invalid in ({"HOSPITAL_API_BASE_URL": "http://unsafe"}, {"HOSPITAL_DETAIL_REQUEST_BUDGET": 0},
                    {"HOSPITAL_SEARCH_TIMEOUT_SECONDS": 25}, {"HOSPITAL_CACHE_MAX_ENTRIES": 0}):
        with pytest.raises(ValidationError):
            Settings(_env_file=None, **invalid)


@pytest.mark.parametrize("cache_state,expected", [
    ("verified_holiday", True), ("verified_empty", False),
    ("unverified_row", None), ("missing", None),
])
@pytest.mark.anyio
async def test_hospital_dependency_reuses_only_verified_request_db_calendar(monkeypatch, tmp_path, cache_state, expected):
    """기존 월별 조회 기록을 재사용하고 미검증·빈 캐시와 외부 장애는 미확인으로 유지한다."""
    engine = create_engine(f"sqlite:///{tmp_path / 'calendar.db'}")
    KoreanHolidayRecord.__table__.create(engine)
    KoreanHolidayMonthFetchRecord.__table__.create(engine)
    upstream = AsyncMock()
    upstream.fetchMonth.side_effect = PharmacyApiUnavailableError("calendar unavailable")
    monkeypatch.setattr(dependencies, "_korean_holiday_api", upstream)
    target = date(2026, 9, 28)
    try:
        with Session(engine) as db:
            repository = PharmacyCatalogRepository(db)
            if cache_state.startswith("verified_"):
                repository.replace_korean_holidays(
                    2026, 9, frozenset({target}) if cache_state == "verified_holiday" else frozenset(),
                )
            elif cache_state == "unverified_row":
                db.add(KoreanHolidayRecord(holiday_date=target))
                db.commit()
            control = get_check_nearby_hospital(db=db)
            lookup = control._holiday_boundary
            assert isinstance(lookup, PersistentKoreanHolidayLookup)
            assert lookup._upstream is upstream
            assert await control._is_holiday(target) is expected
            assert not db.in_transaction()
            if expected is None:
                upstream.fetchMonth.assert_awaited_once_with(2026, 9)
                assert db.get(KoreanHolidayMonthFetchRecord, "2026-09") is None
            else:
                upstream.fetchMonth.assert_not_awaited()
    finally:
        engine.dispose()
