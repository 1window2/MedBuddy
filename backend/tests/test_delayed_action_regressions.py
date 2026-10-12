from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException
from sqlalchemy import event

from controls.check_saved_medication_control import CheckSavedMedication
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.manage_linked_chat_control import ManageLinkedChat
from controls.manage_push_token_control import ManagePushToken
from controls.process_chat_notifications_control import ProcessChatNotifications
from controls.sync_dose_control import SyncDose
from core.application_clock import application_today
from entities.chat_message_entity import _ChatMessage
from entities.chat_notification_job_entity import ChatNotificationJob
from entities.device_push_token_entity import _DevicePushToken
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.saved_medication_entity import _SavedMedication
from schemas.dose_sync import DoseSyncRequest
from services.push_recipient_resolver import PushRecipientResolver
from support.db import make_engine, make_session_factory, seed_account, seed_medication


@pytest.mark.parametrize("action", ["delete", "complete"])
def test_deleted_medication_request_cannot_target_new_medication(fk_db, action):
    old = seed_medication(fk_db, daily_frequency="1", schedule_slot_keys='["morning"]')
    old_id = old.id
    CheckSavedMedication(fk_db).requestDelete(old_id, "patient-a")
    new = seed_medication(fk_db, item_name="new-tablet", daily_frequency="1", schedule_slot_keys='["morning"]')
    new_id = new.id

    with pytest.raises(HTTPException) as error:
        if action == "delete":
            CheckSavedMedication(fk_db).requestDelete(old_id, "patient-a")
        else:
            SyncDose(fk_db).apply("patient-a", DoseSyncRequest(
                operation_id="delayed_old_dose", schedule_date=application_today(),
                slot_key="morning", medication_ids=[old_id], completed=True,
            ))
    assert error.value.status_code in {404, 409}
    fk_db.rollback()
    assert fk_db.get(_SavedMedication, new_id) is not None
    assert not fk_db.get(_SavedMedication, new_id).medication_status


def seed_link(db):
    seed_account(db, "patient-a", "caregiver-a")
    link = _PatientCaregiverLink(patient_hash="patient-a", caregiver_hash="caregiver-a", linked=True)
    db.add(link)
    db.commit()
    return link.id


def send(db, link_id, key):
    return ManageLinkedChat(db).send_message(
        link_id=link_id, sender_hash="patient-a", client_message_id=key, body=key,
    ).message.message_id


def relink(db, link_id):
    control = LinkPatientCaregiver(db)
    control.requestUnlink(link_id, "patient-a")
    code = control.generatePatientHash("patient-a")["data"]["patient_code"]
    assert control.requestPatientCaregiverLink("caregiver-a", code)["data"]["id"] == link_id


def test_delayed_message_delete_after_relink_cannot_erase_new_message(fk_db):
    link_id = seed_link(fk_db)
    old_id = send(fk_db, link_id, "before_unlink")
    relink(fk_db, link_id)
    new_id = send(fk_db, link_id, "after_relink")
    with pytest.raises(HTTPException) as error:
        ManageLinkedChat(fk_db).delete_messages(
            link_id=link_id, user_hash="patient-a", message_ids=[old_id], scope="everyone",
        )
    assert error.value.status_code == 404
    assert fk_db.get(_ChatMessage, new_id).body == "after_relink"


def test_old_chat_worker_cannot_finish_replacement_message(fk_session_factory):
    processor = ProcessChatNotifications(fk_session_factory, lambda: None, AsyncMock(), AsyncMock())
    with fk_session_factory() as db:
        link_id = seed_link(db)
        send(db, link_id, "before_unlink")
        old_claim = processor.claim()
        assert old_claim is not None
        relink(db, link_id)
        new_id = send(db, link_id, "after_relink")
        new_claim = processor.claim()
        assert new_claim is not None
        processor.finish(old_claim, "completed")
        assert db.get(ChatNotificationJob, new_id).status == "processing"


