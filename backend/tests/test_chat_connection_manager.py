# 파일명: test_chat_connection_manager.py
# 역할: 채팅 실시간 연결의 연동 격리, 개인 삭제 이벤트 및 연결·계약 제한을 검증한다.

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


# 클래스명: _FakeWebSocket
# 역할: 연결 수락, 전송 이벤트 및 종료 코드를 메모리에 기록하는 WebSocket 대체 객체다.
# 주요 책임:
# - 네트워크 연결 없이 소켓이 수락되었음을 기록한다.
# - 소켓으로 보낼 JSON 이벤트를 전송 이력에 추가한다.
# - 종료 사유는 사용하지 않고 검증할 WebSocket 종료 코드만 기록한다.
# 속성:
# - headers (object): WebSocket 인증에 제공할 요청 헤더.
# - accepted (bool): WebSocket 연결 수락 기록 여부.
# - closed_code (int | None): 종료 전에는 없는 WebSocket 종료 코드 기록.
# - events (list[dict[str, object]]): 이 대체 소켓에 전달된 JSON 이벤트 기록.
class _FakeWebSocket:
    """연결 수락과 JSON 방송을 메모리에 기록하는 테스트 대체 객체다."""

    # 함수이름: __init__
    # 함수역할:
    # - 선택한 요청 헤더와 미수락·미종료 상태 및 빈 전송 이력을 준비한다.
    # 매개변수:
    # - headers (dict[str, str] | None): WebSocket 대체 객체에 제공할 선택적 요청 헤더.
    # 반환값:
    # - 없음 (None).
    def __init__(self, headers: dict[str, str] | None = None) -> None:
        self.headers = headers or {}
        self.accepted = False
        self.closed_code: int | None = None
        self.events: list[dict[str, object]] = []

    # 함수이름: accept
    # 함수역할:
    # - 네트워크 연결 없이 소켓이 수락되었음을 기록한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    async def accept(self) -> None:
        self.accepted = True

    # 함수이름: send_json
    # 함수역할:
    # - 소켓으로 보낼 JSON 이벤트를 전송 이력에 추가한다.
    # 매개변수:
    # - event (dict[str, object]): 소켓 전송 대신 기록할 JSON 이벤트.
    # 반환값:
    # - 없음 (None).
    async def send_json(self, event: dict[str, object]) -> None:
        self.events.append(event)

    # 함수이름: close
    # 함수역할:
    # - 종료 사유는 사용하지 않고 검증할 WebSocket 종료 코드만 기록한다.
    # 매개변수:
    # - code (int): 기록할 WebSocket 종료 코드.
    # - reason (str | None): 선택적 WebSocket 종료 사유이며 이 기록 객체에서는 사용하지 않음.
    # 반환값:
    # - 없음 (None).
    async def close(self, code: int = 1000, reason: str | None = None) -> None:
        del reason
        self.closed_code = code


# 클래스명: ChatConnectionManagerTest
# 역할: 비동기 연결 관리자의 이벤트 수신 범위와 연결 거절 조건을 검증하는 테스트 모음이다.
# 주요 책임:
# - 개인 삭제 이벤트가 요청자 소켓에만 전달되고 연동 상대에게는 노출되지 않는지 검증한다.
# - 사용자별 연결 상한을 넘는 소켓을 수락하지 않고 4429 코드로 종료하는지 검증한다.
# - 호환 계약의 소켓 인증은 허용하지만 계약 불일치는 HTTP 409로 거절하는지 검증한다.
class ChatConnectionManagerTest(unittest.IsolatedAsyncioTestCase):
    # 함수이름: test_private_delete_event_does_not_reach_peer
    # 함수역할:
    # - 개인 삭제 이벤트가 요청자 소켓에만 전달되고 연동 상대에게는 노출되지 않는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    async def test_private_delete_event_does_not_reach_peer(self) -> None:
        manager = ChatConnectionManager()
        own, peer = _FakeWebSocket(), _FakeWebSocket()
        await manager.connect(link_id=17, user_hash="patient-a", websocket=cast(WebSocket, own))
        await manager.connect(link_id=17, user_hash="caregiver-a", websocket=cast(WebSocket, peer))
        event = {"type": "chat_messages_deleted", "message_ids": [1], "scope": "me"}
        await manager.broadcast(link_id=17, event=event, recipient_hash="patient-a")
        self.assertEqual(own.events, [event])
        self.assertEqual(peer.events, [])

    """연동별 WebSocket 등록, 방송, 해제를 확인한다."""

    # 함수이름: test_broadcast_reaches_all_connections_in_same_link
    # 함수역할:
    # - 같은 연동의 모든 소켓만 방송을 수신하고 연결 해제 후 사용자 접속 상태가 갱신되는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_connect_rejects_connections_above_user_limit
    # 함수역할:
    # - 사용자별 연결 상한을 넘는 소켓을 수락하지 않고 4429 코드로 종료하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_websocket_requires_matching_api_contract
    # 함수역할:
    # - 호환 계약의 소켓 인증은 허용하지만 계약 불일치는 HTTP 409로 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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
