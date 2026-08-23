# 파일명: chat_message_entity.py
# 역할: 환자·보호자 채팅 메시지의 저장 모델과 응답 모델을 정의한다.

"""환자·보호자 채팅 메시지의 저장 모델과 응답 모델을 정의한다."""

from datetime import UTC, datetime

from pydantic import BaseModel, ConfigDict
from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)

from core.database import Base
from entities.medication_image_url_entity import safe_medication_image_url
from entities.patient_caregiver_link_entity import _PatientCaregiverLink  # noqa: F401
from entities.user_account_entity import _UserAccount  # noqa: F401


# 함수이름: utc_now
# 함수역할: 데이터베이스에 저장할 시간대 정보 없는 UTC 현재 시각을 만든다.
# 매개변수: 없음
# 반환값: UTC 기준 datetime
def utc_now() -> datetime:
    """DB에 저장할 시간대 정보 없는 UTC 현재 시각을 반환한다."""
    return datetime.now(UTC).replace(tzinfo=None)


# 클래스명: _ChatMessage
# 역할: 연동별 채팅 메시지와 복약 스냅샷을 영속화한다.
# 주요 책임: 중복 전송 방지 키, 본문, 복약 맥락과 읽음 시각을 저장한다.
class _ChatMessage(Base):
    """하나의 활성 환자·보호자 연동에서 주고받은 메시지를 저장한다."""

    __tablename__ = "chat_messages"
    __table_args__ = (
        UniqueConstraint(
            "link_id",
            "sender_hash",
            "client_message_id",
            name="uq_chat_message_client_request",
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    link_id = Column(
        Integer,
        ForeignKey("patient_caregiver_links.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    sender_hash = Column(
        String,
        ForeignKey("user_accounts.user_hash", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    client_message_id = Column(String(length=64), nullable=False)
    body = Column(Text, nullable=False)
    medication_id = Column(Integer, nullable=True)
    medication_name = Column(String(length=300), nullable=True)
    medication_image_url = Column(Text, nullable=True)
    medication_dosage = Column(String(length=100), nullable=True)
    created_at = Column(DateTime, nullable=False, default=utc_now, index=True)
    read_at = Column(DateTime, nullable=True)


# 클래스명: ChatMessage
# 역할: 서버 내부와 API 응답에서 사용하는 불변 채팅 메시지를 표현한다.
# 주요 책임: DB 행 변환, 복약 스냅샷 정리와 UTC 응답 직렬화를 담당한다.
class ChatMessage(BaseModel):
    """서버 내부와 API 응답에서 사용하는 불변 채팅 메시지 모델이다."""

    model_config = ConfigDict(frozen=True)

    message_id: int
    link_id: int
    sender_hash: str
    client_message_id: str
    body: str
    created_at: datetime
    medication_id: int | None = None
    medication_name: str | None = None
    medication_image_url: str | None = None
    medication_dosage: str | None = None
    read_at: datetime | None = None

    # 함수이름: from_row
    # 함수역할: SQLAlchemy 채팅 행을 불변 응답 모델로 변환한다.
    # 매개변수: row - 저장된 채팅 메시지 행
    # 반환값: ChatMessage
    @classmethod
    def from_row(cls, row: _ChatMessage) -> "ChatMessage":
        """SQLAlchemy 행을 채팅 응답 모델로 변환한다."""
        return cls(
            message_id=int(row.id),
            link_id=int(row.link_id),
            sender_hash=str(row.sender_hash),
            client_message_id=str(row.client_message_id),
            body=str(row.body),
            created_at=row.created_at,
            medication_id=(
                int(row.medication_id) if row.medication_id is not None else None
            ),
            medication_name=row.medication_name,
            medication_image_url=row.medication_image_url,
            medication_dosage=row.medication_dosage,
            read_at=row.read_at,
        )

    # 함수이름: to_response_dict
    # 함수역할: 채팅 메시지를 모바일 앱 응답 필드 형식으로 변환한다.
    # 매개변수: 없음
    # 반환값: JSON 직렬화 가능한 메시지 사전
    def to_response_dict(self) -> dict[str, object]:
        """모바일 앱이 사용하는 JSON 필드 형식으로 변환한다."""
        medication_context = self._medication_context_response()
        return {
            "message_id": self.message_id,
            "link_id": self.link_id,
            "sender_hash": self.sender_hash,
            "client_message_id": self.client_message_id,
            "body": self.body,
            "created_at": _as_utc_isoformat(self.created_at),
            "medication_context": medication_context,
            "read_at": (
                _as_utc_isoformat(self.read_at) if self.read_at is not None else None
            ),
        }

    def _medication_context_response(self) -> dict[str, object] | None:
        """전송 당시 보존한 약 정보를 클라이언트 표시 형식으로 반환한다."""
        medication_name = (self.medication_name or "").strip()
        if not medication_name:
            return None
        return {
            "medication_id": self.medication_id,
            "medication_name": medication_name,
            "image_url": safe_medication_image_url(self.medication_image_url),
            "dosage_per_time": (self.medication_dosage or "").strip(),
        }


# 함수이름: _as_utc_isoformat
# 함수역할: 데이터베이스 시각을 명시적인 UTC ISO 문자열로 변환한다.
# 매개변수: value - 변환할 시각
# 반환값: UTC ISO 8601 문자열
def _as_utc_isoformat(value: datetime) -> str:
    """DB의 시간대 없는 UTC 값을 명시적인 UTC ISO 문자열로 바꾼다."""
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    else:
        value = value.astimezone(UTC)
    return value.isoformat()
