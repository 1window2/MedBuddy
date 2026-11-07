# 파일명: medication_care.py
# 역할: 버전 검사와 재전송 식별자를 포함하는 약 변경·복용 기록 요청을 검증한다.

from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StrictInt, field_validator, model_validator

from entities.medication_schedule_entity import normalize_medication_schedule_slot_keys
from services.medication_dose_rhythm import names_nonpositive_duration


# Class Name: RegimenChanges
# Role: Contains only editable fields for a new medication regimen version.
# Responsibilities: Rejects extra/explicit-null fields and validates names, positive duration labels and supported slots.
# Attributes: item_name, dosage_per_time, daily_frequency, total_days and dosing_mode are optional strings; prescription_date is an optional date; schedule_slot_keys is an optional list[str].
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
    # 함수역할: 변경 약명의 앞뒤 공백을 제거하고 공백뿐인 값을 거절한다.
    # 매개변수: value (str | None)는 새 약명이다.
    # 반환값: 정리된 str 또는 None. 공백뿐인 문자열은 ValueError다.
    @field_validator("item_name")
    @classmethod
    def validate_name(cls, value: str | None) -> str | None:
        if value is not None and not value.strip():
            raise ValueError("A medication name is required.")
        return value.strip() if value is not None else None

    # Function Name: validate_total_days
    # Description: Rejects a recognized nonpositive duration instead of letting it become an open-ended regimen.
    # Parameters: value (str | None) is the proposed duration.
    # Returns: Unchanged value; raises ValueError for a recognized duration of zero or less.
    @field_validator("total_days")
    @classmethod
    def validate_total_days(cls, value: str | None) -> str | None:
        if names_nonpositive_duration(value):
            raise ValueError("The course length must be at least one day.")
        return value

    # 함수이름: validate_slots
    # 함수역할: 시간대를 고정 순서·중복 없는 형태로 바꾸되 지원하지 않는 값이 사라지는 입력은 거절한다.
    # 매개변수: value (list[str] | None)는 변경 시간대다.
    # 반환값: 정규화 목록 또는 None. 정규화 전후 집합이 달라지면 ValueError다.
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
    # 함수역할: 명시적 null을 변경 없음과 혼동하지 않도록 전달된 필드가 None이면 거절한다.
    # 매개변수: 없음. model_fields_set의 입력만 검사한다.
    # 반환값: 현재 RegimenChanges. 명시적 null은 ValueError다.
    @model_validator(mode="after")
    def reject_null_changes(self) -> "RegimenChanges":
        if any(getattr(self, name) is None for name in self.model_fields_set):
            raise ValueError("Omit unchanged fields instead of sending null.")
        return self


# 클래스명: RegimenChangeRequest
# 역할: 적용일을 지정한 처방 수정·중단·교체 요청을 검증한다.
# 주요 책임: 추가 필드를 거절하고 동시 수정 버전과 재전송 UUID를 전달한다.
# 속성: patient_hash (str | None)는 환자, action은 edit/stop/replace, effective_date는 date, expected_revision은 0 이상 StrictInt다.
#   operation_id는 UUID, changes는 RegimenChanges이며 적용 가능 날짜는 제어 계층에서 판단한다.
class RegimenChangeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    patient_hash: str | None = Field(default=None, max_length=128)
    action: Literal["edit", "stop", "replace"]
    effective_date: date
    expected_revision: StrictInt = Field(default=0, ge=0)
    operation_id: UUID
    changes: RegimenChanges = Field(default_factory=RegimenChanges)


# 클래스명: DoseHistoryUpdate
# 역할: 사용자 복용 보고와 재전송·충돌 방지 입력을 검증한다.
# 주요 책임: taken에만 시간대 포함 실제 시각을 허용하고 추가 필드를 거절하며 사유를 정리한다.
# 속성: patient_hash (str | None)는 환자, status는 taken/skipped/unrecorded, actual_taken_at은 datetime | None, reason은 str이다.
#   expected_revision은 0 이상 StrictInt, operation_id는 UUID다.
class DoseHistoryUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    patient_hash: str | None = Field(default=None, max_length=128)
    status: Literal["taken", "skipped", "unrecorded"]
    actual_taken_at: datetime | None = None
    reason: str = Field(default="", max_length=500)
    expected_revision: StrictInt = Field(default=0, ge=0)
    operation_id: UUID

    # 함수이름: validate_taken_time
    # 함수역할: taken에는 시간대 정보가 있는 실제 시각을 요구하고 다른 상태의 시각을 거절한 뒤 사유 공백을 정리한다.
    # 매개변수: 없음. 현재 모델의 상태·실제 시각·사유를 검사한다.
    # 반환값: 현재 DoseHistoryUpdate. 상태와 시각 계약 불일치는 ValueError다.
    @model_validator(mode="after")
    def validate_taken_time(self) -> "DoseHistoryUpdate":
        if self.status == "taken":
            if self.actual_taken_at is None or self.actual_taken_at.tzinfo is None:
                raise ValueError("Taken reports require a timezone-aware actual_taken_at.")
        elif self.actual_taken_at is not None:
            raise ValueError("Only taken reports may have actual_taken_at.")
        self.reason = self.reason.strip()
        return self
