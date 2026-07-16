# File Name: set_caregiver_notification_control.py
# Role: Control class for caregiver notification settings.

import logging

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from controls.link_patient_caregiver_control import LinkPatientCaregiver
from entities.caregiver_notification_entity import (
    CaregiverNotification,
    _CaregiverNotification,
    alert_option_from_enabled,
    enabled_from_alert_option,
)
from entities.patient_hash_entity import normalize_patient_hash

logger = logging.getLogger(__name__)


# Class Name: SetCaregiverNotification
# Role: Coordinates caregiver notification settings.
# Responsibilities:
#   - Validate that a caregiver is linked to the requested patient.
#   - Read the caregiver notification preference for that pair.
#   - Persist enable/disable changes without coupling to medication listing.
# Attributes:
#   - db: SQLAlchemy session used for persistence operations.
class SetCaregiverNotification:
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: requestCaregiverNotificationSetting
    # Description:
    # - Reads the setting for a caregiver-patient pair.
    # Parameters:
    # - caregiver_hash: Caregiver ownership key.
    # - patient_hash: Patient ownership key monitored by the caregiver.
    # Returns:
    # - API-compatible caregiver notification setting dictionary.
    def requestCaregiverNotificationSetting(
        self,
        caregiver_hash: str,
        patient_hash: str,
    ) -> dict[str, object]:
        normalized_caregiver_hash, normalized_patient_hash = self._resolve_scope(
            caregiver_hash,
            patient_hash,
        )
        setting = self._find_setting(
            normalized_caregiver_hash,
            normalized_patient_hash,
        )
        if setting is None:
            setting = CaregiverNotification(
                caregiver_hash=normalized_caregiver_hash,
                patient_hash=normalized_patient_hash,
            )
        return self._success_response(
            "Caregiver notification setting lookup succeeded.",
            setting,
        )

    # Function Name: saveCaregiverNotificationSetting
    # Description:
    # - Creates or updates one caregiver notification setting after link validation.
    # Parameters:
    # - caregiver_hash: Caregiver ownership key.
    # - patient_hash: Patient ownership key monitored by the caregiver.
    # - enabled: Optional boolean toggle state from the UI.
    # - alert_option: Optional UML alert option string.
    # Returns:
    # - API-compatible caregiver notification setting dictionary.
    def saveCaregiverNotificationSetting(
        self,
        caregiver_hash: str,
        patient_hash: str,
        enabled: bool | None = None,
        alert_option: str | None = None,
    ) -> dict[str, object]:
        normalized_caregiver_hash, normalized_patient_hash = self._resolve_scope(
            caregiver_hash,
            patient_hash,
        )
        requested_enabled = self._coerce_enabled(enabled, alert_option)

        try:
            setting = self._find_setting(
                normalized_caregiver_hash,
                normalized_patient_hash,
            )
            if setting is None:
                setting = _CaregiverNotification(
                    caregiver_hash=normalized_caregiver_hash,
                    patient_hash=normalized_patient_hash,
                )
                self.db.add(setting)
            return self._persist_setting_state(setting, requested_enabled)
        except IntegrityError:
            self.db.rollback()
            return self._update_existing_setting_after_conflict(
                normalized_caregiver_hash,
                normalized_patient_hash,
                requested_enabled,
            )
        except HTTPException:
            self.db.rollback()
            raise
        except Exception as exc:
            self.db.rollback()
            logger.error(
                "Caregiver notification setting persistence failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Caregiver notification setting could not be saved.",
            ) from exc

    def _resolve_scope(
        self,
        caregiver_hash: str,
        patient_hash: str,
    ) -> tuple[str, str]:
        normalized_caregiver_hash = normalize_patient_hash(caregiver_hash)
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        linked_patient_hash = LinkPatientCaregiver(
            self.db
        ).getLinkedPatientHash(
            normalized_caregiver_hash,
            normalized_patient_hash,
        )
        if linked_patient_hash != normalized_patient_hash:
            raise HTTPException(
                status_code=403,
                detail="Caregiver is not linked to the requested patient.",
            )
        return normalized_caregiver_hash, normalized_patient_hash

    def _find_setting(
        self,
        caregiver_hash: str,
        patient_hash: str,
    ) -> _CaregiverNotification | None:
        return (
            self.db.query(_CaregiverNotification)
            .filter(
                _CaregiverNotification.caregiver_hash == caregiver_hash,
                _CaregiverNotification.patient_hash == patient_hash,
            )
            .first()
        )

    def _update_existing_setting_after_conflict(
        self,
        caregiver_hash: str,
        patient_hash: str,
        enabled: bool,
    ) -> dict[str, object]:
        setting = self._find_setting(caregiver_hash, patient_hash)
        if setting is None:
            raise HTTPException(
                status_code=409,
                detail="Caregiver notification setting conflict could not be resolved.",
            )
        try:
            return self._persist_setting_state(setting, enabled)
        except Exception as exc:
            self.db.rollback()
            logger.error(
                "Caregiver notification setting conflict recovery failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Caregiver notification setting could not be saved.",
            ) from exc

    def _persist_setting_state(
        self,
        setting: _CaregiverNotification,
        enabled: bool,
    ) -> dict[str, object]:
        setting_state = self._to_entity(setting).updateNotificationSetting(enabled)
        setting.enabled = setting_state.notification_enabled
        setting.alert_option = setting_state.notification_type
        self.db.commit()
        self.db.refresh(setting)
        return self._success_response(
            "Caregiver notification setting was saved.",
            setting,
        )

    def _coerce_enabled(
        self,
        enabled: bool | None,
        alert_option: str | None,
    ) -> bool:
        if isinstance(enabled, bool):
            return enabled
        if enabled is not None:
            try:
                return enabled_from_alert_option(str(enabled))
            except ValueError as exc:
                raise HTTPException(
                    status_code=400,
                    detail="Caregiver notification option is not supported.",
                ) from exc
        try:
            return enabled_from_alert_option(alert_option or "")
        except ValueError as exc:
            raise HTTPException(
                status_code=400,
                detail="Caregiver notification option is not supported.",
            ) from exc

    def _to_entity(
        self,
        setting: _CaregiverNotification | CaregiverNotification,
    ) -> CaregiverNotification:
        if isinstance(setting, CaregiverNotification):
            return setting
        return CaregiverNotification(
            notification_id=setting.id,
            patient_hash=setting.patient_hash,
            caregiver_hash=setting.caregiver_hash,
            notification_enabled=bool(setting.enabled),
            notification_type=(
                setting.alert_option
                or alert_option_from_enabled(bool(setting.enabled))
            ),
        )

    def _to_response_dict(
        self,
        setting: _CaregiverNotification | CaregiverNotification,
    ) -> dict[str, object]:
        return self._to_entity(setting).to_response_dict()

    def _success_response(
        self,
        message: str,
        setting: _CaregiverNotification | CaregiverNotification,
    ) -> dict[str, object]:
        return {
            "success": True,
            "message": message,
            "data": self._to_response_dict(setting),
        }
