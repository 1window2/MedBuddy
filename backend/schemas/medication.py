# 파일명: medication.py
# 역할: 약품 조회·저장·복약 상태·알림·사용자 설정·연동 코드와 처방 분석의 요청·응답 계약을 정의한다.

from datetime import date, timedelta
from typing import Literal, Optional

from pydantic import (
    AliasChoices,
    BaseModel,
    ConfigDict,
    Field,
    ValidationInfo,
    field_validator,
    model_validator,
)

from core.application_clock import application_today
from entities.medication_detail_entity import MedicationDetail
from entities.medication_image_url_entity import safe_medication_image_url
from entities.medication_schedule_entity import (
    normalize_medication_schedule_slot_keys,
)
from entities.patient_hash_entity import (
    DEFAULT_PATIENT_HASH,
    MAX_PATIENT_HASH_LENGTH,
    PATIENT_LINK_CODE_LENGTH,
)
from services.medication_dose_rhythm import names_nonpositive_duration

_MAX_MEDICATION_NAME_LENGTH = 500
_MAX_DETAIL_TEXT_LENGTH = 20_000
_MAX_SHORT_TEXT_LENGTH = 100
_MAX_URL_LENGTH = 2_048
_MAX_PUSH_TOKEN_LENGTH = 4_096
_MIN_PRESCRIPTION_DATE = date(2000, 1, 1)
_MAX_PRESCRIPTION_DATE_OFFSET_DAYS = 365
_PRESCRIPTION_BATCH_ID_PATTERN = r"^[A-Za-z0-9_-]{16,64}$"
_TRUNCATION_MARKER = "…"
_NUMBER_SEPARATORS = ".,/"


# Function Name: _is_number_character
# Description: Identifies digits and dose/count separators so truncation does not retain misleading partial numbers.
# Parameters: character (str) is one character at the truncation boundary.
# Returns: True for a digit or configured number separator.
def _is_number_character(character: str) -> bool:
    return character.isdigit() or character in _NUMBER_SEPARATORS


# Function Name: _truncate_to_field_limit
# Description: Truncates overlong text with an explicit marker, removing a partly cut numeric suffix to avoid changing apparent doses.
# Parameters: model (type[BaseModel]) declares constraints; field_name (str | None) selects the field; value (object) is raw input.
# Returns: Bounded string, or unchanged input when nontext, unconstrained or already within its limit.
def _truncate_to_field_limit(
    model: type[BaseModel],
    field_name: str | None,
    value: object,
) -> object:
    if not isinstance(value, str) or field_name is None:
        return value
    max_length = next(
        (
            constraint.max_length
            for constraint in model.model_fields[field_name].metadata
            if isinstance(getattr(constraint, "max_length", None), int)
        ),
        None,
    )
    if max_length is None or len(value) <= max_length:
        return value
    kept_length = max_length - len(_TRUNCATION_MARKER)
    kept = value[:kept_length]
    if kept and _is_number_character(value[kept_length]):
        while kept and _is_number_character(kept[-1]):
            kept = kept[:-1]
    return kept + _TRUNCATION_MARKER


# 클래스명: MedicationRequest
# 역할:
# - 약품 상세 조회용 추출 텍스트의 선택 여부와 최대 길이를 검증한다.
# 주요 책임:
# - 약품 상세 검색 경계에 과도하게 긴 텍스트가 전달되지 않도록 길이를 제한한다.
# 속성:
# - extracted_text (Optional[str]): 기기 또는 분석 흐름에서 추출한 약품 텍스트.
class MedicationRequest(BaseModel):
    original_text: str | None = Field(default=None, max_length=100)
    search_mode: Literal['fast', 'balanced', 'thorough'] = 'balanced'
    extracted_text: Optional[str] = Field(
        default=None,
        max_length=_MAX_DETAIL_TEXT_LENGTH,
    )


