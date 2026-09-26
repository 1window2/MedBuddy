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
from controls.queue_missed_dose_alerts_control import QueueMissedDoseAlerts

logger = logging.getLogger(__name__)


# 클래스명: CaregiverAlertOutboxWorker
# 역할:
# - 처리 가능한 보호자 알림 요청을 백그라운드에서 반복 조회한다.
# 주요 책임:
# - 전송 대상 알림을 독립 세션에서 주기적으로 처리하고 종료 신호 및 실패 시 롤백을 관리한다.
# 속성:
# - session_factory (sessionmaker[Session]): 주기별 DB 세션 생성기.
# - push_boundary_factory (Callable): 푸시 전송 경계 생성기.
# - interval_seconds (int): 조회 간격(초).
# - _task / _stop_event: 반복 작업과 종료 신호.
class CaregiverAlertOutboxWorker:
    # 함수이름: __init__
    # 함수역할:
    # - 주기별 세션과 푸시 경계 생성기를 보관하고 반복 작업의 종료 신호를 초기화한다.
    # 매개변수:
    # - session_factory (sessionmaker[Session]): 작업 주기마다 독립 SQLAlchemy 세션을 여는 팩터리.
    # - push_boundary_factory (Callable[[], PushNotificationBoundary]): 작업마다 사용할 푸시 전송 경계를 만드는 팩터리.
    # - interval_seconds (int): 아웃박스 처리 사이에 기다릴 시간(초).
    # 반환값:
    # - 없음; 반복 작업은 start에서 시작한다.
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

    # 함수이름: start
    # 함수역할:
    # - 실행 중인 작업이 없을 때만 아웃박스 반복 처리 태스크를 등록한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음; 기존 태스크가 있으면 추가로 시작하지 않는다.
    def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(self._run_loop())

    # 함수이름: stop
    # 함수역할:
    # - 종료 이벤트를 알리고 현재 처리 주기의 종료를 기다린 뒤 태스크 참조를 비운다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음; 실행 중이던 반복 작업이 끝난 뒤 반환한다.
    async def stop(self) -> None:
        self._stop_event.set()
        if self._task is not None:
            await self._task
            self._task = None

    # 함수이름: _run_loop
    # 함수역할:
    # - 동기 아웃박스 처리를 별도 스레드에 맡긴 뒤 설정된 간격 또는 종료 신호까지 대기한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음; 종료 이벤트가 설정되면 반복을 마친다.
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

    # 함수이름: _run_once
    # 함수역할:
    # - 새 세션에서 전송 시점이 된 알림을 처리하고 실패 시 롤백하며 항상 세션을 닫는다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음; 전송 결과나 처리 오류를 로그에 남긴다.
    def _run_once(self) -> None:
        db = self.session_factory()
        try:
            queued_count = QueueMissedDoseAlerts(db).queueDue()
            result = ProcessCaregiverAlertOutbox(
                db=db,
                push_boundary=self.push_boundary_factory(),
            ).processDue()
            if queued_count or result["sent"] or result["failed"]:
                logger.info(
                    "Caregiver alert outbox processed: queued=%s result=%s",
                    queued_count,
                    result,
                )
        except Exception:
            db.rollback()
            logger.exception("Caregiver alert outbox worker failed.")
        finally:
            db.close()
