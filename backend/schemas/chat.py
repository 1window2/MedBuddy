# 파일명: chat.py
# 역할: 환자·보호자 채팅 API 요청 DTO와 검증 규칙을 정의한다.

"""환자·보호자 채팅 API 요청 DTO를 정의한다."""

from pydantic import BaseModel, Field, field_validator

from entities.chat_message_entity import CHAT_MESSAGE_KINDS, CHAT_MESSAGE_KIND_TEXT
from entities.medication_schedule_entity import MEDICATION_SCHEDULE_SLOT_KEYS


# 클래스명: ChatMessageCreate
# 역할: 새 채팅 메시지 전송 요청을 검증한다.
# 주요 책임: 요청 식별자, 본문, 복약 맥락 식별자의 형식과 길이를 제한한다.
class ChatMessageCreate(BaseModel):
    """새 텍스트 메시지 전송 요청을 검증한다."""

    client_message_id: str = Field(
        min_length=8,
        max_length=64,
        pattern=r"^[A-Za-z0-9_-]+$",
    )
    body: str = Field(min_length=1, max_length=500)
    message_kind: str = Field(default=CHAT_MESSAGE_KIND_TEXT, max_length=40)
    medication_id: int | None = Field(default=None, ge=1)
    slot_key: str | None = Field(default=None, max_length=20)
    pharmacy_id: str | None = Field(default=None, max_length=32)

    # 함수이름: normalize_body
    # 함수역할: 메시지 앞뒤 공백을 제거하고 빈 메시지를 거부한다.
    # 매개변수: value - 사용자가 입력한 메시지 본문
    # 반환값: 정규화된 메시지 본문
    @field_validator("body")
    @classmethod
    def normalize_body(cls, value: str) -> str:
        """앞뒤 공백만 제거하고 사용자가 입력한 줄바꿈은 유지한다."""
        normalized = value.strip()
        if not normalized:
            raise ValueError("Chat message must not be blank.")
        return normalized

    @field_validator("message_kind")
    @classmethod
    def validate_message_kind(cls, value: str) -> str:
        """서버가 지원하는 구조화 메시지 유형만 허용한다."""
        normalized = value.strip().lower()
        if normalized not in CHAT_MESSAGE_KINDS:
            raise ValueError("Unsupported chat message kind.")
        return normalized

    @field_validator("slot_key")
    @classmethod
    def validate_slot_key(cls, value: str | None) -> str | None:
        """전달된 복약 시간대가 지원 목록에 포함되는지 확인한다."""
        if value is None:
            return None
        normalized = value.strip().lower()
        if normalized not in MEDICATION_SCHEDULE_SLOT_KEYS:
            raise ValueError("Unsupported medication schedule slot.")
        return normalized

    @field_validator("pharmacy_id")
    @classmethod
    def normalize_pharmacy_id(cls, value: str | None) -> str | None:
        """약국 식별자 앞뒤 공백을 제거하고 빈 값은 사용하지 않는다."""
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None


# 클래스명: ChatReadUpdate
# 역할: 사용자가 확인한 마지막 메시지 식별자를 검증한다.
# 주요 책임: 읽음 처리 범위를 안전한 양의 정수로 제한한다.
class ChatReadUpdate(BaseModel):
    """현재 화면에서 확인한 마지막 메시지 식별자를 전달한다."""

    through_message_id: int | None = Field(default=None, ge=1)
