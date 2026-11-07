# 파일명: test_pharmacy_fallback_share_snapshot.py
# 역할: 주간표가 없는 약국 검색 캐시의 공유 신원, 당일 조회와 운영 상태 불확실성을 검증한다.

"""주간표 없는 검색 캐시 약국의 신뢰된 당일 공유 스냅샷을 검증한다."""

import asyncio
from collections.abc import Iterator
from dataclasses import replace
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
from typing import Any, NoReturn
from unittest.mock import AsyncMock
from zoneinfo import ZoneInfo

import pytest
import httpx
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from api import chat_router, route_support
from boundaries.pharmacy_api_boundary import PharmacyApiResponseError, PharmacyApiUnavailableError
from controls import manage_linked_chat_control
from controls.check_nearby_pharmacy_control import CheckNearbyPharmacy, PharmacySearchMode
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.manage_linked_chat_control import ManageLinkedChat
from core import application_clock
from core.config import settings
from core.database import Base
from entities.chat_message_entity import _ChatMessage
from entities.nearby_pharmacy_entity import PharmacyLocationRecord
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.pharmacy_catalog_entity import PharmacyCatalogRecord, PharmacySearchCacheRecord
from repositories.async_pharmacy_catalog import AsyncPharmacyCatalog
from repositories.pharmacy_catalog_repository import PharmacyCatalogRepository


NOW = datetime(2026, 10, 27, 21, 45, tzinfo=ZoneInfo("Asia/Seoul"))