# 클래스명: SavedMedicationCreate
# 역할: 환자 소유 약 상세와 확인한 복용 지시를 저장하는 요청 모델이다.
# 주요 책임: 약명·날짜·시간대·이미지 출처를 검증하고 상세 안전정보·처방 배치를 보존한다.
# 속성: patient_hash (str)는 소유 범위, item_seq·prescription_batch_id (str | None)는 제품·배치, prescription_date (date | None)는 조제일이다.
#   item_name·efficacy·use_method·warning_message·interaction·side_effect·storage_method는 약명·효능·용법·경고·상호작용·부작용·보관 안내 str이다.
#   dosage_per_time·daily_frequency·total_days (str | None)는 처방 지시, schedule_slot_keys는 list[str], dosing_mode는 정기/필요시 모드다.
#   image_url·ai_guide (str | None)는 이미지와 추가 안내다.
class SavedMedicationCreate(BaseModel):
    patient_hash: str = Field(
        default=DEFAULT_PATIENT_HASH,
        min_length=1,
        max_length=MAX_PATIENT_HASH_LENGTH,
    )
    prescription_date: Optional[date] = None
    prescription_batch_id: Optional[str] = Field(
        default=None,
        pattern=_PRESCRIPTION_BATCH_ID_PATTERN,
    )
    item_seq: Optional[str] = Field(default=None, max_length=64)
    item_name: str = Field(
        min_length=1,
        max_length=_MAX_MEDICATION_NAME_LENGTH,
    )
    efficacy: str = Field(max_length=_MAX_DETAIL_TEXT_LENGTH)
    use_method: str = Field(max_length=_MAX_DETAIL_TEXT_LENGTH)
    warning_message: str = Field(max_length=_MAX_DETAIL_TEXT_LENGTH)
    interaction: str = Field(default="", max_length=_MAX_DETAIL_TEXT_LENGTH)
    side_effect: str = Field(default="", max_length=_MAX_DETAIL_TEXT_LENGTH)
    storage_method: str = Field(default="", max_length=_MAX_DETAIL_TEXT_LENGTH)
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
    schedule_slot_keys: list[str] = Field(default_factory=list, max_length=4)
    dosing_mode: Literal["scheduled", "as_needed"] = "scheduled"
    image_url: Optional[str] = Field(default=None, max_length=_MAX_URL_LENGTH)
    ai_guide: Optional[str] = Field(
        default=None,
        max_length=_MAX_DETAIL_TEXT_LENGTH,
    )

    # Function Name: validate_item_name
    # Description: Trims medication names and refuses whitespace-only input.
    # Parameters: value (str) is the requested name.
    # Returns: Trimmed name; raises ValueError when empty.
    @field_validator("item_name")
    @classmethod
    def validate_item_name(cls, value: str) -> str:
        normalized_name = value.strip()
        if not normalized_name:
            raise ValueError("A medication name is required.")
        return normalized_name

    # Function Name: validate_total_days
    # Description: Rejects explicitly nonpositive duration labels that would otherwise become unknown open-ended courses.
    # Parameters: value (str | None) is the requested duration.
    # Returns: Original value; raises ValueError for a recognized nonpositive duration.
    @field_validator("total_days")
    @classmethod
    def validate_total_days(cls, value: Optional[str]) -> Optional[str]:
        if names_nonpositive_duration(value):
            raise ValueError("The course length must be at least one day.")
        return value

    # 함수이름: validate_schedule_slot_keys
    # 함수역할:
    # - 시간대 목록을 지원 순서로 정리하고 값이 있지만 유효한 시간대가 하나도 없으면 거부한다.
    # 매개변수:
    # - value (list[str]): 저장 요청에 포함된 복용 시간대 목록.
    # 반환값:
    # - 정규화된 시간대 목록; 전부 미지원 값이면 ValueError.
    @field_validator("schedule_slot_keys")
    @classmethod
    def validate_schedule_slot_keys(cls, value: list[str]) -> list[str]:
        normalized_slot_keys = normalize_medication_schedule_slot_keys(value)
        if value and not normalized_slot_keys:
            raise ValueError("At least one supported schedule slot is required.")
        return normalized_slot_keys

    # Function Name: validate_image_url
    # Description:
    # - Accepts only the documented MFDS HTTPS medication-image origin.
    # - Rejects arbitrary client-controlled hosts before persistence.
    # Parameters:
    # - value (str | None): Optional image URL supplied by the client.
    # Returns:
    # - A trusted normalized URL, or None when the field is blank.
    @field_validator("image_url")
    @classmethod
    def validate_image_url(cls, value: str | None) -> str | None:
        if value is None or not value.strip():
            return None
        trusted_url = safe_medication_image_url(value)
        if not trusted_url:
            raise ValueError("Medication image URL is not trusted.")
        return trusted_url

    # 함수이름: validate_prescription_date
    # 함수역할:
    # - 직접 구성한 요청도 화면과 동일한 조제일자 허용 범위를 따르도록 검증한다.
    # 매개변수:
    # - value (date | None): 일정 조회 또는 검증 대상인 달력 날짜.
    # 반환값:
    # - 허용된 조제일자 또는 None; 범위를 벗어나면 ValueError.
    @field_validator("prescription_date")
    @classmethod
    def validate_prescription_date(cls, value: date | None) -> date | None:
        if value is None:
            return value
        maximum_date = application_today() + timedelta(
            days=_MAX_PRESCRIPTION_DATE_OFFSET_DAYS
        )
        if value < _MIN_PRESCRIPTION_DATE or value > maximum_date:
            raise ValueError(
                "Prescription date must be between 2000-01-01 and "
                "one year from today."
            )
        return value


