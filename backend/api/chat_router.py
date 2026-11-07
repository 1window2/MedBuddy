# 파일명: chat_router.py
# 역할: 환자·보호자 연동별 채팅 REST 및 WebSocket API를 제공한다.

"""환자·보호자 연동별 채팅 REST 및 WebSocket API를 제공한다."""

import asyncio
import logging
import time
from datetime import UTC, datetime

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
from starlette.concurrency import run_in_threadpool

from api.dependencies import (
    get_authenticated_app_principal,
    get_authenticated_principal,
    get_authorization_control,
    get_manage_linked_chat,
    get_check_nearby_hospital,
    get_check_nearby_pharmacy,
    verify_app_check_token,
)
from api.route_support import (
    enforce_chat_daily_quota,
    enforce_hospital_share_daily_quota,
    enforce_pharmacy_share_daily_quota,
    get_chat_connection_manager,
    publish_saved_message,
    queue_completion_alerts,
)
from controls.authorization_control import AuthorizationControl
from controls.check_nearby_hospital_control import CheckNearbyHospital
from controls.check_nearby_pharmacy_control import CheckNearbyPharmacy
from controls.check_schedule_control import CheckSchedule
from controls.manage_linked_chat_control import ManageLinkedChat
from core.api_contract import CHAT_CLOSE_CODES_FEATURE, client_declares_feature
from core.config import settings
from core.database import SessionLocal
from core.request_database_work import run_request_database_work
from core.request_rate_limits import RateLimitRule, RequestRateLimitStore
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH
from entities.chat_message_entity import (
    CHAT_MESSAGE_KIND_HOSPITAL_SHARE,
    CHAT_MESSAGE_KIND_PHARMACY_SHARE,
    CHAT_MESSAGE_KIND_PHARMACY_PHONE_VERIFIED,
)
from api.hospital_router import HOSPITAL_BUDGET_EXHAUSTED_DETAIL
from boundaries.hospital_api_boundary import (
    HospitalApiBudgetExhaustedError,
    HospitalApiResponseError,
    HospitalApiUnavailableError,
)
from core.application_clock import seconds_until_next_application_day
from schemas.chat import ChatMedicationTaken, ChatMessageCreate, ChatMessageDelete, ChatReadUpdate
from services.chat_connection_manager import ChatConnectionManager

router = APIRouter()
logger = logging.getLogger(__name__)

# 수락한 스트림을 자격 증명 만료로 닫을 때의 종료 코드. 인증 실패(4401)와 구분해
# 클라이언트가 로그아웃하지 않고 새 토큰으로 다시 연결하게 한다.
_CLOSE_CREDENTIAL_EXPIRED = 4440

# Async routes await each blocking operation sequentially using the bounded
# AnyIO worker pool. Cancellation drains each database operation before request
# cleanup; sessions must never be shared with parallel tasks. FastAPI's get_db
# dependency retains responsibility for REST cleanup.
# WebSocket sessions are closed by the handshake, not retained by idle sockets.


# 함수이름: get_chat_messages
# 함수역할:
# - 인증된 연동 참여자에게 채팅 기록 한 페이지를 반환한다.
# 매개변수:
# - link_id (int): 저장된 환자·보호자 연동 식별자.
# - user_hash (str): 작업 대상 계정의 데이터 소유 범위 식별자.
# - before_message_id (int | None): 이전 기록 조회의 제외 상한 메시지 식별자.
# - limit (int): 반환할 최대 결과 수.
# - principal (AuthenticatedPrincipal): 서버가 검증한 인증 주체와 계정 범위.
# - authorization (AuthorizationControl): 환자·보호자 데이터 접근 범위 판정 Control.
# - chat (ManageLinkedChat): 활성 연동 채팅과 문맥 접근을 관리하는 Control.
# 반환값:
# - 메시지 목록과 페이지 정보
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


