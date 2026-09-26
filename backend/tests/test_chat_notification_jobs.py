# File Name: test_chat_notification_jobs.py
# Role: Verify transaction durability, retry fencing, live privacy checks and message-owned cleanup.

import asyncio
from datetime import timedelta
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

from boundaries.push_notification_boundary import PushDeliveryResult
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.manage_linked_chat_control import ManageLinkedChat
from controls.process_chat_notifications_control import ProcessChatNotifications
from core.database import Base
from entities.chat_message_entity import _ChatMessage
from entities.chat_notification_job_entity import ChatNotificationJob as Job, utc_now
from entities.device_push_token_entity import _DevicePushToken
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.user_setting_entity import _UserSetting
from entities.user_account_entity import _UserAccount
from entities.saved_medication_entity import _SavedMedication
from entities.medication_completion_entity import _MedicationCompletion
from core.application_clock import application_today


# Function Name: database
# Description: Create isolated file-backed sessions usable by worker threads, with FK enforcement.
# Parameters: tmp_path - test storage. Returns: Session factory and active link ID; disposes on exit.
@pytest.fixture
def database(tmp_path: Path):
    engine = create_engine(f"sqlite:///{tmp_path / 'jobs.db'}", connect_args={"check_same_thread": False})
    # Function Name: foreign_keys
    # Description: Enforce deletion cascades in the test database.
    # Parameters: connection - SQLite connection; record - pool metadata. Returns: None.
    @event.listens_for(engine, "connect")
    def foreign_keys(connection: object, record: object) -> None:
        connection.execute("PRAGMA foreign_keys=ON")
    Base.metadata.create_all(engine)
    sessions = sessionmaker(bind=engine)
    with sessions() as db:
        db.add_all([_UserAccount(user_hash="patient"), _UserAccount(user_hash="caregiver")])
        db.commit()
        control = LinkPatientCaregiver(db)
        code = control.generatePatientHash("patient")["data"]["patient_code"]
        link_id = control.requestPatientCaregiverLink("caregiver", code)["data"]["id"]
        db.add(_DevicePushToken(user_hash="caregiver", token="test-token", platform="android", enabled=True))
        db.commit()
    yield sessions, link_id
    engine.dispose()


# Function Name: enqueue
# Description: Use the real chat writer to save both message and job.
# Parameters: database - isolated fixture. Returns: Newly stored message ID.
def enqueue(database: tuple) -> int:
    sessions, link_id = database
    with sessions() as db:
        result = ManageLinkedChat(db).send_message(link_id=link_id, sender_hash="patient",
            client_message_id="durable_message_001", body="Remember your medication")
        return result.message.message_id


# Class Name: Push
# Role: Deterministic push boundary recording attempts without external side effects.
# Attributes: results - queued outcomes; calls - transmitted payloads.
class Push:
    # Function Name: __init__
    # Description: Store outcomes and prepare call recording.
    # Parameters: results - delivery outcomes. Returns: Initialized boundary.
    def __init__(self, *results: PushDeliveryResult | Exception) -> None:
        self.results = list(results)
        self.calls = []

    # Function Name: send_notification
    # Description: Record a payload and return the next selected outcome.
    # Parameters: kwargs - push request fields. Returns: Delivery result.
    def send_notification(self, **kwargs: object) -> PushDeliveryResult:
        self.calls.append(kwargs)
        result = self.results.pop(0) if self.results else PushDeliveryResult(1)
        if isinstance(result, Exception):
            raise result
        return result


# Function Name: processor
# Description: Compose a fresh process-equivalent consumer with injectable delivery policies.
# Parameters: database - fixture; push - boundary. Returns: Durable processor.
def processor(database: tuple, push: Push) -> ProcessChatNotifications:
    return ProcessChatNotifications(database[0], lambda: push,
        AsyncMock(return_value=False), AsyncMock(return_value=True))


# Function Name: test_committed_job_survives_restart_and_duplicate_request
# Description: Retried HTTP input creates no second job; a fresh consumer can deliver without a router task.
# Parameters: database - isolated fixture. Returns: None.
def test_committed_job_survives_restart_and_duplicate_request(database: tuple) -> None:
    message_id = enqueue(database)
    assert enqueue(database) == message_id
    push = Push()
    assert asyncio.run(processor(database, push).run_once()) == 1
    assert asyncio.run(processor(database, push).run_once()) == 0
    assert len(push.calls) == 1
    assert push.calls[0]["data"]["event_id"].endswith(f":{message_id}")
    with database[0]() as db:
        assert db.query(Job).count() == 1
        assert db.get(Job, message_id).status == "completed"


# Function Name: test_failed_commit_rolls_back_message_and_job
# Description: A failed message transaction cannot leave a separately committed notification.
# Parameters: database - isolated fixture. Returns: None.
def test_failed_commit_rolls_back_message_and_job(database: tuple) -> None:
    with database[0]() as db:
        with patch.object(db, "commit", side_effect=RuntimeError("simulated_failure")):
            with pytest.raises(RuntimeError):
                ManageLinkedChat(db).send_message(link_id=database[1], sender_hash="patient",
                    client_message_id="rollback_message", body="Not saved")
        db.rollback()
        assert db.query(_ChatMessage).count() == db.query(Job).count() == 0