# Class Name: MedicationStatusUpdate
# Role: Requests completion changes for all medication slots or one selected slot.
# Responsibilities: Carries completion intent and an optional expected date for stale-day rejection by the control.
# Attributes: medication_status (bool) is the target; slot_key (str | None) selects a slot; expected_schedule_date (date | None) asserts the intended day.
class MedicationStatusUpdate(BaseModel):
    medication_status: bool
    slot_key: Optional[str] = Field(default=None, max_length=32)
    expected_schedule_date: date | None = None


# 클래스명: PushTokenRegistration
# 역할:
# - 인증 사용자의 기기 푸시 토큰 등록·해제 요청을 검증한다.
# 주요 책임:
# - 토큰 양끝 공백을 정리하고 빈 토큰을 거부하며 기기 플랫폼을 전달한다.
# 속성:
# - token (str): Firebase Cloud Messaging이 발급한 기기 토큰
# - platform (str): 토큰을 발급한 모바일 플랫폼
class PushTokenRegistration(BaseModel):
    token: str = Field(min_length=16, max_length=_MAX_PUSH_TOKEN_LENGTH)
    platform: str = Field(default="android", pattern=r"^(android|ios)$")
    supports_caregiver_actions: bool = False
    supports_slot_check_actions: bool = False

    # 함수이름: validate_token
    # 함수역할:
    # - FCM 토큰의 양끝 공백을 제거하고 빈 토큰을 거부한다.
    # 매개변수:
    # - value (str): 기기에서 전달한 FCM 등록 토큰.
    # 반환값:
    # - 공백을 제거한 토큰; 비어 있으면 ValueError.
    @field_validator("token")
    @classmethod
    def validate_token(cls, value: str) -> str:
        normalized_token = value.strip()
        if not normalized_token:
            raise ValueError("Push token must not be blank.")
        return normalized_token


# 클래스명: MedicationAlarmUpdate
# 역할:
# - 복약 알람의 시를 0-23, 분을 0-59로 제한한다.
# 주요 책임:
# - 알람 시·분 범위를 검증하고 생략된 분은 0으로 채운다.
# 속성:
# - hour (int): 24시간제 기준 현지 알람 시.
# - minute (int): 현지 알람 분.
class MedicationAlarmUpdate(BaseModel):
    hour: int = Field(ge=0, le=23)
    minute: int = Field(default=0, ge=0, le=59)


