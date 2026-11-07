# File Name: manage_caregiver_alert_control.py
# Role: Authorizes missed-dose alert actions and persists idempotent snooze deliveries.
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
from repositories.patient_caregiver_link_repository import (
    PatientCaregiverLinkRepository,
)


# Class Name: ManageCaregiverAlert
# Role: Coordinates actions on caregiver-owned missed-dose deliveries without changing medication records.
# Responsibilities: Recheck active links and current missed status, deduplicate snoozes and expose eligible demo deliveries.
# Attributes: db (Session) is the transaction session; link_repository resolves current patient-caregiver links.
class ManageCaregiverAlert:
    """Keep account authority on the server; never update medication or alarm rows."""

    # Function Name: __init__
    # Description: Binds delivery actions and link authorization to the same database session.
    # Parameters: db (Session) is the caller's session.
    # Returns: None; does not query or commit.
    def __init__(self, db: Session) -> None:
        self.db = db
        self.link_repository = PatientCaregiverLinkRepository(db)

    # Function Name: requireSource
    # Description: Resolves an owned missed-dose delivery, its original event and an active caregiver link.
    # Parameters: alert_id (int) identifies this delivery; caregiver_hash (str) is the authorized caller's scope.
    # Returns: (delivery, original event, link); HTTP 404 for missing/foreign deliveries or inactive links, 410 for an expired original.
    def requireSource(self, alert_id: int, caregiver_hash: str):
        """Resolve an owned delivery and its original event under an active link."""
        row = self.db.get(_CaregiverAlertOutbox, alert_id)
        if (row is None or row.event_type != CAREGIVER_ALERT_EVENT_MISSED_DEADLINE
                or row.caregiver_hash != caregiver_hash or row.schedule_date is None):
            raise HTTPException(404, "Caregiver alert was not found.")
        link = self.link_repository.find_active_for_caregiver(
            caregiver_hash, str(row.patient_hash),
        )
        if link is None:
            raise HTTPException(404, "Active caregiver link was not found.")
        root_key = missed_event_key(caregiver_hash, str(row.patient_hash), row.schedule_date, str(row.slot_key))
        # event_key is unique, so a first delivery is its own original event; only snoozes look it up.
        root = (row if row.event_key == root_key
                else self.db.query(_CaregiverAlertOutbox).filter_by(event_key=root_key).first())
        if root is None:
            raise HTTPException(410, "The original caregiver alert has expired.")
        return row, root, link

    # Function Name: requireActionable
    # Description: Requires an already-released delivery whose date, link, settings, deadline and incomplete slot still permit action.
    # Parameters: row (_CaregiverAlertOutbox) is a previously authorized missed-dose event.
    # Returns: None when actionable; raises HTTP 409 otherwise. Does not send a push.
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

    # Function Name: context
    # Description: Revalidates delivery ownership and builds action data with both root-event and current-delivery identities.
    # Parameters: row (_CaregiverAlertOutbox) supplies the delivery ID and caregiver scope.
    # Returns: String-valued action context; source/link validation errors propagate.
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

    # Function Name: snooze
    # Description: Reuses one child per delivered event or commits a new actionable child available ten minutes later, recovering duplicate-insert races.
    # Parameters: alert_id (int) is the source delivery; caregiver_hash (str) is its authorized owner.
    # Returns: Success receipt with created flag; authority/actionability errors and unrecoverable database errors propagate.
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

    # Function Name: _receipt
    # Description: Formats a snooze delivery without exposing medication data.
    # Parameters: row (_CaregiverAlertOutbox) supplies persisted delivery fields; created (bool) distinguishes creation from replay.
    # Returns: Success envelope with alert/event IDs, status and UTC availability timestamp.
    def _receipt(self, row: _CaregiverAlertOutbox, *, created: bool) -> dict[str, object]:
        return {"success": True, "created": created, "data": {
            "alert_id": row.id, "event_id": row.event_key, "status": row.status,
            "available_at": row.available_at.isoformat() + "Z",
        }}

    # Function Name: localDeliveries
    # Description: Reads up to 200 recent sent deliveries for today and excludes events that no longer have valid actions or source links.
    # Parameters: caregiver_hash (str) is the authorized scope; the router must restrict this operation to disabled-auth demo mode.
    # Returns: Action contexts in descending delivery order; skips HTTP validation failures and propagates database errors.
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
