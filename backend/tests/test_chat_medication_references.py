"""검색약 참고 첨부는 저장 약·복용 기록으로 변환하지 않는다."""
import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from datetime import timedelta

from controls.manage_linked_chat_control import ManageLinkedChat
from entities.chat_message_entity import _ChatMessage
from entities.medication_completion_entity import _MedicationCompletion
from entities.medication_detail_entity import MedicationDetail, MedicationSearchCacheRecord
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import utc_now
from repositories.medication_search_cache_repository import MedicationSearchCacheRepository
from schemas.chat import ChatMessageCreate
from support.db import seed_account, seed_medication


REFERENCE = {"item_seq": "202600001", "item_name": "검색정 10mg", "manufacturer": "제조사", "image_url": ""}
OTHER = {"item_seq": "202600002", "item_name": "다른정 5mg", "manufacturer": "다른 제조사", "image_url": ""}


def remember(db, *references):
    MedicationSearchCacheRepository(db).remember([
        MedicationDetail(item_seq=item["item_seq"], item_name=item["item_name"],
                         manufacturer=item["manufacturer"], image_url=item["image_url"],
                         efficacy="", use_method="", warning_message="")
        for item in references
    ])


@pytest.fixture
def chat(fk_db):
    seed_account(fk_db, "patient-a", "caregiver-a", "outsider")
    link = _PatientCaregiverLink(patient_hash="patient-a", caregiver_hash="caregiver-a", linked=True)
    fk_db.add(link)
    fk_db.commit()
    remember(fk_db, REFERENCE, OTHER)
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
        send(chat, medication_references=[OTHER])
    assert failure.value.status_code == 409


def test_reference_card_is_rebuilt_from_the_server_search_result(chat):
    forged = {**REFERENCE, "item_name": "식약처 안내: 하루 6정까지", "manufacturer": "MedBuddy 공식 확인",
              "image_url": "https://nedrug.mfds.go.kr/pbp/cmn/itemImageDownload/other"}
    result = send(chat, medication_references=[forged, forged])
    assert result.message.context_payload["medication_references"] == [REFERENCE]


@pytest.mark.parametrize("age", [None, timedelta(hours=25)])
def test_reference_needs_a_search_from_the_last_day(chat, age):
    db = chat[0].db
    if age is None:
        reference = {**REFERENCE, "item_seq": "NOT_SEARCHED"}
    else:
        reference = REFERENCE
        db.get(MedicationSearchCacheRecord, REFERENCE["item_seq"]).fetched_at = utc_now() - age
        db.commit()
    with pytest.raises(HTTPException) as failure:
        send(chat, medication_references=[reference])
    assert failure.value.status_code == 400
    assert db.query(_ChatMessage).count() == 0


def test_search_cache_keeps_public_fields_only_and_prunes_old_rows(fk_db):
    remember(fk_db, REFERENCE)
    fk_db.get(MedicationSearchCacheRecord, REFERENCE["item_seq"]).fetched_at = utc_now() - timedelta(days=2)
    fk_db.commit()
    remember(fk_db, OTHER, {**OTHER, "item_seq": ""}, {**OTHER, "item_seq": "x" * 65})
    rows = fk_db.query(MedicationSearchCacheRecord).all()
    assert [row.item_seq for row in rows] == [OTHER["item_seq"]]
    assert set(MedicationSearchCacheRecord.__table__.columns.keys()) == {
        "item_seq", "item_name", "manufacturer", "image_url", "fetched_at",
    }


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
    remember(chat[0].db, {**REFERENCE, "image_url": "https://tracking.example/x"})
    result = send(chat)
    assert result.message.context_payload["medication_references"][0]["image_url"] == ""
    hidden = result.message.model_copy(update={"hidden_for_me": True})
    assert hidden.to_response_dict()["context"] is None
