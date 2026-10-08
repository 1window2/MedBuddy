# 파일명: dispatch_caregiver_alert_control.py
# 역할: 환자의 복약 완료 이벤트를 연결된 보호자 푸시 알림으로 변환한다.

import logging
from datetime import date, datetime, time
from typing import NamedTuple

from sqlalchemy.orm import Session

from boundaries.medication_completion_event_boundary import (
    MedicationCompletionEventBoundary,
)
from boundaries.push_notification_boundary import (
    PushDeliveryResult,
    PushNotificationBoundary,
)
from controls.check_schedule_control import CheckSchedule
from core.application_clock import application_now
from entities.caregiver_notification_entity import (
    CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
    _CaregiverNotification,
    effective_slot_settings,
)
from repositories.patient_caregiver_link_repository import (
    PatientCaregiverLinkRepository,
)
from services.push_recipient_resolver import PushRecipientResolver

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


# 클래스명: _PreparedPush
# 역할:
# - DB 세션을 반환하기 전에 완성해 둔 한 번의 푸시 전송 요청을 담는다.
# 주요 책임:
# - 전송 중 세션을 다시 읽지 않도록 ORM 행이 아닌 일반 값만 보관한다.
# 속성:
# - tokens (tuple[str, ...]): 알림을 보낼 기기 토큰.
# - title (str): 알림 제목.
# - body (str): 알림 본문.
# - data (dict[str, str]): 화면 이동용 문자열 데이터.
class _PreparedPush(NamedTuple):
    tokens: tuple[str, ...]
    title: str
    body: str
    data: dict[str, str]


