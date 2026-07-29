# File Name: medication.py
# Role: Defines medication request and response DTOs.

from datetime import date
from typing import Optional

from pydantic import AliasChoices, BaseModel, ConfigDict, Field, field_validator

from entities.medication_detail_entity import MedicationDetail
from entities.patient_hash_entity import (
    DEFAULT_PATIENT_HASH,
    MAX_PATIENT_HASH_LENGTH,
    PATIENT_LINK_CODE_LENGTH,
)

_MAX_MEDICATION_NAME_LENGTH = 500
_MAX_DETAIL_TEXT_LENGTH = 20_000
_MAX_SHORT_TEXT_LENGTH = 100
_MAX_URL_LENGTH = 2_048


# Class Name: MedicationRequest
# Role: Request DTO for medication lookup.
# Attributes:
#   - extracted_text: Raw medication text extracted by the frontend or analysis flow.
class MedicationRequest(BaseModel):
    extracted_text: Optional[str] = Field(
        default=None,
        max_length=_MAX_DETAIL_TEXT_LENGTH,
    )


# Class Name: SavedMedicationCreate
# Role: Request DTO for saving a medication snapshot.
# Attributes:
#   - patient_hash: Patient ownership key used for saved medication scoping.
#   - item_seq: Canonical public product identifier used across MFDS datasets.
#   - item_name: Medication item name.
#   - efficacy: Medication efficacy summary.
#   - use_method: Medication use method summary.
#   - warning_message: Medication warning summary.
#   - dosage_per_time: Optional dose per administration from prescription analysis.
#   - daily_frequency: Optional daily frequency from prescription analysis.
#   - total_days: Optional total medication days from prescription analysis.
#   - ai_guide: Optional AI-generated patient guide.
class SavedMedicationCreate(BaseModel):
    patient_hash: str = Field(
        default=DEFAULT_PATIENT_HASH,
        min_length=1,
        max_length=MAX_PATIENT_HASH_LENGTH,
    )
    prescription_date: Optional[date] = None
    item_seq: Optional[str] = Field(default=None, max_length=64)
    item_name: str = Field(
        min_length=1,
        max_length=_MAX_MEDICATION_NAME_LENGTH,
    )
    efficacy: str = Field(max_length=_MAX_DETAIL_TEXT_LENGTH)
    use_method: str = Field(max_length=_MAX_DETAIL_TEXT_LENGTH)
    warning_message: str = Field(max_length=_MAX_DETAIL_TEXT_LENGTH)
    dosage_per_time: Optional[str] = Field(
        default=None,
        max_length=_MAX_SHORT_TEXT_LENGTH,
    )
    daily_frequency: Optional[str] = Field(
        default=None,
        max_length=_MAX_SHORT_TEXT_LENGTH,
    )
    total_days: Optional[str] = Field(
        default=None,
        max_length=_MAX_SHORT_TEXT_LENGTH,
    )
    image_url: Optional[str] = Field(default=None, max_length=_MAX_URL_LENGTH)
    ai_guide: Optional[str] = Field(
        default=None,
        max_length=_MAX_DETAIL_TEXT_LENGTH,
    )


# Class Name: MedicationStatusUpdate
# Role: Request DTO for updating today's medication completion status.
# Attributes:
#   - medication_status: Whether the medication is completed.
#   - slot_key: Optional time-slot key for per-dose completion updates.
class MedicationStatusUpdate(BaseModel):
    medication_status: bool
    slot_key: Optional[str] = Field(default=None, max_length=32)


# Class Name: MedicationAlarmUpdate
# Role: Request DTO for saving one medication alarm setting.
# Attributes:
#   - hour: 24-hour local alarm hour.
#   - minute: Local alarm minute.
class MedicationAlarmUpdate(BaseModel):
    hour: int = Field(ge=0, le=23)
    minute: int = Field(default=0, ge=0, le=59)


