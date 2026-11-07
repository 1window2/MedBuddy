# 파일명: test_chat_operating_snapshot.py
# 역할: 채팅 공유의 서버 운영 스냅샷과 시간·달력 불확실성, 재시도 불변성을 검증한다.

"""병원·약국 공유의 서버 전송 시각, 정확한 운영 구간과 JSON 보존을 검증한다."""

from dataclasses import replace
from datetime import UTC, date, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock
from zoneinfo import ZoneInfo

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from api import chat_router, route_support
from boundaries.pharmacy_api_boundary import PharmacyApiUnavailableError
from controls import manage_linked_chat_control
from controls.check_nearby_hospital_control import CheckNearbyHospital
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.manage_linked_chat_control import ManageLinkedChat
from core import application_clock
from core.config import settings
from core.database import Base
from entities.chat_message_entity import _ChatMessage
from entities.nearby_hospital_entity import HospitalDetails, HospitalLocationRecord
from entities.pharmacy_catalog_entity import KoreanHolidayMonthFetchRecord, PharmacyCatalogRecord
from services.chat_operating_snapshot import build_operating_snapshot


KST = ZoneInfo("Asia/Seoul")
NOW = datetime(2026, 10, 27, 17, 45, tzinfo=KST)


# 함수이름: anyio_backend
# 함수역할:
# - 공유 스냅샷의 비동기 조회를 asyncio에서 실행한다.
# 매개변수:
# - 없음.
# 반환값:
# - str; asyncio.
@pytest.fixture
def anyio_backend():
    return "asyncio"


# 함수이름: test_exact_status_boundaries_without_inferred_lunch
# 함수역할:
# - 개점·마감 경계의 상태와 시각을 정확히 반환하고 시간표에 없는 점심 휴게를 추정하지 않는지 확인한다.
# 매개변수:
# - time: str; 기준일의 한국 시각.
# - status: str; 개점 전·영업 중·마감 임박·종료 경계에서 기대하는 상태 코드.
# 반환값:
# - None.
@pytest.mark.parametrize("time,status", [
    ("08:59:59", "before_open"), ("09:00:00", "open"),
    ("12:30:00", "open"), ("17:29:59", "open"),
    ("17:30:00", "closing_soon"), ("17:59:59", "closing_soon"),
    ("18:00:00", "closed"), ("23:59:59", "closed"),
])
def test_exact_status_boundaries_without_inferred_lunch(time, status):
    now = datetime.fromisoformat(f"2026-10-27T{time}+09:00")
    snapshot = build_operating_snapshot(
        now=now, today_hours=("0900", "1800"), previous_hours=None,
        today_calendar_verified=True, previous_calendar_verified=True,
    )
    assert snapshot == {
        "status": status, "as_of": now.isoformat(),
        "opens_at": "2026-10-27T09:00:00+09:00",
        "closes_at": "2026-10-27T18:00:00+09:00",
    }


# 함수이름: test_missing_or_ambiguous_times_are_unknown
# 함수역할:
# - 누락·동일·잘못된 영업 시각은 개폐점 추정 없이 unknown으로 반환하는지 확인한다.
# 매개변수:
# - hours: tuple[object, ...] | None; 누락, 길이 0·1, 빈 값, 잘못된 시각, 정수 쌍을 포함한 비정상 시간표.
# 반환값:
# - None.
@pytest.mark.parametrize("hours", [
    None, (), ("0900",), ("", ""), ("0900", ""), ("2500", "1800"),
    ("0900", "2460"), ("2400", "0200"), ("0900", "0900"),
    ("0000", "0000"), ("0900 lunch", "1800"), (900, 1800),
])
def test_missing_or_ambiguous_times_are_unknown(hours):
    assert build_operating_snapshot(
        now=NOW, today_hours=hours, previous_hours=None,
        today_calendar_verified=True, previous_calendar_verified=True,
    ) == {"status": "unknown", "as_of": NOW.isoformat(), "opens_at": None, "closes_at": None}


