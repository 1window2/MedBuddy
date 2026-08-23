# 파일명: chat_message_repository.py
# 역할: 채팅 메시지의 반복 조회와 변경 조건을 한곳에 모은다.

"""채팅 메시지의 반복 조회와 변경 조건을 한곳에 모은다."""

from datetime import datetime

from sqlalchemy.orm import Session

from entities.chat_message_entity import _ChatMessage


# 클래스명: ChatMessageRepository
# 역할: 연동별 채팅 기록과 읽음 상태의 영속성 규칙을 관리한다.
# 주요 책임: 페이지 조회, 중복 전송 조회, 저장과 읽음 상태 변경을 담당한다.
class ChatMessageRepository:
    """연동별 채팅 기록과 읽음 상태의 영속성 규칙을 관리한다."""

    def __init__(self, db: Session) -> None:
        self.db = db

    # 함수이름: list_recent
    # 함수역할: 최신 메시지 기준 페이지를 오래된 순서로 반환한다.
    # 매개변수: link_id, before_message_id, limit
    # 반환값: 채팅 메시지 DB 행 목록
    def list_recent(
        self,
        link_id: int,
        *,
        before_message_id: int | None,
        limit: int,
    ) -> tuple[list[_ChatMessage], bool]:
        """최신 메시지와 실제 이전 페이지 존재 여부를 함께 반환한다."""
        query = self.db.query(_ChatMessage).filter(_ChatMessage.link_id == link_id)
        if before_message_id is not None:
            query = query.filter(_ChatMessage.id < before_message_id)
        rows = query.order_by(_ChatMessage.id.desc()).limit(limit + 1).all()
        has_more = len(rows) > limit
        if has_more:
            rows = rows[:limit]
        rows.reverse()
        return rows, has_more

    # 함수이름: find_client_request
    # 함수역할: 네트워크 재시도로 이미 저장된 동일 전송 요청을 찾는다.
    # 매개변수: link_id, sender_hash, client_message_id
    # 반환값: 일치하는 채팅 메시지 또는 없음
    def find_client_request(
        self,
        *,
        link_id: int,
        sender_hash: str,
        client_message_id: str,
    ) -> _ChatMessage | None:
        """네트워크 재시도로 이미 저장된 동일 전송 요청을 찾는다."""
        return (
            self.db.query(_ChatMessage)
            .filter(
                _ChatMessage.link_id == link_id,
                _ChatMessage.sender_hash == sender_hash,
                _ChatMessage.client_message_id == client_message_id,
            )
            .first()
        )

    # 함수이름: add
    # 함수역할: 새 채팅 메시지를 현재 트랜잭션에 추가한다.
    # 매개변수: message - 저장할 채팅 메시지
    # 반환값: 없음
    def add(self, message: _ChatMessage) -> None:
        """새 채팅 메시지를 현재 트랜잭션에 추가한다."""
        self.db.add(message)

    # 함수이름: mark_incoming_read
    # 함수역할: 상대가 보낸 미확인 메시지를 지정한 범위까지 읽음 처리한다.
    # 매개변수: link_id, reader_hash, through_message_id, read_at
    # 반환값: 변경 개수와 마지막 읽음 메시지 식별자
    def mark_incoming_read(
        self,
        *,
        link_id: int,
        reader_hash: str,
        through_message_id: int | None,
        read_at: datetime,
    ) -> tuple[int, int | None]:
        """상대가 보낸 미확인 메시지를 지정한 메시지까지 읽음 처리한다."""
        query = self.db.query(_ChatMessage).filter(
            _ChatMessage.link_id == link_id,
            _ChatMessage.sender_hash != reader_hash,
            _ChatMessage.read_at.is_(None),
        )
        if through_message_id is not None:
            query = query.filter(_ChatMessage.id <= through_message_id)
        rows = query.order_by(_ChatMessage.id.asc()).all()
        if not rows:
            return 0, None
        for row in rows:
            row.read_at = read_at
        return len(rows), int(rows[-1].id)

    # 함수이름: unread_count
    # 함수역할: 현재 사용자가 읽지 않은 상대 메시지 수를 계산한다.
    # 매개변수: link_id, reader_hash
    # 반환값: 읽지 않은 메시지 수
    def unread_count(self, *, link_id: int, reader_hash: str) -> int:
        """현재 사용자가 아직 읽지 않은 상대 메시지 개수를 반환한다."""
        return (
            self.db.query(_ChatMessage)
            .filter(
                _ChatMessage.link_id == link_id,
                _ChatMessage.sender_hash != reader_hash,
                _ChatMessage.read_at.is_(None),
            )
            .count()
        )
