# 파일명: test_as_needed_caregiver_alerts.py
# 역할: 필요시 복용 알림의 설정·원자성·전송 재검증과 일괄 감시 식별자를 검증한다.

from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta
import hashlib
from threading import Barrier
from unittest.mock import patch
from uuid import uuid4
from zoneinfo import ZoneInfo

from fastapi import BackgroundTasks, HTTPException
import pytest

from api.medication_care_router import update_history
from controls.check_caregiver_monitoring_control import CheckCaregiverMonitoring
from controls.manage_medication_care_control import ManageMedicationCare
from controls.process_caregiver_alert_outbox_control import ProcessCaregiverAlertOutbox
from controls.queue_missed_dose_alerts_control import QueueMissedDoseAlerts
from controls.set_caregiver_notification_control import SetCaregiverNotification
from core.application_clock import application_now, application_today
from entities.caregiver_alert_outbox_entity import (
    CAREGIVER_ALERT_EVENT_AS_NEEDED_COMPLETED, _CaregiverAlertOutbox,
)
from entities.caregiver_notification_entity import (
    CaregiverNotification, _CaregiverNotification, effective_slot_settings, encode_slot_settings,
)
from entities.device_push_token_entity import _DevicePushToken
from entities.medication_care_entity import _MedicationCareOperation
from entities.medication_completion_entity import _MedicationCompletion
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import utc_now
from entities.user_setting_entity import _UserSetting
from services.as_needed_caregiver_events import as_needed_taken_event_key
from support.db import make_engine, make_session_factory, seed_account
from support.fakes import RecordingPushBoundary
from test_medication_care import medication, principal, report


@pytest.fixture
def scene(fk_db):
    med = medication(fk_db, dosing_mode="as_needed")
    seed_account(fk_db, "caregiver-a")
    fk_db.add(_PatientCaregiverLink(patient_hash="patient-a", caregiver_hash="caregiver-a", linked=True))
    fk_db.add(_DevicePushToken(user_hash="caregiver-a", token="caregiver-device"))
    fk_db.add(_UserSetting(user_hash="caregiver-a", chat_notifications_enabled=False))
    fk_db.commit()
    SetCaregiverNotification(fk_db).saveCaregiverNotificationSetting(
        "caregiver-a", "patient-a", slot_key="as_needed", alert_option="dose_completed",
    )
    return med.id


def take(db, medication_id, *, slot=None, day=None, **values):
    slot = slot or f"as_needed:{uuid4()}"
    response = ManageMedicationCare(db).update_history(
        principal(), medication_id, day or application_today(), slot, report(**values),
    )
    return slot, response


def snapshot(db):
    return CheckCaregiverMonitoring(db).requestMonitoringSnapshot("caregiver-a")["data"]["patients"]


@pytest.mark.parametrize("legacy_mode", ["enable", "missed_deadline", "disabled"])
@pytest.mark.parametrize("raw", ["{}", "not-json", '{"lunch":{"notification_type":"disabled"}}'])
def test_missing_prn_never_inherits_legacy_regular_preferences(legacy_mode, raw):
    row = _CaregiverNotification(
        enabled=True, alert_option=legacy_mode, deadline_hour=20, deadline_minute=30,
        slot_settings=raw,
    )
    settings = effective_slot_settings(row)
    assert settings["as_needed"] == {
        "notification_type": "disabled", "deadline_hour": None, "deadline_minute": None,
    }
    assert settings["morning"]["notification_type"] == ("dose_completed" if legacy_mode == "enable" else legacy_mode)
    assert settings["morning"]["deadline_hour"] == 20


