"""주간표 없는 검색 캐시 약국의 신뢰된 당일 공유 스냅샷을 검증한다."""

import asyncio
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock
from zoneinfo import ZoneInfo

import pytest
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


@pytest.fixture
def flow(tmp_path, monkeypatch):
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
        monkeypatch.setattr(route_support, "get_chat_connection_manager",
                            lambda _: SimpleNamespace(broadcast=AsyncMock()))
        with TestClient(app) as client:
            yield SimpleNamespace(
                db=db, chat=chat, client=client, clock=clock, record=record, repository=repository,
                pharmacy=pharmacy, calendar=calendar, boundary=boundary, link_id=link_id,
                path=f"/links/{link_id}/messages",
            )
    engine.dispose()


def send(flow, *, kind="pharmacy_share", sender="patient-share", **extra):
    return flow.client.post(f"{flow.path}?user_hash={sender}", json={
        "client_message_id": "fallback-share-001", "body": "약국 공유", "message_kind": kind,
        "pharmacy_id": "C1110363", **extra,
    })


def context(response):
    assert response.status_code == 200, response.text
    return response.json()["data"]["context"]["pharmacy_context"]


@pytest.mark.parametrize("kind", ["pharmacy_share", "pharmacy_phone_verified"])
@pytest.mark.parametrize("sender", ["patient-share", "caregiver-share"])
def test_empty_catalog_search_cache_share_uses_fresh_exact_id_and_preserves_retry(flow, kind, sender):
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


@pytest.mark.parametrize("error", [PharmacyApiUnavailableError, PharmacyApiResponseError, TimeoutError])
def test_provider_failure_keeps_identity_share_with_unknown_status(flow, error):
    flow.boundary.searchNearby.side_effect = error("Provider unavailable")
    shared = context(send(flow))
    assert shared["pharmacy_id"] == "C1110363" and shared["name"] == "태평양약국"
    assert shared["operating_snapshot"] == {
        "status": "unknown", "as_of": NOW.isoformat(), "opens_at": None, "closes_at": None,
    }
    assert flow.db.query(_ChatMessage).count() == 1


def test_slow_provider_is_cancelled_and_identity_is_still_saved(flow, monkeypatch):
    cancelled = []

    async def slow(**_):
        try:
            await asyncio.Event().wait()
        finally:
            cancelled.append(True)

    flow.boundary.searchNearby.side_effect = slow
    monkeypatch.setattr(settings, "PHARMACY_API_TIMEOUT_SECONDS", 0.01)
    assert context(send(flow))["operating_snapshot"]["status"] == "unknown"
    assert cancelled == [True]


@pytest.mark.parametrize("calendar_state", ["holiday", "unavailable", "missing", "timeout"])
def test_live_date_specific_hours_do_not_guess_holiday_or_calendar_status(flow, calendar_state):
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


def test_live_snapshot_checks_only_todays_calendar(flow):
    assert context(send(flow))["operating_snapshot"]["status"] == "closing_soon"
    flow.calendar.isHoliday.assert_awaited_once_with(NOW.date())


def test_closed_after_todays_hours_does_not_depend_on_yesterday(flow):
    # 공휴일 다음 날 저녁: 당일 09:00~18:00이 끝났으면 전날과 관계없이 영업 종료다.
    flow.clock.now = NOW.replace(hour=20, minute=0)
    flow.boundary.searchNearby.return_value = [replace(flow.record, start_time="0900", end_time="1800")]
    assert context(send(flow))["operating_snapshot"] == {
        "status": "closed", "as_of": flow.clock.now.isoformat(),
        "opens_at": flow.clock.now.replace(hour=9).isoformat(),
        "closes_at": flow.clock.now.replace(hour=18).isoformat(),
    }


@pytest.mark.parametrize("start,end", [("0900", ""), ("0900", "0900"), ("0900 lunch", "2200")])
def test_unconfirmed_live_hours_stay_unknown(flow, start, end):
    flow.boundary.searchNearby.return_value = [replace(flow.record, start_time=start, end_time=end)]
    snapshot = context(send(flow))["operating_snapshot"]
    assert snapshot["status"] == "unknown"
    assert snapshot["opens_at"] is None and snapshot["closes_at"] is None


def test_snapshot_uses_aware_server_clock_after_lookup_not_cached_search_time(flow):
    async def later(**_):
        flow.clock.now = NOW.replace(hour=22, minute=0).astimezone(UTC)
        return [flow.record]

    flow.boundary.searchNearby.side_effect = later
    assert context(send(flow))["operating_snapshot"] == {
        "status": "closed", "as_of": "2026-10-27T22:00:00+09:00",
        "opens_at": "2026-10-27T09:00:00+09:00", "closes_at": "2026-10-27T22:00:00+09:00",
    }


