# 파일명: chat_router.py
# 역할: 환자·보호자 연동별 채팅 REST 및 WebSocket API를 제공한다.

"""환자·보호자 연동별 채팅 REST 및 WebSocket API를 제공한다."""

import asyncio
import logging
import time

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    HTTPException,
    Query,
    Request,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from api.dependencies import (
    get_authenticated_app_principal,
    get_authenticated_principal,
    get_authorization_control,
    get_manage_linked_chat,
    get_push_notification_boundary,
    get_request_rate_limit_store,
    verify_app_check_token,
)
from controls.authorization_control import AuthorizationControl
from controls.dispatch_chat_message_alert_control import DispatchChatMessageAlert
from controls.manage_linked_chat_control import ManageLinkedChat
from core.config import settings
from core.database import SessionLocal
from core.request_rate_limits import RateLimitRule, RequestRateLimitStore
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH
from schemas.chat import ChatMessageCreate, ChatReadUpdate
from services.chat_connection_manager import ChatConnectionManager

router = APIRouter()
logger = logging.getLogger(__name__)


# 함수이름: get_chat_connection_manager
# 함수역할: 애플리케이션에 등록된 채팅 실시간 연결 관리자를 반환한다.
# 매개변수: request - 현재 FastAPI 요청
# 반환값: 초기화된 ChatConnectionManager
def get_chat_connection_manager(request: Request) -> ChatConnectionManager:
    """애플리케이션 단위 실시간 연결 관리자를 반환한다."""
    manager = getattr(request.app.state, "chat_connection_manager", None)
    if not isinstance(manager, ChatConnectionManager):
        raise RuntimeError("Chat connection manager is not initialized.")
    return manager