@pytest.mark.parametrize("registration", ["other_owner", "same_owner", "round_trip"])
def test_late_push_rejection_preserves_new_registration(tmp_path, registration):
    engine = make_engine(tmp_path)
    factory = make_session_factory(engine)
    token = "synthetic-delayed-response-token-12345"
    try:
        with factory() as db:
            seed_account(db, "patient-a", "patient-b")
            ManagePushToken(db).registerPushToken("patient-a", token, "android")
            resolver = PushRecipientResolver(db)
            assert resolver.resolve("patient-a").tokens == (token,)
            db.rollback()
            with factory() as other:
                control = ManagePushToken(other)
                if registration in {"other_owner", "round_trip"}:
                    control.registerPushToken("patient-b", token, "android")
                if registration in {"same_owner", "round_trip"}:
                    control.registerPushToken("patient-a", token, "android")
            resolver.disable_invalid((token,))
        with factory() as observer:
            row = observer.query(_DevicePushToken).one()
            assert row.enabled
            assert row.user_hash == ("patient-b" if registration == "other_owner" else "patient-a")
    finally:
        engine.dispose()


def test_push_rejection_disables_only_the_observed_registration(fk_db):
    seed_account(fk_db, "patient-a", "patient-b")
    control = ManagePushToken(fk_db)
    control.registerPushToken("patient-a", "observed-token-1234567890", "android")
    control.registerPushToken("patient-b", "unobserved-token-1234567890", "android")
    resolver = PushRecipientResolver(fk_db)
    resolver.resolve("patient-a")
    fk_db.rollback()
    resolver.disable_invalid(("observed-token-1234567890", "unobserved-token-1234567890"))
    states = {row.user_hash: row.enabled for row in fk_db.query(_DevicePushToken)}
    assert states == {"patient-a": False, "patient-b": True}


def test_same_owner_reregistration_with_equal_persisted_timestamp_is_preserved(fk_db):
    seed_account(fk_db, "patient-a")
    token = "same-timestamp-registration-token-123"
    control = ManagePushToken(fk_db)
    control.registerPushToken("patient-a", token, "android")
    timestamp = fk_db.query(_DevicePushToken).one().updated_at
    resolver = PushRecipientResolver(fk_db)
    resolver.resolve("patient-a")
    fk_db.rollback()
    control.registerPushToken("patient-a", token, "android")
    # 시계 해상도나 DB 반올림으로 두 등록 시각이 같아지는 상황을 재현한다.
    fk_db.query(_DevicePushToken).update({"updated_at": timestamp})
    fk_db.commit()
    resolver.disable_invalid((token,))
    fk_db.expire_all()
    assert fk_db.query(_DevicePushToken).one().enabled


def test_push_cleanup_rechecks_registration_in_the_update(tmp_path):
    engine = make_engine(tmp_path)
    factory = make_session_factory(engine)
    token = "atomic-cleanup-registration-token-123"
    renewed = False
    try:
        with factory() as db:
            seed_account(db, "patient-a")
            ManagePushToken(db).registerPushToken("patient-a", token, "android")
            resolver = PushRecipientResolver(db)
            resolver.resolve("patient-a")
            db.rollback()

            def renew_before_update(connection, cursor, statement, parameters, context, executemany):
                nonlocal renewed
                if not renewed and statement.startswith("UPDATE device_push_tokens SET enabled="):
                    renewed = True
                    with factory() as registration_db:
                        ManagePushToken(registration_db).registerPushToken("patient-a", token, "android")

            event.listen(engine, "before_cursor_execute", renew_before_update)
            try:
                resolver.disable_invalid((token,))
            finally:
                event.remove(engine, "before_cursor_execute", renew_before_update)
        assert renewed
        with factory() as observer:
            assert observer.query(_DevicePushToken).one().enabled
    finally:
        engine.dispose()