# 클래스명: MedicationAlarmDisable
# 역할: 알림 해제 시 선택적으로 전달하는 시각을 검증한다.
# 주요 책임: 시각 생략은 저장값 유지로 구분하고 시만 입력한 요청은 정각으로 정규화한다.
# 속성: hour (int | None)는 0~23, minute (int | None)는 0~59이며 둘 다 생략 가능하다.
class MedicationAlarmDisable(BaseModel):
    hour: int | None = Field(default=None, ge=0, le=23)
    minute: int | None = Field(default=None, ge=0, le=59)

    # 함수이름: validate_optional_time
    # 함수역할: 분만 입력한 요청을 거절하고 시가 있는데 분이 없으면 0분을 채운다.
    # 매개변수: 없음. 현재 모델의 hour·minute을 검사한다.
    # 반환값: 현재 모델. hour 없이 minute이 있으면 ValueError다.
    @model_validator(mode="after")
    def validate_optional_time(self) -> "MedicationAlarmDisable":
        if self.hour is None and self.minute is not None:
            raise ValueError("Alarm minute requires an hour.")
        if self.hour is not None and self.minute is None:
            self.minute = 0
        return self


# 클래스명: CaregiverNotificationUpdate
# 역할:
# - 보호자 알림의 활성 상태·모드 별칭과 선택적 미복용 마감 시각을 검증한다.
# 주요 책임:
# - 기존 활성·모드 별칭을 수용하고 마감 시·분의 숫자 범위를 제한한다.
# 속성:
# - notification_enabled (Optional[bool]): 해당 알림 설정의 활성 여부.
# - notification_type (Optional[str]): 기존 enable/disable 별칭을 포함하는 지원 알림 모드.
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


# 클래스명: UserSettingUpdate
# 역할:
# - 접근성·언어·시각 표시와 알림 옵션의 허용값 및 기본 복약 시각 형식을 검증한다.
# 주요 책임:
# - 지원되는 접근성 배율·언어·알림 표시 옵션을 제한하고 기본 시간대 값을 제공한다.
# 속성:
# - font_size (int): 지원하는 접근성 범위의 표시 글자 크기.
# - reading_speed (float): 음성 읽기 속도 배율.
# - language (str): 요청한 한국어 또는 영어 콘텐츠 언어.
class UserSettingUpdate(BaseModel):
    expected_revision: int | None = Field(default=None, ge=0, strict=True)
    font_size: int = Field(ge=12, le=24)
    reading_speed: float = Field(ge=0.5, le=2.0)
    language: str = Field(pattern=r"^(ko|en)$")
    language_mode: str = Field(default="ko", pattern=r"^(system|ko|en)$")
    time_format: str = Field(default="24h", pattern=r"^(12h|24h)$")
    # 미전송은 기존 선택 유지, 신규 계정은 내 일정이 기본값이다.
    home_schedule_source: str | None = Field(default=None, pattern=r"^(self|patients)$")
    medication_notifications_enabled: bool = True
    caregiver_notifications_enabled: bool = True
    chat_notifications_enabled: bool = True
    notification_detail_mode: str = Field(
        default="full",
        pattern=r"^(full|type_only)$",
    )
    default_morning_time: str = Field(default="08:00", pattern=r"^\d{2}:\d{2}$")
    default_lunch_time: str = Field(default="12:00", pattern=r"^\d{2}:\d{2}$")
    default_evening_time: str = Field(default="18:00", pattern=r"^\d{2}:\d{2}$")
    default_bedtime: str = Field(default="22:00", pattern=r"^\d{2}:\d{2}$")


