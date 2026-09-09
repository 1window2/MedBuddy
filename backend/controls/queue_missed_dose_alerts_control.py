"""Queue bounded, idempotent caregiver alerts after configured dose deadlines."""

import hashlib
from datetime import datetime, time

from sqlalchemy.dialects.postgresql import insert as postgresql_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from controls.check_schedule_control import CheckSchedule
from core.application_clock import application_now
from entities.caregiver_alert_outbox_entity import (
    CAREGIVER_ALERT_EVENT_MISSED_DEADLINE,
    _CaregiverAlertOutbox,
)
from entities.caregiver_notification_entity import (
    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
    _CaregiverNotification,
    decode_slot_settings,
)
from entities.patient_caregiver_link_entity import _PatientCaregiverLink


class QueueMissedDoseAlerts:
    """Finds due caregiver deadlines and records at most one event per day/slot."""

    def __init__(
        self,
        db: Session,
        check_schedule: CheckSchedule | None = None,
    ) -> None:
        self.db = db
        self.check_schedule = check_schedule or CheckSchedule(db)

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
        for row in rows:
            caregiver_hash = str(row.caregiver_hash)
            patient_hash = str(row.patient_hash)
            for slot_key, slot_setting in decode_slot_settings(
                row.slot_settings
            ).items():
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
                event_source = (
                    "missed_deadline:"
                    f"{caregiver_hash}:{patient_hash}:"
                    f"{schedule_date.isoformat()}:{slot_key}"
                )
                if self._insert_event(
                    {
                        "event_key": hashlib.sha256(
                            event_source.encode("utf-8")
                        ).hexdigest(),
                        "event_type": CAREGIVER_ALERT_EVENT_MISSED_DEADLINE,
                        "caregiver_hash": caregiver_hash,
                        "patient_hash": patient_hash,
                        "schedule_date": schedule_date,
                        "slot_key": slot_key,
                    }
                ):
                    queued_count += 1
        self.db.commit()
        return queued_count

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
