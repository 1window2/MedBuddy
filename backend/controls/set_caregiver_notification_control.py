# 파일명: set_caregiver_notification_control.py
# 역할: 보호자 알림 설정의 조회와 저장 흐름을 조정한다.

import logging

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from controls.link_patient_caregiver_control import LinkPatientCaregiver
from entities.caregiver_notification_entity import (
    CAREGIVER_NOTIFICATION_MODE_DISABLED,
    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
    CAREGIVER_NOTIFICATION_SLOT_KEYS,
    CaregiverNotification,
    _CaregiverNotification,
    alert_option_from_enabled,
    decode_slot_settings,
    encode_slot_settings,
    normalize_notification_mode,
    normalize_notification_slot,
)
from entities.patient_hash_entity import normalize_patient_hash

logger = logging.getLogger(__name__)


# 클래스명: SetCaregiverNotification
# 역할: 연동 권한을 검증하고 시간대별 보호자 알림 설정을 관리한다.
# 주요 책임:
# - 보호자와 환자의 연동 관계를 검증한다.
# - 아침, 점심, 저녁, 취침 전 설정을 서로 독립적으로 조회하고 저장한다.
# - 기존 단일 알림 설정을 시간대별 구조로 호환한다.
class SetCaregiverNotification:
    def __init__(self, db: Session) -> None:
        self.db = db

    # 함수명: requestCaregiverNotificationSetting
    # 역할:
    # - 보호자-환자 조합에서 지정한 복약 시간대의 알림 설정을 조회한다.
    def requestCaregiverNotificationSetting(
        self,
        caregiver_hash: str,
        patient_hash: str,
        slot_key: str = "morning",
    ) -> dict[str, object]:
        normalized_slot_key = self._normalize_slot(slot_key)
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
                slot_key=normalized_slot_key,
            )
        return self._success_response(
            "Caregiver notification setting lookup succeeded.",
            setting,
            normalized_slot_key,
        )

    # 함수명: requestCaregiverNotificationSettings
    # 역할:
    # - 한 보호자-환자 연동의 네 시간대 알림 설정을 한 번에 조회한다.
    def requestCaregiverNotificationSettings(
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
        settings = [
            (
                CaregiverNotification(
                    caregiver_hash=normalized_caregiver_hash,
                    patient_hash=normalized_patient_hash,
                    slot_key=slot_key,
                )
                if setting is None
                else self._to_entity(setting, slot_key)
            ).to_response_dict()
            for slot_key in CAREGIVER_NOTIFICATION_SLOT_KEYS
        ]
        return {
            "success": True,
            "message": "Caregiver notification settings lookup succeeded.",
            "data": settings,
        }

    # 함수명: loadCaregiverNotificationSettingsForPatients
    # 역할:
    # - 이미 연동 권한을 확인한 여러 환자의 시간대별 설정을 한 쿼리로 읽는다.
    # - 설정이 없는 환자도 네 시간대의 비활성 기본값을 반환한다.
    def loadCaregiverNotificationSettingsForPatients(
        self,
        caregiver_hash: str,
        patient_hashes: list[str],
    ) -> dict[str, list[dict[str, object]]]:
        normalized_caregiver_hash = normalize_patient_hash(caregiver_hash)
        normalized_patient_hashes = list(
            dict.fromkeys(
                normalize_patient_hash(patient_hash)
                for patient_hash in patient_hashes
            )
        )
        if not normalized_patient_hashes:
            return {}

        settings = (
            self.db.query(_CaregiverNotification)
            .filter(
                _CaregiverNotification.caregiver_hash
                == normalized_caregiver_hash,
                _CaregiverNotification.patient_hash.in_(
                    normalized_patient_hashes
                ),
            )
            .all()
        )
        setting_by_patient = {
            str(setting.patient_hash): setting for setting in settings
        }
        return {
            patient_hash: [
                (
                    CaregiverNotification(
                        caregiver_hash=normalized_caregiver_hash,
                        patient_hash=patient_hash,
                        slot_key=slot_key,
                    )
                    if setting_by_patient.get(patient_hash) is None
                    else self._to_entity(
                        setting_by_patient[patient_hash],
                        slot_key,
                    )
                ).to_response_dict()
                for slot_key in CAREGIVER_NOTIFICATION_SLOT_KEYS
            ]
            for patient_hash in normalized_patient_hashes
        }

    # 함수명: saveCaregiverNotificationSetting
    # 역할:
    # - 연동 관계를 검증한 뒤 지정한 시간대의 알림 설정만 생성하거나 갱신한다.
    def saveCaregiverNotificationSetting(
        self,
        caregiver_hash: str,
        patient_hash: str,
        enabled: bool | None = None,
        alert_option: str | None = None,
        deadline_hour: int | None = None,
        deadline_minute: int | None = None,
        slot_key: str = "morning",
    ) -> dict[str, object]:
        normalized_slot_key = self._normalize_slot(slot_key)
        normalized_caregiver_hash, normalized_patient_hash = self._resolve_scope(
            caregiver_hash,
            patient_hash,
        )
        requested_mode = self._coerce_notification_mode(enabled, alert_option)
        self._validate_deadline(
            requested_mode,
            deadline_hour,
            deadline_minute,
        )

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
            return self._persist_setting_state(
                setting,
                normalized_slot_key,
                requested_mode,
                deadline_hour,
                deadline_minute,
            )
        except IntegrityError:
            self.db.rollback()
            return self._update_existing_setting_after_conflict(
                normalized_caregiver_hash,
                normalized_patient_hash,
                normalized_slot_key,
                requested_mode,
                deadline_hour,
                deadline_minute,
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
        slot_key: str,
        notification_mode: str,
        deadline_hour: int | None,
        deadline_minute: int | None,
    ) -> dict[str, object]:
        setting = self._find_setting(caregiver_hash, patient_hash)
        if setting is None:
            raise HTTPException(
                status_code=409,
                detail="Caregiver notification setting conflict could not be resolved.",
            )
        try:
            return self._persist_setting_state(
                setting,
                slot_key,
                notification_mode,
                deadline_hour,
                deadline_minute,
            )
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
        slot_key: str,
        notification_mode: str,
        deadline_hour: int | None,
        deadline_minute: int | None,
    ) -> dict[str, object]:
        setting_state = self._to_entity(setting, slot_key).updateNotificationSetting(
            notification_mode,
            deadline_hour,
            deadline_minute,
        )
        slot_settings = self._read_or_seed_slot_settings(setting)
        slot_settings[slot_key] = {
            "notification_type": setting_state.notification_type,
            "deadline_hour": setting_state.deadline_hour,
            "deadline_minute": setting_state.deadline_minute,
        }
        setting.slot_settings = encode_slot_settings(slot_settings)
        setting.enabled = any(
            slot_setting.get("notification_type")
            != CAREGIVER_NOTIFICATION_MODE_DISABLED
            for slot_setting in slot_settings.values()
        )
        setting.alert_option = setting_state.notification_type
        setting.deadline_hour = setting_state.deadline_hour
        setting.deadline_minute = setting_state.deadline_minute
        self.db.commit()
        self.db.refresh(setting)
        return self._success_response(
            "Caregiver notification setting was saved.",
            setting,
            slot_key,
        )

    def _normalize_slot(self, slot_key: str) -> str:
        try:
            return normalize_notification_slot(slot_key)
        except ValueError as exc:
            raise HTTPException(
                status_code=400,
                detail="Caregiver notification slot is not supported.",
            ) from exc

    def _coerce_notification_mode(
        self,
        enabled: bool | None,
        alert_option: str | None,
    ) -> str:
        raw_option: str | bool
        if alert_option is not None:
            raw_option = alert_option
        elif enabled is not None:
            raw_option = enabled
        else:
            raw_option = CAREGIVER_NOTIFICATION_MODE_DISABLED
        try:
            return normalize_notification_mode(raw_option)
        except ValueError as exc:
            raise HTTPException(
                status_code=400,
                detail="Caregiver notification option is not supported.",
            ) from exc

    def _validate_deadline(
        self,
        notification_mode: str,
        deadline_hour: int | None,
        deadline_minute: int | None,
    ) -> None:
        if notification_mode != CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE:
            return
        if deadline_hour is None or deadline_minute is None:
            raise HTTPException(
                status_code=400,
                detail="Missed-dose notifications require a deadline.",
            )

    def _to_entity(
        self,
        setting: _CaregiverNotification | CaregiverNotification,
        slot_key: str = "morning",
    ) -> CaregiverNotification:
        if isinstance(setting, CaregiverNotification):
            return setting
        normalized_slot_key = self._normalize_slot(slot_key)
        slot_settings = self._read_or_seed_slot_settings(setting)
        slot_setting = slot_settings[normalized_slot_key]
        return CaregiverNotification(
            notification_id=setting.id,
            patient_hash=setting.patient_hash,
            caregiver_hash=setting.caregiver_hash,
            slot_key=normalized_slot_key,
            notification_enabled=(
                slot_setting["notification_type"]
                != CAREGIVER_NOTIFICATION_MODE_DISABLED
            ),
            notification_type=str(slot_setting["notification_type"]),
            deadline_hour=slot_setting.get("deadline_hour"),
            deadline_minute=slot_setting.get("deadline_minute"),
        )

    def _read_or_seed_slot_settings(
        self,
        setting: _CaregiverNotification,
    ) -> dict[str, dict[str, object]]:
        slot_settings = decode_slot_settings(setting.slot_settings)
        try:
            legacy_mode = normalize_notification_mode(
                setting.alert_option
                or alert_option_from_enabled(bool(setting.enabled))
            )
        except ValueError:
            legacy_mode = alert_option_from_enabled(bool(setting.enabled))
        for slot_key in CAREGIVER_NOTIFICATION_SLOT_KEYS:
            slot_settings.setdefault(
                slot_key,
                {
                    "notification_type": legacy_mode,
                    "deadline_hour": setting.deadline_hour,
                    "deadline_minute": setting.deadline_minute,
                },
            )
        return slot_settings

    def _to_response_dict(
        self,
        setting: _CaregiverNotification | CaregiverNotification,
        slot_key: str = "morning",
    ) -> dict[str, object]:
        return self._to_entity(setting, slot_key).to_response_dict()

    def _success_response(
        self,
        message: str,
        setting: _CaregiverNotification | CaregiverNotification,
        slot_key: str = "morning",
    ) -> dict[str, object]:
        return {
            "success": True,
            "message": message,
            "data": self._to_response_dict(setting, slot_key),
        }
