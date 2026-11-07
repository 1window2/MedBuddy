# 파일명: chat_connection_manager.py
# 역할: 프로세스 안에서 환자·보호자 채팅 WebSocket 연결을 관리한다.

"""프로세스 안에서 환자·보호자 채팅 WebSocket 연결을 관리한다."""

import asyncio
import math
from collections import defaultdict

from fastapi import WebSocket, WebSocketDisconnect


# 클래스명: ChatConnectionManager
# 역할:
# - 연동과 사용자별 WebSocket 연결을 관리한다.
# 주요 책임:
# - 연결 등록·해제, 접속 여부 확인과 실시간 이벤트 방송을 담당한다.
# 속성:
# - _connections (dict): 연동 ID와 사용자 해시별 WebSocket 집합.
# - _max_connections_per_user (int): 한 연동에서 사용자별 연결 상한.
# - _lock (asyncio.Lock): 연결 목록 변경과 조회를 보호하는 잠금.
# - _send_timeout_seconds (float): Finite deadline for each send and close.
class ChatConnectionManager:
    """연동과 사용자별 WebSocket을 추적하고 실시간 이벤트를 방송한다."""

    # Function Name: __init__
    # Description: Prepares per-link/user socket sets and a registry lock, validating the finite positive transport-write deadline.
    # Parameters: max_connections_per_user (int) caps sockets per user in each link; send_timeout_seconds (float) bounds writes.
    # Returns: None; raises ValueError for a nonfinite or nonpositive send deadline.
    def __init__(
        self, max_connections_per_user: int = 3, *, send_timeout_seconds: float = 5.0,
    ) -> None:
        """Initialize the registry with a finite deadline for transport writes."""
        if not math.isfinite(send_timeout_seconds) or send_timeout_seconds <= 0:
            raise ValueError("send_timeout_seconds must be finite and positive")
        self._send_timeout_seconds = send_timeout_seconds
        self._max_connections_per_user = max_connections_per_user
        self._connections: dict[int, dict[str, set[WebSocket]]] = defaultdict(
            # 함수이름: 연동별 연결 사전 생성 람다
            # 함수역할:
            # - 처음 접근한 연동에 사용자별 WebSocket 집합을 자동 생성하는 사전을 할당한다.
            # 매개변수:
            # - 없음.
            # 반환값:
            # - 사용자 키 누락 시 빈 set을 만드는 defaultdict(set).
            lambda: defaultdict(set)
        )
        self._lock = asyncio.Lock()

    # Function Name: connect
    # Description: Accepts a socket, registers it below the user's link limit, or closes an excess connection outside the registry lock.
    # Parameters: link_id (int), user_hash (str) identify the already-authorized participant; websocket (WebSocket) is the connection.
    # Returns: True when registered, False after an over-limit close with code 4429; acceptance failures propagate.
    async def connect(
        self,
        *,
        link_id: int,
        user_hash: str,
        websocket: WebSocket,
    ) -> bool:
        """사용자별 연결 상한을 확인한 뒤 WebSocket을 등록한다."""
        await websocket.accept()
        async with self._lock:
            user_connections = self._connections[link_id][user_hash]
            if len(user_connections) < self._max_connections_per_user:
                user_connections.add(websocket)
                return True
        # A slow transport must never hold the process-wide registry lock.
        await self._close_transport(websocket, code=4429)
        return False

    # 함수이름: disconnect
    # 함수역할:
    # - 닫힌 연결을 제거하고 빈 연동 항목을 정리한다.
    # 매개변수:
    # - link_id (int): 환자와 보호자 간 연동 ID.
    # - user_hash (str): 접근 범위를 제한할 참여자 소유권 해시.
    # - websocket (WebSocket): 등록하거나 해제할 참여자 WebSocket 연결.
    # 반환값:
    # - 없음
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
    # 함수역할:
    # - 사용자가 현재 서버 프로세스의 채팅방에 연결됐는지 확인한다.
    # 매개변수:
    # - link_id (int): 환자와 보호자 간 연동 ID.
    # - user_hash (str): 접근 범위를 제한할 참여자 소유권 해시.
    # 반환값:
    # - 연결 여부
    async def is_user_connected(self, *, link_id: int, user_hash: str) -> bool:
        """상대 사용자가 현재 이 서버 프로세스의 채팅방에 연결됐는지 확인한다."""
        async with self._lock:
            return bool(self._connections.get(link_id, {}).get(user_hash))

    # Function Name: broadcast
    # Description: Snapshots matching sockets under the lock and delivers concurrently outside it using the bounded per-socket delivery path.
    # Parameters: link_id (int) selects the room; event (dict) is JSON-compatible; recipient_hash (str | None) restricts delivery to one side when present.
    # Returns: None after attempted deliveries; an empty registry is a no-op.
    async def broadcast(
        self, *, link_id: int, event: dict[str, object],
        recipient_hash: str | None = None,
    ) -> None:
        """현재 연동의 모든 기기에 동일한 실시간 이벤트를 전송한다."""
        async with self._lock:
            targets = [
                (user_hash, websocket)
                for user_hash, sockets in self._connections.get(link_id, {}).items()
                if recipient_hash is None or user_hash == recipient_hash
                for websocket in sockets
            ]
        await asyncio.gather(*(
            self._deliver(link_id=link_id, user_hash=user_hash, websocket=websocket, event=event)
            for user_hash, websocket in targets
        ))

    # Function Name: _deliver
    # Description: Send independently with a deadline; remove failed sockets before
    # the caller checks presence for push fallback. Task cancellation propagates.
    # Parameters: link_id/user_hash: Registry scope; websocket: Target; event: JSON event.
    # Returns: None; expected transport failures are isolated from persisted writes.
    async def _deliver(
        self, *, link_id: int, user_hash: str, websocket: WebSocket,
        event: dict[str, object],
    ) -> None:
        try:
            await asyncio.wait_for(
                websocket.send_json(event), timeout=self._send_timeout_seconds,
            )
        except (TimeoutError, WebSocketDisconnect, RuntimeError, OSError):
            await self.disconnect(
                link_id=link_id,
                user_hash=user_hash,
                websocket=websocket,
            )
            await self._close_transport(websocket, code=1011)

    # Function Name: _close_transport
    # Description: Attempt transport cleanup without blocking registry operations
    # or allowing an already-disconnected socket to fail an HTTP response.
    # Parameters: websocket: Transport to close; code: WebSocket close status.
    # Returns: None; expected close failures and timeouts are ignored.
    async def _close_transport(self, websocket: WebSocket, *, code: int) -> None:
        try:
            await asyncio.wait_for(
                websocket.close(code=code), timeout=self._send_timeout_seconds,
            )
        except (TimeoutError, WebSocketDisconnect, RuntimeError, OSError):
            pass
