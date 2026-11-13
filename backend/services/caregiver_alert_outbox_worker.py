# 파일명: caregiver_alert_outbox_worker.py
# 역할: 서버가 실행되는 동안 보호자 알림 아웃박스를 짧은 간격으로 처리한다.

import logging
from collections.abc import Callable

from sqlalchemy.orm import Session, sessionmaker

from boundaries.push_notification_boundary import PushNotificationBoundary
from controls.process_caregiver_alert_outbox_control import (
    ProcessCaregiverAlertOutbox,
)
from controls.queue_missed_dose_alerts_control import QueueMissedDoseAlerts
from services.background_loop_runner import BackgroundLoopRunner


logger = logging.getLogger(__name__)


# Class Name: CaregiverAlertOutboxWorker
# Role: Periodically queues missed-dose alerts and processes durable caregiver deliveries.
# Responsibilities: Gives each cycle its own session and keeps queueing failures from blocking previously queued deliveries.
# Attributes: session_factory creates Sessions; push_boundary_factory creates delivery boundaries; interval_seconds is the polling delay.
# Note: Task and stop-event lifecycle are inherited from BackgroundLoopRunner.
class CaregiverAlertOutboxWorker(BackgroundLoopRunner):
    _cycle_logger = logger
    _cycle_failure_message = "Caregiver alert outbox worker cycle failed: %s"

    # Function Name: __init__
    # Description: Stores per-cycle dependencies and initializes inherited lifecycle state without opening a session.
    # Parameters: session_factory (sessionmaker[Session]) creates worker sessions; push_boundary_factory creates PushNotificationBoundary instances; interval_seconds (int) is the delay.
    # Returns: None; work begins only on start.
    def __init__(
        self,
        session_factory: sessionmaker[Session],
        push_boundary_factory: Callable[[], PushNotificationBoundary],
        interval_seconds: int,
    ) -> None:
        self.session_factory = session_factory
        self.push_boundary_factory = push_boundary_factory
        self.interval_seconds = interval_seconds
        super().__init__()

    # Function Name: _cycle_interval_seconds
    # Description: Supplies the configured delay after each outbox cycle.
    # Parameters: None.
    # Returns: interval_seconds as seconds; the value is not revalidated here.
    def _cycle_interval_seconds(self) -> float:
        return self.interval_seconds

    # Function Name: _run_once
    # Description: Uses a fresh session to queue due misses and process deliveries, independently rolling back/logging each failure and always closing the session.
    # Parameters: None; uses the configured session and push-boundary factories.
    # Returns: None. Queue/delivery errors are logged; session creation, rollback or closure failures may propagate to the outer loop.
    def _run_once(self) -> None:
        db = self.session_factory()
        try:
            queued_count = 0
            try:
                queued_count = QueueMissedDoseAlerts(db).queueDue()
            except Exception:
                db.rollback()
                logger.exception("Caregiver alert outbox worker could not queue alerts.")
            result = {"sent": 0, "failed": 0, "skipped": 0}
            try:
                result = ProcessCaregiverAlertOutbox(
                    db=db,
                    push_boundary=self.push_boundary_factory(),
                ).processDue()
            except Exception:
                db.rollback()
                logger.exception("Caregiver alert outbox worker failed.")
            if queued_count or result["sent"] or result["failed"]:
                logger.info(
                    "Caregiver alert outbox processed: queued=%s result=%s",
                    queued_count,
                    result,
                )
        finally:
            db.close()
