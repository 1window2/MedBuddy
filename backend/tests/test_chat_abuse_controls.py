# 파일명: test_chat_abuse_controls.py
# 역할: 채팅 일일 전송량, 상대별 푸시 간격 및 WebSocket 연결 시도의 공통 호출 제한을 검증한다.

from types import SimpleNamespace
from typing import cast
from unittest.mock import patch

import pytest
from fastapi import FastAPI, HTTPException, Request, WebSocket

from api.chat_router import (
    _enforce_chat_daily_quota,
    _reserve_chat_push_notification,
    _reserve_websocket_connection,
)
from core.config import settings
from core.request_rate_limits import RequestRateLimitStore


# 함수이름: _memory_rate_limit_store
# 함수역할:
# - 외부 Redis 접속과 재시도를 비활성화하여 고정 시간창을 검증할 메모리 저장소를 만든다.
# 매개변수:
# - 없음.
# 반환값:
# - RequestRateLimitStore: Redis 재시도가 비활성화된 메모리 호출 제한 저장소.
def _memory_rate_limit_store() -> RequestRateLimitStore:
    """외부 Redis 없이 고정 시간창을 검증할 메모리 저장소를 만든다."""
    store = RequestRateLimitStore(redis_url="redis://localhost:6379")
    store._redis_available = False
    store._redis_retry_at = float("inf")
    return store


# 함수이름: _request_with_store
# 함수역할:
# - 공통 호출 제한 저장소를 앱 상태에 연결한 채팅 메시지 POST 요청을 구성한다.
# 매개변수:
# - store (RequestRateLimitStore): 시험용 앱에 연결할 공통 호출 제한 저장소.
# 반환값:
# - Request: 지정 호출 제한 저장소가 앱에 등록된 채팅 POST 요청.
def _request_with_store(store: RequestRateLimitStore) -> Request:
    """호출 제한 저장소가 등록된 최소 HTTP 요청을 만든다."""
    app = FastAPI()
    app.state.request_rate_limit_store = store
    return Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/api/v1/chat/links/1/messages",
            "headers": [],
            "app": app,
        }
    )


# 함수이름: test_chat_daily_quota_rejects_messages_above_limit
# 함수역할:
# - 채팅 일일 상한 초과 시 429와 양수 Retry-After가 반환되는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
@pytest.mark.anyio
async def test_chat_daily_quota_rejects_messages_above_limit() -> None:
    """일일 상한을 넘긴 메시지 저장 시도가 429로 차단되는지 검증한다."""
    store = _memory_rate_limit_store()
    request = _request_with_store(store)
    try:
        with patch.object(settings, "CHAT_MESSAGE_DAILY_LIMIT", 2):
            await _enforce_chat_daily_quota(request=request, user_hash="patient-a")
            await _enforce_chat_daily_quota(request=request, user_hash="patient-a")
            with pytest.raises(HTTPException) as context:
                await _enforce_chat_daily_quota(
                    request=request,
                    user_hash="patient-a",
                )
    finally:
        await store.close()

    assert context.value.status_code == 429
    assert int(context.value.headers["Retry-After"]) >= 1


# 함수이름: test_chat_push_is_throttled_per_recipient_and_link
# 함수역할:
# - 동일 상대·연동의 연속 푸시는 한 번만 허용하고 다른 연동의 푸시는 독립적으로 허용하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
@pytest.mark.anyio
async def test_chat_push_is_throttled_per_recipient_and_link() -> None:
    """같은 상대와 연동에 대한 연속 푸시가 한 번만 예약되는지 검증한다."""
    store = _memory_rate_limit_store()
    request = _request_with_store(store)
    try:
        first = await _reserve_chat_push_notification(
            request=request,
            recipient_hash="caregiver-a",
            link_id=17,
        )
        second = await _reserve_chat_push_notification(
            request=request,
            recipient_hash="caregiver-a",
            link_id=17,
        )
        other_link = await _reserve_chat_push_notification(
            request=request,
            recipient_hash="caregiver-a",
            link_id=18,
        )
    finally:
        await store.close()

    assert first is True
    assert second is False
    assert other_link is True


# 함수이름: test_websocket_connection_attempts_use_shared_quota
# 함수역할:
# - 같은 사용자 WebSocket 연결 시도가 공통 저장소의 할당량을 소진하면 다음 시도를 거절하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
@pytest.mark.anyio
async def test_websocket_connection_attempts_use_shared_quota() -> None:
    """WebSocket 연결 시도도 공통 호출 제한 저장소를 사용하는지 검증한다."""
    store = _memory_rate_limit_store()
    websocket = cast(
        WebSocket,
        SimpleNamespace(
            app=SimpleNamespace(
                state=SimpleNamespace(request_rate_limit_store=store)
            )
        ),
    )
    try:
        with patch.object(settings, "CHAT_WEBSOCKET_CONNECTIONS_PER_MINUTE", 1):
            first = await _reserve_websocket_connection(
                websocket=websocket,
                user_hash="patient-a",
            )
            second = await _reserve_websocket_connection(
                websocket=websocket,
                user_hash="patient-a",
            )
    finally:
        await store.close()

    assert first[0] is True
    assert second[0] is False
