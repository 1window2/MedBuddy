# File Name: route_support.py
# Role: Owns the post-commit helpers shared by the medication and chat routers: caregiver completion dispatch, the chat daily quota and chat message publication.

import logging
from collections.abc import Iterable, Mapping

from fastapi import BackgroundTasks, Request
from sqlalchemy.orm import Session

from api.dependencies import (
    enforce_user_quota,
    get_push_notification_boundary,
)
from controls.manage_linked_chat_control import ChatSendResult
from controls.process_caregiver_alert_outbox_control import (
    ProcessCaregiverAlertOutbox,
)
from core.config import settings
from core.database import SessionLocal
from core.request_rate_limits import RateLimitRule
from services.chat_connection_manager import ChatConnectionManager

logger = logging.getLogger(__name__)


# 함수이름: get_chat_connection_manager
# 함수역할:
# - 애플리케이션에 등록된 채팅 실시간 연결 관리자를 반환한다.
# 매개변수:
# - request (Request): 현재 FastAPI 요청
# 반환값:
# - 초기화된 ChatConnectionManager
def get_chat_connection_manager(request: Request) -> ChatConnectionManager:
    """애플리케이션 단위 실시간 연결 관리자를 반환한다."""
    manager = getattr(request.app.state, "chat_connection_manager", None)
    if not isinstance(manager, ChatConnectionManager):
        raise RuntimeError("Chat connection manager is not initialized.")
    return manager


# 함수이름: process_completion_alert
# 함수역할:
# - 복약 체크와 함께 저장된 아웃박스 요청을 별도 DB 세션에서 즉시 처리한다.
# - 실패한 요청은 아웃박스 작업자가 다시 처리하므로 여기서는 예외를 격리한다.
# 매개변수:
# - outbox_id (int): 보호자 알림 아웃박스의 영속 기록 식별자.
# 반환값:
# - 없음.
def process_completion_alert(outbox_id: int) -> None:
    db = SessionLocal()
    try:
        ProcessCaregiverAlertOutbox(
            db=db,
            push_boundary=get_push_notification_boundary(),
        ).processOne(outbox_id)
    except Exception as exc:
        logger.warning(
            "Caregiver push background dispatch failed: %s",
            type(exc).__name__,
        )
    finally:
        db.close()


# Function Name: queue_completion_alerts
# Description:
# - Schedules one response-afterward dispatch per committed completion event.
# - When at least one dispatch was scheduled, ends the request session's transaction so its pooled connection is not held while the push runs; the request session is closed only after the background tasks.
# Parameters:
# - background_tasks (BackgroundTasks): Response-afterward task queue of the current request.
# - events (Iterable[Mapping[str, str | int]]): Committed completion events carrying their outbox_id.
# - db (Session): Request session whose work is already committed.
# Returns:
# - None.
# Note: Call it last, after the response payload has been built as plain values; a later read on db would open a new transaction. Blocking; async handlers call it through run_request_database_work.
def queue_completion_alerts(
    background_tasks: BackgroundTasks,
    events: Iterable[Mapping[str, str | int]],
    db: Session,
) -> None:
    queued = False
    for event in events:
        background_tasks.add_task(process_completion_alert, int(event["outbox_id"]))
        queued = True
    if queued:
        db.rollback()


# 함수이름: enforce_chat_daily_quota
# 함수역할:
# - 한도 검사에 도달한 사용자의 채팅 전송 시도 횟수를 일일 한도로 제한한다. 중복 전송과 이후 검증·저장에 실패한 시도도 한도를 소비한다.
# 매개변수:
# - request (Request): 애플리케이션 공유 상태에 접근할 FastAPI 요청.
# - user_hash (str): 작업 대상 계정의 데이터 소유 범위 식별자.
# 반환값:
# - 없음. 제한 초과 시 HTTP 오류를 발생시킨다.
async def enforce_chat_daily_quota(
    *,
    request: Request,
    user_hash: str,
) -> None:
    if not settings.RATE_LIMIT_ENABLED:
        return
    await enforce_user_quota(
        request,
        user_hash=user_hash,
        request_scope="POST:/api/v1/chat/messages:daily",
        rule=RateLimitRule(settings.CHAT_MESSAGE_DAILY_LIMIT, 86_400),
        exceeded_detail="오늘 보낼 수 있는 채팅 메시지 수를 초과했습니다.",
    )


# Function Name: publish_saved_message
# Description:
# - Builds the response for a committed chat message and, when the message was newly created, broadcasts it to the link's connected devices.
# Parameters:
# - link_id (int): Stored patient-caregiver link identifier.
# - result (ChatSendResult): Saved message and whether this request created it.
# - request (Request): FastAPI request giving access to shared application state.
# Returns:
# - Creation flag and the saved message as plain response values.
async def publish_saved_message(
    link_id: int, result: ChatSendResult, request: Request,
) -> dict[str, object]:
    """Share the same post-commit delivery path for text and dose receipts."""
    response_message = result.message.to_response_dict()
    if result.created:
        manager = get_chat_connection_manager(request)
        await manager.broadcast(
            link_id=link_id,
            event={"type": "chat_message", "message": response_message},
        )
        # Notification delivery was queued atomically with the message. It must
        # not depend on this response, the broadcast, or an in-process task.
    return {
        "success": True,
        "created": result.created,
        "data": response_message,
    }
