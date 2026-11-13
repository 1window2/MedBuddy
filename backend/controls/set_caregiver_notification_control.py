# File Name: set_caregiver_notification_control.py
# Role: Manages linked-patient caregiver alert modes and deadlines per dose slot with legacy preference compatibility.

import logging

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import Session

from controls.link_patient_caregiver_control import LinkPatientCaregiver
from core.account_database_lock import (
    ACCOUNT_BUSY_DETAIL,
    ACCOUNT_DELETED_DETAIL,
    lock_account_operations,
)
from entities.caregiver_notification_entity import (
    CAREGIVER_NOTIFICATION_MODE_DISABLED,
    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
    CAREGIVER_NOTIFICATION_SLOT_KEYS,
    CaregiverNotification,
    _CaregiverNotification,
    effective_slot_settings,
    encode_slot_settings,
    normalize_notification_mode,
    normalize_notification_slot,
)
from entities.patient_hash_entity import normalize_patient_hash
from entities.user_account_entity import _UserAccount

logger = logging.getLogger(__name__)


# Class Name: SetCaregiverNotification
# Role: Manages per-slot caregiver alert settings under an active patient link.
# Responsibilities: Validates linked ownership, independently configures slots/deadlines and interprets legacy single-setting rows.
# Attributes: db (Session) is the request transaction; account locks guard setting writes against unlink/deletion.
class SetCaregiverNotification:
    # Function Name: __init__
    # Description:
    # - Binds caregiver notification settings to the supplied database session.
    # Parameters:
    # - db (Session): SQLAlchemy session for this unit of work.
    # Returns:
    # - None.
    def __init__(self, db: Session) -> None:
        self.db = db

    # 함수이름: requestCaregiverNotificationSetting
    # 함수역할:
    # - 보호자-환자 조합에서 지정한 복약 시간대의 알림 설정을 조회한다.
    # 매개변수:
    # - caregiver_hash (str): 환자와 연동된 보호자 계정 식별자.
    # - patient_hash (str): 작업 대상 환자의 데이터 소유 범위 식별자.
    # - slot_key (str): morning, lunch, evening, bedtime 또는 필요시 복용 알림용 as_needed 키.
    # 반환값:
    # - 선택 시간대의 저장 설정 또는 기본값을 담은 성공 응답.
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

    # 함수이름: requestCaregiverNotificationSettings
    # 함수역할:
    # - 한 보호자-환자 연동의 네 시간대 알림 설정을 한 번에 조회한다.
    # 매개변수:
    # - caregiver_hash (str): 환자와 연동된 보호자 계정 식별자.
    # - patient_hash (str): 작업 대상 환자의 데이터 소유 범위 식별자.
    # 반환값:
    # - 모든 지원 시간대의 알림 설정 목록 응답.
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

    # 함수이름: loadCaregiverNotificationSettingsForPatients
    # 함수역할:
    # - 이미 연동 권한을 확인한 여러 환자의 시간대별 설정을 한 쿼리로 읽는다.
    # - 설정이 없는 환자도 네 시간대의 비활성 기본값을 반환한다.
    # 매개변수:
    # - caregiver_hash (str): 환자와 연동된 보호자 계정 식별자.
    # - patient_hashes (list[str]): 알림 설정을 함께 읽을 연동 환자 식별자 목록.
    # 반환값:
    # - 환자 식별자별 전체 시간대 알림 설정 목록 사전.
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

    # 함수이름: saveCaregiverNotificationSetting
    # 함수역할:
    # - 두 계정 잠금 안에서 삭제·연동을 재검증한 뒤 선택 시간대만 저장한다. 필요시 복용에는 미복용 마감 모드를 허용하지 않는다.
    # 매개변수:
    # - caregiver_hash (str): 환자와 연동된 보호자 계정 식별자.
    # - patient_hash (str): 작업 대상 환자의 데이터 소유 범위 식별자.
    # - enabled (bool | None): 요청한 알림 활성 상태.
    # - alert_option (str | None): 기존 활성 플래그보다 우선하는 선택적 알림 모드.
    # - deadline_hour (int | None): 선택적인 미복용 마감 시.
    # - deadline_minute (int | None): 선택적인 미복용 마감 분.
    # - slot_key (str): morning, lunch, evening, bedtime 또는 필요시 복용 알림용 as_needed 키.
    # 반환값:
    # - 저장된 선택 시간대 응답. 동시 생성은 재시도하며 저장 실패는 롤백한다. 입력·삭제·연동·잠금 오류는 해당 HTTP 상태로 전파한다.
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
        if normalized_slot_key == "as_needed" and requested_mode == CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE:
            raise HTTPException(
                status_code=400,
                detail="As-needed notifications do not support missed deadlines.",
            )
        self._validate_deadline(
            requested_mode,
            deadline_hour,
            deadline_minute,
        )

        try:
            self._lock_notification_scope(normalized_caregiver_hash, normalized_patient_hash)
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

    # 함수이름: _lock_notification_scope
    # 함수역할: 두 계정 잠금 안에서 삭제·연동을 재확인하고 설정 저장까지 유지한다.
    # 매개변수: caregiver_hash, patient_hash: 정규화된 참여자 식별자.
    # 반환값: 없음. 미저장 변경은 RuntimeError, 삭제는 410, 연동 실패는 403/404, 잠금 실패는 503이다.
    def _lock_notification_scope(self, caregiver_hash: str, patient_hash: str) -> None:
        if self.db.new or self.db.dirty or self.db.deleted:
            raise RuntimeError("Notification settings require a clean database session.")
        # 인증 단계에서 만든 계정은 보존하고, 단일 계정 잠금을 풀어 정렬된 순서로 다시 잡는다.
        self.db.commit()
        try:
            lock_account_operations(self.db, (caregiver_hash, patient_hash))
            self.db.expire_all()
            deleted_account = (
                self.db.query(_UserAccount.user_hash)
                .filter(
                    _UserAccount.user_hash.in_((caregiver_hash, patient_hash)),
                    _UserAccount.deletion_requested_at.is_not(None),
                )
                .first()
            )
            if deleted_account is not None:
                raise HTTPException(410, ACCOUNT_DELETED_DETAIL)
            self._resolve_scope(caregiver_hash, patient_hash)
        except OperationalError as exc:
            self.db.rollback()
            raise HTTPException(
                503, ACCOUNT_BUSY_DETAIL, headers={"Retry-After": "5"},
            ) from exc
        except BaseException:
            self.db.rollback()
            raise

    # Function Name: _resolve_scope
    # Description:
    # - Normalizes both participants and verifies the caregiver is linked to the requested patient.
    # Parameters:
    # - caregiver_hash (str): Caregiver account participating in the patient link.
    # - patient_hash (str): Patient ownership scope for the operation.
    # Returns:
    # - Authorized caregiver and patient hashes, or HTTP 403.
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

    # Function Name: _find_setting
    # Description:
    # - Reads the stored notification preferences for one caregiver-patient pair.
    # Parameters:
    # - caregiver_hash (str): Caregiver account participating in the patient link.
    # - patient_hash (str): Patient ownership scope for the operation.
    # Returns:
    # - Notification setting row, or None when the pair has no saved settings.
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

    # 함수이름: _update_existing_setting_after_conflict
    # 함수역할:
    # - 동시 생성 충돌 후 두 계정을 다시 잠그고 삭제·연동을 재검증하여 기존 행의 선택 시간대 설정을 재적용한다.
    # 매개변수:
    # - caregiver_hash (str): 환자와 연동된 보호자 계정 식별자.
    # - patient_hash (str): 작업 대상 환자의 데이터 소유 범위 식별자.
    # - slot_key (str): morning, lunch, evening, bedtime 또는 필요시 복용 알림용 as_needed 키.
    # - notification_mode (str): 정규화된 비활성·복용 완료·미복용 마감 알림 모드.
    # - deadline_hour (int | None): 선택적인 미복용 마감 시.
    # - deadline_minute (int | None): 선택적인 미복용 마감 분.
    # 반환값:
    # - 갱신된 알림 응답. 행 부재는 409, 저장 실패는 500이며 잠금·삭제·연동 오류는 저장 재시도 전에 전파한다.
    def _update_existing_setting_after_conflict(
        self,
        caregiver_hash: str,
        patient_hash: str,
        slot_key: str,
        notification_mode: str,
        deadline_hour: int | None,
        deadline_minute: int | None,
    ) -> dict[str, object]:
        self._lock_notification_scope(caregiver_hash, patient_hash)
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

    # 함수이름: _persist_setting_state
    # 함수역할:
    # - 선택 시간대의 설정을 JSON에 병합하고 기존 호환 열과 전체 활성 상태를 함께 저장한다.
    # 매개변수:
    # - setting (_CaregiverNotification): 기존 호환 열과 시간대별 값을 포함한 보호자·환자 알림 설정 행.
    # - slot_key (str): morning, lunch, evening, bedtime 또는 필요시 복용 알림용 as_needed 키.
    # - notification_mode (str): 정규화된 비활성·복용 완료·미복용 마감 알림 모드.
    # - deadline_hour (int | None): 선택적인 미복용 마감 시.
    # - deadline_minute (int | None): 선택적인 미복용 마감 분.
    # 반환값:
    # - 커밋 전에 구성한 시간대 알림 성공 응답. 저장 오류는 전파하며 롤백은 호출자가 담당한다.
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
        # 잠금 해제 뒤 환자 삭제가 먼저 끝나도 응답 때문에 삭제된 행을 다시 읽지 않는다.
        self.db.flush()
        response = self._success_response(
            "Caregiver notification setting was saved.",
            setting,
            slot_key,
        )
        self.db.commit()
        return response

    # 함수이름: _normalize_slot
    # 함수역할:
    # - 시간대 키를 정규화하고 지원하지 않는 값은 API 입력 오류로 변환한다.
    # 매개변수:
    # - slot_key (str): morning, lunch, evening, bedtime 또는 필요시 복용 알림용 as_needed 키.
    # 반환값:
    # - 지원하는 시간대 키; 잘못된 값은 HTTP 400.
    def _normalize_slot(self, slot_key: str) -> str:
        try:
            return normalize_notification_slot(slot_key)
        except ValueError as exc:
            raise HTTPException(
                status_code=400,
                detail="Caregiver notification slot is not supported.",
            ) from exc

    # 함수이름: _coerce_notification_mode
    # 함수역할:
    # - 명시적 알림 옵션을 우선하고 없으면 기존 활성 플래그 또는 비활성 기본값을 적용한다.
    # 매개변수:
    # - enabled (bool | None): 요청한 알림 활성 상태.
    # - alert_option (str | None): 기존 활성 플래그보다 우선하는 선택적 알림 모드.
    # 반환값:
    # - 정규화된 알림 모드; 미지원 옵션은 HTTP 400.
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

    # 함수이름: _validate_deadline
    # 함수역할:
    # - 미복용 마감 알림 모드에만 마감 시와 분을 필수로 요구한다.
    # 매개변수:
    # - notification_mode (str): 정규화된 비활성·복용 완료·미복용 마감 알림 모드.
    # - deadline_hour (int | None): 선택적인 미복용 마감 시.
    # - deadline_minute (int | None): 선택적인 미복용 마감 분.
    # 반환값:
    # - 없음.
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

    # 함수이름: _to_entity
    # 함수역할:
    # - 저장 행의 시간대별 설정을 도메인 엔티티로 읽고 이미 엔티티인 입력은 유지한다.
    # 매개변수:
    # - setting (_CaregiverNotification | CaregiverNotification): 기존 호환 열과 시간대별 값을 포함한 보호자·환자 알림 설정 행.
    # - slot_key (str): morning, lunch, evening, bedtime 또는 필요시 복용 알림용 as_needed 키.
    # 반환값:
    # - 선택 시간대의 CaregiverNotification.
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

    # Function Name: _read_or_seed_slot_settings
    # Description: Delegates legacy-column and per-slot JSON interpretation to the shared effective settings policy without persisting anything.
    # Parameters: setting (_CaregiverNotification) is the current preference row.
    # Returns: Effective slot-to-setting dictionary used consistently by settings, queueing and dispatch paths.
    def _read_or_seed_slot_settings(
        self,
        setting: _CaregiverNotification,
    ) -> dict[str, dict[str, object]]:
        return effective_slot_settings(setting)

    # 함수이름: _to_response_dict
    # 함수역할:
    # - 선택 시간대의 알림 상태를 도메인 엔티티를 통해 응답 필드로 변환한다.
    # 매개변수:
    # - setting (_CaregiverNotification | CaregiverNotification): 기존 호환 열과 시간대별 값을 포함한 보호자·환자 알림 설정 행.
    # - slot_key (str): morning, lunch, evening, bedtime 또는 필요시 복용 알림용 as_needed 키.
    # 반환값:
    # - 환자·보호자·시간대와 알림 모드·마감 시각을 담은 사전.
    def _to_response_dict(
        self,
        setting: _CaregiverNotification | CaregiverNotification,
        slot_key: str = "morning",
    ) -> dict[str, object]:
        return self._to_entity(setting, slot_key).to_response_dict()

    # 함수이름: _success_response
    # 함수역할:
    # - 처리 결과 문구와 선택 시간대의 알림 설정을 성공 응답으로 묶는다.
    # 매개변수:
    # - message (str): 사용자에게 표시할 처리 결과 문구.
    # - setting (_CaregiverNotification | CaregiverNotification): 기존 호환 열과 시간대별 값을 포함한 보호자·환자 알림 설정 행.
    # - slot_key (str): morning, lunch, evening, bedtime 또는 필요시 복용 알림용 as_needed 키.
    # 반환값:
    # - success, message, data를 포함한 알림 설정 응답.
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