# 함수이름: test_overnight_and_midnight_use_actual_dates
# 함수역할:
# - 전날에서 이어지는 야간 구간과 자정 경계를 실제 날짜가 포함된 시각으로 계산하는지 확인한다.
# 매개변수:
# - now: str; 시간대가 포함된 기준 시각.
# - today: tuple[str, str] | None; 당일 영업 구간 또는 시간표 없음.
# - previous: tuple[str, str] | None; 전날 영업 구간.
# - status: str; 야간·자정 경계에서 기대하는 open·closing_soon·before_open 상태.
# - opens: str | None; 예상 개점 시각.
# - closes: str | None; 예상 폐점 시각.
# 반환값:
# - None.
@pytest.mark.parametrize("now,today,previous,status,opens,closes", [
    ("2026-10-27T23:45:00+09:00", ("2200", "0200"), None, "open",
     "2026-10-27T22:00:00+09:00", "2026-10-28T02:00:00+09:00"),
    ("2026-10-28T01:30:00+09:00", None, ("2200", "0200"), "closing_soon",
     "2026-10-27T22:00:00+09:00", "2026-10-28T02:00:00+09:00"),
    ("2026-10-28T02:00:00+09:00", ("0900", "1800"), ("2200", "0200"), "before_open",
     "2026-10-28T09:00:00+09:00", "2026-10-28T18:00:00+09:00"),
    ("2026-10-27T23:30:00+09:00", ("0900", "2400"), None, "closing_soon",
     "2026-10-27T09:00:00+09:00", "2026-10-28T00:00:00+09:00"),
    ("2026-10-27T12:00:00+09:00", ("0000", "2400"), None, "open",
     "2026-10-27T00:00:00+09:00", None),
])
def test_overnight_and_midnight_use_actual_dates(now, today, previous, status, opens, closes):
    assert build_operating_snapshot(
        now=datetime.fromisoformat(now), today_hours=today, previous_hours=previous,
        today_calendar_verified=True, previous_calendar_verified=True,
    ) == {"status": status, "as_of": now, "opens_at": opens, "closes_at": closes}


# Function Name: test_all_day_hours_stay_open_without_closing_time
# Description:
# - Requires all-day hours to remain open without inventing a closing time, regardless of the previous interval.
# Parameters:
# - time: str; local time on the reference date.
# - previous: tuple[str, str] | None; previous-day opening interval.
# Returns:
# - None.
@pytest.mark.parametrize("time", ["00:00:00", "12:00:00", "23:45:00", "23:59:00"])
@pytest.mark.parametrize("previous", [("0000", "2400"), ("2200", "0200"), None])
def test_all_day_hours_stay_open_without_closing_time(time, previous):
    now = datetime.fromisoformat(f"2026-10-27T{time}+09:00")
    snapshot = build_operating_snapshot(
        now=now, today_hours=("0000", "2400"), previous_hours=previous,
        today_calendar_verified=True, previous_calendar_verified=True,
    )
    assert snapshot["status"] == "open"
    assert snapshot["closes_at"] is None


# 함수이름: test_overlapping_and_touching_intervals_are_merged
# 함수역할:
# - 겹치거나 맞닿은 전날·당일 구간을 합쳐 연속 영업의 개폐점과 상태를 반환하는지 확인한다.
# 매개변수:
# - previous: tuple[str, str]; 당일까지 이어지는 전날 영업 구간.
# - today: tuple[str, str]; 당일 영업 구간.
# - time: str; 기준일의 한국 시각.
# - status: str; 병합된 구간의 예상 open·closing_soon·closed 상태.
# - closing_date: str; 병합된 구간의 예상 폐점 시각.
# 반환값:
# - None.
@pytest.mark.parametrize("previous,today,time,status,closing_date", [
    (("2000", "1000"), ("0900", "1900"), "09:50:00", "open", "2026-10-27T19:00:00+09:00"),
    (("2000", "0900"), ("0900", "1900"), "08:50:00", "open", "2026-10-27T19:00:00+09:00"),
    (("2000", "1000"), ("0900", "1900"), "18:30:00", "closing_soon", "2026-10-27T19:00:00+09:00"),
    (("2000", "1000"), ("0900", "1900"), "19:00:00", "closed", "2026-10-27T19:00:00+09:00"),
    (("2000", "1000"), ("0900", "0800"), "09:50:00", "open", "2026-10-28T08:00:00+09:00"),
])
def test_overlapping_and_touching_intervals_are_merged(previous, today, time, status, closing_date):
    now = datetime.fromisoformat(f"2026-10-27T{time}+09:00")
    snapshot = build_operating_snapshot(
        now=now, today_hours=today, previous_hours=previous,
        today_calendar_verified=True, previous_calendar_verified=True,
    )
    assert snapshot == {"status": status, "as_of": now.isoformat(),
                        "opens_at": "2026-10-26T20:00:00+09:00", "closes_at": closing_date}


