# File Name: test_missed_dose_queue_guards.py
# Role: Covers each condition that must hold before the missed-dose scan queues a caregiver
#   alert, and the identity of the queued events per caregiver and per day.
#
# The baseline of every test is one patient with a lunch medication and one linked caregiver
# whose lunch setting is "missed_deadline" at 13:00. The scan time 13:05 is past that deadline,
# so the baseline queues exactly one event; each guard test changes one condition.
# The patient has no saved lunch alarm, so the lunch reminder time is the product default 12:00
# and the grace period of 30 minutes ends before the baseline deadline.

from datetime import datetime, timedelta

import pytest
from sqlalchemy.orm import Session

from controls.queue_missed_dose_alerts_control import (
    QueueMissedDoseAlerts,
    missed_event_key,
)
from core.application_clock import application_now
from core.config import settings
from entities.caregiver_alert_outbox_entity import (
    CAREGIVER_ALERT_EVENT_MISSED_DEADLINE,
    _CaregiverAlertOutbox,
)
from entities.caregiver_notification_entity import (
    CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
    _CaregiverNotification,
    encode_slot_settings,
)
from entities.medication_alarm_entity import _MedicationAlarm
from entities.medication_completion_entity import _MedicationCompletion
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.saved_medication_entity import _SavedMedication
from entities.user_setting_entity import _UserSetting
from support.db import seed_account, seed_medication

PATIENT_HASH = "guard-patient"
CAREGIVER_HASH = "guard-caregiver-a"
SECOND_CAREGIVER_HASH = "guard-caregiver-b"


# Function Name: due_time
# Description:
# - Provides the scan time of the baseline: today at 13:05 application time, five minutes
#   after the configured lunch deadline.
# Parameters:
# - None.
# Returns:
# - Timezone-aware scan time.
@pytest.fixture
def due_time() -> datetime:
    return application_now().replace(hour=13, minute=5, second=0, microsecond=0)


# Function Name: lunch_medication
# Description:
# - Saves the baseline patient's lunch medication, active from the scan day for a week.
# Parameters:
# - fk_db (Session): Session on the foreign-key-enforcing test database.
# - due_time (datetime): Baseline scan time.
# Returns:
# - The persisted medication row.
@pytest.fixture
def lunch_medication(fk_db: Session, due_time: datetime) -> _SavedMedication:
    return seed_medication(
        fk_db,
        patient_hash=PATIENT_HASH,
        item_name="lunch-tablet",
        created_date=due_time.date(),
        daily_frequency="1 time",
        schedule_slot_keys='["lunch"]',
    )


# Function Name: add_caregiver
# Description:
# - Adds one caregiver account, its link to the baseline patient and its lunch setting, and
#   commits.
# Parameters:
# - db (Session): Session on the test database.
# - caregiver_hash (str): Caregiver account to create.
# - linked (bool): Whether the link is active.
# - enabled (bool): Row-level enabled flag of the setting.
# - notification_type (str): Notification mode stored for the lunch slot.
# - deadline_hour (int): Lunch deadline hour stored with the mode.
# Returns:
# - None.
def add_caregiver(
    db: Session,
    caregiver_hash: str = CAREGIVER_HASH,
    *,
    linked: bool = True,
    enabled: bool = True,
    notification_type: str = CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
    deadline_hour: int = 13,
) -> None:
    seed_account(db, PATIENT_HASH, caregiver_hash)
    db.add(
        _PatientCaregiverLink(
            patient_hash=PATIENT_HASH,
            caregiver_hash=caregiver_hash,
            linked=linked,
        )
    )
    db.add(
        _CaregiverNotification(
            patient_hash=PATIENT_HASH,
            caregiver_hash=caregiver_hash,
            enabled=enabled,
            alert_option=notification_type,
            slot_settings=encode_slot_settings(
                {
                    "lunch": {
                        "notification_type": notification_type,
                        "deadline_hour": deadline_hour,
                        "deadline_minute": 0,
                    }
                }
            ),
        )
    )
    db.commit()