# Class Name: CaregiverNotificationUpdate
# Role: Request DTO for updating caregiver notification state.
# Attributes:
#   - notification_enabled: Boolean toggle value from the Flutter UI.
#   - notification_type: UML option string such as enable or disable.
class CaregiverNotificationUpdate(BaseModel):
    notification_enabled: Optional[bool] = Field(
        default=None,
        validation_alias=AliasChoices(
            "notification_enabled",
            "notificationEnabled",
            "is_enabled",
            "enabled",
        ),
    )
    notification_type: Optional[str] = Field(
        default=None,
        max_length=32,
        validation_alias=AliasChoices(
            "notification_type",
            "notificationType",
            "alert_option",
            "alertOption",
            "option",
        ),
    )
    deadline_hour: Optional[int] = Field(default=None, ge=0, le=23)
    deadline_minute: Optional[int] = Field(default=None, ge=0, le=59)


# Class Name: UserSettingUpdate
# Role: Request DTO for saving user display and reading settings.
# Attributes:
#   - font_size: Selected display font size.
#   - reading_speed: Selected voice/reading speed multiplier.
#   - language: Selected language code.
class UserSettingUpdate(BaseModel):
    font_size: int = Field(ge=12, le=24)
    reading_speed: float = Field(ge=0.5, le=2.0)
    language: str = Field(pattern=r"^(ko|en)$")


# Class Name: VoiceGuideRequest
# Role: Request DTO for medication voice guide generation.
# Attributes:
#   - item_name: Medication item name.
#   - usage_method: Medication use method summary.
#   - warning: Medication warning summary.
#   - language: Selected language code.
class VoiceGuideRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    item_name: str = Field(default="", max_length=_MAX_MEDICATION_NAME_LENGTH)
    usage_method: str = Field(
        default="",
        max_length=_MAX_DETAIL_TEXT_LENGTH,
        validation_alias=AliasChoices("usage_method", "use_method"),
    )
    warning: str = Field(
        default="",
        max_length=_MAX_DETAIL_TEXT_LENGTH,
        validation_alias=AliasChoices("warning", "warning_message"),
    )
    language: str = Field(default="ko", pattern=r"^(ko|en)$")

    def to_medication_detail(self) -> MedicationDetail:
        return MedicationDetail(
            item_name=self.item_name,
            efficacy="",
            use_method=self.usage_method,
            warning_message=self.warning,
        )


# Class Name: PatientCodeCreate
# Role: Request DTO for creating a temporary patient link code.
# Attributes:
#   - patient_hash: Patient ownership key encoded in the generated link code.
class PatientCodeCreate(BaseModel):
    patient_hash: str = Field(
        default=DEFAULT_PATIENT_HASH,
        min_length=1,
        max_length=MAX_PATIENT_HASH_LENGTH,
    )


# Class Name: PatientCodeRegister
# Role: Request DTO for registering a caregiver through a patient code.
# Attributes:
#   - caregiver_hash: Caregiver ownership key.
#   - patient_code: Temporary patient link code generated by the patient.
class PatientCodeRegister(BaseModel):
    caregiver_hash: str = Field(
        default=DEFAULT_PATIENT_HASH,
        min_length=1,
        max_length=MAX_PATIENT_HASH_LENGTH,
        validation_alias=AliasChoices("caregiver_hash", "guardian_hash"),
    )
    patient_code: str = Field(
        min_length=PATIENT_LINK_CODE_LENGTH,
        max_length=PATIENT_LINK_CODE_LENGTH,
        pattern=r"^[A-Z0-9]+$",
    )

    # 함수이름: normalize_patient_code
    # 함수역할:
    # - 환자 연동 코드의 공백을 제거하고 대문자로 통일한 뒤 형식 검증에 전달한다.
    # 매개변수:
    # - value: 요청 본문에서 전달된 환자 연동 코드
    # 반환값:
    # - 대문자로 정규화한 환자 연동 코드
    @field_validator("patient_code", mode="before")
    @classmethod
    def normalize_patient_code(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip().upper()
        return value


# Class Name: MedicationResponse
# Role: Response DTO for medication lookup results.
# Attributes:
#   - success: Whether lookup found data.
#   - message: User-facing result message.
#   - data: MedicationDetail result list.
class MedicationResponse(BaseModel):
    success: bool
    message: str
    data: list[MedicationDetail] = Field(default_factory=list)