# Function Name: delete_chat_messages
# Description: Resolves the caller's scope, persists deletion off the event loop and broadcasts only to the owner for me-scope or both sides otherwise.
# Parameters: link_id (int), payload (ChatMessageDelete) select messages/scope; request (Request) provides the socket manager; user_hash (str) asserts ownership;
#   principal (AuthenticatedPrincipal), authorization (AuthorizationControl) and chat (ManageLinkedChat) are injected dependencies.
# Returns: Deletion envelope; authority/persistence failures propagate before publication.
@router.post("/links/{link_id}/messages/delete")
async def delete_chat_messages(
    link_id: int,
    payload: ChatMessageDelete,
    request: Request,
    user_hash: str = DEFAULT_PATIENT_HASH,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_app_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    chat: ManageLinkedChat = Depends(get_manage_linked_chat),
) -> dict[str, object]:
    authorized_user_hash = await run_request_database_work(
        authorization.resolveOwnUserHash, principal, user_hash,
    )
    response = await run_request_database_work(
        chat.delete_messages,
        link_id=link_id, user_hash=authorized_user_hash,
        message_ids=payload.message_ids, scope=payload.scope,
    )
    await get_chat_connection_manager(request).broadcast(
        link_id=link_id,
        recipient_hash=authorized_user_hash if payload.scope == "me" else None,
        event={"type": "chat_messages_deleted", **response["data"]},
    )
    return response


