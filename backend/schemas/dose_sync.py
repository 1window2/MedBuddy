# 파일명: dose_sync.py
# 역할: 사용자가 지정한 날짜·시간대·약의 복용 변경 요청을 검증한다.

from datetime import date
from typing import Annotated, Literal

from pydantic import BaseModel, Field, model_validator


# 클래스명: DoseSyncRequest
# 역할: 오프라인 복약 변경과 선택적 채팅 영수증 입력을 검증한다.
# 주요 책임: 요청 ID·양수 약 ID·시간대·버전 범위를 제한하고 채팅 완료 및 버전 키 일치를 검증한다.
# 속성: operation_id (str)는 재전송 키, schedule_date (date)·slot_key (str)는 일정, medication_ids는 list[int], completed는 bool이다.
#   link_id (int | None)는 채팅, regimen_revisions (dict[int, int] | None)는 선택 약별 조회 버전이다.
class DoseSyncRequest(BaseModel):
    operation_id: str = Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    schedule_date: date
    slot_key: Literal["morning", "lunch", "evening", "bedtime"]
    medication_ids: list[Annotated[int, Field(gt=0)]] = Field(min_length=1, max_length=100)
    completed: bool
    link_id: Annotated[int, Field(gt=0)] | None = None
    regimen_revisions: dict[Annotated[int, Field(gt=0)], Annotated[int, Field(ge=0)]] | None = Field(default=None, max_length=100)

    # 함수이름: validate_chat
    # 함수역할: 채팅에는 복용 완료만 허용하고 약 ID를 정렬·중복 제거한 뒤 전달된 처방 버전이 선택 약을 정확히 덮는지 확인한다.
    # 매개변수: 없음. 현재 요청 모델의 필드를 검증한다.
    # 반환값: 정규화된 현재 모델. 채팅 취소·버전 키 불일치는 ValueError다.
    @model_validator(mode="after")
    def validate_chat(self) -> "DoseSyncRequest":
        if self.link_id is not None and not self.completed:
            raise ValueError("Chat receipts record completion only.")
        self.medication_ids = sorted(set(self.medication_ids))
        if self.regimen_revisions is not None and set(self.regimen_revisions) != set(self.medication_ids):
            raise ValueError("Regimen revisions must cover exactly the selected medications.")
        return self