# 함수이름: test_snapshot_rejects_naive_clock
# 함수역할:
# - 시간대가 없는 기준 시각은 ValueError로 거부하는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_snapshot_rejects_naive_clock():
    with pytest.raises(ValueError, match="timezone-aware"):
        build_operating_snapshot(
            now=NOW.replace(tzinfo=None), today_hours=("0900", "1800"), previous_hours=None,
            today_calendar_verified=True, previous_calendar_verified=True,
        )


# 함수이름: flow
# 함수역할:
# - 격리 DB에 연동·약국과 고정 시계를 만들고 외부 제공자만 교체하며 종료 후 앱·세션·엔진을 정리한다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - Iterator[SimpleNamespace]; 시계·채팅 컨트롤·HTTP 클라이언트·제공자 대역.
@pytest.fixture
def flow(monkeypatch):
    """외부 조회만 대체하고 실제 전송·저장·공개 응답을 격리 DB에서 실행한다."""
    monkeypatch.setattr(settings, "APPLICATION_TIME_ZONE", "Asia/Seoul")
    clock = SimpleNamespace(now=NOW)
    monkeypatch.setattr(application_clock, "application_now", lambda: clock.now)
    monkeypatch.setattr(manage_linked_chat_control, "application_now", lambda: clock.now)
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    with sessionmaker(bind=engine)() as db:
        links = LinkPatientCaregiver(db)
        code = links.generatePatientHash("patient-snapshot")["data"]["patient_code"]
        link_id = links.requestPatientCaregiverLink("caregiver-snapshot", code)["data"]["id"]
        hours = {"1": ("2200", "0200"), "2": ("0900", "1800"),
                 "3": ("1000", "1300"), "8": ("0900", "1800")}
        db.add(PharmacyCatalogRecord(
            pharmacy_id="P123", name="Snapshot Pharmacy", address="Seoul", telephone="02-000-0000",
            latitude=37.5, longitude=127.0, weekly_hours=hours,
        ))
        db.commit()
        chat = ManageLinkedChat(db)
        chat.pharmacy_repository.replace_korean_holidays(2026, 10, frozenset())
        detail = HospitalDetails(
            "H123", weekly_hours=tuple((key, *values) for key, values in hours.items()),
            location=HospitalLocationRecord("H123", "Snapshot Hospital", "Seoul", "02-000-0000", 37.5, 127.0),
            fetched_at=datetime(2026, 10, 26, 1, tzinfo=UTC),
        )
        boundary = SimpleNamespace(fetchDetails=AsyncMock(return_value=detail))
        calendar = SimpleNamespace(isHoliday=AsyncMock(return_value=False))
        hospital = CheckNearbyHospital(boundary, holiday_boundary=calendar, clock=lambda: clock.now)
        app = FastAPI()
        app.include_router(chat_router.router)
        app.dependency_overrides[chat_router.get_authenticated_app_principal] = lambda: object()
        app.dependency_overrides[chat_router.get_authorization_control] = lambda: SimpleNamespace(
            resolveOwnUserHash=lambda _, value: value,
        )
        app.dependency_overrides[chat_router.get_manage_linked_chat] = lambda: chat
        app.dependency_overrides[chat_router.get_check_nearby_hospital] = lambda: hospital
        app.dependency_overrides[chat_router.get_check_nearby_pharmacy] = lambda: SimpleNamespace(
            requestShareOperatingSnapshot=AsyncMock(side_effect=AssertionError("Catalog shares must not fetch live hours")),
        )
        monkeypatch.setattr(chat_router, "enforce_chat_daily_quota", AsyncMock())
        monkeypatch.setattr(chat_router, "enforce_hospital_share_daily_quota", AsyncMock())
        monkeypatch.setattr(route_support, "get_chat_connection_manager",
                            lambda _: SimpleNamespace(broadcast=AsyncMock()))
        with TestClient(app) as client:
            yield SimpleNamespace(
                clock=clock, db=db, chat=chat, hospital=hospital, boundary=boundary,
                calendar=calendar, detail=detail, client=client,
                url=f"/links/{link_id}/messages?user_hash=patient-snapshot",
            )
    engine.dispose()