# 함수이름: get_chat_medications
# 함수역할:
# - 현재 연동 환자의 복용 중인 약을 채팅 선택 목록으로 반환한다.
# 매개변수:
# - link_id (int): 저장된 환자·보호자 연동 식별자.
# - user_hash (str): 작업 대상 계정의 데이터 소유 범위 식별자.
# - principal (AuthenticatedPrincipal): 서버가 검증한 인증 주체와 계정 범위.
# - authorization (AuthorizationControl): 환자·보호자 데이터 접근 범위 판정 Control.
# - chat (ManageLinkedChat): 활성 연동 채팅과 문맥 접근을 관리하는 Control.
# 반환값:
# - 선택 가능한 복약 정보 목록
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
# 함수역할:
# - 연동 환자의 오늘 복약 상태를 시간대별 채팅 카드 형식으로 반환한다.
# 매개변수:
# - link_id (int): 저장된 환자·보호자 연동 식별자.
# - user_hash (str): 작업 대상 계정의 데이터 소유 범위 식별자.
# - principal (AuthenticatedPrincipal): 서버가 검증한 인증 주체와 계정 범위.
# - authorization (AuthorizationControl): 환자·보호자 데이터 접근 범위 판정 Control.
# - chat (ManageLinkedChat): 활성 연동 채팅과 문맥 접근을 관리하는 Control.
# 반환값:
# - 시간대별 복약 상태 목록
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
# 함수역할:
# - 활성 연동 참여자에게 연동 환자 소유의 저장 약 상세정보를 반환한다. 메시지 첨부 여부나 현재 복용 기간으로 제한하지 않는다.
# 매개변수:
# - link_id (int): 저장된 환자·보호자 연동 식별자.
# - medication_id (int): 선택할 저장 약의 식별자.
# - user_hash (str): 작업 대상 계정의 데이터 소유 범위 식별자.
# - principal (AuthenticatedPrincipal): 서버가 검증한 인증 주체와 계정 범위.
# - authorization (AuthorizationControl): 환자·보호자 데이터 접근 범위 판정 Control.
# - chat (ManageLinkedChat): 활성 연동 채팅과 문맥 접근을 관리하는 Control.
# 반환값:
# - 권한이 확인된 저장 복약 상세정보
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
# 함수역할:
# - 일반 또는 복약 맥락 메시지를 한 번만 저장하고 실시간 전송과 푸시를 연결한다.
# 매개변수:
# - link_id (int): 저장된 환자·보호자 연동 식별자.
# - payload (ChatMessageCreate): 검증된 텍스트·구조화 문맥 메시지 전송 요청.
# - request (Request): 애플리케이션 공유 상태에 접근할 FastAPI 요청.
# - user_hash (str): 작업 대상 계정의 데이터 소유 범위 식별자.
# - principal (AuthenticatedPrincipal): 서버가 검증한 인증 주체와 계정 범위.
# - authorization (AuthorizationControl): 환자·보호자 데이터 접근 범위 판정 Control.
# - chat (ManageLinkedChat): 활성 연동 채팅과 문맥 접근을 관리하는 Control.
# - hospital (CheckNearbyHospital): 병원 공유 메시지의 병원 정보를 서버에서 확인하는 Control.
# - pharmacy (CheckNearbyPharmacy): 주간표 없는 약국 공유의 현재 운영 근거를 제한 조회하는 Control.
# 반환값:
# - 생성 여부와 저장된 메시지. 권한·채팅/장소 한도 오류를 전달하며 병원 검증 실패는 400, 제공자 장애·예산 소진은 503이다.
@router.post("/links/{link_id}/messages")
async def post_chat_message(
    link_id: int,
    payload: ChatMessageCreate,
    request: Request,
    user_hash: str = DEFAULT_PATIENT_HASH,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_app_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    chat: ManageLinkedChat = Depends(get_manage_linked_chat),
    hospital: CheckNearbyHospital = Depends(get_check_nearby_hospital),
    pharmacy: CheckNearbyPharmacy = Depends(get_check_nearby_pharmacy),
) -> dict[str, object]:
    """Persist message and notification job atomically, then broadcast live state."""
    authorized_user_hash = await run_request_database_work(
        authorization.resolveOwnUserHash, principal, user_hash,
    )
    await enforce_chat_daily_quota(
        request=request,
        user_hash=authorized_user_hash,
    )
    share_arguments = {}
    if payload.message_kind in (
        CHAT_MESSAGE_KIND_HOSPITAL_SHARE, CHAT_MESSAGE_KIND_PHARMACY_SHARE,
        CHAT_MESSAGE_KIND_PHARMACY_PHONE_VERIFIED,
    ):
        existing = await run_request_database_work(
            chat.find_sent_message, link_id=link_id, sender_hash=authorized_user_hash,
            client_message_id=payload.client_message_id,
            message_kind=payload.message_kind,
        )
        if existing is not None:
            return await publish_saved_message(link_id, existing, request)
    if payload.message_kind == CHAT_MESSAGE_KIND_HOSPITAL_SHARE:
        await enforce_hospital_share_daily_quota(
            request=request, user_hash=authorized_user_hash,
        )
        try:
            async with asyncio.timeout(settings.HOSPITAL_SEARCH_TIMEOUT_SECONDS):
                share_arguments["hospital_context"] = await hospital.requestShareContext(
                    payload.hospital_id, payload.hospital_schedule_date,
                )
        except ValueError:
            raise HTTPException(400, "Hospital information could not be verified.") from None
        except HospitalApiBudgetExhaustedError:
            raise HTTPException(
                503, HOSPITAL_BUDGET_EXHAUSTED_DETAIL,
                headers={"Retry-After": str(seconds_until_next_application_day())},
            ) from None
        except (HospitalApiUnavailableError, HospitalApiResponseError, TimeoutError):
            raise HTTPException(503, "Hospital information is temporarily unavailable.",
                                headers={"Retry-After": "5"}) from None
    elif payload.message_kind in (CHAT_MESSAGE_KIND_PHARMACY_SHARE, CHAT_MESSAGE_KIND_PHARMACY_PHONE_VERIFIED):
        source = await run_request_database_work(
            chat.prepare_pharmacy_share, link_id=link_id, sender_hash=authorized_user_hash,
            pharmacy_id=payload.pharmacy_id,
        )
        if source is not None:
            await enforce_pharmacy_share_daily_quota(
                request=request, user_hash=authorized_user_hash,
            )
            share_arguments["pharmacy_operating_snapshot"] = await pharmacy.requestShareOperatingSnapshot(source)
    result = await run_request_database_work(
        chat.send_message,
        link_id=link_id,
        sender_hash=authorized_user_hash,
        client_message_id=payload.client_message_id,
        body=payload.body,
        medication_id=payload.medication_id,
        medication_ids=payload.medication_ids,
        medication_references=[item.model_dump() for item in payload.medication_references],
        message_kind=payload.message_kind,
        slot_key=payload.slot_key,
        pharmacy_id=payload.pharmacy_id,
        source_alert_id=payload.source_alert_id,
        history_start_date=payload.history_start_date,
        history_end_date=payload.history_end_date,
        **share_arguments,
    )
    return await publish_saved_message(link_id, result, request)


