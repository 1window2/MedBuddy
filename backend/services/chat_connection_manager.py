# 파일명: chat_connection_manager.py
# 역할: 프로세스 안에서 환자·보호자 채팅 WebSocket 연결을 관리한다.

"""프로세스 안에서 환자·보호자 채팅 WebSocket 연결을 관리한다."""

import asyncio
from collections import defaultdict

from fastapi import WebSocket


# 클래스명: ChatConnectionManager
# 역할: 연동과 사용자별 WebSocket 연결을 관리한다.
# 주요 책임: 연결 등록·해제, 접속 여부 확인과 실시간 이벤트 방송을 담당한다.
class ChatConnectionManager:
    """연동과 사용자별 WebSocket을 추적하고 실시간 이벤트를 방송한다."""

    def __init__(self) -> None:
        self._connections: dict[int, dict[str, set[WebSocket]]] = defaultdict(
            lambda: defaultdict(set)
        )
        self._lock = asyncio.Lock()

    # 함수이름: connect
    # 함수역할: WebSocket을 수락하고 연동 참여자의 연결로 등록한다.
    # 매개변수: link_id, user_hash, websocket
    # 반환값: 없음
    async def connect(
        self,
        *,
        link_id: int,
        user_hash: str,
        websocket: WebSocket,
    ) -> None:
        """WebSocket을 수락하고 해당 연동 참여자의 연결로 등록한다."""
        await websocket.accept()
        async with self._lock:
            self._connections[link_id][user_hash].add(websocket)

    # 함수이름: disconnect
    # 함수역할: 닫힌 연결을 제거하고 빈 연동 항목을 정리한다.
    # 매개변수: link_id, user_hash, websocket
    # 반환값: 없음
    async def disconnect(
        self,
        *,
        link_id: int,
        user_hash: str,
        websocket: WebSocket,
    ) -> None:
        """닫힌 연결을 제거하고 빈 연동 항목을 정리한다."""
        async with self._lock:
            user_connections = self._connections.get(link_id, {}).get(user_hash)
            if user_connections is not None:
                user_connections.discard(websocket)
                if not user_connections:
                    self._connections[link_id].pop(user_hash, None)
            if link_id in self._connections and not self._connections[link_id]:
                self._connections.pop(link_id, None)

    # 함수이름: is_user_connected
    # 함수역할: 사용자가 현재 서버 프로세스의 채팅방에 연결됐는지 확인한다.
    # 매개변수: link_id, user_hash
    # 반환값: 연결 여부
    async def is_user_connected(self, *, link_id: int, user_hash: str) -> bool:
        """상대 사용자가 현재 이 서버 프로세스의 채팅방에 연결됐는지 확인한다."""
        async with self._lock:
            return bool(self._connections.get(link_id, {}).get(user_hash))

    # 함수이름: broadcast
    # 함수역할: 현재 연동의 모든 연결에 동일한 실시간 이벤트를 전송한다.
    # 매개변수: link_id, event
    # 반환값: 없음
    async def broadcast(self, *, link_id: int, event: dict[str, object]) -> None:
        """현재 연동의 모든 기기에 동일한 실시간 이벤트를 전송한다."""
        async with self._lock:
            targets = [
                (user_hash, websocket)
                for user_hash, sockets in self._connections.get(link_id, {}).items()
                for websocket in sockets
            ]
        failed: list[tuple[str, WebSocket]] = []
        for user_hash, websocket in targets:
            try:
                await websocket.send_json(event)
            except (RuntimeError, OSError):
                failed.append((user_hash, websocket))
        for user_hash, websocket in failed:
            await self.disconnect(
                link_id=link_id,
                user_hash=user_hash,
                websocket=websocket,
            )
