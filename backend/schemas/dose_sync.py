# 파일명: dose_sync.py
# 역할: 사용자가 지정한 날짜·시간대·약의 복용 변경 요청을 검증한다.

from datetime import date
from typing import Annotated, Literal

from pydantic import BaseModel, Field, model_validator


# 클래스명: DoseSyncRequest
# 역할: 복약 변경과 선택적 채팅 기록에 필요한 입력을 제한한다.
# 속성: operation_id - 재전송 식별자, schedule_date/slot_key - 대상 일정,
#       medication_ids - 약 목록, completed - 복용 상태, link_id - 채팅 연결.
class DoseSyncRequest(BaseModel):
    operation_id: str = Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    schedule_date: date
    slot_key: Literal["morning", "lunch", "evening", "bedtime"]
    medication_ids: list[Annotated[int, Field(gt=0)]] = Field(min_length=1, max_length=100)
    completed: bool
    link_id: Annotated[int, Field(gt=0)] | None = None

    @model_validator(mode="after")
    # 함수이름: validate_chat
    # 함수역할: 채팅은 복용 완료만 허용하고 약 ID의 중복과 순서 차이를 정규화한다.
    # 매개변수: 없음. 반환값: 검증된 요청. 채팅 취소 요청은 검증 오류.
    def validate_chat(self) -> "DoseSyncRequest":
        if self.link_id is not None and not self.completed:
            raise ValueError("Chat receipts record completion only.")
        self.medication_ids = sorted(set(self.medication_ids))
        return self
