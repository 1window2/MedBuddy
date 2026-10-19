# 파일명: medication_care.py
# 역할: 버전 검사와 재전송 식별자를 포함하는 약 변경·복용 기록 요청을 검증한다.

from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StrictInt, field_validator, model_validator

from entities.medication_schedule_entity import normalize_medication_schedule_slot_keys


# 클래스명: RegimenChanges
# 역할: 새 약 버전에 반영할 사용자 입력만 허용한다.
# 속성: 약 이름·복용량·기간·확인 시간대·복용 모드.
class RegimenChanges(BaseModel):
    model_config = ConfigDict(extra="forbid")
    # 저장과 같은 이름 길이를 허용해, 저장된 긴 이름의 약도 그대로 변경할 수 있게 한다.
    item_name: str | None = Field(default=None, min_length=1, max_length=500)
    dosage_per_time: str | None = Field(default=None, max_length=300)
    daily_frequency: str | None = Field(default=None, max_length=300)
    total_days: str | None = Field(default=None, max_length=300)
    prescription_date: date | None = None
    schedule_slot_keys: list[str] | None = Field(default=None, max_length=4)
    dosing_mode: Literal["scheduled", "as_needed"] | None = None

    # 함수이름: validate_name
    # 함수역할: 공백뿐인 약 이름을 거부한다.
    # 매개변수: value: 새 이름. 반환값: 앞뒤 공백을 제거한 이름.
    @field_validator("item_name")
    @classmethod
    def validate_name(cls, value: str | None) -> str | None:
        if value is not None and not value.strip():
            raise ValueError("A medication name is required.")
        return value.strip() if value is not None else None

    # 함수이름: validate_slots
    # 함수역할: 미지원 시간대를 조용히 버리지 않고 요청 오류로 처리한다.
    # 매개변수: value: 시간대 목록. 반환값: 지원 순서의 중복 없는 목록.
    @field_validator("schedule_slot_keys")
    @classmethod
    def validate_slots(cls, value: list[str] | None) -> list[str] | None:
        if value is None:
            return None
        normalized = normalize_medication_schedule_slot_keys(value)
        if set(value) != set(normalized):
            raise ValueError("Unsupported medication time slot.")
        return normalized

    # 함수이름: reject_null_changes
    # 함수역할: 명시적 null로 필수 복용 정보를 지우는 모호한 변경을 막는다.
    # 매개변수: 없음. 반환값: 검증된 변경 정보.
    @model_validator(mode="after")
    def reject_null_changes(self) -> "RegimenChanges":
        if any(getattr(self, name) is None for name in self.model_fields_set):
            raise ValueError("Omit unchanged fields instead of sending null.")
        return self


# 클래스명: RegimenChangeRequest
# 역할: 미래 적용일 기준의 수정·중단·교체를 요청한다.
# 속성: expected_revision: 조회 버전, operation_id: 재전송 UUID, changes: 새 버전 입력.
class RegimenChangeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    patient_hash: str | None = Field(default=None, max_length=128)
    action: Literal["edit", "stop", "replace"]
    effective_date: date
    expected_revision: StrictInt = Field(default=0, ge=0)
    operation_id: UUID
    changes: RegimenChanges = Field(default_factory=RegimenChanges)


# 클래스명: DoseHistoryUpdate
# 역할: 사용자가 보고한 복용 상태와 실제 복용 시각을 서버 기록 시각과 분리한다.
# 속성: status: 사용자 보고 상태, actual_taken_at: 시간대 포함 실제 시각, reason: 선택적 사유.
class DoseHistoryUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    patient_hash: str | None = Field(default=None, max_length=128)
    status: Literal["taken", "skipped", "unrecorded"]
    actual_taken_at: datetime | None = None
    reason: str = Field(default="", max_length=500)
    expected_revision: StrictInt = Field(default=0, ge=0)
    operation_id: UUID

    # 함수이름: validate_taken_time
    # 함수역할: 복용 보고에는 실제 시각을 요구하고 다른 상태의 복용 시각은 거부한다.
    # 매개변수: 없음. 반환값: 검증된 기록 요청.
    @model_validator(mode="after")
    def validate_taken_time(self) -> "DoseHistoryUpdate":
        if self.status == "taken":
            if self.actual_taken_at is None or self.actual_taken_at.tzinfo is None:
                raise ValueError("Taken reports require a timezone-aware actual_taken_at.")
        elif self.actual_taken_at is not None:
            raise ValueError("Only taken reports may have actual_taken_at.")
        self.reason = self.reason.strip()
        return self