def test_prn_settings_round_trip_and_deadline_rejected(fk_db, scene):
    control = SetCaregiverNotification(fk_db)
    before = control.requestCaregiverNotificationSettings("caregiver-a", "patient-a")["data"]
    assert len(before) == 5
    assert before[-1]["slot_key"] == "as_needed"
    assert before[-1]["notification_type"] == "dose_completed"
    with pytest.raises(HTTPException) as rejected:
        control.saveCaregiverNotificationSetting(
            "caregiver-a", "patient-a", slot_key="as_needed", alert_option="missed_deadline",
            deadline_hour=20, deadline_minute=30,
        )
    assert rejected.value.status_code == 400
    assert control.requestCaregiverNotificationSettings("caregiver-a", "patient-a")["data"] == before
    with pytest.raises(ValueError):
        CaregiverNotification(slot_key="as_needed").updateNotificationSetting("missed_deadline", 20, 30)
    disabled = control.saveCaregiverNotificationSetting(
        "caregiver-a", "patient-a", slot_key="as_needed", enabled=False,
    )["data"]
    assert disabled["notification_type"] == "disabled"
    enabled = control.saveCaregiverNotificationSetting(
        "caregiver-a", "patient-a", slot_key="as_needed", enabled=True, deadline_hour=20, deadline_minute=30,
    )["data"]
    assert enabled["notification_type"] == "dose_completed"
    assert enabled["deadline_hour"] is None and enabled["deadline_minute"] is None
    assert control.requestCaregiverNotificationSettings("caregiver-a", "patient-a")["data"][:-1] == before[:-1]


def test_unconfigured_prn_default_is_disabled_without_persisting(fk_db, scene):
    fk_db.delete(fk_db.query(_CaregiverNotification).one())
    fk_db.commit()
    result = SetCaregiverNotification(fk_db).requestCaregiverNotificationSetting(
        "caregiver-a", "patient-a", slot_key="as_needed",
    )["data"]
    assert result["notification_type"] == "disabled" and not result["notification_enabled"]
    assert result["deadline_hour"] is None and result["deadline_minute"] is None
    assert fk_db.query(_CaregiverNotification).count() == 0
    assert snapshot(fk_db)[0]["as_needed_taken_event_keys"] == []


def test_invalid_stored_prn_deadline_never_queues_missed_alert(fk_db, scene):
    setting = fk_db.query(_CaregiverNotification).one()
    setting.slot_settings = encode_slot_settings({"as_needed": {
        "notification_type": "missed_deadline", "deadline_hour": 0, "deadline_minute": 0,
    }})
    setting.alert_option = "disabled"
    fk_db.commit()
    assert effective_slot_settings(setting)["as_needed"]["notification_type"] == "disabled"
    assert QueueMissedDoseAlerts(fk_db).queueDue() == 0


def test_two_doses_retry_and_timestamp_edit_have_stable_unique_events(fk_db, scene):
    care = ManageMedicationCare(fk_db)
    slot = f"as_needed:{uuid4()}"
    today = application_today()
    request = report()
    first = care.update_history(principal(), scene, today, slot, request)
    first_events = care.consumeCompletionEvents()
    assert len(first_events) == 1
    assert care.update_history(principal(), scene, today, slot, request) == first
    assert care.consumeCompletionEvents() == []
    take(fk_db, scene, slot=slot, expected_revision=1, actual_taken_at=application_now() - timedelta(minutes=1))
    second_slot, _ = take(fk_db, scene)
    rows = fk_db.query(_CaregiverAlertOutbox).order_by(_CaregiverAlertOutbox.id).all()
    expected = {
        hashlib.sha256(f"as_needed:patient-a:{scene}:{today.isoformat()}:{key}".encode("utf-8")).hexdigest()
        for key in (slot, second_slot)
    }
    assert len(rows) == 2 and {row.event_key for row in rows} == expected
    assert all(row.slot_key == "as_needed" and row.event_type == CAREGIVER_ALERT_EVENT_AS_NEEDED_COMPLETED for row in rows)
    assert set(snapshot(fk_db)[0]["as_needed_taken_event_keys"]) == expected
    boundary = RecordingPushBoundary(on_send=lambda _: assert_no_transaction(fk_db))
    worker = ProcessCaregiverAlertOutbox(fk_db, boundary)
    with patch("controls.process_caregiver_alert_outbox_control.ManageLinkedChat.publish_slot_completion") as chat:
        assert worker.processDue() == {"sent": 2, "failed": 0, "skipped": 0}
        assert worker.processDue() == {"sent": 0, "failed": 0, "skipped": 0}
        chat.assert_not_called()
    assert {call["data"]["event_key"] for call in boundary.calls} == expected
    for call in boundary.calls:
        assert call["data"] == {
            "type": "caregiver_dose_completed", "recipient_hash": "caregiver-a",
            "language": "ko", "patient_hash": "patient-a", "slot_key": "as_needed",
            "event_key": call["data"]["event_key"], "schedule_date": today.isoformat(),
        }
        assert call["body"] == "환자가 필요시 약의 복용을 기록했습니다."


