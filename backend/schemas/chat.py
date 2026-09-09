# 파일명: chat.py
# 역할: 환자·보호자 채팅 API 요청 DTO와 검증 규칙을 정의한다.

"""환자·보호자 채팅 API 요청 DTO를 정의한다."""

from typing import Annotated, Literal

from pydantic import BaseModel, Field, field_validator

from entities.chat_message_entity import (
    CHAT_MESSAGE_KINDS,
    CHAT_MESSAGE_KIND_TEXT,
    MAX_CHAT_MEDICATION_CONTEXTS,
)
from entities.medication_schedule_entity import MEDICATION_SCHEDULE_SLOT_KEYS


# 클래스명: ChatMessageCreate
# 역할:
# - 새 채팅 메시지 전송 요청을 검증한다.
# 주요 책임:
# - 요청 식별자, 본문, 복약 맥락 식별자의 형식과 길이를 제한한다.
# 속성:
# - client_message_id (str): 채팅 재전송 중복 방지용 클라이언트 생성 식별자.
# - body (str): 공백과 길이·내용 검증을 통과한 전송 본문.
# - message_kind (str): 텍스트 또는 구조화 문맥 메시지 유형.
# - medication_id (int | None): 선택할 저장 약의 식별자.
# - medication_ids (list[int]): 구조화 채팅 카드에 담을 선택적 저장 약 식별자 목록.
# - slot_key (str | None): morning, lunch, evening, bedtime 중 복용 시간대 키.
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
    medication_ids: list[int] = Field(
        default_factory=list,
        max_length=MAX_CHAT_MEDICATION_CONTEXTS,
    )
    slot_key: str | None = Field(default=None, max_length=20)
    pharmacy_id: str | None = Field(default=None, max_length=32)

    # 함수이름: normalize_body
    # 함수역할:
    # - 메시지 앞뒤 공백을 제거하고 빈 메시지를 거부한다.
    # 매개변수:
    # - value (str): 사용자가 입력한 메시지 본문
    # 반환값:
    # - 정규화된 메시지 본문
    @field_validator("body")
    @classmethod
    def normalize_body(cls, value: str) -> str:
        """앞뒤 공백만 제거하고 사용자가 입력한 줄바꿈은 유지한다."""
        normalized = value.strip()
        if not normalized:
            raise ValueError("Chat message must not be blank.")
        return normalized

    # 함수이름: validate_message_kind
    # 함수역할:
    # - 지원하는 텍스트·구조화 채팅 유형인지 검증한다.
    # 매개변수:
    # - value (str): 요청한 채팅 메시지 유형.
    # 반환값:
    # - 허용된 메시지 유형; 미지원 유형은 ValueError.
    @field_validator("message_kind")
    @classmethod
    def validate_message_kind(cls, value: str) -> str:
        """서버가 지원하는 구조화 메시지 유형만 허용한다."""
        normalized = value.strip().lower()
        if normalized not in CHAT_MESSAGE_KINDS:
            raise ValueError("Unsupported chat message kind.")
        return normalized

    # 함수이름: normalize_medication_ids
    # 함수역할:
    # - 양수 약 식별자를 입력 순서대로 중복 없이 유지한다.
    # 매개변수:
    # - value (list[int]): 요청한 저장 약 식별자 목록.
    # 반환값:
    # - 정리된 약 식별자 목록.
    @field_validator("medication_ids")
    @classmethod
    def normalize_medication_ids(cls, value: list[int]) -> list[int]:
        """양의 약 식별자만 입력 순서대로 중복 없이 유지한다."""
        normalized: list[int] = []
        for medication_id in value:
            if medication_id < 1:
                raise ValueError("Medication identifiers must be positive.")
            if medication_id not in normalized:
                normalized.append(medication_id)
        return normalized

    # 함수이름: validate_slot_key
    # 함수역할:
    # - 선택적 복용 시간대가 서버 지원 목록에 포함되는지 확인한다.
    # 매개변수:
    # - value (str | None): 메시지에 연결할 선택적 복용 시간대 키.
    # 반환값:
    # - 유효한 시간대 또는 None; 미지원 값은 ValueError.
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

    # 함수이름: normalize_pharmacy_id
    # 함수역할:
    # - 약국 식별자 양끝 공백을 제거하고 빈 값은 생략한다.
    # 매개변수:
    # - value (str | None): 메시지에 연결할 선택적 약국 식별자.
    # 반환값:
    # - 정리된 약국 식별자 또는 None.
    @field_validator("pharmacy_id")
    @classmethod
    def normalize_pharmacy_id(cls, value: str | None) -> str | None:
        """약국 식별자 앞뒤 공백을 제거하고 빈 값은 사용하지 않는다."""
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None


# 클래스명: ChatReadUpdate
# 역할:
# - 사용자가 확인한 마지막 메시지 식별자를 검증한다.
# 주요 책임:
# - 읽음 처리 범위를 안전한 양의 정수로 제한한다.
# 속성:
# - through_message_id (int | None): 읽음 처리에 포함할 선택적 마지막 메시지 식별자.
class ChatReadUpdate(BaseModel):
    """현재 화면에서 확인한 마지막 메시지 식별자를 전달한다."""

    through_message_id: int | None = Field(default=None, ge=1)


# 클래스명: ChatMessageDelete
# 역할:
# - 최대 50개의 양수 메시지 식별자와 개인·전체 삭제 범위를 검증한다.
# 주요 책임:
# - 엄격한 양수 정수 선택과 me/everyone 범위를 요구해 임의 일괄 삭제 입력을 제한한다.
# 속성:
# - message_ids (list[Annotated[int, Field(strict=True, gt=0)]]): 삭제 대상으로 명시한 메시지 식별자 목록.
# - scope (Literal['me', 'everyone']): 삭제 범위: me는 개인 숨김, everyone은 양쪽 참여자에서 내용 제거.
class ChatMessageDelete(BaseModel):
    message_ids: list[Annotated[int, Field(strict=True, gt=0)]] = Field(
        min_length=1, max_length=50,
    )
    scope: Literal["me", "everyone"]
