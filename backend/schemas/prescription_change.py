# 파일명: prescription_change.py
# 역할: 처방 변화 비교 요청과 응답 DTO를 정의한다.

from datetime import date
from typing import Literal

from pydantic import BaseModel, Field

from entities.patient_hash_entity import DEFAULT_PATIENT_HASH


# 클래스명: PrescriptionChangeMedication
# 역할: 현재 처방에서 비교에 필요한 약품과 복약 일정 정보를 표현한다.
# 주요 책임:
#   - 공공데이터 품목 식별자, 약품명과 효능 정보를 보관한다.
#   - 용량, 횟수, 기간 비교에 필요한 값을 보관한다.
class PrescriptionChangeMedication(BaseModel):
    item_seq: str = ""
    item_name: str
    efficacy: str = ""
    dosage_per_time: str = ""
    daily_frequency: str = ""
    total_days: str = ""


# 클래스명: PrescriptionChangeRequest
# 역할: 현재 처방과 환자 범위를 처방 변화 비교 Control에 전달한다.
# 주요 책임:
#   - 비교 대상 환자와 현재 조제일자를 지정한다.
#   - 한 번에 비교할 현재 처방 약품 목록을 제한한다.
class PrescriptionChangeRequest(BaseModel):
    patient_hash: str = DEFAULT_PATIENT_HASH
    prescription_date: date | None = None
    medications: list[PrescriptionChangeMedication] = Field(
        min_length=1,
        max_length=50,
    )


# 클래스명: PrescriptionScheduleSnapshot
# 역할: 처방 변화 전후의 복약 일정 값을 표현한다.
class PrescriptionScheduleSnapshot(BaseModel):
    dosage_per_time: str = ""
    daily_frequency: str = ""
    total_days: str = ""


# 클래스명: PrescriptionMedicationChange
# 역할: 약품 한 건의 추가, 미확인, 일정 변경 결과를 표현한다.
class PrescriptionMedicationChange(BaseModel):
    change_type: str
    item_name: str
    changed_fields: list[str] = Field(default_factory=list)
    previous: PrescriptionScheduleSnapshot | None = None
    current: PrescriptionScheduleSnapshot | None = None


# 클래스명: PrescriptionChangeSummary
# 역할: 처방 변화 유형별 개수를 요약한다.
class PrescriptionChangeSummary(BaseModel):
    added_count: int = 0
    missing_count: int = 0
    schedule_changed_count: int = 0
    unchanged_count: int = 0


# 클래스명: PrescriptionChangeResponse
# 역할: 관련성 판정 상태, 이전 처방 기준일과 처방 변화 결과를 반환한다.
class PrescriptionChangeResponse(BaseModel):
    has_previous_prescription: bool
    comparison_status: Literal[
        "comparable",
        "no_history",
        "expired",
        "unrelated",
    ] = "no_history"
    comparison_window_days: int = 90
    similarity_score: float | None = None
    match_basis: str = ""
    previous_prescription_date: date | None = None
    current_prescription_date: date | None = None
    summary: PrescriptionChangeSummary
    changes: list[PrescriptionMedicationChange] = Field(default_factory=list)