def assert_no_transaction(db):
    assert not db.in_transaction()


def test_timestamp_edit_of_preexisting_taken_record_does_not_create_event(fk_db, scene):
    slot = f"as_needed:{uuid4()}"
    fk_db.add(_MedicationCompletion(
        patient_hash="patient-a", saved_medication_id=scene, schedule_date=application_today(),
        slot_key=slot, completed=True, report_status="taken", revision=1,
    ))
    fk_db.commit()
    take(fk_db, scene, slot=slot, expected_revision=1)
    assert fk_db.query(_CaregiverAlertOutbox).count() == 0


@pytest.mark.parametrize("status", ["skipped", "unrecorded"])
def test_non_taken_and_past_reports_do_not_queue_new_events(fk_db, scene, status):
    slot, _ = take(fk_db, scene, status=status)
    take(fk_db, scene, day=application_today() - timedelta(days=1))
    assert fk_db.query(_CaregiverAlertOutbox).count() == 0
    take(fk_db, scene, slot=slot, expected_revision=1)
    assert fk_db.query(_CaregiverAlertOutbox).count() == 1


def test_sent_record_uncheck_recheck_does_not_notify_twice(fk_db, scene):
    slot, _ = take(fk_db, scene)
    boundary = RecordingPushBoundary()
    worker = ProcessCaregiverAlertOutbox(fk_db, boundary)
    assert worker.processDue()["sent"] == 1
    take(fk_db, scene, slot=slot, status="unrecorded", expected_revision=1)
    take(fk_db, scene, slot=slot, expected_revision=2)
    assert worker.processDue()["sent"] == 0
    assert fk_db.query(_CaregiverAlertOutbox).count() == 1 and len(boundary.calls) == 1


@pytest.mark.parametrize("change", ["skipped", "unrecorded", "delete_record", "delete_medication", "yesterday", "tomorrow", "undated", "wrong_key"])
def test_delivery_rejects_noncurrent_dose(fk_db, scene, change):
    slot, _ = take(fk_db, scene)
    event = fk_db.query(_CaregiverAlertOutbox).one()
    event_id = event.id
    if change in ("skipped", "unrecorded"):
        take(fk_db, scene, slot=slot, status=change, expected_revision=1)
    elif change == "delete_record":
        fk_db.delete(fk_db.query(_MedicationCompletion).one())
    elif change == "delete_medication":
        fk_db.delete(fk_db.get(_SavedMedication, scene))
    elif change == "wrong_key":
        event.event_key = "0" * 64
    else:
        event.schedule_date = None if change == "undated" else application_today() + timedelta(days=-1 if change == "yesterday" else 1)
    fk_db.commit()
    boundary = RecordingPushBoundary()
    worker = ProcessCaregiverAlertOutbox(fk_db, boundary)
    assert worker.processOne(event_id) == "skipped"
    assert boundary.calls == []
    event = fk_db.get(_CaregiverAlertOutbox, event_id)
    assert event.status == "dead_letter" and event.last_error == "AsNeededDoseNoLongerCurrent"
    assert worker.processOne(event_id) == "skipped"


