# File Name: queue_missed_dose_alerts_control.py
# Role: Queues bounded, idempotent caregiver alerts after configured dose deadlines.

import hashlib
from datetime import date, datetime, time, timedelta

from sqlalchemy.dialects.postgresql import insert as postgresql_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from controls.check_schedule_control import CheckSchedule
from controls.set_notification_control import SetNotification
from core.application_clock import application_now
from core.config import settings
from entities.caregiver_alert_outbox_entity import (
    CAREGIVER_ALERT_EVENT_MISSED_DEADLINE,
    _CaregiverAlertOutbox,
)
from entities.caregiver_notification_entity import (
    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
    _CaregiverNotification,
    effective_slot_settings,
)
from entities.patient_caregiver_link_entity import _PatientCaregiverLink


def missed_event_key(caregiver_hash: str, patient_hash: str, schedule_date, slot_key: str) -> str:
    """Return the stable original missed-dose identity, independent of deliveries."""
    source = f"missed_deadline:{caregiver_hash}:{patient_hash}:{schedule_date.isoformat()}:{slot_key}"
    return hashlib.sha256(source.encode("utf-8")).hexdigest()


# Class Name: QueueMissedDoseAlerts
# Role: Finds due caregiver deadlines and persists durable delivery work.
# Responsibilities:
# - Check explicit missed-deadline preferences only for active caregiver links.
# - Never report a slot before the patient's own reminder time for it plus a grace period,
#   whatever deadline the caregiver stored.
# - Reuse schedule-course and completion rules to detect genuinely incomplete slots.
# - Insert at most one event for each caregiver, patient, date, and slot.
# Attributes:
# - db: SQLAlchemy session used for settings, schedule, and outbox access.
# - check_schedule: Schedule control used to evaluate the current completion state.
class QueueMissedDoseAlerts:

    def __init__(
        self,
        db: Session,
        check_schedule: CheckSchedule | None = None,
    ) -> None:
        self.db = db
        self.check_schedule = check_schedule or CheckSchedule(db)

    # Function Name: queueDue
    # Description:
    # - Scans active caregiver settings and queues overdue incomplete slots.
    # - Reads today's already queued event keys once, so a slot that was handled on an
    #   earlier scan costs neither a schedule lookup nor a conflicting insert.
    # - A deadline earlier than the patient's reminder for the slot is held back until the
    #   reminder time plus the grace period: the one event of the day must not be spent on a
    #   dose the patient has not been reminded of yet.
    # Parameters:
    # - now: Optional application-time override for deterministic execution.
    # - limit: Maximum number of newly queued events for this scan.
    # Returns:
    # - Number of new outbox events inserted; existing idempotency keys are excluded.
    def queueDue(
        self,
        *,
        now: datetime | None = None,
        limit: int = 200,
    ) -> int:
        current_time = now or application_now()
        schedule_date = current_time.date()
        rows = (
            self.db.query(_CaregiverNotification)
            .join(
                _PatientCaregiverLink,
                (_PatientCaregiverLink.patient_hash == _CaregiverNotification.patient_hash)
                & (
                    _PatientCaregiverLink.caregiver_hash
                    == _CaregiverNotification.caregiver_hash
                ),
            )
            .filter(
                _PatientCaregiverLink.linked.is_(True),
                _CaregiverNotification.enabled.is_(True),
            )
            .order_by(_CaregiverNotification.id.asc())
            .all()
        )
        queued_count = 0
        pending_by_patient_slot: dict[tuple[str, str], bool] = {}
        reminder_times_by_patient: dict[str, dict[str, tuple[int, int]]] = {}
        queued_event_keys: set[str] | None = None
        for row in rows:
            caregiver_hash = str(row.caregiver_hash)
            patient_hash = str(row.patient_hash)
            # Legacy rows without per-slot JSON follow the same seeding as the settings screen.
            for slot_key, slot_setting in effective_slot_settings(row).items():
                if queued_count >= max(1, min(limit, 1_000)):
                    self.db.commit()
                    return queued_count
                if (
                    slot_setting.get("notification_type")
                    != CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE
                ):
                    continue
                deadline = self._deadline(current_time, slot_setting)
                if deadline is None or current_time < deadline:
                    continue
                if queued_event_keys is None:
                    queued_event_keys = self._queued_event_keys(schedule_date)
                event_key = missed_event_key(
                    caregiver_hash, patient_hash, schedule_date, slot_key,
                )
                if event_key in queued_event_keys:
                    continue
                if patient_hash not in reminder_times_by_patient:
                    reminder_times_by_patient[patient_hash] = self._reminder_times(
                        patient_hash,
                    )
                if current_time < self._earliest_alert_time(
                    current_time,
                    reminder_times_by_patient[patient_hash].get(slot_key),
                ):
                    continue
                pending_key = (patient_hash, slot_key)
                is_incomplete = pending_by_patient_slot.get(pending_key)
                if is_incomplete is None:
                    is_incomplete = self.check_schedule.isMedicationSlotIncomplete(
                        patient_hash=patient_hash,
                        schedule_date=schedule_date,
                        slot_key=slot_key,
                    )
                    pending_by_patient_slot[pending_key] = is_incomplete
                if not is_incomplete:
                    continue
                if self._insert_event(
                    {
                        "event_key": event_key,
                        "event_type": CAREGIVER_ALERT_EVENT_MISSED_DEADLINE,
                        "caregiver_hash": caregiver_hash,
                        "patient_hash": patient_hash,
                        "schedule_date": schedule_date,
                        "slot_key": slot_key,
                    }
                ):
                    queued_count += 1
                # Inserted now or lost to a concurrent writer: either way the key exists.
                queued_event_keys.add(event_key)
        self.db.commit()
        return queued_count

    # Function Name: _queued_event_keys
    # Description:
    # - Loads the idempotency keys of the missed-dose events already queued for one day.
    # - Read on every scan, so the unique event key stays the only source of truth.
    # Parameters:
    # - schedule_date: Application-local date whose events are checked.
    # Returns:
    # - Set of existing event keys for that date.
    def _queued_event_keys(self, schedule_date: date) -> set[str]:
        return {
            str(event_key)
            for (event_key,) in self.db.query(_CaregiverAlertOutbox.event_key).filter(
                _CaregiverAlertOutbox.event_type
                == CAREGIVER_ALERT_EVENT_MISSED_DEADLINE,
                _CaregiverAlertOutbox.schedule_date == schedule_date,
            )
        }

    # Function Name: _deadline
    # Description: Combines a slot's configured hour and minute with today's date.
    # Parameters:
    # - current_time: Timezone-aware application time defining the date and zone.
    # - slot_setting: Decoded per-slot caregiver preference.
    # Returns:
    # - A timezone-aware deadline, or None when the stored values are invalid.
    @staticmethod
    def _deadline(
        current_time: datetime,
        slot_setting: dict[str, object],
    ) -> datetime | None:
        try:
            hour = int(slot_setting.get("deadline_hour"))
            minute = int(slot_setting.get("deadline_minute"))
            deadline_time = time(hour=hour, minute=minute)
        except (TypeError, ValueError):
            return None
        return datetime.combine(
            current_time.date(),
            deadline_time,
            tzinfo=current_time.tzinfo,
        )

    # Function Name: _reminder_times
    # Description:
    # - Reads the patient's reminder time of every slot: the saved alarm time, enabled or
    #   not, or the default the patient's app shows for a slot without a saved alarm.
    # Parameters:
    # - patient_hash: Patient whose slots are checked.
    # Returns:
    # - (hour, minute) by slot key.
    def _reminder_times(self, patient_hash: str) -> dict[str, tuple[int, int]]:
        alarms = SetNotification(self.db).requestMedicationAlarm(patient_hash)["data"]
        return {
            str(alarm["slot_key"]): (int(alarm["hour"]), int(alarm["minute"]))
            for alarm in alarms
        }

    # Function Name: _earliest_alert_time
    # Description:
    # - Computes the first moment a slot may be reported as missed today: its reminder time
    #   plus CAREGIVER_MISSED_DOSE_GRACE_MINUTES, kept within the day at 23:59 because the
    #   scan only looks at the current day.
    # Parameters:
    # - current_time: Timezone-aware application time defining the date and zone.
    # - reminder_time: (hour, minute) of the patient's reminder; None when the slot is unknown.
    # Returns:
    # - Timezone-aware earliest alert time; the start of the day when there is no reminder time.
    @staticmethod
    def _earliest_alert_time(
        current_time: datetime,
        reminder_time: tuple[int, int] | None,
    ) -> datetime:
        day = current_time.date()
        if reminder_time is None:
            return datetime.combine(day, time.min, tzinfo=current_time.tzinfo)
        reminded_at = datetime.combine(
            day, time(hour=reminder_time[0], minute=reminder_time[1]),
            tzinfo=current_time.tzinfo,
        )
        return min(
            reminded_at + timedelta(minutes=settings.CAREGIVER_MISSED_DOSE_GRACE_MINUTES),
            datetime.combine(day, time(hour=23, minute=59), tzinfo=current_time.tzinfo),
        )

    # Function Name: _insert_event
    # Description: Inserts an outbox event without failing on an existing event key.
    # Parameters:
    # - values: Validated outbox column values for one missed-dose event.
    # Returns:
    # - True only when this call created a new row.
    def _insert_event(self, values: dict[str, object]) -> bool:
        dialect_name = self.db.get_bind().dialect.name
        if dialect_name == "postgresql":
            result = self.db.execute(
                postgresql_insert(_CaregiverAlertOutbox)
                .values(**values)
                .on_conflict_do_nothing(index_elements=["event_key"])
            )
            return result.rowcount == 1
        if dialect_name == "sqlite":
            result = self.db.execute(
                sqlite_insert(_CaregiverAlertOutbox)
                .values(**values)
                .on_conflict_do_nothing(index_elements=["event_key"])
            )
            return result.rowcount == 1
        try:
            with self.db.begin_nested():
                self.db.add(_CaregiverAlertOutbox(**values))
                self.db.flush()
            return True
        except IntegrityError:
            return False