# Function Name: test_due_incomplete_slot_of_linked_caregiver_is_queued
# Description:
# - The baseline queues one missed-deadline event that carries the caregiver, the patient,
#   the scan day, the slot and the stable event key.
# Parameters:
# - fk_db (Session): Session on the test database.
# - due_time (datetime): Baseline scan time.
# - lunch_medication (_SavedMedication): Baseline lunch medication.
# Returns:
# - None.
def test_due_incomplete_slot_of_linked_caregiver_is_queued(
    fk_db: Session,
    due_time: datetime,
    lunch_medication: _SavedMedication,
) -> None:
    add_caregiver(fk_db)

    assert QueueMissedDoseAlerts(fk_db).queueDue(now=due_time) == 1

    event = fk_db.query(_CaregiverAlertOutbox).one()
    assert event.event_type == CAREGIVER_ALERT_EVENT_MISSED_DEADLINE
    assert (event.caregiver_hash, event.patient_hash) == (CAREGIVER_HASH, PATIENT_HASH)
    assert (event.schedule_date, event.slot_key) == (due_time.date(), "lunch")
    assert event.event_key == missed_event_key(
        CAREGIVER_HASH, PATIENT_HASH, due_time.date(), "lunch",
    )


# Function Name: test_unlinked_caregiver_is_not_queued
# Description:
# - A caregiver whose link to the patient is no longer active receives no missed-dose event.
# Parameters:
# - fk_db (Session): Session on the test database.
# - due_time (datetime): Baseline scan time.
# - lunch_medication (_SavedMedication): Baseline lunch medication.
# Returns:
# - None.
def test_unlinked_caregiver_is_not_queued(
    fk_db: Session,
    due_time: datetime,
    lunch_medication: _SavedMedication,
) -> None:
    add_caregiver(fk_db, linked=False)

    assert QueueMissedDoseAlerts(fk_db).queueDue(now=due_time) == 0
    assert fk_db.query(_CaregiverAlertOutbox).count() == 0


# Function Name: test_disabled_setting_is_not_queued
# Description:
# - A setting row that is switched off as a whole queues nothing, even though its lunch slot
#   still stores a passed deadline.
# Parameters:
# - fk_db (Session): Session on the test database.
# - due_time (datetime): Baseline scan time.
# - lunch_medication (_SavedMedication): Baseline lunch medication.
# Returns:
# - None.
def test_disabled_setting_is_not_queued(
    fk_db: Session,
    due_time: datetime,
    lunch_medication: _SavedMedication,
) -> None:
    add_caregiver(fk_db, enabled=False)

    assert QueueMissedDoseAlerts(fk_db).queueDue(now=due_time) == 0
    assert fk_db.query(_CaregiverAlertOutbox).count() == 0


# Function Name: test_other_notification_mode_is_not_queued
# Description:
# - A slot set to completion alerts is not a missed-deadline subscription.
# Parameters:
# - fk_db (Session): Session on the test database.
# - due_time (datetime): Baseline scan time.
# - lunch_medication (_SavedMedication): Baseline lunch medication.
# Returns:
# - None.
def test_other_notification_mode_is_not_queued(
    fk_db: Session,
    due_time: datetime,
    lunch_medication: _SavedMedication,
) -> None:
    add_caregiver(
        fk_db,
        notification_type=CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
    )

    assert QueueMissedDoseAlerts(fk_db).queueDue(now=due_time) == 0
    assert fk_db.query(_CaregiverAlertOutbox).count() == 0


# Function Name: test_slot_is_not_queued_before_its_deadline
# Description:
# - One minute before the deadline nothing is queued; at the deadline itself the event is.
# Parameters:
# - fk_db (Session): Session on the test database.
# - due_time (datetime): Baseline scan time.
# - lunch_medication (_SavedMedication): Baseline lunch medication.
# Returns:
# - None.
def test_slot_is_not_queued_before_its_deadline(
    fk_db: Session,
    due_time: datetime,
    lunch_medication: _SavedMedication,
) -> None:
    add_caregiver(fk_db)
    queue = QueueMissedDoseAlerts(fk_db)

    assert queue.queueDue(now=due_time.replace(hour=12, minute=59)) == 0
    assert fk_db.query(_CaregiverAlertOutbox).count() == 0
    assert queue.queueDue(now=due_time.replace(hour=13, minute=0)) == 1


