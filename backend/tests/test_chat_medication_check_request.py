"""Selected-medication checks preserve ownership, due-day rules and retry snapshots."""

from collections.abc import Iterator
from datetime import timedelta
from types import SimpleNamespace
from typing import Any
from unittest.mock import AsyncMock, Mock

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from api import chat_router, route_support
from controls.authorization_control import AuthorizationControl
from controls.manage_linked_chat_control import ChatSendResult, ManageLinkedChat
from core import api_contract
from core.application_clock import application_today
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.chat_message_entity import CHAT_MESSAGE_KIND_MEDICATION_CHECK_REQUEST, _ChatMessage
from entities.chat_notification_job_entity import ChatNotificationJob
from entities.medication_alarm_entity import _MedicationAlarm
from entities.medication_completion_entity import _MedicationCompletion
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.saved_medication_entity import _SavedMedication
from entities.user_setting_entity import _UserSetting
from schemas.chat import ChatMessageCreate
from support.db import seed_account, seed_medication
from test_schedule_query_budget import count_statements, statements_of_kind


KIND = CHAT_MESSAGE_KIND_MEDICATION_CHECK_REQUEST
BODY = "Have you taken selected meds?"
Chat = tuple[ManageLinkedChat, int]


# Function Name: chat
# Description: Seed linked accounts and an unrelated account in an isolated database.
# Parameters: fk_db is the foreign-key-enforcing test session.
# Returns: Chat control and active link ID.
@pytest.fixture
def chat(fk_db: Session) -> Chat:
    seed_account(fk_db, "patient-a", "caregiver-a", "outsider")
    link = _PatientCaregiverLink(patient_hash="patient-a", caregiver_hash="caregiver-a", linked=True)
    fk_db.add(link)
    fk_db.commit()
    return ManageLinkedChat(fk_db), int(link.id)


# Function Name: send
# Description: Exercise internal validation without relying on request-schema validation.
# Parameters: chat is the isolated control/link; changes overrides the request defaults.
# Returns: The persisted or replayed send result.
def send(chat: Chat, **changes: Any) -> ChatSendResult:
    return chat[0].send_message(**{
        "link_id": chat[1], "sender_hash": "caregiver-a",
        "client_message_id": "medication_check_001", "body": BODY,
        "message_kind": KIND, **changes,
    })


# Function Name: request
# Description: Build the public request using existing fields only.
# Parameters: changes overrides the request defaults.
# Returns: A validated ChatMessageCreate or its validation error.
def request(**changes: Any) -> ChatMessageCreate:
    return ChatMessageCreate(**{
        "client_message_id": "medication_check_001", "body": BODY,
        "message_kind": KIND, "medication_ids": [1], **changes,
    })


# Function Name: test_schema_accepts_kind_and_optional_slot
# Description: Accept the new enum with saved IDs and the existing slot selector.
# Parameters: slot is omitted or a supported dose slot.
# Returns: None; asserts request normalization.
@pytest.mark.parametrize("slot", [None, "morning", "evening"])
def test_schema_accepts_kind_and_optional_slot(slot: str | None) -> None:
    payload = request(message_kind=f" {KIND.upper()} ", medication_ids=[2, 2, 1], slot_key=slot)
    assert payload.message_kind == "medication_check_request"
    assert payload.medication_ids == [2, 1]
    assert payload.slot_key == slot
    assert request(medication_ids=[], medication_id=1).medication_id == 1


# Function Name: test_schema_rejects_invalid_selection_and_mixed_context
# Description: Reject missing/invalid saved IDs and conflicting structured references.
# Parameters: changes contains an invalid request variant.
# Returns: None; requires validation failure.
@pytest.mark.parametrize("changes", [
    {"medication_ids": []}, {"medication_ids": [0]}, {"medication_ids": [-1]},
    {"medication_ids": list(range(1, 12))}, {"slot_key": "as_needed"},
    {"pharmacy_id": "missing"}, {"source_alert_id": 123},
    {"hospital_id": "A123"}, {"hospital_schedule_date": "2026-11-14"},
    {"history_start_date": "2026-11-14"},
    {"medication_references": [{"item_seq": "123", "item_name": "Searched tablet"}]},
])
def test_schema_rejects_invalid_selection_and_mixed_context(changes: dict[str, Any]) -> None:
    with pytest.raises(ValidationError):
        request(**changes)


