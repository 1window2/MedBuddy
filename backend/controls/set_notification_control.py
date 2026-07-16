# File Name: set_notification_control.py
# Role: Control class for patient medication alarm settings.

import logging

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from entities.medication_alarm_entity import (
    MedicationAlarm,
    _MedicationAlarm,
    default_alarm_hour,
    valid_alarm_slot_keys,
)
from entities.patient_hash_entity import normalize_patient_hash

logger = logging.getLogger(__name__)


# Class Name: SetNotification
# Role: Coordinates patient medication alarms.
# Responsibilities:
#   - Read medication alarm state by patient and schedule slot.
#   - Persist enabled medication alarms with selected local times.
#   - Disable medication alarms while preserving the last selected time.
# Attributes:
#   - db: SQLAlchemy session used for persistence operations.
class SetNotification:
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: requestMedicationAlarm
    # Description:
    # - Reads all slot alarm settings for one patient scope.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope alarm settings.
    # Returns:
    # - API-compatible medication alarm list dictionary.
    def requestMedicationAlarm(
        self,
        patient_hash: str | None = None,
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        rows = {
            row.slot_key: row
            for row in (
                self.db.query(_MedicationAlarm)
                .filter(_MedicationAlarm.patient_hash == normalized_patient_hash)
                .all()
            )
        }
        return {
            "success": True,
            "message": "Medication alarms lookup succeeded.",
            "data": [
                self._to_response_dict(
                    rows.get(slot_key)
                    or self._default_setting_row(normalized_patient_hash, slot_key)
                )
                for slot_key in valid_alarm_slot_keys()
            ],
        }

    # Function Name: requestAlarmToggle
    # Description:
    # - Reads one slot alarm status before a UI toggle decision.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope alarm settings.
    # - slot_key: Medication schedule time slot.
    # Returns:
    # - API-compatible medication alarm dictionary.
    def requestAlarmToggle(
        self,
        patient_hash: str | None,
        slot_key: str,
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        normalized_slot_key = self._normalize_slot_key(slot_key)
        setting = self._find_setting(normalized_patient_hash, normalized_slot_key)
        return {
            "success": True,
            "message": "Medication alarm lookup succeeded.",
            "data": self._to_response_dict(
                setting
                or self._default_setting_row(
                    normalized_patient_hash,
                    normalized_slot_key,
                )
            ),
        }

    # Function Name: saveNotificationSetting
    # Description:
    # - Creates or updates one enabled slot alarm.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope alarm settings.
    # - slot_key: Medication schedule time slot.
    # - hour: 24-hour local alarm hour.
    # - minute: Local alarm minute.
    # Returns:
    # - API-compatible enabled medication alarm dictionary.
    def saveNotificationSetting(
        self,
        patient_hash: str | None,
        slot_key: str,
        hour: int,
        minute: int,
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        normalized_slot_key = self._normalize_slot_key(slot_key)
        self._validate_alarm_time(hour, minute)

        try:
            setting = self._find_setting(normalized_patient_hash, normalized_slot_key)
            if setting is None:
                setting = _MedicationAlarm(
                    patient_hash=normalized_patient_hash,
                    slot_key=normalized_slot_key,
                )
                self.db.add(setting)
            self._apply_alarm_state(
                setting,
                enabled=True,
                hour=hour,
                minute=minute,
            )
            self.db.commit()
            self.db.refresh(setting)
            return {
                "success": True,
                "message": "Medication alarm was saved.",
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
            logger.error(
                "Medication alarm persistence failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Medication alarm could not be saved.",
            ) from exc

    # Function Name: disableAlarmSetting
    # Description:
    # - Disables one slot alarm while preserving its selected time.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope alarm settings.
    # - slot_key: Medication schedule time slot.
    # Returns:
    # - API-compatible disabled medication alarm dictionary.
    def disableAlarmSetting(
        self,
        patient_hash: str | None,
        slot_key: str,
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        normalized_slot_key = self._normalize_slot_key(slot_key)

        try:
            setting = self._find_setting(normalized_patient_hash, normalized_slot_key)
            if setting is None:
                setting = _MedicationAlarm(
                    patient_hash=normalized_patient_hash,
                    slot_key=normalized_slot_key,
                    hour=default_alarm_hour(normalized_slot_key),
                    minute=0,
                    enabled=False,
                )
                self.db.add(setting)
            self._apply_alarm_state(setting, enabled=False)
            self.db.commit()
            self.db.refresh(setting)
            return {
                "success": True,
                "message": "Medication alarm was disabled.",
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
            logger.error(
                "Medication alarm disable failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Medication alarm could not be disabled.",
            ) from exc

    def _find_setting(
        self,
        patient_hash: str,
        slot_key: str,
    ) -> _MedicationAlarm | None:
        return (
            self.db.query(_MedicationAlarm)
            .filter(
                _MedicationAlarm.patient_hash == patient_hash,
                _MedicationAlarm.slot_key == slot_key,
            )
            .first()
        )

    def _normalize_slot_key(self, slot_key: str) -> str:
        normalized_slot_key = (slot_key or "").strip().lower()
        if normalized_slot_key not in valid_alarm_slot_keys():
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
                detail="Medication alarm conflict could not be resolved.",
            )
        try:
            self._apply_alarm_state(
                setting,
                enabled=True,
                hour=hour,
                minute=minute,
            )
            self.db.commit()
            self.db.refresh(setting)
            return {
                "success": True,
                "message": "Medication alarm was saved.",
                "data": self._to_response_dict(setting),
            }
        except Exception as exc:
            self.db.rollback()
            logger.error(
                "Medication alarm conflict recovery failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Medication alarm could not be saved.",
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
                detail="Medication alarm conflict could not be resolved.",
            )
        try:
            self._apply_alarm_state(setting, enabled=False)
            self.db.commit()
            self.db.refresh(setting)
            return {
                "success": True,
                "message": "Medication alarm was disabled.",
                "data": self._to_response_dict(setting),
            }
        except Exception as exc:
            self.db.rollback()
            logger.error(
                "Medication alarm disable conflict recovery failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Medication alarm could not be disabled.",
            ) from exc

    def _default_setting_row(
        self,
        patient_hash: str,
        slot_key: str,
    ) -> MedicationAlarm:
        return MedicationAlarm(
            patient_hash=patient_hash,
            slot_key=slot_key,
            hour=default_alarm_hour(slot_key),
            minute=0,
            enabled=False,
        )

    def _apply_alarm_state(
        self,
        setting: _MedicationAlarm,
        *,
        enabled: bool,
        hour: int | None = None,
        minute: int | None = None,
    ) -> None:
        alarm = self._to_entity(setting)
        alarm = alarm.model_copy(
            update={
                "hour": alarm.hour if hour is None else hour,
                "minute": alarm.minute if minute is None else minute,
            }
        )
        alarm = alarm.enable() if enabled else alarm.disable()
        setting.hour = alarm.hour
        setting.minute = alarm.minute
        setting.enabled = alarm.enabled

    def _to_entity(
        self,
        setting: _MedicationAlarm | MedicationAlarm,
    ) -> MedicationAlarm:
        if isinstance(setting, MedicationAlarm):
            return setting
        slot_key = setting.slot_key
        return MedicationAlarm(
            patient_hash=setting.patient_hash,
            slot_key=slot_key,
            hour=(
                setting.hour
                if setting.hour is not None
                else default_alarm_hour(slot_key)
            ),
            minute=setting.minute if setting.minute is not None else 0,
            enabled=bool(setting.enabled),
        )

    def _to_response_dict(
        self,
        setting: _MedicationAlarm | MedicationAlarm,
    ) -> dict[str, object]:
        return self._to_entity(setting).to_response_dict()