# Function Name: test_completed_slot_is_not_queued
# Description:
# - A slot whose every active medication is recorded as taken is not a missed dose, also
#   after its deadline.
# Parameters:
# - fk_db (Session): Session on the test database.
# - due_time (datetime): Baseline scan time.
# - lunch_medication (_SavedMedication): Baseline lunch medication.
# Returns:
# - None.
def test_completed_slot_is_not_queued(
    fk_db: Session,
    due_time: datetime,
    lunch_medication: _SavedMedication,
) -> None:
    add_caregiver(fk_db)
    fk_db.add(
        _MedicationCompletion(
            saved_medication_id=lunch_medication.id,
            patient_hash=PATIENT_HASH,
            schedule_date=due_time.date(),
            slot_key="lunch",
            completed=True,
        )
    )
    fk_db.commit()

    assert QueueMissedDoseAlerts(fk_db).queueDue(now=due_time) == 0
    assert fk_db.query(_CaregiverAlertOutbox).count() == 0


# Function Name: test_each_linked_caregiver_gets_its_own_event
# Description:
# - Two caregivers of the same patient each get one event for the same missed slot, and a
#   repeated scan adds none.
# Parameters:
# - fk_db (Session): Session on the test database.
# - due_time (datetime): Baseline scan time.
# - lunch_medication (_SavedMedication): Baseline lunch medication.
# Returns:
# - None.
def test_each_linked_caregiver_gets_its_own_event(
    fk_db: Session,
    due_time: datetime,
    lunch_medication: _SavedMedication,
) -> None:
    add_caregiver(fk_db)
    add_caregiver(fk_db, SECOND_CAREGIVER_HASH)
    queue = QueueMissedDoseAlerts(fk_db)

    assert queue.queueDue(now=due_time) == 2
    assert queue.queueDue(now=due_time) == 0

    events = fk_db.query(_CaregiverAlertOutbox).all()
    assert sorted(str(event.caregiver_hash) for event in events) == [
        CAREGIVER_HASH,
        SECOND_CAREGIVER_HASH,
    ]
    assert len({event.event_key for event in events}) == 2


# Function Name: test_next_day_queues_a_new_event
# Description:
# - The same slot missed again on the following day is a new event with its own key and
#   schedule date; the first day's event does not suppress it.
# Parameters:
# - fk_db (Session): Session on the test database.
# - due_time (datetime): Baseline scan time.
# - lunch_medication (_SavedMedication): Baseline lunch medication.
# Returns:
# - None.
def test_next_day_queues_a_new_event(
    fk_db: Session,
    due_time: datetime,
    lunch_medication: _SavedMedication,
) -> None:
    add_caregiver(fk_db)
    queue = QueueMissedDoseAlerts(fk_db)
    next_day = due_time + timedelta(days=1)

    assert queue.queueDue(now=due_time) == 1
    assert queue.queueDue(now=next_day) == 1
    assert queue.queueDue(now=next_day) == 0

    events = fk_db.query(_CaregiverAlertOutbox).order_by(_CaregiverAlertOutbox.id).all()
    assert [event.schedule_date for event in events] == [
        due_time.date(),
        next_day.date(),
    ]
    assert events[0].event_key != events[1].event_key


# Function Name: test_deadline_before_the_reminder_waits_for_the_reminder_and_grace
# Description:
# - A deadline of 11:00 for a slot the patient is reminded of at 12:00 queues nothing at the
#   deadline or at the reminder time; the event is queued once the grace period has passed.
# Parameters:
# - fk_db (Session): Session on the test database.
# - due_time (datetime): Baseline scan time; supplies the day.
# - lunch_medication (_SavedMedication): Baseline lunch medication.
# Returns:
# - None; fails if the day's only event is spent before the patient was reminded.
def test_deadline_before_the_reminder_waits_for_the_reminder_and_grace(
    fk_db: Session,
    due_time: datetime,
    lunch_medication: _SavedMedication,
) -> None:
    add_caregiver(fk_db, deadline_hour=11)
    queue = QueueMissedDoseAlerts(fk_db)

    assert queue.queueDue(now=due_time.replace(hour=11, minute=5)) == 0
    assert queue.queueDue(now=due_time.replace(hour=12, minute=0)) == 0
    assert queue.queueDue(now=due_time.replace(hour=12, minute=29)) == 0
    assert fk_db.query(_CaregiverAlertOutbox).count() == 0
    assert queue.queueDue(now=due_time.replace(hour=12, minute=30)) == 1


