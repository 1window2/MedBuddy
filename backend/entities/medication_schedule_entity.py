# File Name: medication_schedule_entity.py
# Role: Defines OCR and saved-medication schedules with ordered dose-slot normalization and compatibility aliases.

import json
from datetime import date

from pydantic import AliasChoices, BaseModel, ConfigDict, Field

MEDICATION_SCHEDULE_SLOT_KEYS = ("morning", "lunch", "evening", "bedtime")
DEFAULT_MEDICATION_SCHEDULE_SLOT_KEY = MEDICATION_SCHEDULE_SLOT_KEYS[0]


# Function Name: medication_schedule_slot_keys_for_frequency
# Description:
# - Maps a daily medication frequency count to the schedule slots used by MedicationSchedule, MedicationAlarm, and MedicationCompletion.
# Parameters:
# - frequency_count (int): Parsed daily medication frequency count.
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


# 함수이름: normalize_medication_schedule_slot_keys
# 함수역할:
# - 외부 입력의 복약 시간대 키를 지원 순서에 맞는 중복 없는 목록으로 정규화한다.
# 매개변수:
# - values (object): 문자열 시간대 키 목록
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


# 함수이름: decode_medication_schedule_slot_keys
# 함수역할:
# - DB의 JSON 시간대 목록을 읽고 지원 순서로 정리한다.
# 매개변수:
# - raw_value (str | None): 저장된 사용자 확인 복용 시간대 JSON 표현.
# 반환값:
# - 유효한 시간대 목록; 잘못된 JSON이나 비목록 값은 빈 목록.
def decode_medication_schedule_slot_keys(raw_value: str | None) -> list[str]:
    try:
        decoded = json.loads(raw_value or "[]")
    except (TypeError, ValueError):
        return []
    return normalize_medication_schedule_slot_keys(decoded)


# 함수이름: encode_medication_schedule_slot_keys
# 함수역할:
# - 사용자 확인 시간대를 정규화해 공백 없는 JSON 목록으로 저장한다.
# 매개변수:
# - values (object): 정규화할 사용자 확인 시간대 목록 입력.
# 반환값:
# - 순서와 중복이 정리된 시간대 JSON 문자열.
def encode_medication_schedule_slot_keys(values: object) -> str:
    return json.dumps(
        normalize_medication_schedule_slot_keys(values),
        ensure_ascii=False,
        separators=(",", ":"),
    )


# 클래스명: MedicationSchedule
# 역할:
# - OCR 복약 후보와 환자별 일정을 표현하고 API 별칭·시간대별 완료 상태를 직렬화한다.
# 주요 책임:
# - 기존 UML·API 필드 별칭을 수용하고 전체 완료 상태와 사용자 확인·완료 시간대 목록을 함께 전달한다.
# 속성:
# - masked_prescription_text (str): 개인정보가 제거된 처방전 텍스트.
# - created_date (date | None): 일정 또는 복약 스냅샷의 생성 날짜.
# - medication_id (str): OCR 후보 또는 저장된 복약 일정의 약품 식별자.
# - medication_name (str): 약품 표시 이름.
# - dosage (str): 한 번에 복용할 용량.
# - intake_time (str): 일일 복용 횟수 또는 시간 설명.
# - medcation_status (bool): 전체 복용 완료 상태; 철자는 UML 계약을 따른다.
# - patient_id (str): 일정에 포함된 환자 식별자.
# - medication_time (str): 전체 복용 기간 또는 횟수 정보.
# - slot_statuses (dict[str, bool]): 복용 시간대별 완료 여부.
# - completed_slot_keys (list[str]): 이미 완료한 복용 시간대 목록.
# - schedule_slot_keys (list[str]): 사용자가 확인한 morning, lunch, evening, bedtime 복용 시간대 목록.
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
