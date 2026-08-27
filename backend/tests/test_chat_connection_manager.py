# 파일명: test_chat_connection_manager.py
# 역할: 채팅 WebSocket 인증과 연결 관리자의 실시간 방송을 검증한다.

"""채팅 WebSocket 인증과 연결 관리자의 실시간 방송을 검증한다."""

import sys
import unittest
from pathlib import Path
from typing import cast

from fastapi import HTTPException, WebSocket

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from api.chat_router import _authenticate_websocket  # noqa: E402
from core.config import settings  # noqa: E402
from services.chat_connection_manager import ChatConnectionManager  # noqa: E402


class _FakeWebSocket:
    """연결 수락과 JSON 방송을 메모리에 기록하는 테스트 대체 객체다."""

    def __init__(self, headers: dict[str, str] | None = None) -> None:
        self.headers = headers or {}
        self.accepted = False
        self.closed_code: int | None = None
        self.events: list[dict[str, object]] = []

    async def accept(self) -> None:
        self.accepted = True

    async def send_json(self, event: dict[str, object]) -> None:
        self.events.append(event)

    async def close(self, code: int = 1000, reason: str | None = None) -> None:
        del reason
        self.closed_code = code


class ChatConnectionManagerTest(unittest.IsolatedAsyncioTestCase):
    """연동별 WebSocket 등록, 방송, 해제를 확인한다."""

    async def test_broadcast_reaches_all_connections_in_same_link(self) -> None:
        manager = ChatConnectionManager()
        patient_socket = _FakeWebSocket()
        caregiver_socket = _FakeWebSocket()
        other_link_socket = _FakeWebSocket()

        await manager.connect(
            link_id=17,
            user_hash="patient-a",
            websocket=cast(WebSocket, patient_socket),
        )
        await manager.connect(
            link_id=17,
            user_hash="caregiver-a",
            websocket=cast(WebSocket, caregiver_socket),
        )
        await manager.connect(
            link_id=18,
            user_hash="patient-b",
            websocket=cast(WebSocket, other_link_socket),
        )

        await manager.broadcast(
            link_id=17,
            event={"type": "chat_message", "message": {"message_id": 1}},
        )

        self.assertTrue(patient_socket.accepted)
        self.assertTrue(caregiver_socket.accepted)
        self.assertEqual(len(patient_socket.events), 1)
        self.assertEqual(len(caregiver_socket.events), 1)
        self.assertEqual(other_link_socket.events, [])
        self.assertTrue(
            await manager.is_user_connected(
                link_id=17,
                user_hash="caregiver-a",
            )
        )

        await manager.disconnect(
            link_id=17,
            user_hash="caregiver-a",
            websocket=cast(WebSocket, caregiver_socket),
        )

        self.assertFalse(
            await manager.is_user_connected(
                link_id=17,
                user_hash="caregiver-a",
            )
        )

    async def test_connect_rejects_connections_above_user_limit(self) -> None:
        """한 사용자가 연결 상한을 넘어 서버 자원을 점유하지 못하는지 검증한다."""
        manager = ChatConnectionManager(max_connections_per_user=1)
        first_socket = _FakeWebSocket()
        second_socket = _FakeWebSocket()

        first_connected = await manager.connect(
            link_id=17,
            user_hash="patient-a",
            websocket=cast(WebSocket, first_socket),
        )
        second_connected = await manager.connect(
            link_id=17,
            user_hash="patient-a",
            websocket=cast(WebSocket, second_socket),
        )

        self.assertTrue(first_connected)
        self.assertFalse(second_connected)
        self.assertEqual(second_socket.closed_code, 4429)

    def test_websocket_requires_matching_api_contract(self) -> None:
        """호환되지 않는 앱이 실시간 채널에 연결되지 못하는지 검증한다."""
        matching_socket = _FakeWebSocket(
            {"x-medbuddy-api-contract": settings.API_CONTRACT_VERSION}
        )
        principal = _authenticate_websocket(cast(WebSocket, matching_socket))

        self.assertTrue(principal.authentication_disabled)
        with self.assertRaises(HTTPException) as context:
            _authenticate_websocket(cast(WebSocket, _FakeWebSocket()))
        self.assertEqual(context.exception.status_code, 409)


if __name__ == "__main__":
    unittest.main()
