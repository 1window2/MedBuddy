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


# Function Name: _delivery_error_summary
# Description: Keeps only the exception class and allowlisted database codes or missing-table/column diagnostics, omitting SQL parameters and patient data.
# Parameters: exc (Exception) is a failed delivery's exception.
# Returns: Diagnostic string capped at 500 characters; arbitrary exception messages are not included.
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
# 역할: 재시도 가능한 푸시 전송 실패를 아웃박스 처리기에 전달한다.
# 주요 책임: 일시적 전송 실패를 재시도 경로로 분류한다.
# 속성: 상속받은 args에 실패 설명을 보관한다.
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
    # Function Name: __init__
    # Description: Bind the outbox session and push adapter and create the caregiver dispatcher using the same dependencies.
    # Parameters: db (Session) owns outbox state; push_boundary (PushNotificationBoundary) delivers notifications.
    # Returns: None.
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

    # Function Name: _claimable_condition
    # Description: Build the SQL condition for available pending/failed rows or processing rows whose lease has timed out.
    # Parameters: now (datetime) is the UTC availability and lease-expiry reference.
    # Returns: ColumnElement[bool] without executing a query.
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

    # Function Name: processDue
    # Description: Select the oldest claimable outbox IDs and process each through the single-row delivery flow.
    # Parameters: limit (int) caps candidates, clamped to 1 through 200.
    # Returns: dict[str, int] of sent, failed and skipped outcomes; selection or unhandled processing failures propagate.
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

    # Function Name: _mark_sent
    # Description: Set the outbox row to sent, record the current UTC send time, clear its processing timestamp, and commit.
    # Parameters: outbox_id (int) identifies the processed event.
    # Returns: None; database failures propagate.
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