# Function Name: test_partial_failure_retries_from_a_new_processor
# Description: Persist backoff after partial FCM failure and preserve the event ID on retry.
# Parameters: database - isolated fixture. Returns: None.
@pytest.mark.parametrize("failure", [PushDeliveryResult(1, retryable_failure_count=1), RuntimeError("temporary")])
def test_partial_failure_retries_from_a_new_processor(database: tuple, failure: object) -> None:
    message_id = enqueue(database)
    push = Push(failure, PushDeliveryResult(2))
    asyncio.run(processor(database, push).run_once())
    with database[0]() as db:
        job = db.get(Job, message_id)
        assert job.status == "pending" and job.attempts == 1
        assert job.available_at > utc_now()
        job.available_at = utc_now() - timedelta(seconds=1)
        db.commit()
    asyncio.run(processor(database, push).run_once())
    assert len(push.calls) == 2
    assert push.calls[0]["data"]["event_id"] == push.calls[1]["data"]["event_id"]


# Function Name: test_recovered_lease_fences_late_worker
# Description: Only one consumer owns fresh work; stale processing can be reclaimed without late overwrites.
# Parameters: database - isolated fixture. Returns: None.
def test_recovered_lease_fences_late_worker(database: tuple) -> None:
    message_id = enqueue(database)
    worker = processor(database, Push())
    first = worker.claim()
    assert processor(database, Push()).claim() is None
    with database[0]() as db:
        db.get(Job, message_id).available_at = utc_now() - timedelta(seconds=1)
        db.commit()
    second = processor(database, Push()).claim()
    worker.finish(first, "completed")
    with database[0]() as db:
        assert db.get(Job, message_id).status == "processing"
        assert db.get(Job, message_id).attempts == second.attempt == 2
    worker.finish(second, "completed")


# Function Name: test_delivery_rechecks_live_privacy_state
# Description: Queued content cannot bypass deletion, read, unlink or current opt-out settings.
# Parameters: database - fixture; change - invalidating state. Returns: None.
@pytest.mark.parametrize("change", ["read", "private_delete", "shared_delete", "unlink", "disabled", "no_token"])
def test_delivery_rechecks_live_privacy_state(database: tuple, change: str) -> None:
    message_id = enqueue(database)
    with database[0]() as db:
        row = db.get(_ChatMessage, message_id)
        if change == "read": row.read_at = utc_now()
        elif change == "private_delete": row.caregiver_deleted_at = utc_now()
        elif change == "shared_delete": row.deleted_for_everyone_at = utc_now()
        elif change == "unlink": db.get(_PatientCaregiverLink, database[1]).linked = False
        elif change == "disabled": db.add(_UserSetting(user_hash="caregiver", chat_notifications_enabled=False))
        elif change == "no_token": db.query(_DevicePushToken).delete()
        db.commit()
    push = Push()
    asyncio.run(processor(database, push).run_once())
    assert push.calls == []


# Function Name: test_transport_policy_and_expiry
# Description: Preserve connected/cooldown suppression, retry infrastructure failure, and cap stale jobs.
# Parameters: database - fixture; condition - delivery state. Returns: None.
@pytest.mark.parametrize("condition", ["connected", "cooldown", "quota_error", "expired", "exhausted"])
def test_transport_policy_and_expiry(database: tuple, condition: str) -> None:
    message_id = enqueue(database)
    push = Push(PushDeliveryResult(0, retryable_failure_count=1))
    worker = processor(database, push)
    if condition == "connected": worker.connected.return_value = True
    if condition == "cooldown": worker.reserve.return_value = False
    if condition == "quota_error": worker.reserve.side_effect = RuntimeError("private detail")
    with database[0]() as db:
        job = db.get(Job, message_id)
        if condition == "expired": job.created_at = utc_now() - timedelta(days=2)
        if condition == "exhausted": job.attempts = 7
        db.commit()
    asyncio.run(worker.run_once())
    with database[0]() as db:
        job = db.get(Job, message_id)
        assert job.status == ("pending" if condition == "quota_error" else
                              "dead" if condition in {"expired", "exhausted"} else "suppressed")
        assert job.last_error != "private detail"
    assert len(push.calls) == (1 if condition == "exhausted" else 0)


# Function Name: test_message_deletion_cascades_job
# Description: Retention/account cleanup cannot leave content-independent notification jobs behind.
# Parameters: database - isolated fixture. Returns: None.
def test_message_deletion_cascades_job(database: tuple) -> None:
    message_id = enqueue(database)
    with database[0]() as db:
        db.delete(db.get(_ChatMessage, message_id))
        db.commit()
        assert db.get(Job, message_id) is None


# Function Name: test_dose_receipt_job_shares_outer_transaction
# Description: The offline-sync commit=False path must not commit a chat job separately from the dose.
# Parameters: database - fixture; commit - whether the outer owner commits or rolls back.
# Returns: None; fails if notification, chat and dose persistence diverge.
@pytest.mark.parametrize("commit", [False, True])
def test_dose_receipt_job_shares_outer_transaction(database: tuple, commit: bool) -> None:
    with database[0]() as db:
        medication = _SavedMedication(patient_hash="patient", item_name="Test medicine",
            created_date=application_today(), daily_frequency="1", total_days="3",
            schedule_slot_keys='["morning"]')
        db.add(medication)
        db.commit()
        ManageLinkedChat(db).record_medication_taken(
            link_id=database[1], sender_hash="patient", client_message_id="dose_receipt_001",
            schedule_date=application_today(), slot_key="morning", medication_ids=[medication.id], commit=False,
        )
        if commit: db.commit()
        else: db.rollback()
    with database[0]() as db:
        assert db.query(Job).count() == db.query(_ChatMessage).count() == int(commit)
        assert db.query(_MedicationCompletion).count() == int(commit)