# 함수이름: share_payload
# 함수역할:
# - 병원 또는 약국 ID와 병원 선택 날짜를 갖는 공유 요청 본문을 만든다.
# 매개변수:
# - kind: str; hospital_share, pharmacy_share 또는 pharmacy_phone_verified.
# 반환값:
# - dict; 공유 메시지 요청 필드.
def share_payload(kind):
    values = {"client_message_id": "operating-snapshot-001", "body": "Shared care location",
              "message_kind": kind}
    if kind == "hospital_share":
        values.update(hospital_id="H123", hospital_schedule_date="2026-10-28")
    else:
        values["pharmacy_id"] = "P123"
    return values


# 함수이름: shared_context
# 함수역할:
# - 요청 필드를 덮어써 공유하고 HTTP 200을 확인한 뒤 종류에 맞는 서버 문맥을 반환한다.
# 매개변수:
# - flow: SimpleNamespace; 격리 DB·채팅 앱·제공자·시계 대역.
# - kind: str; hospital_share, pharmacy_share 또는 pharmacy_phone_verified.
# - extra: dict; 공유 요청에 덮어쓸 필드.
# 반환값:
# - dict; 병원 또는 약국 공유 문맥. 실패 응답은 AssertionError.
def shared_context(flow, kind, **extra):
    response = flow.client.post(flow.url, json={**share_payload(kind), **extra})
    assert response.status_code == 200, response.text
    key = "hospital_context" if kind == "hospital_share" else "pharmacy_context"
    return response.json()["data"]["context"][key]


# 함수이름: test_public_json_is_server_trusted_and_frozen_across_history_and_retry
# 함수역할:
# - 클라이언트의 위조 운영 상태를 무시하고 서버 스냅샷을 저장하여 이후 이력·재시도에도 바뀌지 않는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 격리 DB·채팅 앱·제공자·시계 대역.
# - kind: str; hospital_share, pharmacy_share 또는 pharmacy_phone_verified.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.parametrize("kind", ["hospital_share", "pharmacy_share", "pharmacy_phone_verified"])
def test_public_json_is_server_trusted_and_frozen_across_history_and_retry(flow, kind, monkeypatch):
    forged = {"status": "open", "as_of": "2099-01-01T00:00:00Z",
              "opens_at": "2099-01-01T00:00:00Z", "closes_at": None}
    key = "hospital_context" if kind == "hospital_share" else "pharmacy_context"
    context = shared_context(flow, kind, operating_snapshot=forged,
                             **{key: {"operating_snapshot": forged},
                                "context": {key: {"operating_snapshot": forged}}})
    snapshot = context["operating_snapshot"]
    assert snapshot == {
        "status": "closing_soon", "as_of": NOW.isoformat(),
        "opens_at": "2026-10-27T09:00:00+09:00",
        "closes_at": "2026-10-27T18:00:00+09:00",
    }
    assert all(datetime.fromisoformat(snapshot[key]).utcoffset() is not None
               for key in ("as_of", "opens_at", "closes_at"))
    if kind == "hospital_share":
        assert context["schedule_date"] == "2026-10-28"
        assert context["today_hours"] == "10:00 - 13:00"
        flow.boundary.fetchDetails.assert_awaited_once_with("H123")
        assert {call.args[0] for call in flow.calendar.isHoliday.await_args_list} == {
            date(2026, 10, 26), date(2026, 10, 27), date(2026, 10, 28),
        }
    else:
        assert context["today_hours"] == "09:00 - 18:00"
        flow.boundary.fetchDetails.assert_not_awaited()
    flow.clock.now = NOW + timedelta(days=1)
    flow.boundary.fetchDetails.side_effect = AssertionError("Unexpected provider request")
    monkeypatch.setattr(flow.chat.pharmacy_repository, "find_by_id",
                        Mock(side_effect=AssertionError("Unexpected catalog request")))
    history = flow.client.get(flow.url)
    assert history.status_code == 200
    assert history.json()["data"][0]["context"][key] == context
    retry = flow.client.post(flow.url, json=share_payload(kind))
    assert retry.status_code == 200 and retry.json()["created"] is False
    assert retry.json()["data"]["context"][key] == context
    assert flow.db.query(_ChatMessage).one().context_payload[key] == context