@pytest.mark.parametrize("matches", [0, 2])
def test_missing_or_ambiguous_exact_id_never_uses_nearest_pharmacy_hours(flow, matches):
    neighbor = replace(flow.record, pharmacy_id="OTHER", start_time="0000", end_time="2400")
    flow.boundary.searchNearby.return_value = [neighbor, *([flow.record] * matches)]
    assert context(send(flow))["operating_snapshot"]["status"] == "unknown"


def test_exact_id_is_found_even_when_not_first_result(flow):
    flow.boundary.searchNearby.return_value = [replace(flow.record, pharmacy_id="OTHER"), flow.record]
    assert context(send(flow))["operating_snapshot"]["closes_at"] == "2026-10-27T22:00:00+09:00"


@pytest.mark.parametrize("case,status", [("outsider", 404), ("missing", 400), ("expired", 400)])
def test_rejected_share_does_not_call_provider(flow, case, status):
    if case == "expired":
        row = flow.db.get(PharmacySearchCacheRecord, "C1110363")
        row.fetched_at = datetime.now(UTC).replace(tzinfo=None) - timedelta(hours=25)
        flow.db.commit()
    response = send(flow, sender="outsider" if case == "outsider" else "patient-share",
                    pharmacy_id="MISSING" if case == "missing" else "C1110363")
    assert response.status_code == status
    flow.boundary.searchNearby.assert_not_awaited()
    assert flow.db.query(_ChatMessage).count() == 0


def test_external_lookup_has_no_request_transaction_and_store_rechecks_link(flow):
    async def revoke(**_):
        assert not flow.db.in_transaction()
        with Session(flow.db.get_bind()) as other:
            other.query(_PatientCaregiverLink).filter_by(id=flow.link_id).update({"linked": False})
            other.commit()
        return [flow.record]

    flow.boundary.searchNearby.side_effect = revoke
    assert send(flow).status_code == 404
    assert flow.db.query(_ChatMessage).count() == 0


def test_store_rechecks_pharmacy_identity_after_provider_lookup(flow):
    async def remove(**_):
        with Session(flow.db.get_bind()) as other:
            other.query(PharmacySearchCacheRecord).filter_by(pharmacy_id="C1110363").delete()
            other.commit()
        return [flow.record]

    flow.boundary.searchNearby.side_effect = remove
    assert send(flow).status_code == 400
    assert flow.db.query(_ChatMessage).count() == 0


def test_lookup_crossing_midnight_does_not_reuse_yesterdays_live_hours(flow):
    async def cross_midnight(**_):
        flow.clock.now = datetime(2026, 10, 28, 0, 1, tzinfo=NOW.tzinfo)
        return [flow.record]

    flow.boundary.searchNearby.side_effect = cross_midnight
    snapshot = context(send(flow))["operating_snapshot"]
    assert snapshot == {"status": "unknown", "as_of": flow.clock.now.isoformat(),
                        "opens_at": None, "closes_at": None}


def test_existing_catalog_hours_skip_live_prefetch(flow):
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


def test_overnight_live_hours_are_not_copied_into_previous_day(flow):
    flow.clock.now = NOW.replace(hour=1, minute=30)
    flow.boundary.searchNearby.return_value = [replace(flow.record, start_time="2200", end_time="0200")]
    snapshot = context(send(flow))["operating_snapshot"]
    # 전날 시간을 모르면 어제 22:00에 열어 아직 영업 중일 수 있으므로 오늘 22:00 개점 전으로 단정하지 않는다.
    assert snapshot == {"status": "unknown", "as_of": flow.clock.now.isoformat(),
                        "opens_at": None, "closes_at": None}
    assert flow.repository.find_by_id("C1110363").weekly_hours == {}


def test_holiday_lookups_run_alongside_the_location_search(flow):
    holiday_started = asyncio.Event()

    async def search(**_):
        await asyncio.wait_for(holiday_started.wait(), 0.5)
        return [flow.record]

    async def holiday(_):
        holiday_started.set()
        return False

    flow.boundary.searchNearby.side_effect = search
    flow.calendar.isHoliday.side_effect = holiday
    assert context(send(flow))["operating_snapshot"]["status"] == "closing_soon"
    assert flow.calendar.isHoliday.await_count == 1