# 클래스명: VoiceGuideRequest
# 역할:
# - 음성 안내에 필요한 약품명·복용법·주의사항과 한국어·영어 선택을 전달한다.
# 주요 책임:
# - 기존 복용법·주의사항 필드 별칭을 수용해 음성 안내용 상세 엔티티로 변환한다.
# 속성:
# - item_name (str): 공공 약품 품목명.
# - usage_method (str): 환자에게 표시할 약품 복용 방법.
# - warning (str): 환자에게 표시할 약품 주의사항.
# - language (str): 요청한 한국어 또는 영어 콘텐츠 언어.
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

    # Function Name: to_medication_detail
    # Description:
    # - Maps speech-source fields to MedicationDetail without adding efficacy content.
    # Parameters:
    # - None.
    # Returns:
    # - Detail entity containing the requested drug name, usage and warning.
    def to_medication_detail(self) -> MedicationDetail:
        return MedicationDetail(
            item_name=self.item_name,
            efficacy="",
            use_method=self.usage_method,
            warning_message=self.warning,
        )


# 클래스명: PatientCodeCreate
# 역할:
# - 임시 환자 연동 코드를 발급할 환자 범위 식별자의 길이를 검증한다.
# 주요 책임:
# - 코드 발급 대상 식별자를 비어 있지 않은 제한 길이 문자열로 전달한다.
# 속성:
# - patient_hash (str): 작업 대상 환자의 데이터 소유 범위 식별자.
class PatientCodeCreate(BaseModel):
    patient_hash: str = Field(
        default=DEFAULT_PATIENT_HASH,
        min_length=1,
        max_length=MAX_PATIENT_HASH_LENGTH,
    )