# Function Name: test_only_linked_caregiver_can_request_check
# Description: Reject the patient, unrelated accounts and unknown senders.
# Parameters: chat is isolated; sender/status specify the rejected caller.
# Returns: None; no message or notification may be persisted.
@pytest.mark.parametrize(("sender", "status"), [
    ("patient-a", 403), ("outsider", 404), ("unknown-sender", 404),
])
def test_only_linked_caregiver_can_request_check(chat: Chat, sender: str, status: int) -> None:
    medication = seed_medication(chat[0].db)
    with pytest.raises(HTTPException) as failure:
        send(chat, sender_hash=sender, medication_ids=[medication.id])
    assert failure.value.status_code == status
    assert chat[0].db.query(_ChatMessage).count() == 0
    assert chat[0].db.query(ChatNotificationJob).count() == 0


# Function Name: test_unlinked_caregiver_cannot_send_or_replay
# Description: Revalidate the active link even when a matching message exists.
# Parameters: chat is the isolated control and link.
# Returns: None; rejects a replay after unlinking.
def test_unlinked_caregiver_cannot_send_or_replay(chat: Chat) -> None:
    db = chat[0].db
    medication_id = int(seed_medication(db).id)
    send(chat, medication_ids=[medication_id])
    db.get(_PatientCaregiverLink, chat[1]).linked = False
    db.commit()
    with pytest.raises(HTTPException) as failure:
        send(chat, medication_ids=[medication_id])
    assert failure.value.status_code == 404


# Function Name: test_invalid_saved_medication_rejects_entire_selection
# Description: Do not silently drop foreign, missing, deleted, inactive or nameless IDs.
# Parameters: chat is isolated; invalid identifies the invalid medication variant.
# Returns: None; rejects the mixed selection without saving any message.
@pytest.mark.parametrize("invalid", [
    "foreign", "caregiver-owned", "deleted", "missing", "expired", "future", "stopped", "nameless",
])
def test_invalid_saved_medication_rejects_entire_selection(chat: Chat, invalid: str) -> None:
    db = chat[0].db
    today = application_today()
    valid_id = int(seed_medication(db).id)
    changes = {
        "foreign": {"patient_hash": "outsider"},
        "caregiver-owned": {"patient_hash": "caregiver-a"},
        "expired": {"prescription_date": today - timedelta(days=8)},
        "future": {"prescription_date": today + timedelta(days=1)},
        "stopped": {"stopped_on": today}, "nameless": {"item_name": " "},
    }.get(invalid, {})
    medication = seed_medication(db, **changes)
    invalid_id = int(medication.id)
    if invalid == "deleted":
        db.delete(medication)
        db.commit()
    elif invalid == "missing":
        invalid_id += 10000
    with pytest.raises(HTTPException) as failure:
        send(chat, medication_ids=[valid_id, invalid_id])
    assert failure.value.status_code == 400
    assert db.query(_ChatMessage).count() == 0


# Function Name: test_control_rejects_invalid_references_before_replay
# Description: Internal callers and cached retries cannot bypass field validation.
# Parameters: chat is isolated; changes contains an invalid field combination.
# Returns: None; initial/retried invalid requests are rejected.
@pytest.mark.parametrize("changes", [
    {"medication_ids": []}, {"slot_key": "as_needed"},
    {"pharmacy_id": "missing"}, {"hospital_context": {}},
    {"pharmacy_operating_snapshot": {}}, {"source_alert_id": 99999},
    {"history_end_date": application_today()},
    {"medication_references": [{"item_seq": "missing", "item_name": "Untrusted"}]},
])
def test_control_rejects_invalid_references_before_replay(chat: Chat, changes: dict[str, Any]) -> None:
    medication_id = int(seed_medication(chat[0].db).id)
    for replay in (False, True):
        if replay:
            send(chat, medication_ids=[medication_id])
        with pytest.raises(HTTPException) as failure:
            send(chat, **{"medication_ids": [medication_id], **changes})
        assert failure.value.status_code == 400
    assert chat[0].db.query(_ChatMessage).count() == 1


# Function Name: test_selection_limit_and_invalid_internal_ids
# Description: Keep attachment limits and positive saved-ID validation on internal sends.
# Parameters: chat is isolated; ids is an oversized or invalid list.
# Returns: None; requires HTTP 400.
@pytest.mark.parametrize("ids", [[0], [-1], list(range(1, 12))])
def test_selection_limit_and_invalid_internal_ids(chat: Chat, ids: list[int]) -> None:
    with pytest.raises(HTTPException) as failure:
        send(chat, medication_ids=ids)
    assert failure.value.status_code == 400


