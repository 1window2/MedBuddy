"""복약 이력 공유의 서버 집계·권한·멱등성·삭제·푸시 개인정보 경계를 검증한다."""

from collections import Counter
import json
from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock
from uuid import uuid4

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError

from api import chat_router, medication_care_router, route_support
from controls.authorization_control import AuthorizationControl
from controls.dispatch_chat_message_alert_control import DispatchChatMessageAlert
from controls.manage_linked_chat_control import ManageLinkedChat
from controls.manage_medication_care_control import ManageMedicationCare
from core.application_clock import application_now, application_today
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.chat_message_entity import _ChatMessage
from entities.chat_notification_job_entity import ChatNotificationJob
from entities.device_push_token_entity import _DevicePushToken
from entities.medication_completion_entity import _MedicationCompletion
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.user_setting_entity import _UserSetting
from schemas.chat import ChatMessageCreate
from schemas.medication_care import DoseHistoryUpdate
from support.db import seed_account, seed_medication
from support.fakes import RecordingPushBoundary


KIND = "medication_history_share"


@pytest.fixture
def chat(fk_db):
    seed_account(fk_db, "patient-a", "caregiver-a", "outsider")
    link = _PatientCaregiverLink(patient_hash="patient-a", caregiver_hash="caregiver-a", linked=True)
    fk_db.add(link)
    fk_db.commit()
    return ManageLinkedChat(fk_db), link.id


def payload(**changes):
    today = application_today()
    return ChatMessageCreate(**{
        "client_message_id": "history_share_001", "body": "복약 기록을 공유해요.",
        "message_kind": KIND, "history_start_date": today - timedelta(days=1),
        "history_end_date": today, **changes,
    })


def send(chat, *, sender="patient-a", **changes):
    request = payload(**changes)
    arguments = request.model_dump(exclude={"hospital_id", "hospital_schedule_date"})
    return chat[0].send_message(link_id=chat[1], sender_hash=sender, **arguments)


@pytest.fixture
def records(chat):
    """정기 일정과 필요시 실제 기록을 함께 만들고 다른 사람의 약도 분리한다."""
    db = chat[0].db
    today = application_today()
    scheduled = seed_medication(
        db, prescription_date=today - timedelta(days=1), daily_frequency="3",
        schedule_slot_keys='["morning", "lunch", "evening"]',
    )
    prn = seed_medication(db, dosing_mode="as_needed", daily_frequency="", schedule_slot_keys="[]")
    seed_medication(db, patient_hash="caregiver-a")
    seed_medication(db, patient_hash="outsider")
    rows = []
    for medication, offset, slot, status in (
        (scheduled, -1, "morning", "taken"), (scheduled, -1, "lunch", "skipped"),
        (prn, -1, f"as_needed:{uuid4()}", "taken"), (prn, -1, f"as_needed:{uuid4()}", "skipped"),
        (prn, 0, f"as_needed:{uuid4()}", "unrecorded"),
    ):
        rows.append(_MedicationCompletion(
            patient_hash="patient-a", saved_medication_id=medication.id,
            schedule_date=today + timedelta(days=offset), slot_key=slot,
            completed=status == "taken", report_status=status, revision=1,
        ))
    db.add_all(rows)
    db.commit()
    return rows


@pytest.mark.parametrize("sender", ["patient-a", "caregiver-a"])
def test_snapshot_counts_all_history_items_including_prn(chat, records, sender):
    response = send(chat, sender=sender).message.to_response_dict()
    request = payload()
    history = ManageMedicationCare(chat[0].db).history(
        AuthenticatedPrincipal(subject=sender, issuer="test", user_hash=sender),
        request.history_start_date, request.history_end_date, "patient-a",
    )
    counts = Counter(item["status"] for item in history["items"])
    assert counts == {"taken": 2, "skipped": 2, "unrecorded": 5}
    assert response["message_kind"] == KIND
    assert response["context"] == {"history_context": {
        "start_date": request.history_start_date.isoformat(),
        "end_date": request.history_end_date.isoformat(),
        **{f"{status}_count": counts[status] for status in ("taken", "skipped", "unrecorded")},
    }}
    assert response["created_at"]
    assert response["medication_context"] is None and response["medication_contexts"] == []
    assert chat[0].db.query(ChatNotificationJob).count() == 1


