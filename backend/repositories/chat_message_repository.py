# 파일명: chat_message_repository.py
# 역할: 채팅 메시지의 반복 조회와 변경 조건을 한곳에 모은다.

"""채팅 메시지의 반복 조회와 변경 조건을 한곳에 모은다."""

from datetime import datetime

from sqlalchemy.orm import Session

from entities.chat_message_entity import _ChatMessage


# 클래스명: ChatMessageRepository
# 역할:
# - 연동별 채팅 기록과 읽음 상태의 영속성 규칙을 관리한다.
# 주요 책임:
# - 페이지 조회, 중복 전송 조회, 저장과 읽음 상태 변경을 담당한다.
# 속성:
# - db (Session): 호출자가 트랜잭션 수명을 관리하는 SQLAlchemy 세션.
class ChatMessageRepository:
    """연동별 채팅 기록과 읽음 상태의 영속성 규칙을 관리한다."""

    # 함수이름: __init__
    # 함수역할:
    # - 채팅 조회와 상태 변경에 공통으로 사용할 호출자 세션을 보관한다.
    # 매개변수:
    # - db (Session): 영속 기록에 접근할 호출자의 SQLAlchemy 세션.
    # 반환값:
    # - 없음; 세션 생성이나 커밋은 수행하지 않는다.
    def __init__(self, db: Session) -> None:
        self.db = db

    # 함수이름: find_selected_for_update
    # 함수역할:
    # - 한 연동에 속한 선택 메시지를 ID 순서로 잠가 원자적 삭제 검사를 준비한다.
    # 매개변수:
    # - link_id (int): 환자와 보호자 간 연동 ID.
    # - message_ids (list[int]): 삭제 검사할 검증된 메시지 ID 목록.
    # 반환값:
    # - 존재하는 해당 연동의 행 목록; 누락되거나 다른 연동의 ID 검사는 Control이 맡는다.
    def find_selected_for_update(
        self, *, link_id: int, message_ids: list[int],
    ) -> list[_ChatMessage]:
        return self.db.query(_ChatMessage).filter(
            _ChatMessage.link_id == link_id,
            _ChatMessage.id.in_(message_ids),
        ).order_by(_ChatMessage.id).with_for_update().all()

    # 함수이름: list_recent
    # 함수역할:
    # - 최신 메시지 기준 페이지를 오래된 순서로 반환한다.
    # 매개변수:
    # - link_id (int): 환자와 보호자 간 연동 ID.
    # - before_message_id (int | None): 이 ID보다 오래된 메시지만 조회한다; None이면 최신 페이지.
    # - limit (int): 반환할 일치 기록의 최대 개수.
    # 반환값:
    # - 오래된 순서로 정렬한 메시지 목록과 이전 페이지 존재 여부의 튜플.
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
    # 함수역할:
    # - 네트워크 재시도로 이미 저장된 동일 전송 요청을 찾는다.
    # 매개변수:
    # - link_id (int): 환자와 보호자 간 연동 ID.
    # - sender_hash (str): 중복 전송을 확인할 발신자 소유권 해시.
    # - client_message_id (str): 클라이언트가 재시도에도 동일하게 보내는 메시지 식별자.
    # 반환값:
    # - 일치하는 채팅 메시지 또는 없음
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
    # 함수역할:
    # - 새 채팅 메시지를 현재 트랜잭션에 추가한다.
    # 매개변수:
    # - message (_ChatMessage): 현재 트랜잭션에 추가할 새 채팅 메시지 엔티티.
    # 반환값:
    # - 없음
    def add(self, message: _ChatMessage) -> None:
        """새 채팅 메시지를 현재 트랜잭션에 추가한다."""
        self.db.add(message)

    # 함수이름: mark_incoming_read
    # 함수역할:
    # - 상대가 보낸 미확인 메시지를 지정한 범위까지 읽음 처리한다.
    # 매개변수:
    # - link_id (int): 환자와 보호자 간 연동 ID.
    # - reader_hash (str): 메시지를 읽은 참여자의 소유권 해시.
    # - through_message_id (int | None): 읽음 처리할 마지막 메시지 ID; None이면 조건에 맞는 전체.
    # - read_at (datetime): 선택 메시지에 저장할 읽음 시각.
    # - is_patient (bool): 환자 기준 삭제 여부를 확인할지; False이면 보호자 기준.
    # 반환값:
    # - 변경 개수와 마지막 읽음 메시지 식별자
    def mark_incoming_read(
        self,
        *,
        link_id: int,
        reader_hash: str,
        through_message_id: int | None,
        read_at: datetime,
        is_patient: bool = False,
    ) -> tuple[int, int | None]:
        """상대가 보낸 미확인 메시지를 지정한 메시지까지 읽음 처리한다."""
        query = self.db.query(_ChatMessage).filter(
            _ChatMessage.link_id == link_id,
            _ChatMessage.sender_hash != reader_hash,
            _ChatMessage.read_at.is_(None),
            _ChatMessage.deleted_for_everyone_at.is_(None),
            (_ChatMessage.patient_deleted_at if is_patient
             else _ChatMessage.caregiver_deleted_at).is_(None),
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
    # 함수역할:
    # - 현재 사용자가 읽지 않은 상대 메시지 수를 계산한다.
    # 매개변수:
    # - link_id (int): 환자와 보호자 간 연동 ID.
    # - reader_hash (str): 미확인 수를 조회할 참여자의 소유권 해시.
    # - is_patient (bool): 환자의 숨김 상태를 적용할지; False이면 보호자의 숨김 상태.
    # 반환값:
    # - 읽지 않은 메시지 수
    def unread_count(
        self, *, link_id: int, reader_hash: str, is_patient: bool = False,
    ) -> int:
        """현재 사용자가 아직 읽지 않은 상대 메시지 개수를 반환한다."""
        return (
            self.db.query(_ChatMessage)
            .filter(
                _ChatMessage.link_id == link_id,
                _ChatMessage.sender_hash != reader_hash,
                _ChatMessage.read_at.is_(None),
                _ChatMessage.deleted_for_everyone_at.is_(None),
                (_ChatMessage.patient_deleted_at if is_patient
                 else _ChatMessage.caregiver_deleted_at).is_(None),
            )
            .count()
        )