# Function Name: test_selected_slot_snapshots_count_only_selected_due_medications
# Description: Preserve attachments while counting selected doses and narrowing each slot snapshot.
# Parameters: chat is isolated; slot optionally restricts the request to one existing slot.
# Returns: None; checks JSON persistence, alarms, subset counts and absence of dose writes.
@pytest.mark.parametrize("slot", [None, "morning", "evening", "lunch"])
def test_selected_slot_snapshots_count_only_selected_due_medications(chat: Chat, slot: str | None) -> None:
    db = chat[0].db
    today = application_today()
    multi_id = int(seed_medication(db, item_name="Selected multi", daily_frequency="2 times",
                                  schedule_slot_keys='["morning", "evening"]').id)
    morning_id = int(seed_medication(db, item_name="Selected morning",
                                    schedule_slot_keys='["morning"]').id)
    prn_id = int(seed_medication(db, dosing_mode="as_needed").id)
    rest_id = int(seed_medication(db, daily_frequency="every other day",
                                 prescription_date=today - timedelta(days=1)).id)
    other_ids = [int(seed_medication(db).id) for _ in range(3)]
    for medication_id, dose_slot in [(morning_id, "morning"), (multi_id, "evening")]:
        db.add(_MedicationCompletion(saved_medication_id=medication_id, patient_hash="patient-a",
                                     schedule_date=today, slot_key=dose_slot, completed=True))
    for medication_id in other_ids:
        db.add(_MedicationCompletion(saved_medication_id=medication_id, patient_hash="patient-a",
                                     schedule_date=today, slot_key="morning", completed=True))
    # Neither a stale completion nor another owner's completion can count for this selection.
    for owner, day in [("patient-a", today - timedelta(days=1)), ("outsider", today)]:
        db.add(_MedicationCompletion(saved_medication_id=multi_id, patient_hash=owner,
                                     schedule_date=day, slot_key="morning", completed=True))
    db.add(_UserSetting(user_hash="patient-a", default_morning_time="07:30"))
    db.add(_MedicationAlarm(patient_hash="patient-a", slot_key="evening", hour=19, minute=15, enabled=True))
    db.commit()
    before = db.query(_MedicationCompletion).count()
    ids = [prn_id, multi_id, morning_id, rest_id]
    result = send(chat, medication_id=multi_id, medication_ids=ids + [multi_id], slot_key=slot)
    response = result.message.to_response_dict()
    context = response["context"]
    assert response["message_kind"] == KIND
    assert context["medication_check_slot_key"] == slot
    assert "schedule_context" not in context
    attachments = {item["medication_id"]: item for item in context["medication_contexts"]}
    assert set(attachments) == set(ids)
    assert attachments[multi_id]["schedule_slot_keys"] == ["morning", "evening"]
    assert attachments[prn_id]["schedule_slot_keys"] == []
    expected = {"morning": (2, 1, "07:30", False), "evening": (1, 1, "19:15", True)}
    checks = context["medication_check_contexts"]
    assert [item["slot_key"] for item in checks] == [key for key in expected if slot is None or key == slot]
    for item in checks:
        key = item["slot_key"]
        assert item["schedule_date"] == today.isoformat()
        assert (item["total_count"], item["completed_count"], item["alarm_time"], item["alarm_enabled"]) == expected[key]
        expected_ids = {multi_id, morning_id} if key == "morning" else {multi_id}
        assert {med["medication_id"] for med in item["medications"]} == expected_ids
        assert all(med["schedule_slot_keys"] == [key] for med in item["medications"])
    assert db.get(_ChatMessage, result.message.message_id).context_payload == context
    history = chat[0].request_history(link_id=chat[1], user_hash="patient-a", before_message_id=None, limit=50)
    assert history["data"][0]["context"] == context
    assert db.query(_MedicationCompletion).count() == before


