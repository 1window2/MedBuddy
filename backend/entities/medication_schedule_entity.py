# 파일명: medication_schedule_entity.py
# 역할: OCR 복약 일정과 사용자 확인 시간대를 표현하는 엔티티를 정의한다.

import json
from datetime import date

from pydantic import AliasChoices, BaseModel, ConfigDict, Field

MEDICATION_SCHEDULE_SLOT_KEYS = ("morning", "lunch", "evening", "bedtime")
DEFAULT_MEDICATION_SCHEDULE_SLOT_KEY = MEDICATION_SCHEDULE_SLOT_KEYS[0]


# Function Name: medication_schedule_slot_keys_for_frequency
# Description:
# - Maps a daily medication frequency count to the schedule slots used by
#   MedicationSchedule, MedicationAlarm, and MedicationCompletion.
# Parameters:
# - frequency_count: Parsed daily medication frequency count.
# Returns:
# - Ordered list of schedule slot keys.
def medication_schedule_slot_keys_for_frequency(frequency_count: int) -> list[str]:
    if frequency_count >= 4:
        return list(MEDICATION_SCHEDULE_SLOT_KEYS)
    if frequency_count == 3:
        return list(MEDICATION_SCHEDULE_SLOT_KEYS[:3])
    if frequency_count == 2:
        return [
            MEDICATION_SCHEDULE_SLOT_KEYS[0],
            MEDICATION_SCHEDULE_SLOT_KEYS[2],
        ]
    return [DEFAULT_MEDICATION_SCHEDULE_SLOT_KEY]


# 함수명: normalize_medication_schedule_slot_keys
# 역할:
# - 외부 입력의 복약 시간대 키를 지원 순서에 맞는 중복 없는 목록으로 정규화한다.
# 매개변수:
# - values: 문자열 시간대 키 목록
# 반환값:
# - morning, lunch, evening, bedtime 순서의 유효한 시간대 목록
def normalize_medication_schedule_slot_keys(
    values: object,
) -> list[str]:
    if not isinstance(values, (list, tuple, set)):
        return []
    requested = {
        str(value).strip().lower()
        for value in values
        if str(value).strip().lower() in MEDICATION_SCHEDULE_SLOT_KEYS
    }
    return [
        slot_key
        for slot_key in MEDICATION_SCHEDULE_SLOT_KEYS
        if slot_key in requested
    ]


# 함수명: decode_medication_schedule_slot_keys
# 역할:
# - DB에 JSON 문자열로 저장된 사용자 확인 복약 시간대를 안전하게 읽는다.
def decode_medication_schedule_slot_keys(raw_value: str | None) -> list[str]:
    try:
        decoded = json.loads(raw_value or "[]")
    except (TypeError, ValueError):
        return []
    return normalize_medication_schedule_slot_keys(decoded)


# 함수명: encode_medication_schedule_slot_keys
# 역할:
# - 사용자 확인 복약 시간대 목록을 DB 저장용 JSON 문자열로 변환한다.
def encode_medication_schedule_slot_keys(values: object) -> str:
    return json.dumps(
        normalize_medication_schedule_slot_keys(values),
        ensure_ascii=False,
        separators=(",", ":"),
    )


# Class Name: MedicationSchedule
# Role: Represents one medication schedule or one extracted medication candidate.
# Responsibilities:
#   - Carry medication schedule fields defined in the class diagram.
#   - Validate and serialize schedule data crossing the control/API boundary.
# Attributes:
#   - masked_prescription_text: Masked prescription text.
#   - created_date: Date when the medication schedule was created.
#   - medication_id: Medication identifier.
#   - medication_name: Medication name.
#   - dosage: Dose per administration.
#   - intake_time: Intake frequency or time label.
#   - medcation_status: Medication completion status. The misspelling follows the diagram.
#   - patient_id: Patient identifier.
#   - medication_time: Total medication duration or time count.
#   - slot_statuses: Completion state keyed by time slot for today's schedule.
#   - completed_slot_keys: Completed time-slot keys for client compatibility.
class MedicationSchedule(BaseModel):
    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)

    masked_prescription_text: str = Field(
        default="",
        validation_alias=AliasChoices("maskedPrescriptionText", "masked_prescription_text"),
        serialization_alias="maskedPrescriptionText",
    )
    created_date: date | None = Field(
        default=None,
        validation_alias=AliasChoices("createdDate", "created_date"),
        serialization_alias="createdDate",
    )
    medication_id: str = Field(
        default="",
        validation_alias=AliasChoices("medicationID", "medication_id"),
        serialization_alias="medicationID",
    )
    medication_name: str = Field(
        default="",
        validation_alias=AliasChoices("medicationName", "medication_name", "drug_name"),
        serialization_alias="drug_name",
    )
    dosage: str = Field(
        default="",
        validation_alias=AliasChoices("dosage", "dosage_per_time"),
        serialization_alias="dosage_per_time",
    )
    intake_time: str = Field(
        default="",
        validation_alias=AliasChoices("intakeTime", "intake_time", "daily_frequency"),
        serialization_alias="daily_frequency",
    )
    medcation_status: bool = Field(
        default=False,
        validation_alias=AliasChoices(
            "medcationStatus",
            "medcation_status",
            "medicationStatus",
            "medication_status",
        ),
        serialization_alias="medication_status",
    )
    patient_id: str = Field(
        default="",
        validation_alias=AliasChoices("patientID", "patient_id"),
        serialization_alias="patientID",
    )
    medication_time: str = Field(
        default="",
        validation_alias=AliasChoices("medicationTime", "medication_time", "total_days"),
        serialization_alias="total_days",
    )
    slot_statuses: dict[str, bool] = Field(
        default_factory=dict,
        validation_alias=AliasChoices("slotStatuses", "slot_statuses"),
        serialization_alias="slot_statuses",
    )
    completed_slot_keys: list[str] = Field(
        default_factory=list,
        validation_alias=AliasChoices("completedSlotKeys", "completed_slot_keys"),
        serialization_alias="completed_slot_keys",
    )
    schedule_slot_keys: list[str] = Field(
        default_factory=list,
        validation_alias=AliasChoices("scheduleSlotKeys", "schedule_slot_keys"),
        serialization_alias="schedule_slot_keys",
    )
