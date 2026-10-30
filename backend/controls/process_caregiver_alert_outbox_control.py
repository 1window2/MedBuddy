# 파일명: process_caregiver_alert_outbox_control.py
# 역할: DB에 보존된 보호자 알림 요청을 안전하게 선점하고 전송한다.

import hashlib
import logging
import re
import sqlite3
from datetime import datetime, timedelta

from sqlalchemy import ColumnElement, case, or_, update
from sqlalchemy.orm import Session
from sqlalchemy.exc import DBAPIError

from boundaries.push_notification_boundary import PushNotificationBoundary
from controls.dispatch_caregiver_alert_control import DispatchCaregiverAlert
from controls.check_schedule_control import CheckSchedule
from controls.manage_linked_chat_control import ManageLinkedChat
from controls.manage_caregiver_alert_control import ManageCaregiverAlert
from fastapi import HTTPException
from core.application_clock import application_today
from entities.caregiver_alert_outbox_entity import (
    CAREGIVER_ALERT_EVENT_AS_NEEDED_COMPLETED,
    CAREGIVER_ALERT_EVENT_DOSE_COMPLETED,
    CAREGIVER_ALERT_EVENT_LATE_LINK_COMPLETED,
    CAREGIVER_ALERT_EVENT_MISSED_DEADLINE,
    CAREGIVER_ALERT_STATUS_DEAD_LETTER,
    CAREGIVER_ALERT_STATUS_FAILED,
    CAREGIVER_ALERT_STATUS_PENDING,
    CAREGIVER_ALERT_STATUS_PROCESSING,
    CAREGIVER_ALERT_STATUS_SENT,
    _CaregiverAlertOutbox,
    utc_now,
)

logger = logging.getLogger(__name__)

_PROCESSING_TIMEOUT = timedelta(minutes=5)
_MAX_RETRY_DELAY_SECONDS = 15 * 60
_MAX_DELIVERY_ATTEMPTS = 8


def _delivery_error_summary(exc: Exception) -> str:
    """Expose schema diagnostics without logging SQL parameters, tokens or patient data."""
    summary = type(exc).__name__
    if isinstance(exc, DBAPIError):
        original = exc.orig
        code = getattr(original, "sqlstate", None) or getattr(original, "sqlite_errorname", None)
        if code and re.fullmatch(r"[A-Z0-9_]+", str(code)):
            summary += f" [{code}]"
        if isinstance(original, sqlite3.OperationalError) and re.fullmatch(
            r"no such (?:column|table): [A-Za-z_][A-Za-z0-9_.]*", str(original)
        ):
            summary += f": {original}; check Alembic migrations"
    return summary[:500]


# 클래스명: _RetryablePushDeliveryError
# 역할:
# - 유효한 일부 기기에 푸시가 전달되지 않아 아웃박스 재시도가 필요함을 표시한다.
# 주요 책임:
# - 일부 유효 기기 전송 실패를 아웃박스 재시도 상태로 전달한다.
class _RetryablePushDeliveryError(RuntimeError):
    pass