# Function Name: test_legacy_completion_fallback_and_explicit_undo
# Description: Reuse completion-query semantics, including false rows overriding legacy status.
# Parameters: legacy_age, explicit and expected define the selected medicine's status.
# Returns: None; unrelated completed medicines never inflate the count.
@pytest.mark.parametrize(("legacy_age", "explicit", "expected"), [
    (0, None, 1), (1, None, 0), (0, False, 0), (1, True, 1),
])
def test_legacy_completion_fallback_and_explicit_undo(chat: Chat, legacy_age: int, explicit: bool | None, expected: int) -> None:
    db = chat[0].db
    today = application_today()
    medication_id = int(seed_medication(db, medication_status=True,
                                       medication_status_date=today - timedelta(days=legacy_age)).id)
    seed_medication(db, medication_status=True, medication_status_date=today)
    if explicit is not None:
        db.add(_MedicationCompletion(saved_medication_id=medication_id, patient_hash="patient-a",
                                     schedule_date=today, slot_key="morning", completed=explicit))
        db.commit()
    context = send(chat, medication_ids=[medication_id], slot_key="morning").message.context_payload
    assert context["medication_check_contexts"][0]["completed_count"] == expected
    assert context["medication_check_contexts"][0]["total_count"] == 1


# Function Name: test_prn_and_rest_day_only_have_attachments
# Description: Even legacy clients get no actionable check context for PRN/rest-day medicine.
# Parameters: dose_days selects current/legacy request capability; slot selects the optional restriction.
# Returns: None; attachment-only requests store an empty list and the original selector.
@pytest.mark.parametrize("dose_days", [False, True])
@pytest.mark.parametrize("slot", [None, "morning"])
def test_prn_and_rest_day_only_have_attachments(chat: Chat, dose_days: bool, slot: str | None) -> None:
    db = chat[0].db
    ids = [int(seed_medication(db, dosing_mode="as_needed").id),
           int(seed_medication(db, daily_frequency="every other day",
                               prescription_date=application_today() - timedelta(days=1)).id)]
    token = api_contract._client_schedules_by_dose_days.set(dose_days)
    try:
        result = send(chat, medication_ids=ids, slot_key=slot)
    finally:
        api_contract._client_schedules_by_dose_days.reset(token)
    assert result.message.context_payload["medication_check_contexts"] == []
    assert result.message.context_payload["medication_check_slot_key"] == slot
    assert len(result.message.context_payload["medication_contexts"]) == 2
    assert db.query(_MedicationCompletion).count() == 0


# Function Name: test_retry_preserves_snapshot_after_schedule_change_or_deletion
# Description: Replays do not rebuild today's context or duplicate the notification job.
# Parameters: mutation changes live completion, date or saved medication after the first send.
# Returns: None; requires the original message and stored context.
@pytest.mark.parametrize("mutation", ["completion", "next-day", "deleted"])
def test_retry_preserves_snapshot_after_schedule_change_or_deletion(chat: Chat, monkeypatch: pytest.MonkeyPatch, mutation: str) -> None:
    db = chat[0].db
    medication_id = int(seed_medication(db).id)
    first = send(chat, medication_ids=[medication_id], slot_key="morning")
    if mutation == "completion":
        db.add(_MedicationCompletion(saved_medication_id=medication_id, patient_hash="patient-a",
                                     schedule_date=application_today(), slot_key="morning", completed=True))
        db.commit()
    elif mutation == "deleted":
        db.delete(db.get(_SavedMedication, medication_id))
        db.commit()
    else:
        tomorrow = application_today() + timedelta(days=1)
        monkeypatch.setattr("controls.manage_linked_chat_control.application_today", lambda: tomorrow)
    retry = send(chat, medication_ids=[medication_id, medication_id], slot_key="morning")
    assert not retry.created and retry.message == first.message
    assert db.query(_ChatMessage).count() == 1
    assert db.query(ChatNotificationJob).count() == 1


# Function Name: test_retry_rejects_changed_body_selection_kind_or_slot
# Description: Persisted slot selectors distinguish empty contexts and omitted slot restrictions.
# Parameters: prn selects empty checks; changes modifies a previously valid request.
# Returns: None; rejects conflicts without additional messages or jobs.
@pytest.mark.parametrize("prn", [False, True])
@pytest.mark.parametrize("changes", [
    {"body": "Changed question"}, {"medication_ids": [99999]}, {"message_kind": "text"},
    {"slot_key": "evening"}, {"slot_key": None},
])
def test_retry_rejects_changed_body_selection_kind_or_slot(chat: Chat, prn: bool, changes: dict[str, Any]) -> None:
    medication_id = int(seed_medication(chat[0].db, dosing_mode="as_needed" if prn else "scheduled").id)
    args = {"medication_ids": [medication_id], "slot_key": "morning"}
    send(chat, **args)
    with pytest.raises(HTTPException) as failure:
        send(chat, **{**args, **changes})
    assert failure.value.status_code == 409
    assert chat[0].db.query(_ChatMessage).count() == 1
    assert chat[0].db.query(ChatNotificationJob).count() == 1


