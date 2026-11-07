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
from entities.medication_schedule_entity import (
    MEDICATION_SLOT_ENGLISH_NAMES,
    MEDICATION_SLOT_KOREAN_NAMES,
)
from services.push_recipient_resolver import PushRecipientResolver
from services.as_needed_caregiver_events import load_as_needed_taken_event_keys

logger = logging.getLogger(__name__)



# Class Name: _PreparedPush
# Role: Hold a resolved caregiver notification before external delivery.
# Responsibilities: Separate recipient lookup from network I/O so the database read transaction can be released.
# Attributes: tokens is the immutable recipient tuple; title and body are display text; data is the string-valued payload.
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

    # 함수이름: notifyAsNeededDoseCompletedIfCurrent
    # 함수역할: 오늘도 유효한 필요시 복용 이벤트만 현재 연동·알림·미리보기 설정에 따라 보호자에게 보낸다.
    # 매개변수: patient_hash (str)는 환자, schedule_date (date | None)는 복용일, event_key (str)는 안정된 복용 이벤트 키다.
    # 반환값: PushDeliveryResult 또는 날짜·기록이 무효이면 None. 채팅은 생성하지 않으며 전송 실패는 전달한다.
    def notifyAsNeededDoseCompletedIfCurrent(
        self, *, patient_hash: str, schedule_date: date | None, event_key: str,
    ) -> PushDeliveryResult | None:
        """오늘의 유효한 개별 필요시 복용을 현재 연동·설정에 따라 알리고 채팅은 만들지 않는다."""
        if schedule_date != application_now().date():
            return None
        keys = load_as_needed_taken_event_keys(self.db, [patient_hash], schedule_date)
        if event_key not in keys[patient_hash]:
            return None
        resolver = PushRecipientResolver(self.db)
        prepared_pushes: list[_PreparedPush] = []
        for caregiver_hash in self._caregivers_for_completed_slot(patient_hash, "as_needed"):
            if not resolver.caregiver_alerts_enabled(caregiver_hash):
                continue
            recipient = resolver.resolve(caregiver_hash)
            if not recipient.tokens:
                continue
            is_english = recipient.language == "en"
            if recipient.show_details:
                body = (
                    "The patient recorded an as-needed dose as taken."
                    if is_english else "환자가 필요시 약의 복용을 기록했습니다."
                )
            else:
                body = (
                    "A linked patient's medication status was updated."
                    if is_english else "연동된 환자의 복약 상태가 변경되었습니다."
                )
            prepared_pushes.append(_PreparedPush(
                tokens=recipient.tokens,
                title="As-needed dose recorded" if is_english else "필요시 복용 기록",
                body=body,
                data={
                    "type": "caregiver_dose_completed",
                    "recipient_hash": caregiver_hash,
                    "language": recipient.language,
                    "patient_hash": patient_hash,
                    "slot_key": "as_needed",
                    "event_key": event_key,
                    "schedule_date": schedule_date.isoformat(),
                },
            ))
        return self._send_prepared_pushes(prepared_pushes, resolver)

    # 함수이름: notifySlotCompleted
    # 함수역할:
    # - 모든 약이 새로 완료된 복약 시간대를 구독한 보호자 기기에 알린다.
    # - 수신자와 문구를 모두 읽은 뒤 세션의 읽기 트랜잭션을 끝내고 전송한다. 호출자는 자신의 변경을 먼저 커밋해야 한다.
    # 매개변수:
    # - patient_hash (str): 복약을 완료한 환자의 식별 hash
    # - slot_key (str): 완료된 복약 시간대
    # - only_caregiver_hash (str | None): 지정하면 구독한 보호자 가운데 이 보호자에게만 보낸다.
    # - event_key (str | None): 아웃박스 요청의 고정 식별자. 재시도에도 같은 기기 알림을 사용한다.
    # 반환값:
    # - 전체 보호자 기기의 성공, 영구 실패 토큰, 재시도 가능한 실패 집계
    def notifySlotCompleted(
        self,
        *,
        patient_hash: str,
        slot_key: str,
        only_caregiver_hash: str | None = None,
        event_key: str | None = None,
    ) -> PushDeliveryResult:
        resolver = PushRecipientResolver(self.db)
        caregiver_hashes = self._caregivers_for_completed_slot(
            patient_hash,
            slot_key,
        )
        if only_caregiver_hash is not None:
            caregiver_hashes = [
                caregiver_hash for caregiver_hash in caregiver_hashes
                if caregiver_hash == only_caregiver_hash
            ]
        slot_name = MEDICATION_SLOT_KOREAN_NAMES.get(slot_key, "복약")
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
                    f"The patient completed all {MEDICATION_SLOT_ENGLISH_NAMES.get(slot_key, 'scheduled')} medications."
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
                        **({"event_key": event_key} if event_key is not None else {}),
                    },
                )
            )
        return self._send_prepared_pushes(prepared_pushes, resolver)

    # Function Name: notifySlotMissed
    # Description: Delegate missed-dose delivery after rechecking actionability, mapping a no-longer-actionable result to zero deliveries.
    # Parameters: caregiver_hash identifies the recipient; patient_hash, slot_key and schedule_date identify the missed slot; alert_context optionally supplies notification action data.
    # Returns: PushDeliveryResult; delivery errors propagate.
    def notifySlotMissed(
        self,
        *,
        caregiver_hash: str,
        patient_hash: str,
        slot_key: str,
        schedule_date: date,
        alert_context: dict[str, str] | None = None,
    ) -> PushDeliveryResult:
        result = self.notifySlotMissedIfActionable(
            caregiver_hash=caregiver_hash, patient_hash=patient_hash,
            slot_key=slot_key, schedule_date=schedule_date, alert_context=alert_context,
        )
        return PushDeliveryResult(success_count=0) if result is None else result

    # Function Name: notifySlotMissedIfActionable
    # Description: Recheck the link, preferences, deadline and dose state before sending a missed-slot alert.
    # Parameters: caregiver_hash identifies the recipient; patient_hash, slot_key and schedule_date identify the case; alert_context optionally supplies action data.
    # Returns: PushDeliveryResult, or None when the missed slot is no longer actionable; delivery errors propagate.
    def notifySlotMissedIfActionable(
        self,
        *,
        caregiver_hash: str,
        patient_hash: str,
        slot_key: str,
        schedule_date: date,
        alert_context: dict[str, str] | None = None,
    ) -> PushDeliveryResult | None:
        resolver = PushRecipientResolver(self.db)
        if not self._missed_slot_is_actionable(
            resolver,
            caregiver_hash=caregiver_hash, patient_hash=patient_hash,
            slot_key=slot_key, schedule_date=schedule_date,
        ):
            return None
        return self._send_missed_notification(
            resolver,
            caregiver_hash=caregiver_hash, patient_hash=patient_hash,
            slot_key=slot_key, alert_context=alert_context,
        )

    # Function Name: isMissedSlotActionable
    # Description: Applies the same current-date, link, preference, deadline and completion checks used before missed-dose delivery.
    # Parameters: caregiver_hash, patient_hash (str) identify the pair; slot_key (str) selects the slot; schedule_date (date) is the event day.
    # Returns: bool indicating whether a new action is still valid; database failures propagate.
    def isMissedSlotActionable(
        self, *, caregiver_hash: str, patient_hash: str, slot_key: str, schedule_date: date,
    ) -> bool:
        """Share date, link, preference and completion checks with notification actions."""
        return self._missed_slot_is_actionable(
            PushRecipientResolver(self.db),
            caregiver_hash=caregiver_hash, patient_hash=patient_hash,
            slot_key=slot_key, schedule_date=schedule_date,
        )

    # Function Name: _missed_slot_is_actionable
    # Description: Rejects stale dates, inactive links, disabled/non-missed settings, future deadlines and completed or absent scheduled doses.
    # Parameters: resolver (PushRecipientResolver) reuses recipient preferences; caregiver_hash, patient_hash and slot_key (str) identify the scope; schedule_date (date) is the event day.
    # Returns: True only when the slot remains incomplete and caregiver alerts are enabled; query errors propagate.
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

    # Function Name: _send_missed_notification
    # Description: Localizes privacy-aware missed-dose text and splits tokens between legacy OS notifications and opted-in action payloads.
    # Parameters: resolver resolves tokens/preferences; caregiver_hash, patient_hash and slot_key (str) identify the event; alert_context (dict | None) enables actions when present.
    # Returns: PushDeliveryResult, with zero successes when no tokens exist; dispatch errors propagate.
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
            MEDICATION_SLOT_ENGLISH_NAMES.get(slot_key, "scheduled")
            if is_english
            else MEDICATION_SLOT_KOREAN_NAMES.get(slot_key, "복약")
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

    # Function Name: _send_prepared_pushes
    # Description: Release the read transaction before sending prepared notifications, aggregate delivery results, and disable invalid registrations through the resolver.
    # Parameters: prepared_pushes (list[_PreparedPush]) contains resolved payloads; resolver (PushRecipientResolver) owns registration cleanup.
    # Returns: PushDeliveryResult with totals and deduplicated invalid tokens; unexpected sender/cleanup errors propagate.
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

    # Function Name: _deadline_has_passed
    # Description: Compare the current time against today's configured deadline in the same time zone.
    # Parameters: current_time (datetime) supplies date/time/zone; slot_setting (dict[str, object]) supplies deadline_hour and deadline_minute.
    # Returns: bool, including True exactly at the deadline and False for missing or invalid deadline values.
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
            if setting is None or (slot_key == "as_needed" and not setting.enabled):
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