@pytest.mark.parametrize("change", ["revoked", "disabled", "global_disabled", "row_disabled", "missing_setting"])
def test_retry_rechecks_link_and_settings_at_delivery(fk_db, scene, change):
    take(fk_db, scene)
    boundary = RecordingPushBoundary(retryable=1)
    worker = ProcessCaregiverAlertOutbox(fk_db, boundary)
    assert worker.processDue()["failed"] == 1
    event = fk_db.query(_CaregiverAlertOutbox).one()
    event.available_at = utc_now() - timedelta(seconds=1)
    if change == "revoked":
        fk_db.query(_PatientCaregiverLink).one().linked = False
    elif change == "global_disabled":
        fk_db.query(_UserSetting).one().caregiver_notifications_enabled = False
    elif change == "row_disabled":
        fk_db.query(_CaregiverNotification).one().enabled = False
    elif change == "missing_setting":
        fk_db.delete(fk_db.query(_CaregiverNotification).one())
    else:
        fk_db.query(_CaregiverNotification).one().slot_settings = encode_slot_settings({
            "as_needed": {"notification_type": "disabled"},
        })
    fk_db.commit()
    boundary.retryable = 0
    assert worker.processDue()["sent"] == 1
    assert len(boundary.calls) == 1


def test_transient_failure_retries_same_key_then_stops(fk_db, scene):
    take(fk_db, scene)
    boundary = RecordingPushBoundary(retryable=1)
    worker = ProcessCaregiverAlertOutbox(fk_db, boundary)
    assert worker.processDue()["failed"] == 1
    event = fk_db.query(_CaregiverAlertOutbox).one()
    assert event.attempt_count == 1 and event.sent_at is None
    event.available_at = utc_now() - timedelta(seconds=1)
    fk_db.commit()
    boundary.retryable = 0
    assert worker.processDue()["sent"] == 1
    assert boundary.calls[0]["data"] == boundary.calls[1]["data"]
    assert worker.processDue()["sent"] == 0


@pytest.mark.parametrize("language", ["ko", "en"])
@pytest.mark.parametrize("details", [True, False])
def test_prn_wording_respects_language_privacy_and_never_claims_all(fk_db, scene, language, details):
    setting = fk_db.query(_UserSetting).one()
    setting.language = language
    setting.notification_detail_mode = "details" if details else "type_only"
    fk_db.commit()
    take(fk_db, scene)
    boundary = RecordingPushBoundary()
    assert ProcessCaregiverAlertOutbox(fk_db, boundary).processDue()["sent"] == 1
    body = boundary.calls[0]["body"]
    assert "all " not in body and "모두" not in body
    assert ("as-needed" in body or "필요시" in body) == details
    assert boundary.calls[0]["data"]["language"] == language


def test_record_and_outbox_rollback_together(fk_db, scene, monkeypatch):
    care = ManageMedicationCare(fk_db)
    def fail_commit():
        raise RuntimeError("test commit failure")
    monkeypatch.setattr(fk_db, "commit", fail_commit)
    with pytest.raises(RuntimeError):
        care.update_history(principal(), scene, application_today(), f"as_needed:{uuid4()}", report())
    assert fk_db.query(_MedicationCompletion).count() == 0
    assert fk_db.query(_CaregiverAlertOutbox).count() == 0
    assert fk_db.query(_MedicationCareOperation).count() == 0
    assert care.consumeCompletionEvents() == []


def test_http_handler_schedules_committed_prn_once(fk_db, scene):
    tasks = BackgroundTasks()
    slot = f"as_needed:{uuid4()}"
    request = report()
    response = update_history(scene, application_today(), slot, request, tasks, principal(), fk_db)
    assert response["success"] and len(tasks.tasks) == 1
    assert not fk_db.in_transaction()
    assert fk_db.get(_CaregiverAlertOutbox, tasks.tasks[0].args[0]).status == "pending"
    tasks = BackgroundTasks()
    assert update_history(scene, application_today(), slot, request, tasks, principal(), fk_db) == response
    assert tasks.tasks == []