# Function Name: test_retry_rejects_adding_slot_to_empty_check
# Description: Omitted and explicit slot selectors differ even with no actionable context.
# Parameters: chat is the isolated control and link.
# Returns: None; requires HTTP 409.
def test_retry_rejects_adding_slot_to_empty_check(chat: Chat) -> None:
    medication_id = int(seed_medication(chat[0].db, dosing_mode="as_needed").id)
    send(chat, medication_ids=[medication_id])
    with pytest.raises(HTTPException) as failure:
        send(chat, medication_ids=[medication_id], slot_key="morning")
    assert failure.value.status_code == 409


# Function Name: test_insert_race_revalidates_slot_selector
# Description: The integrity-error recovery path applies the same immutable-request checks.
# Parameters: changed switches the losing request to a different slot.
# Returns: None; returns the winner or rejects conflict, with only one notification job.
@pytest.mark.parametrize("changed", [False, True])
def test_insert_race_revalidates_slot_selector(chat: Chat, monkeypatch: pytest.MonkeyPatch, changed: bool) -> None:
    medication_id = int(seed_medication(chat[0].db).id)
    first = send(chat, medication_ids=[medication_id], slot_key="morning")
    repository = chat[0].message_repository
    existing = chat[0].db.get(_ChatMessage, first.message.message_id)
    monkeypatch.setattr(repository, "find_client_request", Mock(side_effect=[None, existing]))
    monkeypatch.setattr(repository, "add", Mock(side_effect=IntegrityError("duplicate", {}, Exception())))
    if changed:
        with pytest.raises(HTTPException) as failure:
            send(chat, medication_ids=[medication_id], slot_key="evening")
        assert failure.value.status_code == 409
    else:
        retry = send(chat, medication_ids=[medication_id], slot_key="morning")
        assert not retry.created and retry.message == first.message
    assert chat[0].db.query(ChatNotificationJob).count() == 1


# Function Name: test_plain_question_text_never_generates_checks_or_records_doses
# Description: Only the explicit message kind creates check buttons.
# Parameters: chat is the isolated control and link.
# Returns: None; ordinary quick-reply wording remains ordinary text.
def test_plain_question_text_never_generates_checks_or_records_doses(chat: Chat) -> None:
    medication_id = int(seed_medication(chat[0].db).id)
    result = send(chat, message_kind="text", medication_ids=[medication_id])
    assert "medication_check_contexts" not in result.message.context_payload
    assert chat[0].db.query(_MedicationCompletion).count() == 0


# Function Name: test_check_queries_do_not_grow_with_selection
# Description: Cold sessions batch attachment validation and per-dose completion reads.
# Parameters: chat is the isolated control and link.
# Returns: None; ten medications require the same bounded reads as one medication.
def test_check_queries_do_not_grow_with_selection(chat: Chat) -> None:
    db = chat[0].db
    ids = [int(seed_medication(db).id) for _ in range(10)]
    counts = []
    for size in (1, 10):
        db.expunge_all()
        with count_statements(db.get_bind()) as statements:
            send(chat, client_message_id=f"query_budget_{size}", medication_ids=ids[:size])
        selects = statements_of_kind(statements, "SELECT")
        counts.append(len(selects))
        assert sum("FROM medication_completions" in sql for sql in selects) == 1
        assert sum("FROM saved_medications" in sql for sql in selects) == 2
    assert counts[0] == counts[1]
    assert counts[0] <= 9