# 함수이름: test_both_share_types_use_current_day_and_overnight_hours
# 함수역할:
# - 병원·약국 공유 모두 현재 날짜와 전날 야간 이월 구간으로 운영 상태를 계산하는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 격리 DB·채팅 앱·제공자·시계 대역.
# - kind: str; hospital_share 또는 pharmacy_share.
# - time: str; 기준일의 한국 시각.
# - status: str; 예상 closing_soon·before_open·open·closed 상태.
# - opens: str | None; 예상 개점 시각.
# - closes: str | None; 예상 폐점 시각.
# 반환값:
# - None.
@pytest.mark.parametrize("kind", ["hospital_share", "pharmacy_share"])
@pytest.mark.parametrize("time,status,opens,closes", [
    ("01:30:00", "closing_soon", "2026-10-26T22:00:00+09:00", "2026-10-27T02:00:00+09:00"),
    ("08:00:00", "before_open", "2026-10-27T09:00:00+09:00", "2026-10-27T18:00:00+09:00"),
    ("12:00:00", "open", "2026-10-27T09:00:00+09:00", "2026-10-27T18:00:00+09:00"),
    ("18:00:00", "closed", "2026-10-27T09:00:00+09:00", "2026-10-27T18:00:00+09:00"),
])
def test_both_share_types_use_current_day_and_overnight_hours(flow, kind, time, status, opens, closes):
    flow.clock.now = datetime.fromisoformat(f"2026-10-27T{time}+09:00")
    snapshot = shared_context(flow, kind)["operating_snapshot"]
    assert snapshot == {"status": status, "as_of": flow.clock.now.isoformat(),
                        "opens_at": opens, "closes_at": closes}


# 함수이름: test_share_merges_verified_intervals_and_keeps_past_closed_bounds
# 함수역할:
# - 확인된 연속 구간을 병합하고 영업 종료 후에도 실제 과거 개폐점 시각을 보존하는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 격리 DB·채팅 앱·제공자·시계 대역.
# - kind: str; hospital_share 또는 pharmacy_share.
# - previous_end: str; 전날 구간의 종료 시각.
# - time: str; 기준일의 한국 시각.
# - status: str; 병합 구간의 예상 open 또는 closed 상태.
# 반환값:
# - None.
@pytest.mark.parametrize("kind", ["hospital_share", "pharmacy_share"])
@pytest.mark.parametrize("previous_end,time,status", [
    ("1000", "09:50:00", "open"), ("0900", "08:50:00", "open"),
    ("1000", "19:00:00", "closed"),
])
def test_share_merges_verified_intervals_and_keeps_past_closed_bounds(flow, kind, previous_end, time, status):
    hours = {"1": ("2000", previous_end), "2": ("0900", "1900")}
    flow.boundary.fetchDetails.return_value = replace(
        flow.detail, weekly_hours=tuple((key, *value) for key, value in hours.items()),
    )
    pharmacy = flow.db.get(PharmacyCatalogRecord, "P123")
    pharmacy.weekly_hours = hours
    flow.db.commit()
    flow.clock.now = datetime.fromisoformat(f"2026-10-27T{time}+09:00")
    assert shared_context(flow, kind)["operating_snapshot"] == {
        "status": status, "as_of": flow.clock.now.isoformat(),
        "opens_at": "2026-10-26T20:00:00+09:00", "closes_at": "2026-10-27T19:00:00+09:00",
    }


