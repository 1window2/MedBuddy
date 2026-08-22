# 파일명: caregiver_alert_outbox_worker.py
# 역할: 서버가 실행되는 동안 보호자 알림 아웃박스를 짧은 간격으로 처리한다.

import asyncio
import logging
from collections.abc import Callable

from sqlalchemy.orm import Session, sessionmaker

from boundaries.push_notification_boundary import PushNotificationBoundary
from controls.process_caregiver_alert_outbox_control import (
    ProcessCaregiverAlertOutbox,
)

logger = logging.getLogger(__name__)


# 클래스명: CaregiverAlertOutboxWorker
# 역할: 처리 가능한 보호자 알림 요청을 백그라운드에서 반복 조회한다.
class CaregiverAlertOutboxWorker:
    def __init__(
        self,
        session_factory: sessionmaker[Session],
        push_boundary_factory: Callable[[], PushNotificationBoundary],
        interval_seconds: int,
    ) -> None:
        self.session_factory = session_factory
        self.push_boundary_factory = push_boundary_factory
        self.interval_seconds = interval_seconds
        self._stop_event = asyncio.Event()
        self._task: asyncio.Task[None] | None = None

    def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(self._run_loop())

    async def stop(self) -> None:
        self._stop_event.set()
        if self._task is not None:
            await self._task
            self._task = None

    async def _run_loop(self) -> None:
        while not self._stop_event.is_set():
            await asyncio.to_thread(self._run_once)
            try:
                await asyncio.wait_for(
                    self._stop_event.wait(),
                    timeout=self.interval_seconds,
                )
            except TimeoutError:
                continue

    def _run_once(self) -> None:
        db = self.session_factory()
        try:
            result = ProcessCaregiverAlertOutbox(
                db=db,
                push_boundary=self.push_boundary_factory(),
            ).processDue()
            if result["sent"] or result["failed"]:
                logger.info("Caregiver alert outbox processed: %s", result)
        except Exception:
            db.rollback()
            logger.exception("Caregiver alert outbox worker failed.")
        finally:
            db.close()