# Function Name: flow
# Description:
# - Seeds a linked chat and a location-only pharmacy search cache with fake providers; closes the client, session and engine after use.
# Parameters:
# - tmp_path: Path; isolated temporary directory.
# - monkeypatch: pytest.MonkeyPatch; restores temporary dependency replacements.
# Returns:
# - Iterator[SimpleNamespace]; isolated chat, search providers, clock, repository and HTTP client.
@pytest.fixture
def flow(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[SimpleNamespace]:
    """실제 제공자 대신 공개 시험 ID와 가상 좌표를 쓰고 검색부터 저장까지 연결한다."""
    monkeypatch.setattr(settings, "APPLICATION_TIME_ZONE", "Asia/Seoul")
    clock = SimpleNamespace(now=NOW)
    monkeypatch.setattr(application_clock, "application_now", lambda: clock.now)
    monkeypatch.setattr(manage_linked_chat_control, "application_now", lambda: clock.now)
    engine = create_engine(f"sqlite:///{tmp_path / 'fallback-share.db'}")
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        links = LinkPatientCaregiver(db)
        code = links.generatePatientHash("patient-share")["data"]["patient_code"]
        link_id = links.requestPatientCaregiverLink("caregiver-share", code)["data"]["id"]
        record = PharmacyLocationRecord(
            pharmacy_id="C1110363", name="태평양약국", address="시험 주소", telephone="02-000-0000",
            latitude=37.5, longitude=127.0, distance_km=None, start_time="0900", end_time="2200",
        )
        boundary = SimpleNamespace(searchNearby=AsyncMock(return_value=[record]))
        calendar = SimpleNamespace(isHoliday=AsyncMock(return_value=False))
        pharmacy = CheckNearbyPharmacy(
            pharmacy_boundary=boundary, pharmacy_repository=AsyncPharmacyCatalog(sessionmaker(bind=engine)),
            holiday_boundary=calendar, now_provider=lambda: clock.now,
        )
        found = asyncio.run(pharmacy.requestNearbyPharmacySearch(
            latitude=record.latitude, longitude=record.longitude, search_mode=PharmacySearchMode.ALL,
        ))
        assert found.data[0].is_open_now is True
        assert found.data[0].today_open_time == "09:00"
        assert found.data[0].today_close_time == "22:00"
        repository = PharmacyCatalogRepository(db)
        assert repository.count() == 0
        assert repository.find_by_id(record.pharmacy_id).weekly_hours == {}
        boundary.searchNearby.reset_mock()
        calendar.isHoliday.reset_mock()
        chat = ManageLinkedChat(db)
        app = FastAPI()
        app.include_router(chat_router.router)
        app.dependency_overrides[chat_router.get_authenticated_app_principal] = lambda: object()
        app.dependency_overrides[chat_router.get_authorization_control] = lambda: SimpleNamespace(
            resolveOwnUserHash=lambda _, value: value,
        )
        app.dependency_overrides[chat_router.get_manage_linked_chat] = lambda: chat
        app.dependency_overrides[chat_router.get_check_nearby_pharmacy] = lambda: pharmacy
        app.dependency_overrides[chat_router.get_check_nearby_hospital] = lambda: object()
        monkeypatch.setattr(chat_router, "enforce_chat_daily_quota", AsyncMock())
        monkeypatch.setattr(chat_router, "enforce_pharmacy_share_daily_quota", AsyncMock())
        monkeypatch.setattr(route_support, "get_chat_connection_manager",
                            lambda _: SimpleNamespace(broadcast=AsyncMock()))
        with TestClient(app) as client:
            yield SimpleNamespace(
                db=db, chat=chat, client=client, clock=clock, record=record, repository=repository,
                pharmacy=pharmacy, calendar=calendar, boundary=boundary, link_id=link_id,
                path=f"/links/{link_id}/messages",
            )
    engine.dispose()


# 함수이름: send
# 함수역할:
# - 선택 사용자로 약국 공유 경로에 요청을 보내고 HTTP 응답을 그대로 반환한다.
# 매개변수:
# - flow: SimpleNamespace; 검색 캐시·채팅 앱·약국 제공자·시계 대역.
# - kind: str; 약국 공유 또는 전화 확인 메시지 종류.
# - sender: str; 연동 환자 또는 보호자 식별자.
# - extra: dict; 공유 요청의 덮어쓸 필드.
# 반환값:
# - httpx.Response; 공유 성공 또는 거부 응답.
def send(flow: SimpleNamespace, *, kind: str = "pharmacy_share", sender: str = "patient-share", **extra: Any) -> httpx.Response:
    return flow.client.post(f"{flow.path}?user_hash={sender}", json={
        "client_message_id": "fallback-share-001", "body": "약국 공유", "message_kind": kind,
        "pharmacy_id": "C1110363", **extra,
    })


# 함수이름: context
# 함수역할:
# - 공유 응답이 200인지 확인하고 약국 문맥만 추출한다.
# 매개변수:
# - response: httpx.Response; 공유 요청 결과.
# 반환값:
# - dict; 약국 공유 문맥. 비정상 상태는 AssertionError.
def context(response: httpx.Response) -> dict[str, Any]:
    assert response.status_code == 200, response.text
    return response.json()["data"]["context"]["pharmacy_context"]


# 함수이름: test_empty_catalog_search_cache_share_uses_fresh_exact_id_and_preserves_retry
# 함수역할:
# - 카탈로그가 없어도 서버 검색 캐시의 정확한 ID·좌표로 당일 시간을 확인하고 재시도·이력에 최초 스냅샷을 유지하는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 검색 캐시·채팅 앱·약국 제공자·시계 대역.
# - kind: str; 약국 공유 또는 전화 확인 메시지 종류.
# - sender: str; 연동 환자 또는 보호자 식별자.
# 반환값:
# - None.
@pytest.mark.parametrize("kind", ["pharmacy_share", "pharmacy_phone_verified"])
@pytest.mark.parametrize("sender", ["patient-share", "caregiver-share"])
def test_empty_catalog_search_cache_share_uses_fresh_exact_id_and_preserves_retry(flow: SimpleNamespace, kind: str, sender: str) -> None:
    forged = {"status": "closed", "as_of": "2099-01-01T00:00:00Z"}
    first = send(flow, kind=kind, sender=sender, latitude=1, longitude=2,
                 operating_snapshot=forged, pharmacy_operating_snapshot=forged,
                 pharmacy_context={"latitude": 1, "longitude": 2, "operating_snapshot": forged})
    shared = context(first)
    assert shared["name"] == "태평양약국"
    assert shared["today_hours"] == "" and shared["source_updated_at"] is None
    assert shared["operating_snapshot"] == {
        "status": "closing_soon", "as_of": NOW.isoformat(),
        "opens_at": "2026-10-27T09:00:00+09:00", "closes_at": "2026-10-27T22:00:00+09:00",
    }
    flow.boundary.searchNearby.assert_awaited_once_with(latitude=37.5, longitude=127.0, limit=30)
    assert flow.repository.count() == 0
    assert flow.repository.find_by_id("C1110363").weekly_hours == {}
    assert flow.db.query(PharmacySearchCacheRecord).count() == 1
    flow.clock.now += timedelta(days=1)
    flow.boundary.searchNearby.side_effect = AssertionError("Retry must not call provider")
    retry = send(flow, kind=kind, sender=sender)
    assert context(retry) == shared and retry.json()["created"] is False
    history = flow.client.get(f"{flow.path}?user_hash={sender}")
    assert history.status_code == 200
    assert history.json()["data"][0]["context"]["pharmacy_context"] == shared
    assert flow.db.query(_ChatMessage).count() == 1


# 함수이름: test_provider_failure_keeps_identity_share_with_unknown_status
# 함수역할:
# - 제공자 실패 시 약국 신원은 공유하되 운영 상태는 unknown으로 저장하는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 검색 캐시·채팅 앱·약국 제공자·시계 대역.
# - error: type[Exception]; 재현할 제공자 실패 유형.
# 반환값:
# - None.
@pytest.mark.parametrize("error", [PharmacyApiUnavailableError, PharmacyApiResponseError, TimeoutError])
def test_provider_failure_keeps_identity_share_with_unknown_status(flow: SimpleNamespace, error: type[Exception]) -> None:
    flow.boundary.searchNearby.side_effect = error("Provider unavailable")
    shared = context(send(flow))
    assert shared["pharmacy_id"] == "C1110363" and shared["name"] == "태평양약국"
    assert shared["operating_snapshot"] == {
        "status": "unknown", "as_of": NOW.isoformat(), "opens_at": None, "closes_at": None,
    }
    assert flow.db.query(_ChatMessage).count() == 1


# 함수이름: test_slow_provider_is_cancelled_and_identity_is_still_saved
# 함수역할:
# - 느린 조회를 취소한 뒤에도 약국 신원과 미확인 상태를 정상 저장하는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 검색 캐시·채팅 앱·약국 제공자·시계 대역.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
def test_slow_provider_is_cancelled_and_identity_is_still_saved(flow: SimpleNamespace, monkeypatch: pytest.MonkeyPatch) -> None:
    cancelled = []

    # 함수이름: slow
    # 함수역할:
    # - 위치 조회를 무기한 지연하고 취소될 때 기록 목록에 표시한다.
    # 매개변수:
    # - _: dict; 사용하지 않는 위치 조회 조건.
    # 반환값:
    # - 정상 반환 없음; 호출자가 취소할 때까지 대기.
    async def slow(**_: float | int) -> NoReturn:
        try:
            await asyncio.Event().wait()
        finally:
            cancelled.append(True)

    flow.boundary.searchNearby.side_effect = slow
    monkeypatch.setattr(settings, "PHARMACY_API_TIMEOUT_SECONDS", 0.01)
    assert context(send(flow))["operating_snapshot"]["status"] == "unknown"
    assert cancelled == [True]


# 함수이름: test_live_date_specific_hours_do_not_guess_holiday_or_calendar_status
# 함수역할:
# - 당일 제공자 시간이 있어도 공휴일이거나 달력이 미확인 상태이면 영업 여부를 추정하지 않는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 검색 캐시·채팅 앱·약국 제공자·시계 대역.
# - calendar_state: str; 공휴일·달력 부재·실패 조건.
# 반환값:
# - None.
@pytest.mark.parametrize("calendar_state", ["holiday", "unavailable", "missing", "timeout"])
def test_live_date_specific_hours_do_not_guess_holiday_or_calendar_status(flow: SimpleNamespace, calendar_state: str) -> None:
    if calendar_state == "holiday":
        flow.calendar.isHoliday.return_value = True
    elif calendar_state == "missing":
        flow.pharmacy._holiday_boundary = None
    else:
        flow.calendar.isHoliday.side_effect = (
            TimeoutError() if calendar_state == "timeout" else PharmacyApiUnavailableError("Calendar unavailable")
        )
    snapshot = context(send(flow))["operating_snapshot"]
    assert snapshot == {"status": "unknown", "as_of": NOW.isoformat(), "opens_at": None, "closes_at": None}


# Function Name: test_live_snapshot_checks_only_todays_calendar
# Description:
# - Requires live-hour snapshots to query only the current calendar date.
# Parameters:
# - flow: SimpleNamespace; isolated search, chat, provider and clock fixtures.
# Returns:
# - None.
def test_live_snapshot_checks_only_todays_calendar(flow: SimpleNamespace) -> None:
    assert context(send(flow))["operating_snapshot"]["status"] == "closing_soon"
    flow.calendar.isHoliday.assert_awaited_once_with(NOW.date())


# Function Name: test_closed_after_todays_hours_does_not_depend_on_yesterday
# Description:
# - Requires verified current-day closing hours to establish closed status without depending on yesterday.
# Parameters:
# - flow: SimpleNamespace; isolated search, chat, provider and clock fixtures.
# Returns:
# - None.
def test_closed_after_todays_hours_does_not_depend_on_yesterday(flow: SimpleNamespace) -> None:
    # 공휴일 다음 날 저녁: 당일 09:00~18:00이 끝났으면 전날과 관계없이 영업 종료다.
    flow.clock.now = NOW.replace(hour=20, minute=0)
    flow.boundary.searchNearby.return_value = [replace(flow.record, start_time="0900", end_time="1800")]
    assert context(send(flow))["operating_snapshot"] == {
        "status": "closed", "as_of": flow.clock.now.isoformat(),
        "opens_at": flow.clock.now.replace(hour=9).isoformat(),
        "closes_at": flow.clock.now.replace(hour=18).isoformat(),
    }


# 함수이름: test_unconfirmed_live_hours_stay_unknown
# 함수역할:
# - 누락·모호·형식 오류가 있는 실시간 시간표는 개폐점 없이 unknown으로 남기는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 검색 캐시·채팅 앱·약국 제공자·시계 대역.
# - start: str; 제공자 시작 시각.
# - end: str; 제공자 종료 시각.
# 반환값:
# - None.
@pytest.mark.parametrize("start,end", [("0900", ""), ("0900", "0900"), ("0900 lunch", "2200")])
def test_unconfirmed_live_hours_stay_unknown(flow: SimpleNamespace, start: str, end: str) -> None:
    flow.boundary.searchNearby.return_value = [replace(flow.record, start_time=start, end_time=end)]
    snapshot = context(send(flow))["operating_snapshot"]
    assert snapshot["status"] == "unknown"
    assert snapshot["opens_at"] is None and snapshot["closes_at"] is None


# 함수이름: test_snapshot_uses_aware_server_clock_after_lookup_not_cached_search_time
# 함수역할:
# - 저장 시점의 운영 상태는 검색 캐시 시간이 아니라 외부 조회 완료 후 시간대가 있는 서버 시각으로 계산하는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 검색 캐시·채팅 앱·약국 제공자·시계 대역.
# 반환값:
# - None.
def test_snapshot_uses_aware_server_clock_after_lookup_not_cached_search_time(flow: SimpleNamespace) -> None:
    # 함수이름: later
    # 함수역할:
    # - 조회 완료 직전 서버 시계를 UTC로 표현한 마감 시각으로 옮기고 약국을 반환한다.
    # 매개변수:
    # - _: dict; 사용하지 않는 위치 조회 조건.
    # 반환값:
    # - list[PharmacyLocationRecord]; 준비된 약국 한 건.
    async def later(**_: float | int) -> list[PharmacyLocationRecord]:
        flow.clock.now = NOW.replace(hour=22, minute=0).astimezone(UTC)
        return [flow.record]

    flow.boundary.searchNearby.side_effect = later
    assert context(send(flow))["operating_snapshot"] == {
        "status": "closed", "as_of": "2026-10-27T22:00:00+09:00",
        "opens_at": "2026-10-27T09:00:00+09:00", "closes_at": "2026-10-27T22:00:00+09:00",
    }


# 함수이름: test_missing_or_ambiguous_exact_id_never_uses_nearest_pharmacy_hours
# 함수역할:
# - 정확한 ID가 없거나 중복되면 가까운 다른 약국의 영업시간을 대신 사용하지 않는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 검색 캐시·채팅 앱·약국 제공자·시계 대역.
# - matches: int; 동일 ID 결과 개수(0 또는 2).
# 반환값:
# - None.
@pytest.mark.parametrize("matches", [0, 2])
def test_missing_or_ambiguous_exact_id_never_uses_nearest_pharmacy_hours(flow: SimpleNamespace, matches: int) -> None:
    neighbor = replace(flow.record, pharmacy_id="OTHER", start_time="0000", end_time="2400")
    flow.boundary.searchNearby.return_value = [neighbor, *([flow.record] * matches)]
    assert context(send(flow))["operating_snapshot"]["status"] == "unknown"


# 함수이름: test_exact_id_is_found_even_when_not_first_result
# 함수역할:
# - 정확한 약국 ID가 두 번째 결과여도 해당 약국의 마감 시각을 사용하는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 검색 캐시·채팅 앱·약국 제공자·시계 대역.
# 반환값:
# - None.
def test_exact_id_is_found_even_when_not_first_result(flow: SimpleNamespace) -> None:
    flow.boundary.searchNearby.return_value = [replace(flow.record, pharmacy_id="OTHER"), flow.record]
    assert context(send(flow))["operating_snapshot"]["closes_at"] == "2026-10-27T22:00:00+09:00"


# 함수이름: test_rejected_share_does_not_call_provider
# 함수역할:
# - 권한·약국 신원·캐시 만료 검증 실패는 외부 조회 전에 거부하고 메시지를 저장하지 않는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 검색 캐시·채팅 앱·약국 제공자·시계 대역.
# - case: str; 연동 외 사용자 또는 누락·만료된 약국 조건.
# - status: int; 예상 HTTP 거부 상태.
# 반환값:
# - None.
@pytest.mark.parametrize("case,status", [("outsider", 404), ("missing", 400), ("expired", 400)])
def test_rejected_share_does_not_call_provider(flow: SimpleNamespace, case: str, status: int) -> None:
    if case == "expired":
        row = flow.db.get(PharmacySearchCacheRecord, "C1110363")
        row.fetched_at = datetime.now(UTC).replace(tzinfo=None) - timedelta(hours=25)
        flow.db.commit()
    response = send(flow, sender="outsider" if case == "outsider" else "patient-share",
                    pharmacy_id="MISSING" if case == "missing" else "C1110363")
    assert response.status_code == status
    flow.boundary.searchNearby.assert_not_awaited()
    assert flow.db.query(_ChatMessage).count() == 0


# 함수이름: test_external_lookup_has_no_request_transaction_and_store_rechecks_link
# 함수역할:
# - 외부 조회 중 요청 트랜잭션을 잡지 않으며 그 사이 연동이 해제되면 저장을 거부하는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 검색 캐시·채팅 앱·약국 제공자·시계 대역.
# 반환값:
# - None.
def test_external_lookup_has_no_request_transaction_and_store_rechecks_link(flow: SimpleNamespace) -> None:
    # 함수이름: revoke
    # 함수역할:
    # - 요청 트랜잭션이 없음을 확인하고 다른 세션에서 연동을 해제한 뒤 약국을 반환한다.
    # 매개변수:
    # - _: dict; 사용하지 않는 위치 조회 조건.
    # 반환값:
    # - list[PharmacyLocationRecord]; 준비된 약국 한 건.
    async def revoke(**_: float | int) -> list[PharmacyLocationRecord]:
        assert not flow.db.in_transaction()
        with Session(flow.db.get_bind()) as other:
            other.query(_PatientCaregiverLink).filter_by(id=flow.link_id).update({"linked": False})
            other.commit()
        return [flow.record]

    flow.boundary.searchNearby.side_effect = revoke
    assert send(flow).status_code == 404
    assert flow.db.query(_ChatMessage).count() == 0


# 함수이름: test_store_rechecks_pharmacy_identity_after_provider_lookup
# 함수역할:
# - 제공자 조회 중 검색 캐시의 약국이 제거되면 저장 전에 신원을 재검증하여 거부하는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 검색 캐시·채팅 앱·약국 제공자·시계 대역.
# 반환값:
# - None.
def test_store_rechecks_pharmacy_identity_after_provider_lookup(flow: SimpleNamespace) -> None:
    # 함수이름: remove
    # 함수역할:
    # - 다른 세션에서 약국 검색 캐시를 삭제·커밋한 뒤 기존 위치 응답을 반환한다.
    # 매개변수:
    # - _: dict; 사용하지 않는 위치 조회 조건.
    # 반환값:
    # - list[PharmacyLocationRecord]; 삭제 전 조회한 약국 한 건.
    async def remove(**_: float | int) -> list[PharmacyLocationRecord]:
        with Session(flow.db.get_bind()) as other:
            other.query(PharmacySearchCacheRecord).filter_by(pharmacy_id="C1110363").delete()
            other.commit()
        return [flow.record]

    flow.boundary.searchNearby.side_effect = remove
    assert send(flow).status_code == 400
    assert flow.db.query(_ChatMessage).count() == 0


# 함수이름: test_lookup_crossing_midnight_does_not_reuse_yesterdays_live_hours
# 함수역할:
# - 조회 중 자정을 넘으면 전날 실시간 시간을 새 날짜에 적용하지 않는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 검색 캐시·채팅 앱·약국 제공자·시계 대역.
# 반환값:
# - None.
def test_lookup_crossing_midnight_does_not_reuse_yesterdays_live_hours(flow: SimpleNamespace) -> None:
    # 함수이름: cross_midnight
    # 함수역할:
    # - 서버 시계를 다음 날 00:01로 변경하고 이전 조회의 약국 시간을 반환한다.
    # 매개변수:
    # - _: dict; 사용하지 않는 위치 조회 조건.
    # 반환값:
    # - list[PharmacyLocationRecord]; 이전 날짜의 약국 응답.
    async def cross_midnight(**_: float | int) -> list[PharmacyLocationRecord]:
        flow.clock.now = datetime(2026, 10, 28, 0, 1, tzinfo=NOW.tzinfo)
        return [flow.record]

    flow.boundary.searchNearby.side_effect = cross_midnight
    snapshot = context(send(flow))["operating_snapshot"]
    assert snapshot == {"status": "unknown", "as_of": flow.clock.now.isoformat(),
                        "opens_at": None, "closes_at": None}


# 함수이름: test_existing_catalog_hours_skip_live_prefetch
# 함수역할:
# - 검증된 카탈로그 시간표가 있으면 실시간 위치 조회 없이 공유 스냅샷을 만드는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 검색 캐시·채팅 앱·약국 제공자·시계 대역.
# 반환값:
# - None.
def test_existing_catalog_hours_skip_live_prefetch(flow: SimpleNamespace) -> None:
    flow.db.add(PharmacyCatalogRecord(
        pharmacy_id="C1110363", name="Catalog Pharmacy", address="시험 주소", telephone="02-000-0000",
        latitude=37.5, longitude=127.0, weekly_hours={"2": ["0900", "2300"]},
    ))
    flow.db.commit()
    flow.repository.replace_korean_holidays(2026, 10, frozenset())
    shared = context(send(flow))
    assert shared["operating_snapshot"]["status"] == "open"
    assert shared["operating_snapshot"]["closes_at"] == "2026-10-27T23:00:00+09:00"
    flow.boundary.searchNearby.assert_not_awaited()


# Function Name: test_overnight_live_hours_are_not_copied_into_previous_day
# Description:
# - Requires unknown previous-day hours to prevent an early-morning closed claim and leaves weekly catalog hours untouched.
# Parameters:
# - flow: SimpleNamespace; isolated search, chat, provider and clock fixtures.
# Returns:
# - None.
def test_overnight_live_hours_are_not_copied_into_previous_day(flow: SimpleNamespace) -> None:
    flow.clock.now = NOW.replace(hour=1, minute=30)
    flow.boundary.searchNearby.return_value = [replace(flow.record, start_time="2200", end_time="0200")]
    snapshot = context(send(flow))["operating_snapshot"]
    # 전날 시간을 모르면 어제 22:00에 열어 아직 영업 중일 수 있으므로 오늘 22:00 개점 전으로 단정하지 않는다.
    assert snapshot == {"status": "unknown", "as_of": flow.clock.now.isoformat(),
                        "opens_at": None, "closes_at": None}
    assert flow.repository.find_by_id("C1110363").weekly_hours == {}


# Function Name: test_holiday_lookups_run_alongside_the_location_search
# Description:
# - Requires the current-day calendar check to start concurrently with location lookup and run once.
# Parameters:
# - flow: SimpleNamespace; isolated search, chat, provider and clock fixtures.
# Returns:
# - None.
def test_holiday_lookups_run_alongside_the_location_search(flow: SimpleNamespace) -> None:
    holiday_started = asyncio.Event()

    # Function Name: search
    # Description:
    # - Waits for the calendar lookup to start before returning the pharmacy, detecting sequential provider execution.
    # Parameters:
    # - _: dict; unused search options.
    # Returns:
    # - list[PharmacyLocationRecord]; prepared pharmacy, or TimeoutError if calendar work never starts.
    async def search(**_: float | int) -> list[PharmacyLocationRecord]:
        await asyncio.wait_for(holiday_started.wait(), 0.5)
        return [flow.record]

    # Function Name: holiday
    # Description:
    # - Signals that the calendar lookup started and reports a nonholiday.
    # Parameters:
    # - _: date; requested date, unused.
    # Returns:
    # - bool; False.
    async def holiday(_: date) -> bool:
        holiday_started.set()
        return False

    flow.boundary.searchNearby.side_effect = search
    flow.calendar.isHoliday.side_effect = holiday
    assert context(send(flow))["operating_snapshot"]["status"] == "closing_soon"
    assert flow.calendar.isHoliday.await_count == 1
