"""이력 공유와 연동 해제·계정 삭제가 같은 잠금 순서로 직렬화되는지 검증한다."""

from threading import Event, Thread
from unittest.mock import Mock

import pytest
from fastapi import HTTPException
from sqlalchemy.exc import OperationalError

from controls import manage_linked_chat_control
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.manage_account_control import ManageAccount
from controls.manage_linked_chat_control import ManageLinkedChat
from controls.manage_medication_care_control import ManageMedicationCare
from core.account_database_lock import ACCOUNT_BUSY_DETAIL, lock_account_operations
from core.application_clock import application_today
from entities.chat_message_entity import _ChatMessage
from entities.chat_notification_job_entity import ChatNotificationJob
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.user_account_entity import _UserAccount, utc_now
from support.db import make_engine, make_session_factory, seed_account


@pytest.fixture
def scene(tmp_path):
    engine = make_engine(tmp_path)
    factory = make_session_factory(engine)
    with factory() as db:
        seed_account(db, "patient-a", "caregiver-a")
        link = _PatientCaregiverLink(patient_hash="patient-a", caregiver_hash="caregiver-a", linked=True)
        db.add(link)
        db.commit()
        link_id = link.id
    try:
        yield factory, link_id
    finally:
        engine.dispose()


def send_history(db, link_id):
    return ManageLinkedChat(db).send_message(
        link_id=link_id, sender_hash="caregiver-a", client_message_id="history_lock_001",
        body="복약 기록을 공유해요.", message_kind="medication_history_share",
        history_start_date=application_today(), history_end_date=application_today(),
    )


def revoke(db, link_id, actor, action):
    if action == "unlink":
        LinkPatientCaregiver(db).requestUnlink(link_id, actor)
    elif action == "delete":
        ManageAccount(db).deleteAccountData(actor)
    else:
        db.get(_UserAccount, actor).deletion_requested_at = utc_now()
        db.commit()


@pytest.mark.parametrize("actor", ["patient-a", "caregiver-a"])
@pytest.mark.parametrize("action", ["unlink", "delete", "tombstone"])
def test_revocation_after_preflight_is_rechecked_before_snapshot(scene, monkeypatch, actor, action):
    """초기 연동 조회가 성공해도 잠금 전 해제·삭제가 완료되면 공유를 만들지 않는다."""
    factory, link_id = scene
    calls = []

    def lock_after_revocation(db, participants):
        assert not db.in_transaction()
        assert set(participants) == {"patient-a", "caregiver-a"}
        calls.append(participants)
        with factory() as other:
            lock_account_operations(other, [actor])
            revoke(other, link_id, actor, action)
        lock_account_operations(db, participants)

    lookup = Mock(side_effect=AssertionError("Revoked history must not be read"))
    monkeypatch.setattr(manage_linked_chat_control, "lock_account_operations", lock_after_revocation)
    monkeypatch.setattr(ManageMedicationCare, "history_share_context", lookup)
    with factory() as db:
        # 인증 단계에서 이미 가진 단일 계정 잠금도 재정렬 전에 반환해야 한다.
        lock_account_operations(db, ["caregiver-a"])
        with pytest.raises(HTTPException) as caught:
            send_history(db, link_id)
        assert caught.value.status_code == (404 if action == "unlink" else 410)
        assert len(calls) == 1 and not db.in_transaction()
        assert db.query(_ChatMessage).count() == 0
        assert db.query(ChatNotificationJob).count() == 0
    lookup.assert_not_called()


@pytest.mark.parametrize("actor", ["patient-a", "caregiver-a"])
@pytest.mark.parametrize("action", ["unlink", "delete"])
def test_revocation_waits_for_snapshot_commit_then_removes_message(scene, monkeypatch, actor, action):
    """공유가 먼저 잠그면 해제·삭제가 커밋까지 기다린 뒤 메시지와 알림을 함께 제거한다."""
    factory, link_id = scene
    reading = Event()
    attempted = Event()
    acquired = Event()
    failures = []
    original = ManageMedicationCare.history_share_context

    def snapshot_while_locked(self, *args):
        reading.set()
        assert attempted.wait(3)
        assert not acquired.wait(0.1)
        return original(self, *args)

    def mutation():
        try:
            assert reading.wait(3)
            with factory() as db:
                attempted.set()
                lock_account_operations(db, [actor])
                acquired.set()
                revoke(db, link_id, actor, action)
        except BaseException as exc:
            failures.append(exc)

    monkeypatch.setattr(ManageMedicationCare, "history_share_context", snapshot_while_locked)
    worker = Thread(target=mutation, daemon=True)
    worker.start()
    try:
        with factory() as db:
            sent = send_history(db, link_id)
            assert sent.created and sent.message.context_payload["history_context"]["taken_count"] == 0
    finally:
        worker.join(8)
    assert not worker.is_alive() and not failures and acquired.is_set()
    with factory() as db:
        assert db.query(_ChatMessage).count() == 0
        assert db.query(ChatNotificationJob).count() == 0


def test_lock_timeout_is_retryable_without_partial_snapshot(scene, monkeypatch):
    factory, link_id = scene
    monkeypatch.setattr(manage_linked_chat_control, "lock_account_operations", Mock(
        side_effect=OperationalError("lock", {}, Exception("timeout")),
    ))
    with factory() as db:
        with pytest.raises(HTTPException) as caught:
            send_history(db, link_id)
        assert caught.value.status_code == 503
        assert caught.value.detail == ACCOUNT_BUSY_DETAIL
        assert caught.value.headers == {"Retry-After": "5"}
        assert not db.in_transaction()
        assert db.query(_ChatMessage).count() == 0
