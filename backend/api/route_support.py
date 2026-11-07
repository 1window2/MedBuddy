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
from core.request_rate_limits import (
    DAILY_QUOTA_EXCEEDED_DETAIL,
    RateLimitRule,
    resolve_daily_quota,
)
from services.chat_connection_manager import ChatConnectionManager

logger = logging.getLogger(__name__)


# Function Name: get_chat_connection_manager
# Description: Retrieves the initialized application-wide socket registry without creating a replacement.
# Parameters: request (Request) supplies application state.
# Returns: ChatConnectionManager; raises RuntimeError when missing or the wrong type.
def get_chat_connection_manager(request: Request) -> ChatConnectionManager:
    """애플리케이션 단위 실시간 연결 관리자를 반환한다."""
    manager = getattr(request.app.state, "chat_connection_manager", None)
    if not isinstance(manager, ChatConnectionManager):
        raise RuntimeError("Chat connection manager is not initialized.")
    return manager


# Function Name: process_completion_alert
# Description: Processes one durable completion event in a new session; logs dispatch errors so the outbox worker can retry without failing the completed request.
# Parameters: outbox_id (int) identifies the committed event.
# Returns: None; processing exceptions are isolated and the session closes, while session creation/closure errors can propagate.
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


# Function Name: enforce_chat_daily_quota
# Description: Charges a chat attempt against the account's daily budget, including retries and attempts whose later validation/save may fail.
# Parameters: request (Request) locates shared quota state; user_hash (str) identifies the authenticated account.
# Returns: None when allowed or limiting is disabled; raises HTTP 429 for exhaustion or 503 for required-store failure.
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


# Function Name: enforce_hospital_share_daily_quota
# Description: Charges hospital sharing to the same daily account budget as hospital search so chat cannot bypass provider-cost limits.
# Parameters: request (Request) supplies quota state; user_hash (str) is the authenticated account.
# Returns: None on allowance; quota/store HTTP failures propagate.
async def enforce_hospital_share_daily_quota(
    *,
    request: Request,
    user_hash: str,
) -> None:
    await _enforce_search_daily_quota(
        request=request, user_hash=user_hash, search_path="/api/v1/hospitals/nearby",
    )


# Function Name: enforce_pharmacy_share_daily_quota
# Description: Charges live pharmacy-share lookups against the nearby-pharmacy search budget.
# Parameters: request (Request) supplies quota state; user_hash (str) is the authenticated account.
# Returns: None on allowance; quota/store HTTP failures propagate.
async def enforce_pharmacy_share_daily_quota(
    *,
    request: Request,
    user_hash: str,
) -> None:
    await _enforce_search_daily_quota(
        request=request, user_hash=user_hash, search_path="/api/v1/pharmacy/nearby",
    )


# Function Name: _enforce_search_daily_quota
# Description: Resolves the selected GET search route's daily rule and charges the same account counter used by search.
# Parameters: request (Request) supplies the store; user_hash (str) is authenticated; search_path (str) is the canonical search route.
# Returns: None when allowed, unconfigured or limiting is disabled; exhaustion/storage failures propagate as HTTP errors.
async def _enforce_search_daily_quota(
    *,
    request: Request,
    user_hash: str,
    search_path: str,
) -> None:
    quota = resolve_daily_quota("GET", search_path)
    if not settings.RATE_LIMIT_ENABLED or quota is None:
        return
    rule, scope = quota
    await enforce_user_quota(
        request,
        user_hash=user_hash,
        request_scope=scope,
        rule=rule,
        exceeded_detail=DAILY_QUOTA_EXCEEDED_DETAIL,
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