# 클래스명: PatientCodeRegister
# 역할:
# - 보호자 식별자 별칭과 고정 길이 영숫자 환자 연동 코드를 검증한다.
# 주요 책임:
# - 보호자 호환 별칭을 수용하고 연동 코드를 대문자로 정리한 뒤 고정 길이 형식을 검증한다.
# 속성:
# - caregiver_hash (str): 환자와 연동된 보호자 계정 식별자.
# - patient_code (str): 보호자 연동 등록을 위해 입력한 임시 환자 코드.
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
    # - value (object): 요청 본문에서 전달된 환자 연동 코드
    # 반환값:
    # - 대문자로 정규화한 환자 연동 코드
    @field_validator("patient_code", mode="before")
    @classmethod
    def normalize_patient_code(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip().upper()
        return value


# 클래스명: PatientAliasUpdate
# 역할:
# - 보호자가 환자별로 지정하는 표시 이름을 검증한다.
# - 빈 문자열을 허용해 저장된 별칭을 기본 이름으로 되돌릴 수 있게 한다.
# 주요 책임:
# - 별칭 길이를 제한하면서 빈 문자열을 통한 기본 이름 복원을 허용한다.
# 속성:
# - patient_alias (str): 보호자가 지정한 환자 표시 이름; 빈 값은 별칭 해제.
class PatientAliasUpdate(BaseModel):
    patient_alias: str = Field(
        default="",
        max_length=20,
        validation_alias=AliasChoices(
            "patient_alias",
            "patientAlias",
            "display_name",
        ),
    )


# 클래스명: CaregiverAliasUpdate
# 역할: 환자가 지정하는 보호자 별칭을 검증한다.
# 주요 책임: 최대 20자를 허용하며 빈 문자열은 기본 이름 복원을 뜻한다.
# 속성: caregiver_alias (str): 환자가 지정한 보호자 표시 이름.
class CaregiverAliasUpdate(BaseModel):
    caregiver_alias: str = Field(
        max_length=20,
        validation_alias=AliasChoices("caregiver_alias", "caregiverAlias"),
    )


# 클래스명: MedicationResponse
# 역할: 약 조회의 확정 결과와 사용자 확인이 필요한 후보를 구분한다.
# 주요 책임: 성공·안내 문구와 후보 확인 요구·이유를 함께 직렬화한다.
# 속성: success는 bool, message·review_reason은 str, data·candidates는 list[MedicationDetail], requires_confirmation은 bool이다.
class MedicationResponse(BaseModel):
    success: bool
    message: str
    data: list[MedicationDetail] = Field(default_factory=list)
    candidates: list[MedicationDetail] = Field(default_factory=list)
    requires_confirmation: bool = False
    review_reason: str = ''


# 클래스명: PrescriptionMedicationResponse
# 역할:
# - 처방전에서 검증된 한 약의 일정 정보를 고정된 응답 형태로 제공한다.
# 주요 책임:
# - 약품명 검증 근거·신뢰도와 용량·횟수·기간을 한 약의 응답 계약으로 고정한다.
# 속성:
# - prescription_date (str): 확인된 경우 처방 조제일자.
# - drug_name (str): 검색 또는 직렬화할 약품명.
# - dosage_per_time (str): 처방에 표시된 1회 복용량.
# - daily_frequency (str): 하루 복용 횟수 또는 그 설명.
# - total_days (str): 처방된 총 복용 기간.
# 참고: AI가 길이 제한을 넘는 문자열을 돌려줘도 분석 전체가 실패하지 않도록 넘친 값은 말줄임표를 붙여 줄인다.
class PrescriptionMedicationResponse(BaseModel):
    prescription_date: str = Field(max_length=_MAX_SHORT_TEXT_LENGTH)
    drug_name: str = Field(max_length=_MAX_MEDICATION_NAME_LENGTH)
    raw_drug_name: str = Field(max_length=_MAX_MEDICATION_NAME_LENGTH)
    name_confidence: float = Field(ge=0.0, le=1.0)
    name_correction_source: str = Field(max_length=64)
    dosage_per_time: str = Field(max_length=_MAX_SHORT_TEXT_LENGTH)
    daily_frequency: str = Field(max_length=_MAX_SHORT_TEXT_LENGTH)
    total_days: str = Field(max_length=_MAX_SHORT_TEXT_LENGTH)

    # Function Name: truncate_overlong_text
    # Description: Enforces response field lengths before validation without leaving partial dose numbers.
    # Parameters: value (object) is raw input; info (ValidationInfo) identifies the field.
    # Returns: Marked truncated text or unchanged input when no truncation applies.
    @field_validator("*", mode="before")
    @classmethod
    def truncate_overlong_text(cls, value: object, info: ValidationInfo) -> object:
        return _truncate_to_field_limit(cls, info.field_name, value)


# 클래스명: PrescriptionAnalysisResponse
# 역할:
# - 기기 내 OCR 텍스트 분석 결과의 HTTP 응답 계약을 정의한다.
# 주요 책임:
# - 처방 메타데이터·배치 식별자와 원본·파싱·제외 약품 수를 일정 결과와 함께 전달한다.
# 속성:
# - hospital_name (str): 정규화된 처방에 남은 병원 이름.
# - prescription_date (str): 확인된 경우 처방 조제일자.
# - prescription_batch_id (str): 같은 분석에서 나온 약을 묶는 선택적 처방 배치 식별자.
# - raw_medication_count (int): 정규화·중복 제거 전 원본 약품 행 수.
# 참고: 길이 제한을 넘는 병원 이름·조제일자는 말줄임표를 붙여 줄인다.
class PrescriptionAnalysisResponse(BaseModel):
    hospital_name: str = Field(max_length=_MAX_MEDICATION_NAME_LENGTH)
    prescription_date: str = Field(max_length=_MAX_SHORT_TEXT_LENGTH)
    prescription_batch_id: str = Field(pattern=_PRESCRIPTION_BATCH_ID_PATTERN)
    medications: list[PrescriptionMedicationResponse] = Field(default_factory=list)
    raw_medication_count: int = Field(ge=0)
    parsed_medication_count: int = Field(ge=0)
    skipped_medication_count: int = Field(ge=0)

    # Function Name: truncate_overlong_text
    # Description: Enforces response field lengths before validation without leaving partial dose numbers.
    # Parameters: value (object) is raw input; info (ValidationInfo) identifies the field.
    # Returns: Marked truncated text or unchanged input when no truncation applies.
    @field_validator("*", mode="before")
    @classmethod
    def truncate_overlong_text(cls, value: object, info: ValidationInfo) -> object:
        return _truncate_to_field_limit(cls, info.field_name, value)
