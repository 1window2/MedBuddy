# 파일명: chat.py
# 역할: 환자·보호자 채팅 API 요청 DTO와 검증 규칙을 정의한다.

"""환자·보호자 채팅 API 요청 DTO를 정의한다."""

from pydantic import BaseModel, Field, field_validator


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
    medication_id: int | None = Field(default=None, ge=1)

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


# 클래스명: ChatReadUpdate
# 역할: 사용자가 확인한 마지막 메시지 식별자를 검증한다.
# 주요 책임: 읽음 처리 범위를 안전한 양의 정수로 제한한다.
class ChatReadUpdate(BaseModel):
    """현재 화면에서 확인한 마지막 메시지 식별자를 전달한다."""

    through_message_id: int | None = Field(default=None, ge=1)