# Function Name: test_confirmation_rejects_prn_and_nondue_attachments
# Description: Dose-day-aware recording rejects tampered selections without partially writing doses.
# Parameters: invalid specifies the attachment that is not a scheduled dose today.
# Returns: None; records neither dose rows nor a confirmation message.
@pytest.mark.parametrize("invalid", ["prn", "rest-day"])
def test_confirmation_rejects_prn_and_nondue_attachments(chat: Chat, invalid: str) -> None:
    db = chat[0].db
    due_id = int(seed_medication(db).id)
    changes = ({"dosing_mode": "as_needed"} if invalid == "prn" else {
        "daily_frequency": "every other day", "prescription_date": application_today() - timedelta(days=1),
    })
    invalid_id = int(seed_medication(db, **changes).id)
    first = send(chat, medication_ids=[due_id, invalid_id], slot_key="morning")
    check = first.message.context_payload["medication_check_contexts"][0]
    assert [item["medication_id"] for item in check["medications"]] == [due_id]
    token = api_contract._client_schedules_by_dose_days.set(True)
    try:
        with pytest.raises(HTTPException) as failure:
            chat[0].record_medication_taken(
                link_id=chat[1], sender_hash="patient-a", client_message_id="invalid_taken_001",
                schedule_date=application_today(), slot_key="morning", medication_ids=[due_id, invalid_id],
            )
        assert failure.value.status_code == 409
    finally:
        api_contract._client_schedules_by_dose_days.reset(token)
    assert db.query(_MedicationCompletion).count() == 0
    assert db.query(_ChatMessage).count() == 1


# Function Name: client
# Description: Exercise the real HTTP schema/authentication/control path with external work isolated.
# Parameters: chat is the real isolated control; monkeypatch restores replaced collaborators.
# Returns: An authenticated caregiver TestClient.
@pytest.fixture
def client(chat: Chat, monkeypatch: pytest.MonkeyPatch) -> Iterator[TestClient]:
    app = FastAPI()
    app.include_router(chat_router.router)
    app.dependency_overrides[chat_router.get_authenticated_app_principal] = lambda: AuthenticatedPrincipal(
        subject="caregiver-a", issuer="test", user_hash="caregiver-a",
    )
    app.dependency_overrides[chat_router.get_authorization_control] = lambda: AuthorizationControl(chat[0].db)
    app.dependency_overrides[chat_router.get_manage_linked_chat] = lambda: chat[0]
    provider = SimpleNamespace(requestShareContext=AsyncMock())
    app.dependency_overrides[chat_router.get_check_nearby_hospital] = lambda: provider
    app.dependency_overrides[chat_router.get_check_nearby_pharmacy] = lambda: provider
    monkeypatch.setattr(chat_router, "enforce_chat_daily_quota", AsyncMock())
    monkeypatch.setattr(route_support, "get_chat_connection_manager", lambda _: SimpleNamespace(broadcast=AsyncMock()))
    with TestClient(app) as result:
        yield result
    provider.requestShareContext.assert_not_awaited()


# Function Name: test_route_retries_validate_body_slot_and_place_preflight
# Description: The real route preserves selectors and cannot reuse check IDs through place shortcuts.
# Parameters: client is authenticated as caregiver; chat supplies saved medications.
# Returns: None; checks success, immutable retries, forbidden mixed references and trusted snapshots.
def test_route_retries_validate_body_slot_and_place_preflight(chat: Chat, client: TestClient) -> None:
    medication_id = int(seed_medication(chat[0].db).id)
    url = f"/links/{chat[1]}/messages?user_hash=outsider"
    payload = request(medication_ids=[medication_id], slot_key="morning").model_dump(mode="json")
    first = client.post(url, json={**payload, "context": {"medication_check_contexts": [{"total_count": 999}]}})
    assert first.status_code == 200
    context = first.json()["data"]["context"]
    assert first.json()["data"]["sender_hash"] == "caregiver-a"
    assert context["medication_check_slot_key"] == "morning"
    assert [item["slot_key"] for item in context["medication_check_contexts"]] == ["morning"]
    assert context["medication_check_contexts"][0]["total_count"] == 1
    retry = client.post(url, json=payload)
    assert retry.status_code == 200 and not retry.json()["created"]
    for changes in ({"body": "Changed"}, {"slot_key": "evening"}, {"slot_key": None}):
        assert client.post(url, json={**payload, **changes}).status_code == 409
    for changes in ({"medication_ids": []}, {"source_alert_id": 999}, {"slot_key": "invalid"}):
        assert client.post(url, json={**payload, **changes}).status_code == 422
    for kind, fields in (
        ("pharmacy_share", {"pharmacy_id": "missing"}),
        ("pharmacy_phone_verified", {"pharmacy_id": "missing"}),
        ("hospital_share", {"hospital_id": "A123", "hospital_schedule_date": application_today().isoformat()}),
    ):
        response = client.post(url, json={
            "client_message_id": payload["client_message_id"], "body": "Place",
            "message_kind": kind, **fields,
        })
        assert response.status_code == 409
    assert chat[0].db.query(_ChatMessage).count() == 1
    assert chat[0].db.query(ChatNotificationJob).count() == 1