def test_snapshot_current_keys_survive_edits_include_disabled_and_omit_revoked(fk_db, scene):
    slot, _ = take(fk_db, scene)
    first = snapshot(fk_db)[0]
    assert first["as_needed_schedule_date"] == application_today().isoformat()
    assert len(first["as_needed_taken_event_keys"]) == 1
    take(fk_db, scene, slot=slot, expected_revision=1)
    assert snapshot(fk_db)[0]["as_needed_taken_event_keys"] == first["as_needed_taken_event_keys"]
    take(fk_db, scene, day=application_today() - timedelta(days=1))
    take(fk_db, scene, status="skipped")
    take(fk_db, scene, status="unrecorded")
    regular = medication(fk_db)
    ManageMedicationCare(fk_db).update_history(principal(), regular.id, application_today(), "morning", report())
    private = medication(fk_db, patient_hash="unlinked", dosing_mode="as_needed")
    fk_db.add(_MedicationCompletion(
        patient_hash="unlinked", saved_medication_id=private.id, schedule_date=application_today(),
        slot_key=f"as_needed:{uuid4()}", completed=True,
    ))
    fk_db.commit()
    SetCaregiverNotification(fk_db).saveCaregiverNotificationSetting(
        "caregiver-a", "patient-a", slot_key="as_needed", enabled=False,
    )
    assert snapshot(fk_db)[0]["as_needed_taken_event_keys"] == first["as_needed_taken_event_keys"]
    take(fk_db, scene, slot=slot, status="skipped", expected_revision=2)
    assert snapshot(fk_db)[0]["as_needed_taken_event_keys"] == []
    fk_db.query(_PatientCaregiverLink).one().linked = False
    fk_db.commit()
    assert snapshot(fk_db) == []


def test_snapshot_uses_application_day_not_utc_day(fk_db, scene, monkeypatch):
    local_now = datetime(2026, 10, 17, 0, 30, tzinfo=ZoneInfo("Asia/Seoul"))
    monkeypatch.setattr("core.application_clock.application_now", lambda: local_now)
    for day in (date(2026, 10, 16), date(2026, 10, 17), date(2026, 10, 18)):
        fk_db.add(_MedicationCompletion(
            patient_hash="patient-a", saved_medication_id=scene, schedule_date=day,
            slot_key=f"as_needed:{uuid4()}", completed=True, report_status="taken",
        ))
    fk_db.commit()
    result = snapshot(fk_db)[0]
    assert result["as_needed_schedule_date"] == "2026-10-17"
    row = fk_db.query(_MedicationCompletion).filter_by(schedule_date=local_now.date()).one()
    assert result["as_needed_taken_event_keys"] == [as_needed_taken_event_key("patient-a", scene, row.schedule_date, row.slot_key)]


def test_concurrent_prn_retries_create_one_record_and_event(tmp_path):
    engine = make_engine(tmp_path)
    factory = make_session_factory(engine)
    try:
        with factory() as db:
            med_id = medication(db, dosing_mode="as_needed").id
        slot, request, barrier = f"as_needed:{uuid4()}", report(), Barrier(2)
        def write(_):
            with factory() as db:
                barrier.wait(timeout=10)
                try:
                    ManageMedicationCare(db).update_history(principal(), med_id, application_today(), slot, request)
                    return 200
                except HTTPException as exc:
                    return exc.status_code
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(write, range(2)))
        assert 200 in results and all(result in (200, 409, 503) for result in results)
        with factory() as db:
            ManageMedicationCare(db).update_history(principal(), med_id, application_today(), slot, request)
            assert db.query(_MedicationCompletion).count() == 1
            assert db.query(_CaregiverAlertOutbox).count() == 1
    finally:
        engine.dispose()