# 함수이름: test_previous_holiday_only_blocks_status_that_needs_overnight_evidence
# 함수역할:
# - 전날 공휴일 정보는 야간 이월 판단이 필요한 때만 상태를 미확인으로 만드는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 격리 DB·채팅 앱·제공자·시계 대역.
# - kind: str; hospital_share 또는 pharmacy_share.
# - hour: int; 스냅샷 계산 시각의 시.
# - status: str; 전날 근거가 필요한 새벽의 unknown 또는 당일 낮의 open.
# 반환값:
# - None.
@pytest.mark.parametrize("kind", ["hospital_share", "pharmacy_share"])
@pytest.mark.parametrize("hour,status", [(1, "unknown"), (12, "open")])
def test_previous_holiday_only_blocks_status_that_needs_overnight_evidence(flow, kind, hour, status):
    previous = NOW.date() - timedelta(days=1)
    flow.calendar.isHoliday.side_effect = lambda value: value == previous
    flow.chat.pharmacy_repository.replace_korean_holidays(2026, 10, frozenset({previous}))
    flow.clock.now = NOW.replace(hour=hour)
    snapshot = shared_context(flow, kind)["operating_snapshot"]
    assert snapshot["status"] == status
    assert snapshot["opens_at"] == ("2026-10-27T09:00:00+09:00" if status == "open" else None)
    assert snapshot["closes_at"] == ("2026-10-27T18:00:00+09:00" if status == "open" else None)


# 함수이름: test_holidays_and_calendar_failure_do_not_claim_regular_hours
# 함수역할:
# - 공휴일 또는 달력 누락·만료·장애 시 평일 시간표를 정상 운영 상태로 오인하지 않는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 격리 DB·채팅 앱·제공자·시계 대역.
# - kind: str; hospital_share 또는 pharmacy_share.
# - calendar_state: str; 공휴일 또는 달력 누락·만료·실패 상태.
# 반환값:
# - None.
@pytest.mark.parametrize("kind", ["hospital_share", "pharmacy_share"])
@pytest.mark.parametrize("calendar_state", ["holiday", "missing", "expired", "timeout"])
def test_holidays_and_calendar_failure_do_not_claim_regular_hours(flow, kind, calendar_state):
    if calendar_state == "holiday":
        holiday = NOW.date()
        flow.calendar.isHoliday.side_effect = lambda value: value == holiday
        flow.chat.pharmacy_repository.replace_korean_holidays(2026, 10, frozenset({holiday}))
    else:
        flow.calendar.isHoliday.side_effect = (
            TimeoutError() if calendar_state == "timeout"
            else PharmacyApiUnavailableError("Calendar unavailable")
        )
        marker = flow.db.get(KoreanHolidayMonthFetchRecord, "2026-10")
        if calendar_state in {"missing", "timeout"}:
            flow.db.delete(marker)
        else:
            marker.fetched_at = datetime(2000, 1, 1)
        flow.db.commit()
    snapshot = shared_context(flow, kind)["operating_snapshot"]
    assert snapshot == {"status": "unknown", "as_of": NOW.isoformat(),
                        "opens_at": None, "closes_at": None}


# 함수이름: test_hospital_break_notes_do_not_infer_precise_availability
# 함수역할:
# - 정확하지 않은 점심 안내가 있으면 병원의 현재 진료 여부를 unknown으로 남기는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 격리 DB·채팅 앱·제공자·시계 대역.
# 반환값:
# - None.
def test_hospital_break_notes_do_not_infer_precise_availability(flow):
    flow.boundary.fetchDetails.return_value = replace(flow.detail, operating_notes="점심시간 전화 문의")
    assert shared_context(flow, "hospital_share")["operating_snapshot"]["status"] == "unknown"


# 함수이름: test_unknown_current_hours_remain_unknown_even_with_future_hours
# 함수역할:
# - 미래 날짜 시간표가 있어도 현재 날짜 시간이 없으면 현재 상태를 추정하지 않는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 격리 DB·채팅 앱·제공자·시계 대역.
# - kind: str; hospital_share 또는 pharmacy_share.
# 반환값:
# - None.
@pytest.mark.parametrize("kind", ["hospital_share", "pharmacy_share"])
def test_unknown_current_hours_remain_unknown_even_with_future_hours(flow, kind):
    flow.boundary.fetchDetails.return_value = replace(flow.detail, weekly_hours=(("3", "1000", "1300"),))
    pharmacy = flow.db.get(PharmacyCatalogRecord, "P123")
    pharmacy.weekly_hours = {"3": ["1000", "1300"]}
    flow.db.commit()
    snapshot = shared_context(flow, kind)["operating_snapshot"]
    assert snapshot == {"status": "unknown", "as_of": NOW.isoformat(),
                        "opens_at": None, "closes_at": None}