def test_prn_undo_matches_latest_care_history_without_rewriting_shared_snapshot(chat):
    """필요시 취소는 복용 건수에서 빠지고 미기록으로 남으며 이전 공유는 바뀌지 않는다."""
    db = chat[0].db
    today = application_today()
    prn = seed_medication(db, dosing_mode="as_needed", daily_frequency="", schedule_slot_keys="[]")
    seed_medication(db, dosing_mode="as_needed", daily_frequency="", schedule_slot_keys="[]")
    principal = AuthenticatedPrincipal(subject="patient-a", issuer="test", user_hash="patient-a")
    care = ManageMedicationCare(db)
    keys = [f"as_needed:{uuid4()}" for _ in range(2)]
    for key in keys:
        care.update_history(principal, prn.id, today, key, DoseHistoryUpdate(
            operation_id=uuid4(), status="taken", actual_taken_at=application_now() - timedelta(seconds=1),
        ))
    first = send(chat)
    assert first.message.context_payload["history_context"]["taken_count"] == 2
    care.update_history(principal, prn.id, today, keys[0], DoseHistoryUpdate(
        operation_id=uuid4(), status="unrecorded", expected_revision=1,
    ))
    latest = medication_care_router.get_history(
        start_date=today - timedelta(days=1), end_date=today, principal=principal, db=db,
    )
    assert len(latest["items"]) == 2
    assert Counter(item["status"] for item in latest["items"]) == {"taken": 1, "unrecorded": 1}
    fresh = send(chat, client_message_id="history_share_after_undo")
    assert fresh.message.context_payload["history_context"] == {
        "start_date": latest["start_date"], "end_date": latest["end_date"],
        "taken_count": 1, "skipped_count": 0, "unrecorded_count": 1,
    }
    replay = send(chat)
    assert not replay.created and replay.message.to_response_dict() == first.message.to_response_dict()


@pytest.mark.parametrize("start,end", [(-90, -90), (-31, 0), (1, 1), (0, -1)])
def test_invalid_range_creates_no_message_or_notification(chat, start, end):
    today = application_today()
    with pytest.raises(HTTPException) as caught:
        send(chat, history_start_date=today + timedelta(days=start), history_end_date=today + timedelta(days=end))
    assert caught.value.status_code == 422
    assert chat[0].db.query(_ChatMessage).count() == 0
    assert chat[0].db.query(ChatNotificationJob).count() == 0


@pytest.mark.parametrize("start,end", [(-89, -89), (-30, 0), (-89, -59), (0, 0)])
def test_inclusive_range_boundaries_and_empty_history(chat, start, end):
    today = application_today()
    context = send(chat, history_start_date=today + timedelta(days=start),
                   history_end_date=today + timedelta(days=end)).message.context_payload["history_context"]
    assert [context[key] for key in ("taken_count", "skipped_count", "unrecorded_count")] == [0, 0, 0]


@pytest.mark.parametrize("sender,active", [("outsider", True), ("patient-a", False), ("caregiver-a", False)])
def test_requires_active_link_participant_before_history_lookup(chat, monkeypatch, sender, active):
    db = chat[0].db
    db.get(_PatientCaregiverLink, chat[1]).linked = active
    db.commit()
    lookup = Mock(side_effect=AssertionError("Unauthorized history lookup"))
    monkeypatch.setattr(ManageMedicationCare, "history_share_context", lookup)
    with pytest.raises(HTTPException) as caught:
        send(chat, sender=sender)
    assert caught.value.status_code == 404
    lookup.assert_not_called()


@pytest.mark.parametrize("changes", [
    {"history_start_date": None}, {"history_end_date": None},
    {"history_start_date": "not-a-date"}, {"message_kind": "text"},
    {"medication_id": 1}, {"medication_ids": [1]}, {"slot_key": "morning"},
    {"pharmacy_id": "P123"}, {"hospital_id": "A123"},
    {"hospital_schedule_date": "2026-10-01"}, {"source_alert_id": 1},
    {"patient_hash": "outsider"}, {"patient_id": 1},
    {"taken_count": 100}, {"skipped_count": 100}, {"unrecorded_count": 100},
    {"history_context": {"taken_count": 100}}, {"context": {"history_context": {}}},
])
def test_invalid_request_fields_are_rejected(changes):
    with pytest.raises(ValidationError):
        payload(**changes)


