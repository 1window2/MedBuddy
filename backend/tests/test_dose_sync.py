"""Offline retries, undo, ownership and midnight must not invent new doses."""
from datetime import timedelta
from unittest.mock import patch

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from controls.sync_dose_control import SyncDose
from controls.check_schedule_control import CheckSchedule
from core.application_clock import application_today
from core.database import Base
from entities.dose_sync_operation_entity import _DoseSyncOperation
from entities.medication_completion_entity import _MedicationCompletion
from entities.caregiver_alert_outbox_entity import _CaregiverAlertOutbox
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import _UserAccount
from schemas.dose_sync import DoseSyncRequest
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from entities.chat_message_entity import _ChatMessage


@pytest.fixture
def fixture():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        db.add(_UserAccount(user_hash="offline-patient"))
        db.add(_UserAccount(user_hash="other-patient"))
        med = _SavedMedication(patient_hash="offline-patient", item_name="offline fixture",
            created_date=application_today()-timedelta(days=3), total_days="30",
            daily_frequency="1", dosage_per_time="1", schedule_slot_keys='["morning"]')
        db.add(med)
        db.commit()
        yield db, med.id
    engine.dispose()


def operation(med_id, **changes):
    return DoseSyncRequest(**dict(dict(operation_id="offline_dose_0001",
        schedule_date=application_today(), slot_key="morning", medication_ids=[med_id], completed=True), **changes))


def test_retry_after_undo_never_reapplies(fixture):
    db, med_id = fixture
    control = SyncDose(db)
    first = operation(med_id)
    control.apply("offline-patient", first)
    control.apply("offline-patient", operation(med_id, operation_id="offline_undo_0002", completed=False))
    control.apply("offline-patient", first)
    assert db.query(_MedicationCompletion).one().completed is False
    assert db.query(_DoseSyncOperation).count() == 2
    assert db.query(_CaregiverAlertOutbox).count() == 1


def test_midnight_records_original_day_without_today_or_live_alert(fixture):
    db, med_id = fixture
    yesterday = application_today()-timedelta(days=1)
    SyncDose(db).apply("offline-patient", operation(med_id, schedule_date=yesterday))
    row = db.query(_MedicationCompletion).one()
    assert row.schedule_date == yesterday and row.completed
    assert db.query(_CaregiverAlertOutbox).count() == 0
    assert not CheckSchedule(db).requestTodayMedicationSchedule("offline-patient")["data"][0]["medication_status"]


@pytest.mark.parametrize("days", [1, -31])
def test_future_and_expired_dates_reject_without_receipt(fixture, days):
    db, med_id = fixture
    with pytest.raises(HTTPException) as error:
        SyncDose(db).apply("offline-patient", operation(med_id, schedule_date=application_today()+timedelta(days=days)))
    assert error.value.status_code == 409
    assert db.query(_DoseSyncOperation).count() == 0
    assert db.query(_MedicationCompletion).count() == 0


def test_wrong_owner_and_deleted_medication_reject(fixture):
    db, med_id = fixture
    with pytest.raises(HTTPException):
        SyncDose(db).apply("other-patient", operation(med_id))
    assert db.query(_DoseSyncOperation).count() == 0
    with pytest.raises(HTTPException):
        SyncDose(db).apply("offline-patient", operation(med_id+999))
    assert db.query(_MedicationCompletion).count() == 0


def test_receipt_payload_cannot_change(fixture):
    db, med_id = fixture
    SyncDose(db).apply("offline-patient", operation(med_id))
    with pytest.raises(HTTPException) as error:
        SyncDose(db).apply("offline-patient", operation(med_id, completed=False))
    assert error.value.status_code == 409
    assert db.query(_MedicationCompletion).one().completed


def test_transaction_failure_rolls_back_receipt_and_dose(fixture):
    db, med_id = fixture
    with patch.object(db, "commit", side_effect=RuntimeError("disk failure")):
        with pytest.raises(RuntimeError):
            SyncDose(db).apply("offline-patient", operation(med_id))
    assert db.query(_DoseSyncOperation).count() == 0
    assert db.query(_MedicationCompletion).count() == 0
    assert db.query(_CaregiverAlertOutbox).count() == 0


def test_chat_and_historical_dose_share_one_idempotent_transaction(fixture):
    db, med_id = fixture
    links = LinkPatientCaregiver(db)
    code = links.generatePatientHash("offline-patient")["data"]["patient_code"]
    link_id = links.requestPatientCaregiverLink("other-patient", code)["data"]["id"]
    yesterday = application_today()-timedelta(days=1)
    request = operation(med_id, link_id=link_id, schedule_date=yesterday)
    events, message = SyncDose(db).apply("offline-patient", request)
    assert events == [] and message.created
    SyncDose(db).apply("offline-patient", request)
    assert db.query(_ChatMessage).count() == 1
    assert db.query(_DoseSyncOperation).count() == 1
    assert yesterday.isoformat() in db.query(_ChatMessage).one().body
    assert db.query(_ChatMessage).one().context_payload["schedule_context"]["schedule_date"] == yesterday.isoformat()


def test_chat_failure_rolls_back_the_dose_and_receipt(fixture):
    db, med_id = fixture
    links = LinkPatientCaregiver(db)
    code = links.generatePatientHash("offline-patient")["data"]["patient_code"]
    link_id = links.requestPatientCaregiverLink("other-patient", code)["data"]["id"]
    with patch("repositories.chat_message_repository.ChatMessageRepository.add", side_effect=RuntimeError("chat failure")):
        with pytest.raises(RuntimeError):
            SyncDose(db).apply("offline-patient", operation(med_id, link_id=link_id))
    assert db.query(_DoseSyncOperation).count() == 0
    assert db.query(_MedicationCompletion).count() == 0


def test_route_rejects_a_previous_accounts_queued_request(fixture):
    import asyncio
    from fastapi import BackgroundTasks, Request
    from api.router import sync_dose_operation
    from controls.authorization_control import AuthorizationControl
    from entities.authenticated_principal_entity import AuthenticatedPrincipal
    db, med_id = fixture
    with pytest.raises(HTTPException) as error:
        asyncio.run(sync_dose_operation(
            payload=operation(med_id), request=Request({"type": "http"}),
            background_tasks=BackgroundTasks(), patient_hash="offline-patient",
            principal=AuthenticatedPrincipal(subject="other", issuer="test", user_hash="other-patient"),
            authorization=AuthorizationControl(db), check_schedule=CheckSchedule(db),
        ))
    assert error.value.status_code == 403
    assert db.query(_DoseSyncOperation).count() == 0


def test_migration_accepts_demo_metadata_initialization(fixture):
    import importlib.util
    from pathlib import Path
    from alembic.migration import MigrationContext
    from alembic.operations import Operations
    db, _ = fixture
    path = Path(__file__).parents[1] / "migrations/versions/a6e2d903bc71_add_dose_sync_operations.py"
    spec = importlib.util.spec_from_file_location("dose_migration", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with db.bind.begin() as connection:
        with patch.object(module, "op", Operations(MigrationContext.configure(connection))):
            module.upgrade()
            module.upgrade()