# 함수이름: test_previous_calendar_failure_does_not_discard_verified_today
# 함수역할:
# - 전월 달력 조회 실패가 당일 확인된 영업 구간까지 버리지 않고 필요한 경우에만 미확인 처리되는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 격리 DB·채팅 앱·제공자·시계 대역.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# - kind: str; hospital_share 또는 pharmacy_share.
# - hour: int; 스냅샷 계산 시각의 시.
# - status: str; 전월 근거가 필요한 새벽의 unknown 또는 확인된 당일 낮의 open.
# 반환값:
# - None.
@pytest.mark.parametrize("kind", ["hospital_share", "pharmacy_share"])
@pytest.mark.parametrize("hour,status", [(1, "unknown"), (12, "open")])
def test_previous_calendar_failure_does_not_discard_verified_today(flow, monkeypatch, kind, hour, status):
    flow.clock.now = datetime(2026, 11, 1, hour, tzinfo=KST)
    hours = {"6": ("2000", "1000"), "7": ("0900", "1800")}
    flow.boundary.fetchDetails.return_value = replace(
        flow.detail, weekly_hours=tuple((key, *value) for key, value in hours.items()),
    )
    pharmacy = flow.db.get(PharmacyCatalogRecord, "P123")
    pharmacy.weekly_hours = hours
    flow.db.commit()

    # 함수이름: holiday
    # 함수역할:
    # - 전월 달력 조회에는 오류를 내고 당월 날짜에는 평일을 반환한다.
    # 매개변수:
    # - value: date; 공휴일 조회 날짜.
    # 반환값:
    # - bool; 전월에는 PharmacyApiUnavailableError.
    async def holiday(value):
        if value.month == 10:
            raise PharmacyApiUnavailableError("Previous calendar unavailable")
        return False

    flow.calendar.isHoliday.side_effect = holiday
    lookup = Mock(side_effect=lambda year, month, **_: frozenset() if month == 11 else None)
    monkeypatch.setattr(flow.chat.pharmacy_repository, "get_cached_korean_holidays", lookup)
    snapshot = shared_context(flow, kind)["operating_snapshot"]
    assert snapshot["status"] == status
    assert snapshot["closes_at"] == ("2026-11-01T18:00:00+09:00" if status == "open" else None)
    if kind == "pharmacy_share":
        assert {call.args for call in lookup.call_args_list} == {(2026, 10), (2026, 11)}


# 함수이름: test_hospital_server_utc_clock_is_normalized_and_calendar_dates_deduplicated
# 함수역할:
# - 서버 UTC 시각을 한국 시간으로 변환하고 중복 날짜의 달력 조회를 합쳐 야간 상태를 계산하는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 격리 DB·채팅 앱·제공자·시계 대역.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_hospital_server_utc_clock_is_normalized_and_calendar_dates_deduplicated(flow):
    local_now = NOW.replace(hour=1, minute=30)
    flow.clock.now = local_now.astimezone(UTC)
    context = await flow.hospital.requestShareContext("H123", NOW.date())
    assert context["operating_snapshot"]["as_of"] == local_now.isoformat()
    assert context["operating_snapshot"]["status"] == "closing_soon"
    assert flow.calendar.isHoliday.await_count == 2
    flow.boundary.fetchDetails.assert_awaited_once()