@pytest.mark.parametrize("changes", [
    {"history_start_date": None}, {"history_end_date": None}, {"message_kind": "text"},
    {"medication_id": 1}, {"medication_ids": [1]}, {"slot_key": "morning"},
    {"pharmacy_id": "P123"}, {"hospital_context": {}}, {"source_alert_id": 1},
])
def test_internal_send_also_rejects_mixed_contexts_before_retry(chat, changes):
    send(chat)
    arguments = payload().model_dump(exclude={"hospital_id", "hospital_schedule_date"})
    with pytest.raises(HTTPException) as caught:
        chat[0].send_message(link_id=chat[1], sender_hash="patient-a", **{**arguments, **changes})
    assert caught.value.status_code == 400


def test_retry_preserves_snapshot_after_records_change(chat, records, monkeypatch):
    first = send(chat)
    records[0].report_status = "skipped"
    records[0].completed = False
    chat[0].db.commit()
    second = send(chat)
    assert not second.created
    assert second.message.to_response_dict() == first.message.to_response_dict()
    fresh = send(chat, client_message_id="history_share_002")
    assert fresh.message.context_payload["history_context"]["taken_count"] == 1
    assert fresh.message.context_payload["history_context"]["skipped_count"] == 3
    # 시간이 지나 조회 가능 범위를 벗어나도 같은 요청은 저장된 스냅샷을 반환한다.
    monkeypatch.setattr("controls.manage_medication_care_control.application_today",
                        lambda: application_today() + timedelta(days=91))
    assert send(chat).message.to_response_dict() == first.message.to_response_dict()
    assert chat[0].db.query(ChatNotificationJob).count() == 2


@pytest.mark.parametrize("changes", [
    {"history_start_date": application_today()},
    {"history_end_date": application_today() - timedelta(days=1)},
    {"body": "다른 요청"},
    {"message_kind": "text", "history_start_date": None, "history_end_date": None},
])
def test_request_id_cannot_change_history_period_body_or_kind(chat, changes):
    send(chat)
    with pytest.raises(HTTPException) as caught:
        send(chat, **changes)
    assert caught.value.status_code == 409
    assert chat[0].db.query(_ChatMessage).count() == 1


def test_history_cannot_reuse_another_message_kind_id(chat):
    send(chat, message_kind="text", history_start_date=None, history_end_date=None)
    with pytest.raises(HTTPException) as caught:
        send(chat)
    assert caught.value.status_code == 409


@pytest.mark.parametrize("changed", [False, True])
def test_insert_race_checks_the_winning_request(chat, monkeypatch, changed):
    first = send(chat)
    repository = chat[0].message_repository
    existing = repository.find_client_request(link_id=chat[1], sender_hash="patient-a",
                                              client_message_id=payload().client_message_id)
    monkeypatch.setattr(repository, "find_client_request", Mock(side_effect=[None, existing]))
    monkeypatch.setattr(repository, "add", Mock(side_effect=IntegrityError("duplicate", {}, Exception())))
    if changed:
        with pytest.raises(HTTPException) as caught:
            send(chat, history_start_date=application_today())
        assert caught.value.status_code == 409
    else:
        replay = send(chat)
        assert not replay.created and replay.message == first.message
    assert chat[0].db.query(ChatNotificationJob).count() == 1


@pytest.mark.parametrize("scope", ["me", "everyone"])
def test_deleted_messages_never_return_history_context(chat, scope):
    first = send(chat)
    control, link_id = chat
    control.delete_messages(link_id=link_id, user_hash="patient-a",
                            message_ids=[first.message.message_id], scope=scope)
    response = control.request_history(link_id=link_id, user_hash="patient-a", before_message_id=None, limit=50)
    assert response["data"][0]["context"] is None
    assert response["data"][0]["message_kind"] == "text"
    if scope == "me":
        assert send(chat).message.to_response_dict()["context"] is None
    else:
        assert control.db.get(_ChatMessage, first.message.message_id).context_payload is None
        with pytest.raises(HTTPException) as caught:
            send(chat)
        assert caught.value.status_code == 409
        other = control.request_history(link_id=link_id, user_hash="caregiver-a", before_message_id=None, limit=50)
        assert other["data"][0]["context"] is None


