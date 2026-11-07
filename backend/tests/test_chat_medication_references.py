"""검색약 참고 첨부는 저장 약·복용 기록으로 변환하지 않는다."""
import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from controls.manage_linked_chat_control import ManageLinkedChat
from entities.chat_message_entity import _ChatMessage
from entities.medication_completion_entity import _MedicationCompletion
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.saved_medication_entity import _SavedMedication
from schemas.chat import ChatMessageCreate
from support.db import seed_account, seed_medication


REFERENCE = {"item_seq": "202600001", "item_name": "검색정 10mg", "manufacturer": "제조사", "image_url": ""}


@pytest.fixture
def chat(fk_db):
    seed_account(fk_db, "patient-a", "caregiver-a", "outsider")
    link = _PatientCaregiverLink(patient_hash="patient-a", caregiver_hash="caregiver-a", linked=True)
    fk_db.add(link)
    fk_db.commit()
    return ManageLinkedChat(fk_db), link


def send(chat, **changes):
    control, link = chat
    return control.send_message(**{
        "link_id": link.id, "sender_hash": "patient-a",
        "client_message_id": "reference_request_001", "body": "이 약에 대해 궁금해요.",
        "medication_references": [REFERENCE], **changes,
    })


@pytest.mark.parametrize("sender", ["patient-a", "caregiver-a"])
def test_reference_roundtrip_without_medication_or_dose_creation(chat, sender):
    result = send(chat, sender_hash=sender)
    response = result.message.to_response_dict()
    assert response["context"]["medication_references"] == [REFERENCE]
    assert response["medication_context"] is None
    assert response["medication_contexts"] == []
    assert chat[0].db.query(_SavedMedication).count() == 0
    assert chat[0].db.query(_MedicationCompletion).count() == 0
    assert not send(chat, sender_hash=sender).created
    assert chat[0].db.query(_ChatMessage).count() == 1


def test_reference_keeps_saved_medication_authorization(chat):
    other = seed_medication(chat[0].db, patient_hash="outsider")
    with pytest.raises(HTTPException) as failure:
        send(chat, medication_ids=[other.id])
    assert failure.value.status_code == 400
    with pytest.raises(HTTPException) as failure:
        send(chat, sender_hash="outsider")
    assert failure.value.status_code == 404
    chat[1].linked = False
    chat[0].db.commit()
    with pytest.raises(HTTPException):
        send(chat)
    assert chat[0].db.query(_ChatMessage).count() == 0


def test_reference_retry_cannot_change_snapshot(chat):
    send(chat)
    with pytest.raises(HTTPException) as failure:
        send(chat, medication_references=[{**REFERENCE, "item_name": "다른 약"}])
    assert failure.value.status_code == 409


@pytest.mark.parametrize("extra", [
    {"medication_id": 1}, {"patient_hash": "outsider"},
    {"dosage_per_time": "1정"}, {"schedule_slot_keys": ["morning"]},
    {"item_seq": ""}, {"item_name": " "},
])
def test_reference_schema_rejects_ownership_dose_and_invalid_fields(extra):
    with pytest.raises(ValidationError):
        ChatMessageCreate(client_message_id="reference_request_001", body="질문",
                          medication_references=[{**REFERENCE, **extra}])


@pytest.mark.parametrize("changes", [
    {"message_kind": "slot_completion"}, {"message_kind": "slot_check_request", "slot_key": "morning"},
    {"slot_key": "morning"}, {"message_kind": "medication_shortage"},
    {"medication_ids": list(range(1, 11))},
])
def test_reference_rejects_dose_context_and_combined_limit(chat, changes):
    with pytest.raises(ValidationError):
        ChatMessageCreate(client_message_id="reference_request_001", body="질문",
                          medication_references=[REFERENCE], **changes)
    with pytest.raises(HTTPException) as failure:
        send(chat, **changes)
    assert failure.value.status_code == 400


def test_reference_image_is_sanitized_and_delete_redacts_snapshot(chat):
    result = send(chat, medication_references=[{**REFERENCE, "image_url": "https://tracking.example/x"}])
    assert result.message.context_payload["medication_references"][0]["image_url"] == ""
    hidden = result.message.model_copy(update={"hidden_for_me": True})
    assert hidden.to_response_dict()["context"] is None
