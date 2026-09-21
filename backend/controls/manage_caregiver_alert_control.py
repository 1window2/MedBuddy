"""Authorize missed-dose actions and schedule durable, idempotent deliveries."""

import hashlib
from datetime import timedelta

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from boundaries.push_notification_boundary import DisabledPushNotificationBoundary
from controls.dispatch_caregiver_alert_control import DispatchCaregiverAlert
from controls.queue_missed_dose_alerts_control import missed_event_key
from core.application_clock import application_today
from entities.caregiver_alert_outbox_entity import (
    _CaregiverAlertOutbox, CAREGIVER_ALERT_EVENT_MISSED_DEADLINE, utc_now,
)
from entities.patient_caregiver_link_entity import _PatientCaregiverLink


class ManageCaregiverAlert:
    """Keep account authority on the server; never update medication or alarm rows."""

    def __init__(self, db: Session) -> None:
        self.db = db

    def requireSource(self, alert_id: int, caregiver_hash: str):
        """Resolve an owned delivery and its original event under an active link."""
        row = self.db.get(_CaregiverAlertOutbox, alert_id)
        if (row is None or row.event_type != CAREGIVER_ALERT_EVENT_MISSED_DEADLINE
                or row.caregiver_hash != caregiver_hash or row.schedule_date is None):
            raise HTTPException(404, "Caregiver alert was not found.")
        link = self.db.query(_PatientCaregiverLink).filter(
            _PatientCaregiverLink.caregiver_hash == caregiver_hash,
            _PatientCaregiverLink.patient_hash == row.patient_hash,
            _PatientCaregiverLink.linked.is_(True),
        ).first()
        if link is None:
            raise HTTPException(404, "Active caregiver link was not found.")
        root_key = missed_event_key(caregiver_hash, str(row.patient_hash), row.schedule_date, str(row.slot_key))
        root = self.db.query(_CaregiverAlertOutbox).filter_by(event_key=root_key).first()
        if root is None:
            raise HTTPException(410, "The original caregiver alert has expired.")
        return row, root, link

    def requireActionable(self, row: _CaregiverAlertOutbox) -> None:
        """Only already released, still-current missed events accept a new action."""
        released = row.status in ("sent", "processing") or (
            row.status in ("failed", "dead_letter") and int(row.attempt_count or 0) > 0
        )
        if (not released
                or not DispatchCaregiverAlert(self.db, DisabledPushNotificationBoundary()).isMissedSlotActionable(
                    caregiver_hash=str(row.caregiver_hash), patient_hash=str(row.patient_hash),
                    slot_key=str(row.slot_key), schedule_date=row.schedule_date,
                )):
            raise HTTPException(409, "This missed-dose alert is no longer actionable.")

    def context(self, row: _CaregiverAlertOutbox) -> dict[str, str]:
        """Carry both the original event and this delivery through FCM/local actions."""
        row, root, link = self.requireSource(int(row.id), str(row.caregiver_hash))
        return {
            "type": "caregiver_slot_missed", "action_version": "1",
            "patient_hash": str(row.patient_hash), "recipient_hash": str(row.caregiver_hash),
            "slot_key": str(row.slot_key), "schedule_date": row.schedule_date.isoformat(),
            "source_alert_id": str(root.id), "alert_id": str(row.id),
            "source_event_id": str(root.event_key), "event_id": str(row.event_key),
            "link_id": str(link.id),
        }

    def snooze(self, alert_id: int, caregiver_hash: str) -> dict[str, object]:
        """One child per delivered event; a delivered child can itself be snoozed."""
        source, _, _ = self.requireSource(alert_id, caregiver_hash)
        key = hashlib.sha256(f"snooze:{source.event_key}".encode()).hexdigest()
        existing = self.db.query(_CaregiverAlertOutbox).filter_by(event_key=key).first()
        if existing is not None:
            return self._receipt(existing, created=False)
        self.requireActionable(source)
        row = _CaregiverAlertOutbox(
            event_key=key, event_type=CAREGIVER_ALERT_EVENT_MISSED_DEADLINE,
            caregiver_hash=caregiver_hash, patient_hash=source.patient_hash,
            schedule_date=source.schedule_date, slot_key=source.slot_key,
            available_at=utc_now() + timedelta(minutes=10),
        )
        created = True
        try:
            with self.db.begin_nested():
                self.db.add(row)
                self.db.flush()
        except IntegrityError:
            created = False
            row = self.db.query(_CaregiverAlertOutbox).filter_by(event_key=key).one()
        self.db.commit()
        return self._receipt(row, created=created)

    def _receipt(self, row: _CaregiverAlertOutbox, *, created: bool) -> dict[str, object]:
        return {"success": True, "created": created, "data": {
            "alert_id": row.id, "event_id": row.event_key, "status": row.status,
            "available_at": row.available_at.isoformat() + "Z",
        }}

    def localDeliveries(self, caregiver_hash: str) -> list[dict[str, str]]:
        """Expose released server events for the explicitly disabled-auth demo only."""
        rows = self.db.query(_CaregiverAlertOutbox).filter(
            _CaregiverAlertOutbox.caregiver_hash == caregiver_hash,
            _CaregiverAlertOutbox.event_type == CAREGIVER_ALERT_EVENT_MISSED_DEADLINE,
            _CaregiverAlertOutbox.schedule_date == application_today(),
            _CaregiverAlertOutbox.status == "sent",
            _CaregiverAlertOutbox.available_at <= utc_now(),
        ).order_by(_CaregiverAlertOutbox.id.desc()).limit(200).all()
        result = []
        for row in rows:
            try:
                self.requireActionable(row)
                result.append(self.context(row))
            except HTTPException:
                continue
        return result
