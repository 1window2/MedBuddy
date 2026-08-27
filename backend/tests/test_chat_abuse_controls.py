# 파일명: test_chat_abuse_controls.py
# 역할: 채팅 저장·푸시·실시간 연결의 반복 요청 방어 정책을 검증한다.

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


def _memory_rate_limit_store() -> RequestRateLimitStore:
    """외부 Redis 없이 고정 시간창을 검증할 메모리 저장소를 만든다."""
    store = RequestRateLimitStore(redis_url="redis://localhost:6379")
    store._redis_available = False
    store._redis_retry_at = float("inf")
    return store


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
