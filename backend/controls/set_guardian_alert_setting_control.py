# File Name: set_guardian_alert_setting_control.py
# Role: Control class for guardian alert settings.

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from controls.patient_guardian_link_control import PatientGuardianLinkControl
from entities.guardian_alert_setting_entity import (
    GuardianAlertSetting,
    _GuardianAlertSetting,
    alert_option_from_enabled,
    enabled_from_alert_option,
)
from entities.patient_hash_entity import normalize_patient_hash


# Class Name: SetGuardianAlertSetting
# Role: Coordinates guardian alert settings.
# Responsibilities:
#   - Validate that a guardian is linked to the requested patient.
#   - Read or initialize the guardian alert preference for that pair.
#   - Persist enable/disable changes without coupling to medication listing.
# Attributes:
#   - db: SQLAlchemy session used for persistence operations.
class SetGuardianAlertSetting:
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: requestGuardianAlertSetting
    # Description:
    # - Class diagram compatible wrapper for guardian alert setting lookup.
    # Parameters:
    # - guardian_hash: Guardian ownership key.
    # - patient_hash: Patient ownership key monitored by the guardian.
    # Returns:
    # - API-compatible guardian alert setting dictionary.
    def requestGuardianAlertSetting(
        self,
        guardian_hash: str,
        patient_hash: str,
    ) -> dict[str, object]:
        return self.request_guardian_alert_setting(guardian_hash, patient_hash)

    # Function Name: request_guardian_alert_setting
    # Description:
    # - Reads the setting for a guardian-patient pair, creating a disabled default
    #   row when none exists as described in UC-13.
    # Parameters:
    # - guardian_hash: Guardian ownership key.
    # - patient_hash: Patient ownership key monitored by the guardian.
    # Returns:
    # - API-compatible guardian alert setting dictionary.
    def request_guardian_alert_setting(
        self,
        guardian_hash: str,
        patient_hash: str,
    ) -> dict[str, object]:
        normalized_guardian_hash, normalized_patient_hash = self._resolve_scope(
            guardian_hash,
            patient_hash,
        )
        setting = self._find_setting(normalized_guardian_hash, normalized_patient_hash)
        if setting is None:
            setting = self._create_default_setting(
                normalized_guardian_hash,
                normalized_patient_hash,
            )
        return self._success_response(
            "Guardian alert setting lookup succeeded.",
            setting,
        )

    # Function Name: updateGuardianAlertSetting
    # Description:
    # - Class diagram compatible wrapper for changing guardian alert option.
    # Parameters:
    # - guardian_hash: Guardian ownership key.
    # - patient_hash: Patient ownership key monitored by the guardian.
    # - enabled: Optional boolean toggle state from the UI.
    # - alert_option: Optional UML alert option string.
    # Returns:
    # - API-compatible guardian alert setting dictionary.
    def updateGuardianAlertSetting(
        self,
        guardian_hash: str,
        patient_hash: str,
        enabled: bool | None = None,
        alert_option: str | None = None,
    ) -> dict[str, object]:
        return self.update_guardian_alert_setting(
            guardian_hash,
            patient_hash,
            enabled,
            alert_option,
        )

    # Function Name: update_guardian_alert_setting
    # Description:
    # - Creates or updates one guardian alert setting after link validation.
    # Parameters:
    # - guardian_hash: Guardian ownership key.
    # - patient_hash: Patient ownership key monitored by the guardian.
    # - enabled: Optional boolean toggle state from the UI.
    # - alert_option: Optional UML alert option string.
    # Returns:
    # - API-compatible guardian alert setting dictionary.
    def update_guardian_alert_setting(
        self,
        guardian_hash: str,
        patient_hash: str,
        enabled: bool | None = None,
        alert_option: str | None = None,
    ) -> dict[str, object]:
        normalized_guardian_hash, normalized_patient_hash = self._resolve_scope(
            guardian_hash,
            patient_hash,
        )
        requested_enabled = self._coerce_enabled(enabled, alert_option)

        try:
            setting = self._find_setting(
                normalized_guardian_hash,
                normalized_patient_hash,
            )
            if setting is None:
                setting = _GuardianAlertSetting(
                    guardian_hash=normalized_guardian_hash,
                    patient_hash=normalized_patient_hash,
                )
                self.db.add(setting)
            return self._persist_setting_state(setting, requested_enabled)
        except IntegrityError:
            self.db.rollback()
            return self._update_existing_setting_after_conflict(
                normalized_guardian_hash,
                normalized_patient_hash,
                requested_enabled,
            )
        except HTTPException:
            self.db.rollback()
            raise
        except Exception as exc:
            self.db.rollback()
            raise HTTPException(
                status_code=500,
                detail=f"Guardian alert setting save failed: {exc}",
            ) from exc

    # Function Name: enableGuardianAlert
    # Description:
    # - Enables guardian alerts for one guardian-patient pair.
    # Parameters:
    # - guardian_hash: Guardian ownership key.
    # - patient_hash: Patient ownership key monitored by the guardian.
    # Returns:
    # - API-compatible enabled guardian alert setting dictionary.
    def enableGuardianAlert(
        self,
        guardian_hash: str,
        patient_hash: str,
    ) -> dict[str, object]:
        return self.update_guardian_alert_setting(
            guardian_hash,
            patient_hash,
            True,
        )

    # Function Name: disableGuardianAlert
    # Description:
    # - Disables guardian alerts for one guardian-patient pair.
    # Parameters:
    # - guardian_hash: Guardian ownership key.
    # - patient_hash: Patient ownership key monitored by the guardian.
    # Returns:
    # - API-compatible disabled guardian alert setting dictionary.
    def disableGuardianAlert(
        self,
        guardian_hash: str,
        patient_hash: str,
    ) -> dict[str, object]:
        return self.update_guardian_alert_setting(
            guardian_hash,
            patient_hash,
            False,
        )

    def _resolve_scope(
        self,
        guardian_hash: str,
        patient_hash: str,
    ) -> tuple[str, str]:
        normalized_guardian_hash = normalize_patient_hash(guardian_hash)
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        linked_patient_hash = PatientGuardianLinkControl(
            self.db
        ).get_linked_patient_hash(
            normalized_guardian_hash,
            normalized_patient_hash,
        )
        if linked_patient_hash != normalized_patient_hash:
            raise HTTPException(
                status_code=403,
                detail="Guardian is not linked to the requested patient.",
            )
        return normalized_guardian_hash, normalized_patient_hash

    def _find_setting(
        self,
        guardian_hash: str,
        patient_hash: str,
    ) -> _GuardianAlertSetting | None:
        return (
            self.db.query(_GuardianAlertSetting)
            .filter(
                _GuardianAlertSetting.guardian_hash == guardian_hash,
                _GuardianAlertSetting.patient_hash == patient_hash,
            )
            .first()
        )

    def _create_default_setting(
        self,
        guardian_hash: str,
        patient_hash: str,
    ) -> _GuardianAlertSetting:
        try:
            setting = _GuardianAlertSetting(
                guardian_hash=guardian_hash,
                patient_hash=patient_hash,
                enabled=False,
                alert_option=alert_option_from_enabled(False),
            )
            self.db.add(setting)
            self.db.commit()
            self.db.refresh(setting)
            return setting
        except IntegrityError:
            self.db.rollback()
            existing_setting = self._find_setting(guardian_hash, patient_hash)
            if existing_setting is None:
                raise HTTPException(
                    status_code=409,
                    detail="Guardian alert setting conflict could not be resolved.",
                )
            return existing_setting
        except Exception as exc:
            self.db.rollback()
            raise HTTPException(
                status_code=500,
                detail=f"Guardian alert setting initialization failed: {exc}",
            ) from exc

    def _update_existing_setting_after_conflict(
        self,
        guardian_hash: str,
        patient_hash: str,
        enabled: bool,
    ) -> dict[str, object]:
        setting = self._find_setting(guardian_hash, patient_hash)
        if setting is None:
            raise HTTPException(
                status_code=409,
                detail="Guardian alert setting conflict could not be resolved.",
            )
        try:
            return self._persist_setting_state(setting, enabled)
        except Exception as exc:
            self.db.rollback()
            raise HTTPException(
                status_code=500,
                detail=f"Guardian alert setting save failed: {exc}",
            ) from exc

    def _persist_setting_state(
        self,
        setting: _GuardianAlertSetting,
        enabled: bool,
    ) -> dict[str, object]:
        setting.enabled = enabled
        setting.alert_option = alert_option_from_enabled(enabled)
        self.db.commit()
        self.db.refresh(setting)
        return self._success_response(
            "Guardian alert setting was saved.",
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
                    detail="Guardian alert option is not supported.",
                ) from exc
        try:
            return enabled_from_alert_option(alert_option or "")
        except ValueError as exc:
            raise HTTPException(
                status_code=400,
                detail="Guardian alert option is not supported.",
            ) from exc

    def _to_response_dict(
        self,
        setting: _GuardianAlertSetting | GuardianAlertSetting,
    ) -> dict[str, object]:
        if isinstance(setting, GuardianAlertSetting):
            return setting.to_response_dict()
        return GuardianAlertSetting(
            setting_id=setting.id,
            patient_hash=setting.patient_hash,
            guardian_hash=setting.guardian_hash,
            enabled=setting.enabled,
            alert_option=setting.alert_option,
        ).to_response_dict()

    def _success_response(
        self,
        message: str,
        setting: _GuardianAlertSetting | GuardianAlertSetting,
    ) -> dict[str, object]:
        return {
            "success": True,
            "message": message,
            "data": self._to_response_dict(setting),
        }