# Function Name: test_patient_reminder_time_moves_the_earliest_alert
# Description:
# - The reminder time is the patient's own: a saved alarm time, also of an alarm that is
#   switched off, or the patient's default for the slot. The baseline deadline of 13:00 is
#   held back until that time plus the grace period.
# Parameters:
# - fk_db (Session): Session on the test database.
# - due_time (datetime): Baseline scan time; supplies the day.
# - lunch_medication (_SavedMedication): Baseline lunch medication.
# - source (str): Where the patient's lunch time of 14:10 is stored.
# Returns:
# - None.
@pytest.mark.parametrize("source", ["enabled_alarm", "disabled_alarm", "default_time"])
def test_patient_reminder_time_moves_the_earliest_alert(
    fk_db: Session,
    due_time: datetime,
    lunch_medication: _SavedMedication,
    source: str,
) -> None:
    add_caregiver(fk_db)
    if source == "default_time":
        fk_db.add(_UserSetting(user_hash=PATIENT_HASH, default_lunch_time="14:10"))
    else:
        fk_db.add(
            _MedicationAlarm(
                patient_hash=PATIENT_HASH, slot_key="lunch", hour=14, minute=10,
                enabled=source == "enabled_alarm",
            )
        )
    fk_db.commit()
    queue = QueueMissedDoseAlerts(fk_db)

    assert queue.queueDue(now=due_time) == 0
    assert queue.queueDue(now=due_time.replace(hour=14, minute=39)) == 0
    assert queue.queueDue(now=due_time.replace(hour=14, minute=40)) == 1


# Function Name: test_reminder_late_in_the_evening_is_still_reported_the_same_day
# Description:
# - When the reminder time plus the grace period would fall on the next day, the slot becomes
#   reportable at 23:59, because the scan never looks back at the previous day.
# Parameters:
# - fk_db (Session): Session on the test database.
# - due_time (datetime): Baseline scan time; supplies the day.
# - lunch_medication (_SavedMedication): Baseline lunch medication.
# Returns:
# - None; fails if a late reminder makes the missed dose unreportable.
def test_reminder_late_in_the_evening_is_still_reported_the_same_day(
    fk_db: Session,
    due_time: datetime,
    lunch_medication: _SavedMedication,
) -> None:
    add_caregiver(fk_db)
    fk_db.add(
        _MedicationAlarm(
            patient_hash=PATIENT_HASH, slot_key="lunch", hour=23, minute=45, enabled=True,
        )
    )
    fk_db.commit()
    queue = QueueMissedDoseAlerts(fk_db)

    assert queue.queueDue(now=due_time.replace(hour=23, minute=58)) == 0
    assert queue.queueDue(now=due_time.replace(hour=23, minute=59)) == 1


# Function Name: test_grace_period_is_configurable
# Description:
# - With a grace period of zero a deadline before the reminder is reported at the reminder
#   time itself, and still not before it.
# Parameters:
# - fk_db (Session): Session on the test database.
# - due_time (datetime): Baseline scan time; supplies the day.
# - lunch_medication (_SavedMedication): Baseline lunch medication.
# - monkeypatch (pytest.MonkeyPatch): Sets the grace period for this test.
# Returns:
# - None.
def test_grace_period_is_configurable(
    fk_db: Session,
    due_time: datetime,
    lunch_medication: _SavedMedication,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "CAREGIVER_MISSED_DOSE_GRACE_MINUTES", 0)
    add_caregiver(fk_db, deadline_hour=11)
    queue = QueueMissedDoseAlerts(fk_db)

    assert queue.queueDue(now=due_time.replace(hour=11, minute=59)) == 0
    assert queue.queueDue(now=due_time.replace(hour=12, minute=0)) == 1