@pytest.mark.parametrize("language", ["ko", "en"])
@pytest.mark.parametrize("mode", ["full", "type_only"])
def test_push_preview_is_generic_even_when_body_contains_health_details(chat, language, mode):
    first = send(chat, body="PRIVATE-DRUG 2026-10-20 taken 198 skipped 77")
    db = chat[0].db
    db.add(_DevicePushToken(user_hash="caregiver-a", token="history-share-push-token"))
    db.add(_UserSetting(user_hash="caregiver-a", language=language, notification_detail_mode=mode))
    db.commit()
    boundary = RecordingPushBoundary()
    DispatchChatMessageAlert(db, boundary).notify_new_message(
        recipient_hash="caregiver-a", link_id=chat[1], message_body="",
        message_id=first.message.message_id,
    )
    fallback = ("You received a new message from a linked family member." if language == "en"
                else "연동된 가족에게 새 메시지가 도착했습니다.")
    call = boundary.calls[0]
    assert call["body"] == fallback
    assert call["data"]["message_preview"] == (fallback if mode == "full" else "")
    summary = json.loads(call["data"]["chat_summary"])
    # 해시 식별자에 우연히 같은 숫자가 들어가도 실제 표시 내용과 혼동하지 않는다.
    visible = [call["title"], call["body"], call["data"]["message_preview"],
               summary["sender_name"], *summary["lines"]]
    assert all(secret not in str(visible) for secret in ("PRIVATE-DRUG", "2026-10-20", "198", "77"))
    assert summary["lines"] == ([fallback] if mode == "full" else [])
    assert summary["count"] == 1 and summary["latest_message_id"] == first.message.message_id


@pytest.fixture
def client(chat, monkeypatch):
    """실제 요청 검증·권한·DB 작업·응답을 쓰되 외부 조회와 실시간 전송은 격리한다."""
    app = FastAPI()
    app.include_router(chat_router.router)
    app.dependency_overrides[chat_router.get_authenticated_app_principal] = lambda: AuthenticatedPrincipal(
        subject="caregiver-a", issuer="test", user_hash="caregiver-a",
    )
    app.dependency_overrides[chat_router.get_authorization_control] = lambda: AuthorizationControl(chat[0].db)
    app.dependency_overrides[chat_router.get_manage_linked_chat] = lambda: chat[0]
    provider = SimpleNamespace(requestShareContext=AsyncMock())
    app.dependency_overrides[chat_router.get_check_nearby_hospital] = lambda: provider
    monkeypatch.setattr(chat_router, "enforce_chat_daily_quota", AsyncMock())
    monkeypatch.setattr(chat_router, "enforce_hospital_share_daily_quota", AsyncMock())
    monkeypatch.setattr(route_support, "get_chat_connection_manager", lambda _: SimpleNamespace(broadcast=AsyncMock()))
    with TestClient(app) as result:
        yield result
    provider.requestShareContext.assert_not_awaited()


def test_route_maps_dates_and_uses_authenticated_sender_and_link_patient(chat, records, client):
    url = f"/links/{chat[1]}/messages?user_hash=outsider"
    first = client.post(url, json=payload().model_dump(mode="json"))
    assert first.status_code == 200
    data = first.json()["data"]
    assert data["sender_hash"] == "caregiver-a"
    assert data["context"]["history_context"]["taken_count"] == 2
    retry = client.post(url, json=payload().model_dump(mode="json"))
    assert retry.status_code == 200 and not retry.json()["created"]
    changed = client.post(url, json=payload(history_start_date=application_today()).model_dump(mode="json"))
    assert changed.status_code == 409
    # 병원 공유의 빠른 중복 조회로도 이력 공유 ID를 재사용할 수 없다.
    hospital = client.post(url, json={
        "client_message_id": payload().client_message_id, "body": "병원 공유", "message_kind": "hospital_share",
        "hospital_id": "A123", "hospital_schedule_date": application_today().isoformat(),
    })
    assert hospital.status_code == 409


def test_route_rejects_forged_snapshot(chat, client):
    response = client.post(f"/links/{chat[1]}/messages", json={
        **payload().model_dump(mode="json"), "context": {"history_context": {"taken_count": 999}},
    })
    assert response.status_code == 422
    assert chat[0].db.query(_ChatMessage).count() == 0