# Function Name: record_chat_medication_taken
# Description: Checks sender scope/quota, records the patient's explicit doses and chat receipt, then publishes current schedules and queues completion alerts.
# Parameters: link_id (int) selects the chat; payload (ChatMedicationTaken) selects the dose/request; request supplies publication/quota state; background_tasks defers alerts;
#   user_hash (str) asserts owner scope; principal, authorization and chat are injected authentication/use-case dependencies.
# Returns: Message response with freshly read schedules even on replay; authorization, quota and changed-confirmation errors propagate.
@router.post("/links/{link_id}/medication-taken")
async def record_chat_medication_taken(
    link_id: int,
    payload: ChatMedicationTaken,
    request: Request,
    background_tasks: BackgroundTasks,
    user_hash: str = DEFAULT_PATIENT_HASH,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_app_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    chat: ManageLinkedChat = Depends(get_manage_linked_chat),
) -> dict[str, object]:
    """Record only the patient's explicitly confirmed dose and publish its receipt."""
    authorized_user_hash = await run_request_database_work(
        authorization.resolveOwnUserHash, principal, user_hash,
    )
    await enforce_chat_daily_quota(request=request, user_hash=authorized_user_hash)
    result, completion_events = await run_request_database_work(
        chat.record_medication_taken,
        link_id=link_id, sender_hash=authorized_user_hash,
        client_message_id=payload.client_message_id,
        schedule_date=payload.schedule_date, slot_key=payload.slot_key,
        medication_ids=payload.medication_ids,
    )
    # Return current state on retries too, rather than the historical message's
    # snapshot, so a later correction is never visually changed back to taken.
    schedule_response = await run_request_database_work(
        CheckSchedule(chat.db).requestTodayMedicationSchedule, authorized_user_hash,
    )
    schedules = schedule_response["data"]
    response = await publish_saved_message(link_id, result, request)
    # Last database step: the reads above left a read transaction open, and the
    # request session stays open until the queued push has finished.
    await run_request_database_work(
        queue_completion_alerts, background_tasks, completion_events, chat.db,
    )
    return {**response, "schedules": schedules}


