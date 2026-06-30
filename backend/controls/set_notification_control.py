# File Name: set_notification_control.py
# Role: Control class for patient medication alarm settings.

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from controls.link_patient_caregiver_control import LinkPatientCaregiver
from entities.notification_setting_entity import (
    NotificationSetting,
    _NotificationSetting,
    default_notification_hour,
    valid_notification_slot_keys,
)
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH, normalize_patient_hash


_GUARDIAN_ROLES = {"guardian", "caregiver"}


# Class Name: SetNotification
# Role: Coordinates patient notification settings.
# Responsibilities:
#   - Read medication alarm state by patient and schedule slot.
#   - Persist enabled medication alarms with selected local times.
#   - Disable medication alarms while preserving the last selected time.
# Attributes:
#   - db: SQLAlchemy session used for persistence operations.
class SetNotification:
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: requestNotificationSetting
    # Description:
    # - Class diagram compatible wrapper for notification setting lookup.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope alarm settings.
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # Returns:
    # - API-compatible notification setting list dictionary.
    def requestNotificationSetting(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        return self.request_notification_setting(patient_hash, user_hash, role)

    # Function Name: request_notification_setting
    # Description:
    # - Reads all slot alarm settings for one patient scope.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope alarm settings.
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # Returns:
    # - API-compatible notification setting list dictionary.
    def request_notification_setting(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        normalized_patient_hash = self._resolve_patient_hash(
            patient_hash,
            user_hash,
            role,
        )
        rows = {
            row.slot_key: row
            for row in (
                self.db.query(_NotificationSetting)
                .filter(_NotificationSetting.patient_hash == normalized_patient_hash)
                .all()
            )
        }
        return {
            "success": True,
            "message": "Notification settings lookup succeeded.",
            "data": [
                self._to_response_dict(
                    rows.get(slot_key)
                    or self._default_setting_row(normalized_patient_hash, slot_key)
                )
                for slot_key in valid_notification_slot_keys()
            ],
        }

    # Function Name: requestAlarmToggle
    # Description:
    # - Reads one slot alarm status before a UI toggle decision.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope alarm settings.
    # - slot_key: Medication schedule time slot.
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # Returns:
    # - API-compatible notification setting dictionary.
    def requestAlarmToggle(
        self,
        patient_hash: str,
        slot_key: str,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        return self.get_alarm_status(patient_hash, slot_key, user_hash, role)

    # Function Name: get_alarm_status
    # Description:
    # - Reads one slot alarm status with default fallback.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope alarm settings.
    # - slot_key: Medication schedule time slot.
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # Returns:
    # - API-compatible notification setting dictionary.
    def get_alarm_status(
        self,
        patient_hash: str,
        slot_key: str,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        normalized_patient_hash = self._resolve_patient_hash(
            patient_hash,
            user_hash,
            role,
        )
        normalized_slot_key = self._normalize_slot_key(slot_key)
        setting = self._find_setting(normalized_patient_hash, normalized_slot_key)
        return {
            "success": True,
            "message": "Notification setting lookup succeeded.",
            "data": self._to_response_dict(
                setting
                or self._default_setting_row(
                    normalized_patient_hash,
                    normalized_slot_key,
                )
            ),
        }

    # Function Name: setMedicationAlarm
    # Description:
    # - Class diagram compatible wrapper for enabling one slot alarm.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope alarm settings.
    # - slot_key: Medication schedule time slot.
    # - hour: 24-hour local alarm hour.
    # - minute: Local alarm minute.
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # Returns:
    # - API-compatible enabled notification setting dictionary.
    def setMedicationAlarm(
        self,
        patient_hash: str,
        slot_key: str,
        hour: int,
        minute: int,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        return self.set_medication_alarm(
            patient_hash,
            slot_key,
            hour,
            minute,
            user_hash,
            role,
        )

    # Function Name: set_medication_alarm
    # Description:
    # - Creates or updates one enabled slot alarm.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope alarm settings.
    # - slot_key: Medication schedule time slot.
    # - hour: 24-hour local alarm hour.
    # - minute: Local alarm minute.
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # Returns:
    # - API-compatible enabled notification setting dictionary.
    def set_medication_alarm(
        self,
        patient_hash: str,
        slot_key: str,
        hour: int,
        minute: int,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        normalized_patient_hash = self._resolve_patient_hash(
            patient_hash,
            user_hash,
            role,
        )
        normalized_slot_key = self._normalize_slot_key(slot_key)
        self._validate_alarm_time(hour, minute)

        try:
            setting = self._find_setting(normalized_patient_hash, normalized_slot_key)
            if setting is None:
                setting = _NotificationSetting(
                    patient_hash=normalized_patient_hash,
                    slot_key=normalized_slot_key,
                )
                self.db.add(setting)
            setting.hour = hour
            setting.minute = minute
            setting.enabled = True
            self.db.commit()
            self.db.refresh(setting)
            return {
                "success": True,
                "message": "Notification setting was saved.",
                "data": self._to_response_dict(setting),
            }
        except IntegrityError:
            self.db.rollback()
            return self._update_existing_alarm_after_conflict(
                normalized_patient_hash,
                normalized_slot_key,
                hour,
                minute,
            )
        except Exception as exc:
            self.db.rollback()
            raise HTTPException(
                status_code=500,
                detail=f"Notification setting save failed: {exc}",
            ) from exc

    # Function Name: disableAlarmSetting
    # Description:
    # - Class diagram compatible wrapper for disabling one slot alarm.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope alarm settings.
    # - slot_key: Medication schedule time slot.
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # Returns:
    # - API-compatible disabled notification setting dictionary.
    def disableAlarmSetting(
        self,
        patient_hash: str,
        slot_key: str,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        return self.disable_alarm_setting(patient_hash, slot_key, user_hash, role)

    # Function Name: disable_alarm_setting
    # Description:
    # - Disables one slot alarm while preserving its selected time.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope alarm settings.
    # - slot_key: Medication schedule time slot.
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # Returns:
    # - API-compatible disabled notification setting dictionary.
    def disable_alarm_setting(
        self,
        patient_hash: str,
        slot_key: str,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        normalized_patient_hash = self._resolve_patient_hash(
            patient_hash,
            user_hash,
            role,
        )
        normalized_slot_key = self._normalize_slot_key(slot_key)

        try:
            setting = self._find_setting(normalized_patient_hash, normalized_slot_key)
            if setting is None:
                setting = _NotificationSetting(
                    patient_hash=normalized_patient_hash,
                    slot_key=normalized_slot_key,
                    hour=default_notification_hour(normalized_slot_key),
                    minute=0,
                    enabled=False,
                )
                self.db.add(setting)
            setting.enabled = False
            self.db.commit()
            self.db.refresh(setting)
            return {
                "success": True,
                "message": "Notification setting was disabled.",
                "data": self._to_response_dict(setting),
            }
        except IntegrityError:
            self.db.rollback()
            return self._disable_existing_alarm_after_conflict(
                normalized_patient_hash,
                normalized_slot_key,
            )
        except Exception as exc:
            self.db.rollback()
            raise HTTPException(
                status_code=500,
                detail=f"Notification setting disable failed: {exc}",
            ) from exc

    def _resolve_patient_hash(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> str:
        normalized_role = (role or "patient").strip().lower()
        if normalized_role in _GUARDIAN_ROLES:
            return LinkPatientCaregiver(self.db).get_linked_patient_hash(
                user_hash or patient_hash,
                patient_hash,
            )
        return normalize_patient_hash(user_hash or patient_hash)

    def _find_setting(
        self,
        patient_hash: str,
        slot_key: str,
    ) -> _NotificationSetting | None:
        return (
            self.db.query(_NotificationSetting)
            .filter(
                _NotificationSetting.patient_hash == patient_hash,
                _NotificationSetting.slot_key == slot_key,
            )
            .first()
        )

    def _normalize_slot_key(self, slot_key: str) -> str:
        normalized_slot_key = (slot_key or "").strip().lower()
        if normalized_slot_key not in valid_notification_slot_keys():
            raise HTTPException(
                status_code=400,
                detail="Requested alarm slot is not supported.",
            )
        return normalized_slot_key

    def _validate_alarm_time(self, hour: int, minute: int) -> None:
        if hour < 0 or hour > 23:
            raise HTTPException(status_code=400, detail="Alarm hour is invalid.")
        if minute < 0 or minute > 59:
            raise HTTPException(status_code=400, detail="Alarm minute is invalid.")

    def _update_existing_alarm_after_conflict(
        self,
        patient_hash: str,
        slot_key: str,
        hour: int,
        minute: int,
    ) -> dict[str, object]:
        setting = self._find_setting(patient_hash, slot_key)
        if setting is None:
            raise HTTPException(
                status_code=409,
                detail="Notification setting conflict could not be resolved.",
            )
        try:
            setting.hour = hour
            setting.minute = minute
            setting.enabled = True
            self.db.commit()
            self.db.refresh(setting)
            return {
                "success": True,
                "message": "Notification setting was saved.",
                "data": self._to_response_dict(setting),
            }
        except Exception as exc:
            self.db.rollback()
            raise HTTPException(
                status_code=500,
                detail=f"Notification setting save failed: {exc}",
            ) from exc

    def _disable_existing_alarm_after_conflict(
        self,
        patient_hash: str,
        slot_key: str,
    ) -> dict[str, object]:
        setting = self._find_setting(patient_hash, slot_key)
        if setting is None:
            raise HTTPException(
                status_code=409,
                detail="Notification setting conflict could not be resolved.",
            )
        try:
            setting.enabled = False
            self.db.commit()
            self.db.refresh(setting)
            return {
                "success": True,
                "message": "Notification setting was disabled.",
                "data": self._to_response_dict(setting),
            }
        except Exception as exc:
            self.db.rollback()
            raise HTTPException(
                status_code=500,
                detail=f"Notification setting disable failed: {exc}",
            ) from exc

    def _default_setting_row(
        self,
        patient_hash: str,
        slot_key: str,
    ) -> NotificationSetting:
        return NotificationSetting(
            patient_hash=patient_hash,
            slot_key=slot_key,
            hour=default_notification_hour(slot_key),
            minute=0,
            enabled=False,
        )

    def _to_response_dict(
        self,
        setting: _NotificationSetting | NotificationSetting,
    ) -> dict[str, object]:
        if isinstance(setting, NotificationSetting):
            return setting.to_response_dict()
        return NotificationSetting(
            patient_hash=setting.patient_hash,
            slot_key=setting.slot_key,
            hour=setting.hour,
            minute=setting.minute,
            enabled=setting.enabled,
        ).to_response_dict()
