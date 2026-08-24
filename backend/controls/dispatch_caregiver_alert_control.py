# 파일명: dispatch_caregiver_alert_control.py
# 역할: 환자의 복약 완료 이벤트를 연결된 보호자 푸시 알림으로 변환한다.

import logging

from sqlalchemy.orm import Session

from boundaries.medication_completion_event_boundary import (
    MedicationCompletionEventBoundary,
)
from boundaries.push_notification_boundary import (
    PushDeliveryResult,
    PushNotificationBoundary,
)
from entities.caregiver_notification_entity import (
    CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
    _CaregiverNotification,
    decode_slot_settings,
)
from entities.device_push_token_entity import _DevicePushToken
from entities.user_setting_entity import _UserSetting
from repositories.patient_caregiver_link_repository import (
    PatientCaregiverLinkRepository,
)

logger = logging.getLogger(__name__)

_SLOT_NAMES = {
    "morning": "아침",
    "lunch": "점심",
    "evening": "저녁",
    "bedtime": "취침 전",
}
_ENGLISH_SLOT_NAMES = {
    "morning": "morning",
    "lunch": "lunch",
    "evening": "evening",
    "bedtime": "bedtime",
}


# 클래스명: DispatchCaregiverAlert
# 역할: 복약 상태 변경을 보호자 설정에 맞는 원격 알림으로 전달한다.
# 주요 책임:
#   - 활성 환자·보호자 연결과 시간대별 알림 설정을 확인한다.
#   - 알림을 원하는 보호자의 활성 FCM 토큰만 선택한다.
#   - Firebase가 거부한 만료 토큰을 비활성화한다.
class DispatchCaregiverAlert(MedicationCompletionEventBoundary):
    # 함수명: __init__
    # 역할:
    # - 보호자 연결 조회용 DB 세션과 푸시 전송 경계를 연결한다.
    def __init__(
        self,
        db: Session,
        push_boundary: PushNotificationBoundary,
        link_repository: PatientCaregiverLinkRepository | None = None,
    ) -> None:
        self.db = db
        self.push_boundary = push_boundary
        self.link_repository = (
            link_repository or PatientCaregiverLinkRepository(db)
        )

    # 함수명: notifySlotCompleted
    # 역할:
    # - 모든 약이 새로 완료된 복약 시간대를 구독한 보호자 기기에 알린다.
    # 매개변수:
    # - patient_hash: 복약을 완료한 환자의 식별 hash
    # - slot_key: 완료된 복약 시간대
    # 반환값:
    # - 전체 보호자 기기의 성공, 영구 실패 토큰, 재시도 가능한 실패 집계
    def notifySlotCompleted(
        self,
        *,
        patient_hash: str,
        slot_key: str,
    ) -> PushDeliveryResult:
        caregiver_hashes = self._caregivers_for_completed_slot(
            patient_hash,
            slot_key,
        )
        slot_name = _SLOT_NAMES.get(slot_key, "복약")
        success_count = 0
        invalid_tokens: list[str] = []
        retryable_failure_count = 0
        for caregiver_hash in caregiver_hashes:
            user_setting = self._user_setting(caregiver_hash)
            if user_setting is not None and not bool(
                user_setting.caregiver_notifications_enabled
            ):
                continue
            token_rows = (
                self.db.query(_DevicePushToken)
                .filter(
                    _DevicePushToken.user_hash == caregiver_hash,
                    _DevicePushToken.enabled.is_(True),
                )
                .all()
            )
            if not token_rows:
                continue
            is_english = (
                user_setting is not None
                and str(user_setting.language or "").strip().lower() == "en"
            )
            show_details = (
                user_setting is None
                or user_setting.notification_detail_mode != "type_only"
            )
            if is_english:
                title = "Medication completed"
                body = (
                    f"The patient completed all {_ENGLISH_SLOT_NAMES.get(slot_key, 'scheduled')} medications."
                    if show_details
                    else "A linked patient's medication status was updated."
                )
            else:
                title = "환자 복약 완료"
                body = (
                    f"환자가 {slot_name}에 복용할 약을 모두 복용했습니다."
                    if show_details
                    else "연동된 환자의 복약 상태가 변경되었습니다."
                )
            result = self.push_boundary.send_notification(
                tokens=[str(row.token) for row in token_rows],
                title=title,
                body=body,
                data={
                    "type": "caregiver_slot_completed",
                    "patient_hash": patient_hash,
                    "slot_key": slot_key,
                },
            )
            success_count += result.success_count
            invalid_tokens.extend(result.invalid_tokens)
            retryable_failure_count += result.retryable_failure_count
            if result.invalid_tokens:
                self._disable_invalid_tokens(result.invalid_tokens)
        return PushDeliveryResult(
            success_count=success_count,
            invalid_tokens=tuple(dict.fromkeys(invalid_tokens)),
            retryable_failure_count=retryable_failure_count,
        )

    # 함수명: _caregivers_for_completed_slot
    # 역할:
    # - 환자와 연결됐으며 해당 시간대 즉시 알림을 선택한 보호자만 찾는다.
    # 반환값:
    # - 알림을 받을 보호자 hash 목록
    def _caregivers_for_completed_slot(
        self,
        patient_hash: str,
        slot_key: str,
    ) -> list[str]:
        links = self.link_repository.list_active_for_patient(patient_hash)
        caregiver_hashes: list[str] = []
        for link in links:
            setting = (
                self.db.query(_CaregiverNotification)
                .filter(
                    _CaregiverNotification.patient_hash == patient_hash,
                    _CaregiverNotification.caregiver_hash == link.caregiver_hash,
                )
                .first()
            )
            if setting is None:
                continue
            slot_setting = decode_slot_settings(setting.slot_settings).get(slot_key)
            if (
                slot_setting is not None
                and slot_setting.get("notification_type")
                == CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED
            ):
                caregiver_hashes.append(str(link.caregiver_hash))
        return caregiver_hashes

    # 함수명: _user_setting
    # 역할: 보호자의 전역 알림 및 잠금 화면 개인정보 설정을 조회한다.
    def _user_setting(self, user_hash: str) -> _UserSetting | None:
        return (
            self.db.query(_UserSetting)
            .filter(_UserSetting.user_hash == user_hash)
            .first()
        )

    # 함수명: _disable_invalid_tokens
    # 역할:
    # - Firebase가 만료 또는 불일치로 거부한 토큰을 재사용하지 않도록 비활성화한다.
    # 매개변수:
    # - invalid_tokens: Firebase가 거부한 토큰 목록
    # 반환값:
    # - 없음
    def _disable_invalid_tokens(self, invalid_tokens: tuple[str, ...]) -> None:
        self.db.query(_DevicePushToken).filter(
            _DevicePushToken.token.in_(invalid_tokens)
        ).update({"enabled": False}, synchronize_session=False)
        self.db.commit()
