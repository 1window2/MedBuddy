# 파일명: process_caregiver_alert_outbox_control.py
# 역할: DB에 보존된 보호자 알림 요청을 안전하게 선점하고 전송한다.

import logging
from datetime import timedelta

from sqlalchemy import or_, update
from sqlalchemy.orm import Session

from boundaries.push_notification_boundary import PushNotificationBoundary
from controls.dispatch_caregiver_alert_control import DispatchCaregiverAlert
from entities.caregiver_alert_outbox_entity import (
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


# 클래스명: _RetryablePushDeliveryError
# 역할: 유효한 일부 기기에 푸시가 전달되지 않아 아웃박스 재시도가 필요함을 표시한다.
class _RetryablePushDeliveryError(RuntimeError):
    pass


# 클래스명: ProcessCaregiverAlertOutbox
# 역할: 보호자 알림 아웃박스를 한 건씩 선점하여 푸시 전송 결과를 기록한다.
# 주요 책임:
# - 여러 서버가 같은 요청을 동시에 처리하지 않도록 원자적으로 선점한다.
# - 실패한 요청을 지수 간격으로 다시 시도할 수 있게 만든다.
# - 재시도 한도를 넘긴 요청을 종료 상태로 전환한다.
# - 전송 완료 요청을 다시 보내지 않는다.
class ProcessCaregiverAlertOutbox:
    def __init__(
        self,
        db: Session,
        push_boundary: PushNotificationBoundary,
    ) -> None:
        self.db = db
        self.push_boundary = push_boundary

    # 함수명: processDue
    # 역할:
    # - 지금 처리 가능한 알림 요청을 제한된 개수만큼 전송한다.
    # 매개변수:
    # - limit: 한 번에 처리할 최대 요청 수
    # 반환값:
    # - 처리 결과별 요청 개수
    def processDue(self, limit: int = 50) -> dict[str, int]:
        now = utc_now()
        stale_before = now - _PROCESSING_TIMEOUT
        candidate_ids = [
            int(row.id)
            for row in (
                self.db.query(_CaregiverAlertOutbox.id)
                .filter(
                    or_(
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
                )
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

    # 함수명: processOne
    # 역할:
    # - 한 알림 요청을 선점한 뒤 보호자 알림 전송을 시도한다.
    # 매개변수:
    # - outbox_id: 처리할 아웃박스 기본키
    # 반환값:
    # - sent, failed, skipped 중 하나
    def processOne(self, outbox_id: int) -> str:
        now = utc_now()
        stale_before = now - _PROCESSING_TIMEOUT
        claim = self.db.execute(
            update(_CaregiverAlertOutbox)
            .where(
                _CaregiverAlertOutbox.id == outbox_id,
                or_(
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
                ),
            )
            .values(
                status=CAREGIVER_ALERT_STATUS_PROCESSING,
                processing_started_at=now,
                last_error=None,
            )
        )
        self.db.commit()
        if claim.rowcount != 1:
            return "skipped"

        row = self.db.get(_CaregiverAlertOutbox, outbox_id)
        if row is None:
            return "skipped"
        try:
            delivery_result = DispatchCaregiverAlert(
                db=self.db,
                push_boundary=self.push_boundary,
            ).notifySlotCompleted(
                patient_hash=str(row.patient_hash),
                slot_key=str(row.slot_key),
            )
            if not delivery_result.all_valid_targets_succeeded:
                raise _RetryablePushDeliveryError(
                    "Some valid caregiver devices did not receive the notification."
                )
            row.status = CAREGIVER_ALERT_STATUS_SENT
            row.sent_at = utc_now()
            row.processing_started_at = None
            self.db.commit()
            return "sent"
        except Exception as exc:
            self.db.rollback()
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
            row.last_error = type(exc).__name__[:500]
            self.db.commit()
            logger.warning(
                "Caregiver alert outbox delivery failed "
                "(id=%s, attempt=%s, terminal=%s): %s",
                outbox_id,
                row.attempt_count,
                attempts_exhausted,
                type(exc).__name__,
            )
            return "failed"