# Function Name: mark_chat_read
# Description: Marks the authorized participant's incoming messages read and broadcasts a receipt only when at least one row changed.
# Parameters: link_id (int), payload (ChatReadUpdate) select the room/read ceiling; request (Request) supplies the socket manager; user_hash (str) asserts scope;
#   principal (AuthenticatedPrincipal), authorization (AuthorizationControl), chat (ManageLinkedChat) are injected dependencies.
# Returns: Read-count/last-message response; authorization and persistence errors propagate.
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
    authorized_user_hash = await run_request_database_work(
        authorization.resolveOwnUserHash, principal, user_hash,
    )
    response = await run_request_database_work(
        chat.mark_read,
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
# 함수역할:
# - 현재 사용자가 읽지 않은 상대 메시지 수를 반환한다.
# 매개변수:
# - link_id (int): 저장된 환자·보호자 연동 식별자.
# - user_hash (str): 작업 대상 계정의 데이터 소유 범위 식별자.
# - principal (AuthenticatedPrincipal): 서버가 검증한 인증 주체와 계정 범위.
# - authorization (AuthorizationControl): 환자·보호자 데이터 접근 범위 판정 Control.
# - chat (ManageLinkedChat): 활성 연동 채팅과 문맥 접근을 관리하는 Control.
# - include_notification_preview (bool): 개인정보 표시 설정을 따른 알림 요약도 요청할지 여부.
# 반환값:
# - 미확인 개수·첫 미확인 ID와 선택적 알림 요약을 담은 응답. 읽음 상태는 바꾸지 않으며 권한·조회 오류는 전달한다.
@router.get("/links/{link_id}/unread-count")
def get_chat_unread_count(
    link_id: int,
    user_hash: str = DEFAULT_PATIENT_HASH,
    include_notification_preview: bool = False,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_app_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    chat: ManageLinkedChat = Depends(get_manage_linked_chat),
) -> dict[str, object]:
    """현재 참여자가 읽지 않은 채팅 메시지 개수를 반환한다."""
    authorized_user_hash = authorization.resolveOwnUserHash(principal, user_hash)
    return chat.request_unread_count(
        link_id=link_id,
        user_hash=authorized_user_hash,
        include_notification_preview=include_notification_preview,
    )


# Function Name: stream_chat_events
# Description: Authenticates and rate-limits a linked participant, releases the handshake database session, then keeps a ping-only stream with expiry, frame and heartbeat limits.
# Parameters: websocket (WebSocket) is the pending connection; link_id (int) selects the room; user_hash (str) asserts the participant scope.
# Returns: None after disconnection; closes on credential expiry, invalid/revoked identity, inactive link, idle timeout, oversized/unsupported frames or rate excess.
# Note: Credentials/link are periodically rechecked on ping; temporary recheck errors retry on a later ping without extending token lifetime. Registered sockets are always removed.
@router.websocket("/links/{link_id}/stream")
async def stream_chat_events(
    websocket: WebSocket,
    link_id: int,
    user_hash: str = DEFAULT_PATIENT_HASH,
) -> None:
    """인증된 연동 참여자에게 새 메시지와 읽음 이벤트를 실시간 전달한다."""
    manager = getattr(websocket.app.state, "chat_connection_manager", None)
    if not isinstance(manager, ChatConnectionManager):
        await _reject(websocket, 1011)
        return
    db = SessionLocal()
    authorized_user_hash = ""
    connected = False
    credential_deadline: float | None = None
    try:
        principal = await run_in_threadpool(_authenticate_websocket, websocket)
        credential_deadline = _credential_deadline(principal)
        authorization = AuthorizationControl(db)
        authorized_user_hash = await run_request_database_work(
            authorization.resolveOwnUserHash, principal, user_hash,
        )
        try:
            allowed, retry_after = await _reserve_websocket_connection(
                websocket=websocket,
                user_hash=authorized_user_hash,
            )
        except RuntimeError:
            await _reject(websocket, 1013)
            return
        if not allowed:
            await _reject(websocket, 4429, str(max(1, retry_after)))
            return
        await run_request_database_work(
            ManageLinkedChat(db).require_active_link,
            link_id=link_id,
            user_hash=authorized_user_hash,
        )
        await run_request_database_work(db.commit)
    except HTTPException as exc:
        await run_request_database_work(db.rollback)
        await _reject(websocket, _websocket_close_code(exc.status_code))
        return
    except Exception:
        await run_request_database_work(db.rollback)
        await _reject(websocket, 1011)
        return
    finally:
        await run_request_database_work(db.close)
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
        last_validated_at = time.monotonic()
        while True:
            receive_timeout = float(settings.CHAT_WEBSOCKET_IDLE_TIMEOUT_SECONDS)
            if credential_deadline is not None:
                # 만료 시각이 유휴 제한보다 먼저 오면 그때 깨어나 연결을 닫는다.
                receive_timeout = min(
                    receive_timeout, credential_deadline - time.monotonic(),
                )
                if receive_timeout <= 0:
                    await websocket.close(code=_CLOSE_CREDENTIAL_EXPIRED)
                    return
            try:
                message = await asyncio.wait_for(
                    websocket.receive_text(),
                    timeout=receive_timeout,
                )
            except TimeoutError:
                expired = (
                    credential_deadline is not None
                    and time.monotonic() >= credential_deadline
                )
                await websocket.close(
                    code=_CLOSE_CREDENTIAL_EXPIRED if expired else 4408,
                )
                return
            except KeyError:
                # A binary frame carries no text; this stream accepts text pings only.
                await websocket.close(code=1003)
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
            if (
                now - last_validated_at
                >= settings.CHAT_WEBSOCKET_REVALIDATION_INTERVAL_SECONDS
            ):
                try:
                    # 운영은 REST 요청마다 세션 취소·계정 정지를 확인하므로 열린 연결도 같은 주기로 다시 확인한다.
                    credential_valid = await run_in_threadpool(
                        _credential_is_still_valid, websocket, authorized_user_hash,
                    )
                    if not credential_valid:
                        await websocket.close(code=4401)
                        return
                    still_active = await run_request_database_work(
                        _link_is_still_active, link_id, authorized_user_hash,
                    )
                except Exception as exc:
                    # 일시적인 DB 장애로 모든 연결을 한꺼번에 끊어 재연결이 몰리지 않게
                    # 다음 ping에서 다시 확인한다. 토큰 만료 시각은 그대로 적용된다.
                    logger.warning(
                        "Chat stream revalidation failed: %s", type(exc).__name__,
                    )
                else:
                    if not still_active:
                        await websocket.close(code=4404)
                        return
                    last_validated_at = now
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


# Function Name: _reject
# Description: Logs only link ID/close code and rejects the handshake; clients declaring close-code support are briefly accepted so they can receive a specific code/reason.
# Parameters: websocket (WebSocket) is pending; code (int) selects the close reason; reason (str) optionally carries retry seconds.
# Returns: None after close; legacy clients remain pre-accept rejections to avoid their immediate reconnect loop.
async def _reject(websocket: WebSocket, code: int, reason: str = "") -> None:
    # 서버 접속 로그는 거절을 모두 403으로만 남기므로, 원인을 구분할 종료 코드를 따로 기록한다.
    logger.info(
        "Chat stream refused: link=%s code=%s",
        getattr(websocket, "path_params", {}).get("link_id"),
        code,
    )
    if client_declares_feature(websocket, CHAT_CLOSE_CODES_FEATURE):
        await websocket.accept()
    if reason:
        await websocket.close(code=code, reason=reason)
    else:
        await websocket.close(code=code)


# Function Name: _credential_deadline
# Description: Converts the verified wall-clock expiry into a monotonic deadline for this process.
# Parameters: principal (AuthenticatedPrincipal) supplies the aware token expiry.
# Returns: Monotonic float deadline, possibly already elapsed, or None when expiry is absent.
def _credential_deadline(principal: AuthenticatedPrincipal) -> float | None:
    expires_at = principal.expires_at
    if expires_at is None:
        return None
    return time.monotonic() + (expires_at - datetime.now(UTC)).total_seconds()


# Function Name: _link_is_still_active
# Description: Rechecks room membership in a fresh short-lived session, which also excludes links removed by account deletion.
# Parameters: link_id (int) and user_hash (str) identify the previously authorized connection.
# Returns: True for active membership, False for HTTP authorization failures; other database errors propagate and the session always closes.
def _link_is_still_active(link_id: int, user_hash: str) -> bool:
    db = SessionLocal()
    try:
        ManageLinkedChat(db).require_active_link(link_id=link_id, user_hash=user_hash)
        return True
    except HTTPException:
        return False
    finally:
        db.close()


# 함수이름: _reserve_websocket_connection
# 함수역할:
# - 반복적인 실시간 연결 시도로 서버 자원이 고갈되지 않게 제한한다.
# 매개변수:
# - websocket (WebSocket): 연결 대기 중이거나 활성 상태인 실시간 채팅 연결.
# - user_hash (str): 작업 대상 계정의 데이터 소유 범위 식별자.
# 반환값:
# - 연결 허용 여부와 재시도 대기 초
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
# 함수역할:
# - WebSocket 요청을 HTTP API와 같은 인증 정책으로 검증한다.
# 매개변수:
# - websocket (WebSocket): 연결 요청
# 반환값:
# - 검증된 사용자 주체
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


# Function Name: _credential_is_still_valid
# Description: Revalidates the handshake identity token and requires the same user; App Check is not repeated on the already-open stream.
# Parameters: websocket (WebSocket) retains the original headers; user_hash (str) is the authenticated connection owner.
# Returns: False for malformed/revoked/mismatched identity, True for the same valid account or disabled authentication; verifier 5xx errors propagate for retry.
def _credential_is_still_valid(websocket: WebSocket, user_hash: str) -> bool:
    authorization_header = websocket.headers.get("authorization", "").strip()
    credentials: HTTPAuthorizationCredentials | None = None
    if authorization_header:
        scheme, separator, token = authorization_header.partition(" ")
        if not separator or not token.strip():
            return False
        credentials = HTTPAuthorizationCredentials(scheme=scheme, credentials=token.strip())
    try:
        principal = get_authenticated_principal(credentials)
    except HTTPException as exc:
        if exc.status_code >= 500:
            raise
        return False
    return principal.authentication_disabled or principal.user_hash == user_hash


# 함수이름: _websocket_close_code
# 함수역할:
# - HTTP 오류 상태를 WebSocket 종료 코드로 변환한다.
# 매개변수:
# - status_code (int): HTTP 상태 코드
# 반환값:
# - WebSocket 종료 코드
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
