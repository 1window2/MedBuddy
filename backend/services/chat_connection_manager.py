# 파일명: chat_connection_manager.py
# 역할: 프로세스 안에서 환자·보호자 채팅 WebSocket 연결을 관리한다.

"""프로세스 안에서 환자·보호자 채팅 WebSocket 연결을 관리한다."""

import asyncio
from collections import defaultdict

from fastapi import WebSocket


# 클래스명: ChatConnectionManager
# 역할:
# - 연동과 사용자별 WebSocket 연결을 관리한다.
# 주요 책임:
# - 연결 등록·해제, 접속 여부 확인과 실시간 이벤트 방송을 담당한다.
# 속성:
# - _connections (dict): 연동 ID와 사용자 해시별 WebSocket 집합.
# - _max_connections_per_user (int): 한 연동에서 사용자별 연결 상한.
# - _lock (asyncio.Lock): 연결 목록 변경과 조회를 보호하는 잠금.
class ChatConnectionManager:
    """연동과 사용자별 WebSocket을 추적하고 실시간 이벤트를 방송한다."""

    # 함수이름: __init__
    # 함수역할:
    # - 사용자별 연결 상한을 저장하고 연동별 연결 사전과 비동기 잠금을 준비한다.
    # 매개변수:
    # - max_connections_per_user (int): 한 연동에서 사용자 한 명이 동시에 유지할 수 있는 최대 연결 수.
    # 반환값:
    # - 없음; 초기 연결 목록은 비어 있다.
    def __init__(self, max_connections_per_user: int = 3) -> None:
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

    # 함수이름: connect
    # 함수역할:
    # - WebSocket을 수락하고 연동 참여자의 연결로 등록한다.
    # 매개변수:
    # - link_id (int): 환자와 보호자 간 연동 ID.
    # - user_hash (str): 접근 범위를 제한할 참여자 소유권 해시.
    # - websocket (WebSocket): 등록하거나 해제할 참여자 WebSocket 연결.
    # 반환값:
    # - 등록하면 True; 상한에 도달하면 코드 4429로 연결을 닫고 False.
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
            if len(user_connections) >= self._max_connections_per_user:
                await websocket.close(code=4429)
                if not user_connections:
                    self._connections[link_id].pop(user_hash, None)
                if not self._connections[link_id]:
                    self._connections.pop(link_id, None)
                return False
            user_connections.add(websocket)
            return True

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

    # 함수이름: broadcast
    # 함수역할:
    # - 현재 연동의 모든 연결에 동일한 실시간 이벤트를 전송한다.
    # 매개변수:
    # - link_id (int): 환자와 보호자 간 연동 ID.
    # - event (dict[str, object]): 연동 참여자에게 전송할 JSON 직렬화 가능한 실시간 이벤트.
    # - recipient_hash (str | None): 수신자 해시; None이면 양쪽 참여자에게 전송한다.
    # 반환값:
    # - 없음
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