# 클래스명: DispatchCaregiverAlert
# 역할:
# - 복약 상태 변경을 보호자 설정에 맞는 원격 알림으로 전달한다.
# 주요 책임:
# - 활성 환자·보호자 연결과 시간대별 알림 설정을 확인한다.
# - 알림을 원하는 보호자의 활성 FCM 토큰만 선택한다.
# - 전송에 필요한 값을 모두 읽은 뒤 DB 연결을 반환하고 나서 Firebase를 호출한다.
# - Firebase가 거부한 만료 토큰을 비활성화한다.
# 속성:
# - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
# - push_boundary (PushNotificationBoundary): 인증 모드에 맞춰 선택된 기기 푸시 전송 경계.
# - link_repository (PatientCaregiverLinkRepository): 활성 환자·보호자 연동 저장소.
class DispatchCaregiverAlert(MedicationCompletionEventBoundary):
    # 함수이름: __init__
    # 함수역할:
    # - 보호자 연결 조회용 DB 세션과 푸시 전송 경계를 연결한다.
    # 매개변수:
    # - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
    # - push_boundary (PushNotificationBoundary): 인증 모드에 맞춰 선택된 기기 푸시 전송 경계.
    # - link_repository (PatientCaregiverLinkRepository | None): 활성 환자·보호자 연동 저장소.
    # 반환값:
    # - 없음.
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

    # 함수이름: notifySlotCompleted
    # 함수역할:
    # - 모든 약이 새로 완료된 복약 시간대를 구독한 보호자 기기에 알린다.
    # - 수신자와 문구를 모두 읽은 뒤 세션의 읽기 트랜잭션을 끝내고 전송한다. 호출자는 자신의 변경을 먼저 커밋해야 한다.
    # 매개변수:
    # - patient_hash (str): 복약을 완료한 환자의 식별 hash
    # - slot_key (str): 완료된 복약 시간대
    # 반환값:
    # - 전체 보호자 기기의 성공, 영구 실패 토큰, 재시도 가능한 실패 집계
    def notifySlotCompleted(
        self,
        *,
        patient_hash: str,
        slot_key: str,
    ) -> PushDeliveryResult:
        resolver = PushRecipientResolver(self.db)
        caregiver_hashes = self._caregivers_for_completed_slot(
            patient_hash,
            slot_key,
        )
        slot_name = _SLOT_NAMES.get(slot_key, "복약")
        prepared_pushes: list[_PreparedPush] = []
        for caregiver_hash in caregiver_hashes:
            if not resolver.caregiver_alerts_enabled(caregiver_hash):
                continue
            recipient = resolver.resolve(caregiver_hash)
            if not recipient.tokens:
                continue
            is_english = recipient.language == "en"
            if is_english:
                title = "Medication completed"
                body = (
                    f"The patient completed all {_ENGLISH_SLOT_NAMES.get(slot_key, 'scheduled')} medications."
                    if recipient.show_details
                    else "A linked patient's medication status was updated."
                )
            else:
                title = "환자 복약 완료"
                body = (
                    f"환자가 {slot_name}에 복용할 약을 모두 복용했습니다."
                    if recipient.show_details
                    else "연동된 환자의 복약 상태가 변경되었습니다."
                )
            prepared_pushes.append(
                _PreparedPush(
                    tokens=recipient.tokens,
                    title=title,
                    body=body,
                    data={
                        "type": "caregiver_slot_completed",
                        "recipient_hash": caregiver_hash,
                        "language": recipient.language,
                        "patient_hash": patient_hash,
                        "slot_key": slot_key,
                    },
                )
            )
        return self._send_prepared_pushes(prepared_pushes, resolver)

    # 함수이름: notifySlotMissed
    # 함수역할:
    # - 보호자가 명시적으로 선택한 마감 시각 이후에도 미완료인 복약 시간대를 알린다.
    # - 전송 직전에 연결, 설정, 날짜와 실제 완료 상태를 다시 확인해 오래된 알림을 막는다.
    # - 수신자와 문구를 모두 읽은 뒤 세션의 읽기 트랜잭션을 끝내고 전송한다. 호출자는 자신의 변경을 먼저 커밋해야 한다.
    # 매개변수:
    # - caregiver_hash (str): 알림 수신 보호자 식별자.
    # - patient_hash (str): 확인할 연결 환자 식별자.
    # - slot_key (str): 확인할 복약 시간대 키.
    # - schedule_date (date): 알림 이벤트의 복약 날짜.
    # 반환값:
    # - 유효 대상별 FCM 성공·실패·무효 토큰 집계.
    def notifySlotMissed(
        self,
        *,
        caregiver_hash: str,
        patient_hash: str,
        slot_key: str,
        schedule_date: date,
        alert_context: dict[str, str] | None = None,
    ) -> PushDeliveryResult:
        resolver = PushRecipientResolver(self.db)
        if not self._missed_slot_is_actionable(
            resolver,
            caregiver_hash=caregiver_hash, patient_hash=patient_hash,
            slot_key=slot_key, schedule_date=schedule_date,
        ):
            return PushDeliveryResult(success_count=0)
        return self._send_missed_notification(
            resolver,
            caregiver_hash=caregiver_hash, patient_hash=patient_hash,
            slot_key=slot_key, alert_context=alert_context,
        )

    def isMissedSlotActionable(
        self, *, caregiver_hash: str, patient_hash: str, slot_key: str, schedule_date: date,
    ) -> bool:
        """Share date, link, preference and completion checks with notification actions."""
        return self._missed_slot_is_actionable(
            PushRecipientResolver(self.db),
            caregiver_hash=caregiver_hash, patient_hash=patient_hash,
            slot_key=slot_key, schedule_date=schedule_date,
        )

    def _missed_slot_is_actionable(
        self, resolver: PushRecipientResolver, *, caregiver_hash: str,
        patient_hash: str, slot_key: str, schedule_date: date,
    ) -> bool:
        """Run the checks with the caller's resolver so one event reads the recipient once."""
        current_time = application_now()
        if schedule_date != current_time.date():
            return False
        if not self.link_repository.has_active_pair(caregiver_hash, patient_hash):
            return False
        setting = (
            self.db.query(_CaregiverNotification)
            .filter(
                _CaregiverNotification.patient_hash == patient_hash,
                _CaregiverNotification.caregiver_hash == caregiver_hash,
                _CaregiverNotification.enabled.is_(True),
            )
            .first()
        )
        if setting is None:
            return False
        # 시간대 JSON이 없는 기존 행도 설정 화면과 같은 규칙으로 읽는다.
        slot_setting = effective_slot_settings(setting).get(slot_key)
        if (
            slot_setting is None
            or slot_setting.get("notification_type")
            != CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE
            or not self._deadline_has_passed(current_time, slot_setting)
        ):
            return False
        if not CheckSchedule(self.db).isMedicationSlotIncomplete(
            patient_hash=patient_hash,
            schedule_date=schedule_date,
            slot_key=slot_key,
        ):
            return False

        return resolver.caregiver_alerts_enabled(caregiver_hash)

    def _send_missed_notification(
        self, resolver: PushRecipientResolver, *, caregiver_hash: str,
        patient_hash: str, slot_key: str, alert_context: dict[str, str] | None,
    ) -> PushDeliveryResult:
        """Keep old devices on OS notifications; opt-in devices render action data."""
        recipient = resolver.resolve(caregiver_hash)
        if not recipient.tokens:
            return PushDeliveryResult(success_count=0)
        is_english = recipient.language == "en"
        slot_name = (
            _ENGLISH_SLOT_NAMES.get(slot_key, "scheduled")
            if is_english
            else _SLOT_NAMES.get(slot_key, "복약")
        )
        title = "Medication not checked" if is_english else "미복용 일정 확인"
        if recipient.show_details:
            body = (
                f"The linked patient's {slot_name} medication is not checked yet. Please contact them if needed."
                if is_english
                else f"연동된 환자의 {slot_name} 복약이 아직 확인되지 않았습니다. 필요하면 연락해 주세요."
            )
        else:
            body = (
                "A linked patient has a medication update."
                if is_english
                else "연동된 환자의 복약 상태를 확인해 주세요."
            )
        base_data = {
                "type": "caregiver_slot_missed",
                "recipient_hash": caregiver_hash,
                "language": recipient.language,
                "patient_hash": patient_hash,
                "slot_key": slot_key,
        }
        prepared_pushes: list[_PreparedPush] = []
        for supports_actions in (False, True):
            tokens = tuple(
                token for token in recipient.tokens
                if bool(token in recipient.action_tokens and alert_context) == supports_actions
            )
            if not tokens:
                continue
            data = dict(base_data)
            if supports_actions:
                data.update(alert_context or {})
                data.update(action_version="1", title=title, body=body)
            prepared_pushes.append(_PreparedPush(tokens=tokens, title=title, body=body, data=data))
        return self._send_prepared_pushes(prepared_pushes, resolver)

    # 함수이름: _send_prepared_pushes
    # 함수역할:
    # - 준비된 전송 요청을 DB 연결 없이 Firebase로 보내고 결과를 하나로 집계한다.
    # - Firebase 호출이 느려도 풀 연결과 읽기 트랜잭션을 잡고 있지 않도록 전송 전에 세션을 반환한다.
    # - 거부된 토큰은 전송 직후 짧은 별도 트랜잭션으로 비활성화한다.
    # 매개변수:
    # - prepared_pushes (list[_PreparedPush]): 세션에서 이미 읽어 완성한 전송 요청 목록.
    # - resolver (PushRecipientResolver): 이번 전송에서 수신자를 읽은 해석기.
    # 반환값:
    # - 전체 요청의 성공 수, 중복을 제거한 무효 토큰과 재시도 가능한 실패 수.
    def _send_prepared_pushes(
        self,
        prepared_pushes: list[_PreparedPush],
        resolver: PushRecipientResolver,
    ) -> PushDeliveryResult:
        if not prepared_pushes:
            return PushDeliveryResult(success_count=0)
        self.db.rollback()
        success_count = 0
        invalid_tokens: list[str] = []
        retryable_failure_count = 0
        for prepared_push in prepared_pushes:
            result = self.push_boundary.send_notification(
                tokens=list(prepared_push.tokens),
                title=prepared_push.title,
                body=prepared_push.body,
                data=prepared_push.data,
            )
            success_count += result.success_count
            invalid_tokens.extend(result.invalid_tokens)
            retryable_failure_count += result.retryable_failure_count
            if result.invalid_tokens:
                resolver.disable_invalid(result.invalid_tokens)
        return PushDeliveryResult(
            success_count=success_count,
            invalid_tokens=tuple(dict.fromkeys(invalid_tokens)),
            retryable_failure_count=retryable_failure_count,
        )

    # 함수이름: _deadline_has_passed
    # 함수역할: 저장된 시·분을 현재 날짜의 마감 시각으로 조합해 경과 여부를 검사한다.
    # 매개변수:
    # - current_time (datetime): 애플리케이션 시간대가 적용된 현재 시각.
    # - slot_setting (dict[str, object]): 마감 시·분을 포함한 시간대별 설정.
    # 반환값:
    # - 유효한 마감 시각을 지났으면 True, 값이 잘못됐거나 아직 전이면 False.
    @staticmethod
    def _deadline_has_passed(
        current_time: datetime,
        slot_setting: dict[str, object],
    ) -> bool:
        try:
            deadline_time = time(
                hour=int(slot_setting.get("deadline_hour")),
                minute=int(slot_setting.get("deadline_minute")),
            )
        except (TypeError, ValueError):
            return False
        deadline = datetime.combine(
            current_time.date(),
            deadline_time,
            tzinfo=current_time.tzinfo,
        )
        return current_time >= deadline

    # 함수이름: _caregivers_for_completed_slot
    # 함수역할:
    # - 환자와 연결됐으며 해당 시간대 즉시 알림을 선택한 보호자만 찾는다.
    # 매개변수:
    # - patient_hash (str): 작업 대상 환자의 데이터 소유 범위 식별자.
    # - slot_key (str): morning, lunch, evening, bedtime 중 복용 시간대 키.
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
            # 시간대 JSON이 없는 기존 행도 설정 화면과 같은 규칙으로 읽는다.
            slot_setting = effective_slot_settings(setting).get(slot_key)
            if (
                slot_setting is not None
                and slot_setting.get("notification_type")
                == CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED
            ):
                caregiver_hashes.append(str(link.caregiver_hash))
        return caregiver_hashes