# 함수이름: test_hospital_reads_server_clock_after_provider_and_calendar_work
# 함수역할:
# - 상세·달력 조회 완료 후 시계를 다시 읽어 그 사이 도달한 마감 시각을 반영하는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 격리 DB·채팅 앱·제공자·시계 대역.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_hospital_reads_server_clock_after_provider_and_calendar_work(flow):
    # 함수이름: details
    # 함수역할:
    # - 상세 조회 중 시계를 마감 직전으로 옮기고 준비된 병원 상세를 반환한다.
    # 매개변수:
    # - _: object; 사용하지 않는 제공자 조회 인수.
    # 반환값:
    # - HospitalDetails; 고정 병원 상세.
    async def details(_):
        flow.clock.now = NOW.replace(hour=17, minute=59, second=59)
        return flow.detail

    # 함수이름: holiday
    # 함수역할:
    # - 달력 조회 중 시계를 마감 시각으로 옮기고 평일 여부를 반환한다.
    # 매개변수:
    # - _: object; 사용하지 않는 제공자 조회 인수.
    # 반환값:
    # - bool; False.
    async def holiday(_):
        flow.clock.now = NOW.replace(hour=18, minute=0, second=0)
        return False

    flow.boundary.fetchDetails.side_effect = details
    flow.calendar.isHoliday.side_effect = holiday
    context = await flow.hospital.requestShareContext("H123", date(2026, 10, 28))
    assert context["operating_snapshot"]["status"] == "closed"
    assert context["operating_snapshot"]["as_of"] == "2026-10-27T18:00:00+09:00"
    flow.boundary.fetchDetails.assert_awaited_once()


# 함수이름: test_crossing_midnight_during_calendar_lookup_does_not_guess_new_day
# 함수역할:
# - 달력 조회 중 자정을 넘으면 이전 날짜의 근거로 새 날짜 운영 상태를 추정하지 않는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 격리 DB·채팅 앱·제공자·시계 대역.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_crossing_midnight_during_calendar_lookup_does_not_guess_new_day(flow):
    flow.clock.now = NOW.replace(hour=23, minute=59, second=59)

    # 함수이름: holiday
    # 함수역할:
    # - 달력 조회 중 시계를 다음 날 자정으로 옮기고 평일 여부를 반환한다.
    # 매개변수:
    # - _: object; 사용하지 않는 제공자 조회 인수.
    # 반환값:
    # - bool; False.
    async def holiday(_):
        flow.clock.now = datetime(2026, 10, 28, tzinfo=KST)
        return False

    flow.calendar.isHoliday.side_effect = holiday
    context = await flow.hospital.requestShareContext("H123", NOW.date())
    assert context["operating_snapshot"] == {
        "status": "unknown", "as_of": "2026-10-28T00:00:00+09:00",
        "opens_at": None, "closes_at": None,
    }


# 함수이름: test_future_holiday_selection_does_not_replace_current_hospital_status
# 함수역할:
# - 미래 공휴일의 선택 시간표와 현재 운영 스냅샷을 분리하여 현재 상태를 유지하는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 격리 DB·채팅 앱·제공자·시계 대역.
# 반환값:
# - None.
def test_future_holiday_selection_does_not_replace_current_hospital_status(flow):
    flow.calendar.isHoliday.side_effect = lambda value: value == date(2026, 10, 28)
    context = shared_context(flow, "hospital_share")
    assert context["schedule_date"] == "2026-10-28"
    assert context["today_hours"] == "09:00 - 18:00"
    assert context["operating_snapshot"]["status"] == "closing_soon"
    assert context["operating_snapshot"]["as_of"] == NOW.isoformat()


# 함수이름: test_pharmacy_reuses_calendar_month_without_provider_work
# 함수역할:
# - 약국 공유는 검증된 월별 달력 캐시를 한 번만 읽고 외부 병원·달력 조회는 생략하는지 확인한다.
# 매개변수:
# - flow: SimpleNamespace; 격리 DB·채팅 앱·제공자·시계 대역.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
def test_pharmacy_reuses_calendar_month_without_provider_work(flow, monkeypatch):
    lookup = Mock(wraps=flow.chat.pharmacy_repository.get_cached_korean_holidays)
    monkeypatch.setattr(flow.chat.pharmacy_repository, "get_cached_korean_holidays", lookup)
    assert shared_context(flow, "pharmacy_share")["operating_snapshot"]["status"] == "closing_soon"
    lookup.assert_called_once_with(2026, 10, max_age=timedelta(days=30))
    flow.boundary.fetchDetails.assert_not_awaited()
    flow.calendar.isHoliday.assert_not_awaited()