# 클래스명: ProcessCaregiverAlertOutbox
# 역할:
# - 보호자 알림 아웃박스를 한 건씩 선점하여 푸시 전송 결과를 기록한다.
# 주요 책임:
# - 여러 서버가 같은 요청을 동시에 처리하지 않도록 원자적으로 선점한다.
# - 실패한 요청을 지수 간격으로 다시 시도할 수 있게 만든다.
# - 재시도 한도를 넘긴 요청을 종료 상태로 전환한다.
# - 전송 완료 요청을 다시 보내지 않는다.
# - 선점은 전송 전에 커밋하고 전송 결과는 전송 뒤 짧은 별도 트랜잭션으로 기록한다.
# 속성:
# - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
# - push_boundary (PushNotificationBoundary): 인증 모드에 맞춰 선택된 기기 푸시 전송 경계.
# - dispatcher (DispatchCaregiverAlert): 이 처리기가 다루는 모든 요청이 함께 쓰는 보호자 알림 전송 제어.
class ProcessCaregiverAlertOutbox:
    # 함수이름: __init__
    # 함수역할:
    # - 완료 알림 아웃박스를 처리할 DB 세션과 푸시 전송 경계를 연결한다.
    # 매개변수:
    # - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
    # - push_boundary (PushNotificationBoundary): 인증 모드에 맞춰 선택된 기기 푸시 전송 경계.
    # 반환값:
    # - 없음.
    def __init__(
        self,
        db: Session,
        push_boundary: PushNotificationBoundary,
    ) -> None:
        self.db = db
        self.push_boundary = push_boundary
        self.dispatcher = DispatchCaregiverAlert(
            db=db,
            push_boundary=push_boundary,
        )

    # 함수이름: _claimable_condition
    # 함수역할:
    # - 대기·실패 상태로 재시도 시각이 된 요청과 처리 중에 시간 제한을 넘겨 멈춘 요청을 고르는 조건을 만든다.
    # - 후보 조회와 선점 갱신이 같은 기준을 쓰게 한다.
    # 매개변수:
    # - now (datetime): 재시도 가능 시각과 처리 중 시간 제한을 비교할 기준 UTC 시각.
    # 반환값:
    # - 지금 선점할 수 있는 아웃박스 행을 고르는 SQL 조건.
    @staticmethod
    def _claimable_condition(now: datetime) -> ColumnElement[bool]:
        stale_before = now - _PROCESSING_TIMEOUT
        return or_(
            (
                _CaregiverAlertOutbox.status.in_(
                    (
                        CAREGIVER_ALERT_STATUS_PENDING,
                        CAREGIVER_ALERT_STATUS_FAILED,
                    )
                )
                & (_CaregiverAlertOutbox.available_at <= now)
            ),
            (
                _CaregiverAlertOutbox.status
                == CAREGIVER_ALERT_STATUS_PROCESSING
            )
            & (
                _CaregiverAlertOutbox.processing_started_at
                <= stale_before
            ),
        )

    # 함수이름: processDue
    # 함수역할:
    # - 지금 처리 가능한 알림 요청을 제한된 개수만큼 전송한다.
    # 매개변수:
    # - limit (int): 한 번에 처리할 최대 요청 수
    # 반환값:
    # - 처리 결과별 요청 개수
    def processDue(self, limit: int = 50) -> dict[str, int]:
        now = utc_now()
        candidate_ids = [
            int(row.id)
            for row in (
                self.db.query(_CaregiverAlertOutbox.id)
                .filter(self._claimable_condition(now))
                .order_by(_CaregiverAlertOutbox.created_at.asc())
                .limit(max(1, min(limit, 200)))
                .all()
            )
        ]
        results = {"sent": 0, "failed": 0, "skipped": 0}
        for outbox_id in candidate_ids:
            outcome = self.processOne(outbox_id)
            results[outcome] += 1
        return results

    # 함수이름: processOne
    # 함수역할:
    # - 한 알림 요청을 선점한 뒤 보호자 알림 전송을 시도한다.
    # - 전송 제어가 Firebase 호출 전에 세션을 반환하므로 요청 값은 전송 전에 미리 읽어 둔다.
    # - 전송이 끝난 뒤의 기록 실패는 재전송으로 이어지지 않도록 전송 완료 기록만 다시 시도한다.
    # 매개변수:
    # - outbox_id (int): 처리할 아웃박스 기본키
    # 반환값:
    # - 전송 결과를 나타내는 sent, failed 또는 skipped 문자열.
    def processOne(self, outbox_id: int) -> str:
        now = utc_now()
        claim = self.db.execute(
            update(_CaregiverAlertOutbox)
            .where(
                _CaregiverAlertOutbox.id == outbox_id,
                self._claimable_condition(now),
            )
            .values(
                status=CAREGIVER_ALERT_STATUS_PROCESSING,
                processing_started_at=now,
                last_error=None,
                # 처리 중에 멈춘 행을 다시 가져오는 것도 한 번의 시도로 센다. 세지 않으면 전송 뒤
                # 기록 단계에서 멈추는 행이 5분마다 재전송되고 끝내 포기되지 않는다.
                attempt_count=case(
                    (
                        _CaregiverAlertOutbox.status == CAREGIVER_ALERT_STATUS_PROCESSING,
                        _CaregiverAlertOutbox.attempt_count + 1,
                    ),
                    else_=_CaregiverAlertOutbox.attempt_count,
                ),
            )
        )
        self.db.commit()
        if claim.rowcount != 1:
            return "skipped"

        row = self.db.get(_CaregiverAlertOutbox, outbox_id)
        if row is None:
            return "skipped"
        if int(row.attempt_count or 0) >= _MAX_DELIVERY_ATTEMPTS:
            row.status = CAREGIVER_ALERT_STATUS_DEAD_LETTER
            row.processing_started_at = None
            row.last_error = "StalledProcessing"
            self.db.commit()
            logger.warning(
                "Caregiver alert outbox row stalled repeatedly and was given up (id=%s).",
                outbox_id,
            )
            return "failed"
        delivered = False
        try:
            event_type = str(
                row.event_type or CAREGIVER_ALERT_EVENT_DOSE_COMPLETED
            )
            patient_hash = str(row.patient_hash)
            slot_key = str(row.slot_key)
            schedule_date = row.schedule_date
            if event_type in (
                CAREGIVER_ALERT_EVENT_DOSE_COMPLETED,
                CAREGIVER_ALERT_EVENT_LATE_LINK_COMPLETED,
            ):
                # A late-link event reaches only the caregiver it names; the others
                # were already told by the patient's event for this slot and day.
                recipient_scope: dict[str, str] = {}
                if event_type == CAREGIVER_ALERT_EVENT_LATE_LINK_COMPLETED:
                    if row.caregiver_hash is None:
                        raise ValueError("Late-link completion event has no caregiver.")
                    recipient_scope["only_caregiver_hash"] = str(row.caregiver_hash)
                # Never reinterpret an old or undated event as today's dose.
                reason = None
                if schedule_date != application_today():
                    reason = "StaleOrUndatedCompletion"
                elif not CheckSchedule(self.db).is_medication_slot_complete(
                    patient_hash=patient_hash,
                    schedule_date=schedule_date,
                    slot_key=slot_key,
                ):
                    reason = "CompletionNoLongerCurrent"
                if reason is not None:
                    row.status = CAREGIVER_ALERT_STATUS_DEAD_LETTER
                    row.processing_started_at = None
                    row.last_error = reason
                    self.db.commit()
                    return "skipped"
                # 채팅 완료 기록은 푸시 공급자의 일시 장애와 무관하게 먼저 보존한다.
                # 날짜·시간대가 같아도 다른 아웃박스 요청은 구별하고 재시도에는 같은 키를 쓴다.
                # 생성 시각을 포함해 정리 이후 기본키가 재사용되어도 이전 알림과 합쳐지지 않게 한다.
                completion_event_key = hashlib.sha256(
                    f"caregiver-slot-completed:{row.id}:{row.created_at.isoformat()}".encode("utf-8")
                ).hexdigest()
                ManageLinkedChat(self.db).publish_slot_completion(
                    patient_hash=patient_hash,
                    slot_key=slot_key,
                    **recipient_scope,
                )
                delivery_result = self.dispatcher.notifySlotCompleted(
                    patient_hash=patient_hash,
                    slot_key=slot_key,
                    event_key=completion_event_key,
                    **recipient_scope,
                )
            elif event_type == CAREGIVER_ALERT_EVENT_AS_NEEDED_COMPLETED:
                if slot_key != "as_needed":
                    raise ValueError("As-needed outbox event has an invalid slot.")
                prn_result = self.dispatcher.notifyAsNeededDoseCompletedIfCurrent(
                    patient_hash=patient_hash, schedule_date=schedule_date,
                    event_key=str(row.event_key),
                )
                if prn_result is None:
                    # 날짜가 지났거나 복용이 취소·삭제된 이벤트는 재시도하지 않는다.
                    row.status = CAREGIVER_ALERT_STATUS_DEAD_LETTER
                    row.processing_started_at = None
                    row.last_error = "AsNeededDoseNoLongerCurrent"
                    self.db.commit()
                    return "skipped"
                delivery_result = prn_result
            elif event_type == CAREGIVER_ALERT_EVENT_MISSED_DEADLINE:
                if row.caregiver_hash is None or schedule_date is None:
                    raise ValueError("Missed-dose outbox event is incomplete.")
                caregiver_hash = str(row.caregiver_hash)
                try:
                    alert_context = ManageCaregiverAlert(self.db).context(row)
                except HTTPException:
                    alert_context = None
                missed_result = self.dispatcher.notifySlotMissedIfActionable(
                    caregiver_hash=caregiver_hash,
                    patient_hash=patient_hash,
                    slot_key=slot_key,
                    schedule_date=schedule_date,
                    alert_context=alert_context,
                )
                if missed_result is None:
                    # 그사이 복용했거나 기한이 바뀌었거나 날짜가 지나 보낼 필요가 없어졌다. 보내지 않은
                    # 알림을 전송 완료로 남기지 않도록 완료 알림과 같이 이유를 적어 포기한다.
                    row = self.db.get(_CaregiverAlertOutbox, outbox_id)
                    if row is not None:
                        row.status = CAREGIVER_ALERT_STATUS_DEAD_LETTER
                        row.processing_started_at = None
                        row.last_error = "MissedDoseNoLongerCurrent"
                        self.db.commit()
                    return "skipped"
                delivery_result = missed_result
            else:
                raise ValueError("Unsupported caregiver outbox event type.")
            if not delivery_result.all_valid_targets_succeeded:
                raise _RetryablePushDeliveryError(
                    "Some valid caregiver devices did not receive the notification."
                )
            delivered = True
            self._mark_sent(outbox_id)
            return "sent"
        except Exception as exc:
            self.db.rollback()
            if delivered:
                # 푸시는 이미 전달됐다. 실패로 기록하면 같은 알림을 다시 보내므로 전송 완료
                # 기록만 한 번 더 시도한다. 이 기록도 실패하면 예외를 올려 선점 상태로 남긴다.
                self._mark_sent(outbox_id)
                logger.warning(
                    "Caregiver alert outbox delivery was recorded on the second "
                    "attempt (id=%s): %s",
                    outbox_id,
                    _delivery_error_summary(exc),
                )
                return "sent"
            row = self.db.get(_CaregiverAlertOutbox, outbox_id)
            if row is None:
                return "failed"
            row.attempt_count = int(row.attempt_count or 0) + 1
            attempts_exhausted = row.attempt_count >= _MAX_DELIVERY_ATTEMPTS
            if attempts_exhausted:
                row.status = CAREGIVER_ALERT_STATUS_DEAD_LETTER
                row.available_at = utc_now()
            else:
                retry_seconds = min(
                    2 ** min(row.attempt_count, 10) * 5,
                    _MAX_RETRY_DELAY_SECONDS,
                )
                row.status = CAREGIVER_ALERT_STATUS_FAILED
                row.available_at = utc_now() + timedelta(seconds=retry_seconds)
            row.processing_started_at = None
            row.last_error = _delivery_error_summary(exc)
            self.db.commit()
            logger.warning(
                "Caregiver alert outbox delivery failed "
                "(id=%s, attempt=%s, terminal=%s): %s",
                outbox_id,
                row.attempt_count,
                attempts_exhausted,
                row.last_error,
            )
            return "failed"

    # 함수이름: _mark_sent
    # 함수역할:
    # - 전달이 끝난 알림 요청을 전송 완료로 기록하고 바로 커밋한다.
    # - 전송 전에 세션을 반환해 만료된 행을 다시 읽지 않도록 기본키 조건의 UPDATE 한 문장으로 쓴다.
    # 매개변수:
    # - outbox_id (int): 이 처리기가 선점해 전송을 마친 아웃박스 기본키.
    # 반환값:
    # - 없음.
    def _mark_sent(self, outbox_id: int) -> None:
        self.db.execute(
            update(_CaregiverAlertOutbox)
            .where(_CaregiverAlertOutbox.id == outbox_id)
            .values(
                status=CAREGIVER_ALERT_STATUS_SENT,
                sent_at=utc_now(),
                processing_started_at=None,
            )
        )
        self.db.commit()