# 함수이름: get_chat_messages
# 함수역할: 인증된 연동 참여자에게 채팅 기록 한 페이지를 반환한다.
# 매개변수: link_id, user_hash, 페이지 기준과 인증·인가 의존성
# 반환값: 메시지 목록과 페이지 정보
@router.get("/links/{link_id}/messages")
def get_chat_messages(
    link_id: int,
    user_hash: str = DEFAULT_PATIENT_HASH,
    before_message_id: int | None = Query(default=None, ge=1),
    limit: int = Query(default=50, ge=1, le=100),
    principal: AuthenticatedPrincipal = Depends(get_authenticated_app_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    chat: ManageLinkedChat = Depends(get_manage_linked_chat),
) -> dict[str, object]:
    """현재 참여자가 접근할 수 있는 채팅 기록 한 페이지를 반환한다."""
    authorized_user_hash = authorization.resolveOwnUserHash(principal, user_hash)
    return chat.request_history(
        link_id=link_id,
        user_hash=authorized_user_hash,
        before_message_id=before_message_id,
        limit=limit,
    )


# 함수이름: get_chat_medications
# 함수역할: 현재 연동 환자의 복용 중인 약을 채팅 선택 목록으로 반환한다.
# 매개변수: link_id, user_hash와 인증·인가 의존성
# 반환값: 선택 가능한 복약 정보 목록
@router.get("/links/{link_id}/medications")
def get_chat_medications(
    link_id: int,
    user_hash: str = DEFAULT_PATIENT_HASH,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_app_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    chat: ManageLinkedChat = Depends(get_manage_linked_chat),
) -> dict[str, object]:
    """현재 연동 환자의 복용 중인 약을 채팅 선택 목록으로 반환한다."""
    authorized_user_hash = authorization.resolveOwnUserHash(principal, user_hash)
    return chat.request_medication_contexts(
        link_id=link_id,
        user_hash=authorized_user_hash,
    )


# 함수이름: get_chat_schedule_contexts
# 함수역할: 연동 환자의 오늘 복약 상태를 시간대별 채팅 카드 형식으로 반환한다.
# 매개변수: link_id, user_hash와 인증·인가 의존성
# 반환값: 시간대별 복약 상태 목록
@router.get("/links/{link_id}/schedule-contexts")
def get_chat_schedule_contexts(
    link_id: int,
    user_hash: str = DEFAULT_PATIENT_HASH,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_app_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    chat: ManageLinkedChat = Depends(get_manage_linked_chat),
) -> dict[str, object]:
    """현재 연동의 시간대별 약 목록과 완료 진행률을 반환한다."""
    authorized_user_hash = authorization.resolveOwnUserHash(principal, user_hash)
    return chat.request_schedule_contexts(
        link_id=link_id,
        user_hash=authorized_user_hash,
    )


# 함수이름: get_chat_medication_detail
# 함수역할: 채팅 참여자에게 메시지에 연결된 약의 상세정보를 반환한다.
# 매개변수: link_id, medication_id, user_hash와 인증·인가 의존성
# 반환값: 권한이 확인된 저장 복약 상세정보
@router.get("/links/{link_id}/medications/{medication_id}")
def get_chat_medication_detail(
    link_id: int,
    medication_id: int,
    user_hash: str = DEFAULT_PATIENT_HASH,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_app_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    chat: ManageLinkedChat = Depends(get_manage_linked_chat),
) -> dict[str, object]:
    """활성 연동 참여자에게 환자 소유 약의 상세정보를 반환한다."""
    authorized_user_hash = authorization.resolveOwnUserHash(principal, user_hash)
    return chat.request_medication_detail(
        link_id=link_id,
        user_hash=authorized_user_hash,
        medication_id=medication_id,
    )


# 함수이름: post_chat_message
# 함수역할: 일반 또는 복약 맥락 메시지를 한 번만 저장하고 실시간 전송과 푸시를 연결한다.
# 매개변수: link_id, 메시지 DTO, 사용자 식별값과 요청 의존성
# 반환값: 생성 여부와 저장된 메시지
@router.post("/links/{link_id}/messages")
async def post_chat_message(
    link_id: int,
    payload: ChatMessageCreate,
    background_tasks: BackgroundTasks,
    request: Request,
    user_hash: str = DEFAULT_PATIENT_HASH,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_app_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    chat: ManageLinkedChat = Depends(get_manage_linked_chat),
) -> dict[str, object]:
    """메시지를 저장하고 채팅방에 즉시 방송하며 필요하면 푸시를 예약한다."""
    authorized_user_hash = authorization.resolveOwnUserHash(principal, user_hash)
    await _enforce_chat_daily_quota(
        request=request,
        user_hash=authorized_user_hash,
    )
    result = chat.send_message(
        link_id=link_id,
        sender_hash=authorized_user_hash,
        client_message_id=payload.client_message_id,
        body=payload.body,
        medication_id=payload.medication_id,
        medication_ids=payload.medication_ids,
        message_kind=payload.message_kind,
        slot_key=payload.slot_key,
        pharmacy_id=payload.pharmacy_id,
    )
    response_message = result.message.to_response_dict()
    if result.created:
        manager = get_chat_connection_manager(request)
        await manager.broadcast(
            link_id=link_id,
            event={"type": "chat_message", "message": response_message},
        )
        recipient_is_connected = await manager.is_user_connected(
            link_id=link_id,
            user_hash=result.recipient_hash,
        )
        if not recipient_is_connected and await _reserve_chat_push_notification(
            request=request,
            recipient_hash=result.recipient_hash,
            link_id=link_id,
        ):
            background_tasks.add_task(
                _dispatch_chat_notification,
                recipient_hash=result.recipient_hash,
                link_id=link_id,
                message_body=result.message.body,
                message_kind=result.message.message_kind,
                context_payload=result.message.context_payload,
            )
    return {
        "success": True,
        "created": result.created,
        "data": response_message,
    }


# 함수이름: mark_chat_read
# 함수역할: 상대 메시지를 읽음 처리하고 연결된 기기에 변경을 방송한다.
# 매개변수: link_id, 마지막 확인 메시지, 사용자 식별값과 요청 의존성
# 반환값: 읽음 처리 개수와 마지막 메시지 정보
@router.post("/links/{link_id}/read")
async def mark_chat_read(
    link_id: int,
    payload: ChatReadUpdate,
    request: Request,
    user_hash: str = DEFAULT_PATIENT_HASH,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_app_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    chat: ManageLinkedChat = Depends(get_manage_linked_chat),
) -> dict[str, object]:
    """현재 참여자가 확인한 상대 메시지를 읽음 처리하고 실시간으로 알린다."""
    authorized_user_hash = authorization.resolveOwnUserHash(principal, user_hash)
    response = chat.mark_read(
        link_id=link_id,
        reader_hash=authorized_user_hash,
        through_message_id=payload.through_message_id,
    )
    read_data = response["data"]
    if isinstance(read_data, dict) and read_data.get("updated_count", 0):
        await get_chat_connection_manager(request).broadcast(
            link_id=link_id,
            event={
                "type": "chat_read",
                "reader_hash": authorized_user_hash,
                **read_data,
            },
        )
    return response


# 함수이름: get_chat_unread_count
# 함수역할: 현재 사용자가 읽지 않은 상대 메시지 수를 반환한다.
# 매개변수: link_id, user_hash와 인증·인가 의존성
# 반환값: 읽지 않은 메시지 수
@router.get("/links/{link_id}/unread-count")
def get_chat_unread_count(
    link_id: int,
    user_hash: str = DEFAULT_PATIENT_HASH,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_app_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    chat: ManageLinkedChat = Depends(get_manage_linked_chat),
) -> dict[str, object]:
    """현재 참여자가 읽지 않은 채팅 메시지 개수를 반환한다."""
    authorized_user_hash = authorization.resolveOwnUserHash(principal, user_hash)
    return chat.request_unread_count(
        link_id=link_id,
        user_hash=authorized_user_hash,
    )


# 함수이름: stream_chat_events
# 함수역할: 인증된 연동 참여자에게 메시지와 읽음 이벤트를 실시간 전달한다.
# 매개변수: websocket, link_id, user_hash
# 반환값: 없음
@router.websocket("/links/{link_id}/stream")
async def stream_chat_events(
    websocket: WebSocket,
    link_id: int,
    user_hash: str = DEFAULT_PATIENT_HASH,
) -> None:
    """인증된 연동 참여자에게 새 메시지와 읽음 이벤트를 실시간 전달한다."""
    db = SessionLocal()
    manager = getattr(websocket.app.state, "chat_connection_manager", None)
    if not isinstance(manager, ChatConnectionManager):
        await websocket.close(code=1011)
        db.close()
        return
    authorized_user_hash = ""
    connected = False
    try:
        principal = _authenticate_websocket(websocket)
        authorization = AuthorizationControl(db)
        authorized_user_hash = authorization.resolveOwnUserHash(principal, user_hash)
        try:
            allowed, retry_after = await _reserve_websocket_connection(
                websocket=websocket,
                user_hash=authorized_user_hash,
            )
        except RuntimeError:
            await websocket.close(code=1013)
            db.close()
            return
        if not allowed:
            await websocket.close(code=4429, reason=str(max(1, retry_after)))
            db.close()
            return
        ManageLinkedChat(db).require_active_link(
            link_id=link_id,
            user_hash=authorized_user_hash,
        )
        db.commit()
    except HTTPException as exc:
        db.rollback()
        await websocket.close(code=_websocket_close_code(exc.status_code))
        db.close()
        return
    except Exception:
        db.rollback()
        await websocket.close(code=1011)
        db.close()
        return

    try:
        connected = await manager.connect(
            link_id=link_id,
            user_hash=authorized_user_hash,
            websocket=websocket,
        )
        if not connected:
            return
        await websocket.send_json({"type": "chat_ready", "link_id": link_id})
        last_ping_at = 0.0
        while True:
            try:
                message = await asyncio.wait_for(
                    websocket.receive_text(),
                    timeout=settings.CHAT_WEBSOCKET_IDLE_TIMEOUT_SECONDS,
                )
            except TimeoutError:
                await websocket.close(code=4408)
                return
            if len(message.encode("utf-8")) > settings.CHAT_WEBSOCKET_MAX_FRAME_BYTES:
                await websocket.close(code=1009)
                return
            if message != "ping":
                await websocket.close(code=1003)
                return
            now = time.monotonic()
            if (
                last_ping_at > 0
                and now - last_ping_at
                < settings.CHAT_WEBSOCKET_MIN_PING_INTERVAL_SECONDS
            ):
                await websocket.close(code=4429)
                return
            last_ping_at = now
            await websocket.send_json({"type": "pong"})
    except WebSocketDisconnect:
        pass
    finally:
        if connected:
            await manager.disconnect(
                link_id=link_id,
                user_hash=authorized_user_hash,
                websocket=websocket,
            )
        db.close()


# 함수이름: _enforce_chat_daily_quota
# 함수역할: 한 사용자가 하루 동안 저장할 수 있는 채팅 메시지 수를 제한한다.
# 매개변수: request, user_hash
# 반환값: 없음. 제한 초과 시 HTTP 오류를 발생시킨다.
async def _enforce_chat_daily_quota(
    *,
    request: Request,
    user_hash: str,
) -> None:
    if not settings.RATE_LIMIT_ENABLED:
        return
    try:
        allowed, retry_after = await get_request_rate_limit_store(request).consume(
            identity=f"user:{user_hash}",
            request_scope="POST:/api/v1/chat/messages:daily",
            rule=RateLimitRule(
                settings.CHAT_MESSAGE_DAILY_LIMIT,
                86_400,
            ),
        )
    except RuntimeError as exc:
        raise HTTPException(
            status_code=503,
            detail="Request quota storage is temporarily unavailable.",
            headers={"Retry-After": "5"},
        ) from exc
    if not allowed:
        raise HTTPException(
            status_code=429,
            detail="오늘 보낼 수 있는 채팅 메시지 수를 초과했습니다.",
            headers={"Retry-After": str(max(1, retry_after))},
        )


# 함수이름: _reserve_chat_push_notification
# 함수역할: 짧은 시간에 같은 상대에게 푸시가 반복 전송되지 않도록 예약한다.
# 매개변수: request, recipient_hash, link_id
# 반환값: 이번 메시지에 푸시를 전송할지 여부
async def _reserve_chat_push_notification(
    *,
    request: Request,
    recipient_hash: str,
    link_id: int,
) -> bool:
    if not settings.RATE_LIMIT_ENABLED:
        return True
    try:
        allowed, _ = await get_request_rate_limit_store(request).consume(
            identity=f"chat-push:{recipient_hash}:{link_id}",
            request_scope="POST:/api/v1/chat/push",
            rule=RateLimitRule(
                1,
                settings.CHAT_PUSH_MIN_INTERVAL_SECONDS,
            ),
        )
        return allowed
    except RuntimeError:
        # 푸시 제한 저장소 장애가 채팅 저장 자체를 실패시키지 않게 한다.
        logger.warning("Chat push quota storage is temporarily unavailable.")
        return False


# 함수이름: _reserve_websocket_connection
# 함수역할: 반복적인 실시간 연결 시도로 서버 자원이 고갈되지 않게 제한한다.
# 매개변수: websocket, user_hash
# 반환값: 연결 허용 여부와 재시도 대기 초
async def _reserve_websocket_connection(
    *,
    websocket: WebSocket,
    user_hash: str,
) -> tuple[bool, int]:
    if not settings.RATE_LIMIT_ENABLED:
        return True, 0
    store = getattr(websocket.app.state, "request_rate_limit_store", None)
    if not isinstance(store, RequestRateLimitStore):
        raise RuntimeError("Request rate-limit store is not initialized.")
    return await store.consume(
        identity=f"websocket:{user_hash}",
        request_scope="CONNECT:/api/v1/chat/stream",
        rule=RateLimitRule(
            settings.CHAT_WEBSOCKET_CONNECTIONS_PER_MINUTE,
            60,
        ),
    )


# 함수이름: _authenticate_websocket
# 함수역할: WebSocket 요청을 HTTP API와 같은 인증 정책으로 검증한다.
# 매개변수: websocket - 연결 요청
# 반환값: 검증된 사용자 주체
def _authenticate_websocket(websocket: WebSocket) -> AuthenticatedPrincipal:
    """HTTP API와 같은 Firebase 및 App Check 규칙으로 WebSocket을 인증한다."""
    contract_version = websocket.headers.get("x-medbuddy-api-contract", "").strip()
    if contract_version != settings.API_CONTRACT_VERSION:
        raise HTTPException(status_code=409, detail="API contract mismatch.")
    verify_app_check_token(websocket.headers.get("x-firebase-appcheck"))
    authorization_header = websocket.headers.get("authorization", "").strip()
    credentials: HTTPAuthorizationCredentials | None = None
    if authorization_header:
        scheme, separator, token = authorization_header.partition(" ")
        if not separator or not token.strip():
            raise HTTPException(status_code=401, detail="Invalid authorization header.")
        credentials = HTTPAuthorizationCredentials(
            scheme=scheme,
            credentials=token.strip(),
        )
    return get_authenticated_principal(credentials)


# 함수이름: _websocket_close_code
# 함수역할: HTTP 오류 상태를 WebSocket 종료 코드로 변환한다.
# 매개변수: status_code - HTTP 상태 코드
# 반환값: WebSocket 종료 코드
def _websocket_close_code(status_code: int) -> int:
    """HTTP 인증 오류를 브라우저 호환 WebSocket 종료 코드로 변환한다."""
    if status_code == 401:
        return 4401
    if status_code == 403:
        return 4403
    if status_code == 404:
        return 4404
    if status_code == 409:
        return 4409
    return 1011


# 함수이름: _dispatch_chat_notification
# 함수역할: 채팅방에 접속하지 않은 상대에게 새 메시지 알림을 전달한다.
# 매개변수: recipient_hash, link_id, message_body
# 반환값: 없음
def _dispatch_chat_notification(
    *,
    recipient_hash: str,
    link_id: int,
    message_body: str,
    message_kind: str,
    context_payload: dict[str, object] | None,
) -> None:
    """응답 이후 별도 DB 세션으로 오프라인 상대의 푸시를 전송한다."""
    db = SessionLocal()
    try:
        DispatchChatMessageAlert(
            db,
            get_push_notification_boundary(),
        ).notify_new_message(
            recipient_hash=recipient_hash,
            link_id=link_id,
            message_body=message_body,
            message_kind=message_kind,
            slot_key=_notification_slot_key(context_payload),
        )
    finally:
        db.close()


def _notification_slot_key(
    context_payload: dict[str, object] | None,
) -> str | None:
    """구조화 메시지에서 알림 이동에 사용할 시간대 식별자를 꺼낸다."""
    if not isinstance(context_payload, dict):
        return None
    schedule_context = context_payload.get("schedule_context")
    if not isinstance(schedule_context, dict):
        return None
    slot_key = schedule_context.get("slot_key")
    return str(slot_key) if slot_key else None
