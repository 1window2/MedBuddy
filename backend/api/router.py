# File Name: router.py
# Role: Defines medication-related HTTP endpoints for the MedBuddy backend.

import logging

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel

from api.dependencies import (
    get_check_medication_detail,
    get_check_schedule,
    get_check_saved_medication,
    get_check_today_medication_info,
    get_manage_user_setting,
    get_patient_guardian_link_control,
    get_prescription_analysis_control,
    get_request_health_recommendation,
    get_request_voice_guide,
    get_set_guardian_alert_setting,
    get_set_guardian_medication,
    get_set_notification,
)
from controls.check_medication_detail_control import CheckMedicationDetail
from controls.check_schedule_control import CheckSchedule
from controls.check_saved_medication_control import CheckSavedMedication
from controls.check_today_medication_info_control import CheckTodayMedicationInfo
from controls.input_prescription_control import (
    MAX_PRESCRIPTION_IMAGE_BYTES,
    PrescriptionAnalysisControl,
)
from controls.manage_user_setting_control import ManageUserSetting
from controls.patient_guardian_link_control import PatientGuardianLinkControl
from controls.check_health_recommendation_control import CheckHealthRecommendation
from controls.request_voice_guide_control import RequestVoiceGuide
from controls.set_guardian_alert_setting_control import SetGuardianAlertSetting
from controls.set_guardian_medication_control import SetGuardianMedication
from controls.set_notification_control import SetNotification
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH
from schemas.medication import (
    MedicationRequest,
    MedicationResponse,
    MedicationStatusUpdate,
    MedicationAlarmUpdate,
    GuardianAlertUpdate,
    PatientCodeCreate,
    PatientCodeRegister,
    SavedMedicationCreate,
    UserSettingUpdate,
    VoiceGuideRequest,
)
from services.prescription_parser import parse_prescription

router = APIRouter()
logger = logging.getLogger(__name__)


# Class Name: OCRParseRequest
# Role: Request DTO for legacy OCR text parsing endpoint.
# Attributes:
#   - text: Raw OCR text from the frontend.
class OCRParseRequest(BaseModel):
    text: str


# Function Name: identify_medication
# Description:
# - Receives raw medication text and returns public drug information with AI guide.
# Parameters:
# - request: MedicationRequest containing extracted text.
# - check_medication_detail: CheckMedicationDetail injected by FastAPI.
# Returns:
# - MedicationResponse DTO.
@router.post("/identify", response_model=MedicationResponse)
async def identify_medication(
    request: MedicationRequest,
    check_medication_detail: CheckMedicationDetail = Depends(
        get_check_medication_detail
    ),
) -> MedicationResponse:
    if not request.extracted_text:
        raise HTTPException(status_code=400, detail="추출된 텍스트가 없습니다.")

    try:
        return await check_medication_detail.request_medication_detail(
            request.extracted_text
        )
    except HTTPException:
        raise
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        logger.error("Identify API internal error: %s", type(exc).__name__)
        raise HTTPException(status_code=500, detail="서버 내부 오류가 발생했습니다.") from exc


# Function Name: save_medication
# Description:
# - Saves selected medication information into the user's pillbox.
# Parameters:
# - medication: SavedMedicationCreate request DTO.
# - check_saved_medication: CheckSavedMedication injected by FastAPI.
# Returns:
# - API-compatible success dictionary.
@router.post("/save")
def save_medication(
    medication: SavedMedicationCreate,
    check_saved_medication: CheckSavedMedication = Depends(get_check_saved_medication),
) -> dict[str, object]:
    return check_saved_medication.save_medication_detail(medication)


# Function Name: get_saved_medications
# Description:
# - Returns saved medication rows scoped to patient or linked guardian access.
# Parameters:
# - patient_hash: Patient ownership key used to scope saved medication lookup.
# - user_hash: Requesting user hash. Used for guardian role resolution.
# - role: Requesting user role such as patient or guardian.
# - check_saved_medication: CheckSavedMedication injected by FastAPI.
# Returns:
# - API-compatible list dictionary.
@router.get("/list")
def get_saved_medications(
    patient_hash: str | None = None,
    user_hash: str | None = None,
    role: str = "patient",
    check_saved_medication: CheckSavedMedication = Depends(get_check_saved_medication),
) -> dict[str, object]:
    try:
        return check_saved_medication.request_saved_medication_info(
            patient_hash,
            user_hash,
            role,
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Saved medication lookup failed: %s", type(exc).__name__)
        raise HTTPException(
            status_code=500,
            detail="저장된 복약 정보를 불러오지 못했습니다.",
        ) from exc


# Function Name: get_today_medication_schedule
# Description:
# - Returns today's active medication schedule scoped to patient or linked guardian access.
# Parameters:
# - patient_hash: Patient ownership key used to scope schedule lookup.
# - user_hash: Requesting user hash. Used for guardian role resolution.
# - role: Requesting user role such as patient or guardian.
# - check_schedule: CheckSchedule injected by FastAPI.
# Returns:
# - API-compatible schedule list dictionary.
@router.get("/schedule/today")
def get_today_medication_schedule(
    patient_hash: str | None = None,
    user_hash: str | None = None,
    role: str = "patient",
    check_schedule: CheckSchedule = Depends(get_check_schedule),
) -> dict[str, object]:
    try:
        return check_schedule.request_today_medication_schedule(
            patient_hash,
            user_hash,
            role,
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.error(
            "Today medication schedule lookup failed: %s",
            type(exc).__name__,
        )
        raise HTTPException(
            status_code=500,
            detail="오늘의 복약 일정을 불러오지 못했습니다.",
        ) from exc


# Function Name: get_today_medication_info
# Description:
# - Returns today's medication summary scoped to patient or linked guardian access.
# Parameters:
# - patient_hash: Patient ownership key used to scope summary lookup.
# - user_hash: Requesting user hash. Used for guardian role resolution.
# - role: Requesting user role such as patient or guardian.
# - check_today_medication_info: CheckTodayMedicationInfo injected by FastAPI.
# Returns:
# - API-compatible today medication summary dictionary.
@router.get("/schedule/today/info")
def get_today_medication_info(
    patient_hash: str | None = None,
    user_hash: str | None = None,
    role: str = "patient",
    check_today_medication_info: CheckTodayMedicationInfo = Depends(
        get_check_today_medication_info
    ),
) -> dict[str, object]:
    try:
        return check_today_medication_info.request_today_medication_info(
            patient_hash,
            user_hash,
            role,
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.error(
            "Today medication info lookup failed: %s",
            type(exc).__name__,
        )
        raise HTTPException(
            status_code=500,
            detail="오늘의 복약 정보를 불러오지 못했습니다.",
        ) from exc


# Function Name: update_medication_status
# Description:
# - Updates today's medication completion status for one saved medication.
# Parameters:
# - medication_id: Saved medication primary key from route path.
# - request: MedicationStatusUpdate request DTO.
# - patient_hash: Patient ownership key used to scope status update.
# - check_schedule: CheckSchedule injected by FastAPI.
# Returns:
# - API-compatible status update dictionary.
@router.patch("/schedule/{medication_id}/status")
def update_medication_status(
    medication_id: int,
    request: MedicationStatusUpdate,
    patient_hash: str | None = None,
    user_hash: str | None = None,
    role: str = "patient",
    check_schedule: CheckSchedule = Depends(get_check_schedule),
) -> dict[str, object]:
    return check_schedule.update_medication_status(
        medication_id,
        request.medication_status,
        patient_hash,
        user_hash,
        role,
        request.slot_key,
    )


# Function Name: get_medication_alarms
# Description:
# - Returns all medication alarm settings scoped to patient or linked guardian access.
# Parameters:
# - patient_hash: Patient ownership key used to scope alarm setting lookup.
# - user_hash: Requesting user hash. Used for guardian role resolution.
# - role: Requesting user role such as patient or guardian.
# - set_notification: SetNotification injected by FastAPI.
# Returns:
# - API-compatible medication alarm list dictionary.
@router.get("/notification/settings")
def get_medication_alarms(
    patient_hash: str | None = None,
    user_hash: str | None = None,
    role: str = "patient",
    set_notification: SetNotification = Depends(get_set_notification),
) -> dict[str, object]:
    return set_notification.request_medication_alarm(
        patient_hash,
        user_hash,
        role,
    )


# Function Name: get_medication_alarm
# Description:
# - Returns one medication alarm status for a schedule slot.
# Parameters:
# - slot_key: Medication schedule time slot from the route path.
# - patient_hash: Patient ownership key used to scope alarm setting lookup.
# - user_hash: Requesting user hash. Used for guardian role resolution.
# - role: Requesting user role such as patient or guardian.
# - set_notification: SetNotification injected by FastAPI.
# Returns:
# - API-compatible medication alarm dictionary.
@router.get("/notification/settings/{slot_key}")
def get_medication_alarm(
    slot_key: str,
    patient_hash: str | None = None,
    user_hash: str | None = None,
    role: str = "patient",
    set_notification: SetNotification = Depends(get_set_notification),
) -> dict[str, object]:
    return set_notification.get_alarm_status(
        patient_hash,
        slot_key,
        user_hash,
        role,
    )


# Function Name: save_medication_alarm
# Description:
# - Enables or updates one medication alarm setting for a schedule slot.
# Parameters:
# - slot_key: Medication schedule time slot from the route path.
# - request: MedicationAlarmUpdate request DTO.
# - patient_hash: Patient ownership key used to scope alarm setting update.
# - user_hash: Requesting user hash. Used for guardian role resolution.
# - role: Requesting user role such as patient or guardian.
# - set_notification: SetNotification injected by FastAPI.
# Returns:
# - API-compatible medication alarm dictionary.
@router.put("/notification/settings/{slot_key}")
def save_medication_alarm(
    slot_key: str,
    request: MedicationAlarmUpdate,
    patient_hash: str | None = None,
    user_hash: str | None = None,
    role: str = "patient",
    set_notification: SetNotification = Depends(get_set_notification),
) -> dict[str, object]:
    return set_notification.set_medication_alarm(
        patient_hash,
        slot_key,
        request.hour,
        request.minute,
        user_hash,
        role,
    )


# Function Name: disable_medication_alarm
# Description:
# - Disables one medication alarm setting for a schedule slot.
# Parameters:
# - slot_key: Medication schedule time slot from the route path.
# - patient_hash: Patient ownership key used to scope alarm setting update.
# - user_hash: Requesting user hash. Used for guardian role resolution.
# - role: Requesting user role such as patient or guardian.
# - set_notification: SetNotification injected by FastAPI.
# Returns:
# - API-compatible medication alarm dictionary.
@router.patch("/notification/settings/{slot_key}/disable")
def disable_medication_alarm(
    slot_key: str,
    patient_hash: str | None = None,
    user_hash: str | None = None,
    role: str = "patient",
    set_notification: SetNotification = Depends(get_set_notification),
) -> dict[str, object]:
    return set_notification.disable_alarm_setting(
        patient_hash,
        slot_key,
        user_hash,
        role,
    )


# Function Name: get_user_setting
# Description:
# - Returns user display and reading settings.
# Parameters:
# - user_hash: User ownership key used to scope settings.
# - manage_user_setting: ManageUserSetting injected by FastAPI.
# Returns:
# - API-compatible user setting dictionary.
@router.get("/settings/user")
def get_user_setting(
    user_hash: str = DEFAULT_PATIENT_HASH,
    manage_user_setting: ManageUserSetting = Depends(get_manage_user_setting),
) -> dict[str, object]:
    return manage_user_setting.request_user_setting(user_hash)


# Function Name: save_user_setting
# Description:
# - Saves user display and reading settings.
# Parameters:
# - request: UserSettingUpdate request DTO.
# - user_hash: User ownership key used to scope settings.
# - manage_user_setting: ManageUserSetting injected by FastAPI.
# Returns:
# - API-compatible user setting dictionary.
@router.put("/settings/user")
def save_user_setting(
    request: UserSettingUpdate,
    user_hash: str = DEFAULT_PATIENT_HASH,
    manage_user_setting: ManageUserSetting = Depends(get_manage_user_setting),
) -> dict[str, object]:
    return manage_user_setting.save_user_setting(
        user_hash,
        request.font_size,
        request.reading_speed,
        request.language,
    )


# Function Name: request_voice_guide
# Description:
# - Builds voice guide text from medication detail information.
# Parameters:
# - request: VoiceGuideRequest containing medication guide source data.
# - request_voice_guide_control: RequestVoiceGuide injected by FastAPI.
# Returns:
# - API-compatible voice guide dictionary.
@router.post("/voice-guide")
def request_voice_guide(
    request: VoiceGuideRequest,
    request_voice_guide_control: RequestVoiceGuide = Depends(get_request_voice_guide),
) -> dict[str, object]:
    return request_voice_guide_control.request_voice_guide(
        request.to_medication_detail(),
        request.language,
    )


# 함수명: get_health_recommendation
# 함수역할:
# - 현재 복용 중인 약 조합을 바탕으로 AI 건강 관리 추천을 반환한다.
# 매개변수:
# - patient_hash: 추천 조회 범위를 구분하는 환자 해시
# - user_hash: 보호자 요청자의 사용자 해시
# - role: 요청자 역할
# - request_health_recommendation: CheckHealthRecommendation injected by FastAPI.
# 반환값:
# - API-compatible health recommendation dictionary.
@router.get("/health/recommendation")
async def get_health_recommendation(
    patient_hash: str | None = None,
    user_hash: str | None = None,
    role: str = "patient",
    language: str = "ko",
    request_health_recommendation: CheckHealthRecommendation = Depends(
        get_request_health_recommendation
    ),
) -> dict[str, object]:
    try:
        return await request_health_recommendation.request_health_recommendation(
            patient_hash,
            user_hash,
            role,
            language,
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Health recommendation failed: %s", type(exc).__name__)
        raise HTTPException(
            status_code=500,
            detail="건강 관리 추천을 생성하지 못했습니다.",
        ) from exc


# Function Name: get_guardian_alert_setting
# Description:
# - Returns the guardian alert setting for one linked guardian-patient pair.
# Parameters:
# - patient_hash: Patient ownership key monitored by the guardian.
# - guardian_hash: Guardian ownership key requesting alert state.
# - set_guardian_alert_setting: SetGuardianAlertSetting injected by FastAPI.
# Returns:
# - API-compatible guardian alert setting dictionary.
@router.get("/guardian-alert/settings/{patient_hash}")
def get_guardian_alert_setting(
    patient_hash: str,
    guardian_hash: str,
    set_guardian_alert_setting: SetGuardianAlertSetting = Depends(
        get_set_guardian_alert_setting
    ),
) -> dict[str, object]:
    return set_guardian_alert_setting.request_guardian_alert_setting(
        guardian_hash,
        patient_hash,
    )


# Function Name: update_guardian_alert_setting
# Description:
# - Updates guardian alert enable/disable state for one linked pair.
# Parameters:
# - patient_hash: Patient ownership key monitored by the guardian.
# - guardian_hash: Guardian ownership key requesting alert state update.
# - request: GuardianAlertUpdate request DTO.
# - set_guardian_alert_setting: SetGuardianAlertSetting injected by FastAPI.
# Returns:
# - API-compatible guardian alert setting dictionary.
@router.put("/guardian-alert/settings/{patient_hash}")
def update_guardian_alert_setting(
    patient_hash: str,
    guardian_hash: str,
    request: GuardianAlertUpdate,
    set_guardian_alert_setting: SetGuardianAlertSetting = Depends(
        get_set_guardian_alert_setting
    ),
) -> dict[str, object]:
    return set_guardian_alert_setting.update_guardian_alert_setting(
        guardian_hash,
        patient_hash,
        request.is_enabled,
        request.alert_option,
    )


# Function Name: get_guardian_medication
# Description:
# - Returns saved medications and today's summary for one linked guardian-patient pair.
# Parameters:
# - patient_hash: Patient ownership key monitored by the guardian.
# - guardian_hash: Guardian ownership key requesting medication data.
# - set_guardian_medication: SetGuardianMedication injected by FastAPI.
# Returns:
# - API-compatible guardian medication dictionary.
@router.get("/guardian/medications/{patient_hash}")
def get_guardian_medication(
    patient_hash: str,
    guardian_hash: str,
    set_guardian_medication: SetGuardianMedication = Depends(
        get_set_guardian_medication
    ),
) -> dict[str, object]:
    return set_guardian_medication.request_guardian_medication(
        guardian_hash,
        patient_hash,
    )


# Function Name: get_patient_guardian_links
# Description:
# - Returns active patient-guardian links for a patient or guardian hash.
# Parameters:
# - user_hash: Patient or guardian ownership key.
# - patient_guardian_link_control: PatientGuardianLinkControl injected by FastAPI.
# Returns:
# - API-compatible link list dictionary.
@router.get("/link/list")
def get_patient_guardian_links(
    user_hash: str = DEFAULT_PATIENT_HASH,
    patient_guardian_link_control: PatientGuardianLinkControl = Depends(
        get_patient_guardian_link_control
    ),
) -> dict[str, object]:
    return patient_guardian_link_control.request_link_page(user_hash)


# Function Name: create_patient_link_code
# Description:
# - Creates a temporary patient code for UC-6 guardian registration.
# Parameters:
# - request: PatientCodeCreate request DTO.
# - patient_guardian_link_control: PatientGuardianLinkControl injected by FastAPI.
# Returns:
# - API-compatible patient code dictionary.
@router.post("/link/code")
def create_patient_link_code(
    request: PatientCodeCreate,
    patient_guardian_link_control: PatientGuardianLinkControl = Depends(
        get_patient_guardian_link_control
    ),
) -> dict[str, object]:
    return patient_guardian_link_control.request_patient_code(request.patient_hash)


# Function Name: register_patient_link_code
# Description:
# - Registers a guardian with a valid temporary patient code.
# Parameters:
# - request: PatientCodeRegister request DTO.
# - patient_guardian_link_control: PatientGuardianLinkControl injected by FastAPI.
# Returns:
# - API-compatible link dictionary.
@router.post("/link/register")
def register_patient_link_code(
    request: PatientCodeRegister,
    patient_guardian_link_control: PatientGuardianLinkControl = Depends(
        get_patient_guardian_link_control
    ),
) -> dict[str, object]:
    return patient_guardian_link_control.register_patient_code(
        request.guardian_hash,
        request.patient_code,
    )


# Function Name: unlink_patient_guardian
# Description:
# - Removes one active patient-guardian link for a participating user hash.
# Parameters:
# - link_id: Patient-guardian link primary key from route path.
# - user_hash: Patient or guardian ownership key allowed to unlink.
# - patient_guardian_link_control: PatientGuardianLinkControl injected by FastAPI.
# Returns:
# - API-compatible unlink dictionary.
@router.delete("/link/{link_id}")
def unlink_patient_guardian(
    link_id: int,
    user_hash: str = DEFAULT_PATIENT_HASH,
    patient_guardian_link_control: PatientGuardianLinkControl = Depends(
        get_patient_guardian_link_control
    ),
) -> dict[str, object]:
    return patient_guardian_link_control.request_unlink(link_id, user_hash)


# Function Name: delete_medication
# Description:
# - Deletes a saved medication by id.
# Parameters:
# - drug_id: Saved medication primary key from route path.
# - patient_hash: Patient ownership key used to scope deletion.
# - check_saved_medication: CheckSavedMedication injected by FastAPI.
# Returns:
# - API-compatible delete success dictionary.
@router.delete("/delete/{drug_id}")
def delete_medication(
    drug_id: int,
    patient_hash: str = DEFAULT_PATIENT_HASH,
    check_saved_medication: CheckSavedMedication = Depends(get_check_saved_medication),
) -> dict[str, object]:
    return check_saved_medication.request_delete(drug_id, patient_hash)


# Function Name: parse_prescription_endpoint
# Description:
# - Parses OCR text into a structured prescription dictionary.
# Parameters:
# - request: OCRParseRequest containing raw OCR text.
# Returns:
# - API-compatible parse result dictionary.
@router.post("/parse-prescription")
def parse_prescription_endpoint(
    request: OCRParseRequest,
) -> dict[str, object]:
    if not request.text:
        raise HTTPException(status_code=400, detail="OCR 텍스트가 없습니다.")

    try:
        parsed_data = parse_prescription(request.text.splitlines())
        return {
            "success": True,
            "message": "처방전 파싱 성공",
            "parsed": parsed_data,
        }
    except Exception as exc:
        logger.error(
            "Legacy prescription parsing failed: %s",
            type(exc).__name__,
        )
        raise HTTPException(
            status_code=500,
            detail="처방전 텍스트를 파싱하지 못했습니다.",
        ) from exc


# Function Name: upload_and_parse_prescription
# Description:
# - Receives a prescription image and returns structured medication candidates.
# Parameters:
# - file: Uploaded image file.
# - prescription_analysis_control: PrescriptionAnalysisControl injected by FastAPI.
# Returns:
# - API-compatible prescription analysis dictionary.
@router.post("/upload-prescription")
async def upload_and_parse_prescription(
    file: UploadFile = File(...),
    prescription_analysis_control: PrescriptionAnalysisControl = Depends(
        get_prescription_analysis_control
    ),
) -> dict[str, object]:
    try:
        image_bytes = await file.read(MAX_PRESCRIPTION_IMAGE_BYTES + 1)
        logger.info(
            "Prescription image upload received: content_type=%s, bytes=%d",
            file.content_type,
            len(image_bytes),
        )
        return await prescription_analysis_control.request_prescription_image(
            image_bytes
        )
    except ValueError as exc:
        logger.warning("Prescription image upload rejected: %s", exc)
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        logger.error(
            "Prescription image parsing failed: %s",
            type(exc).__name__,
        )
        raise HTTPException(
            status_code=500,
            detail="데이터 추출 중 서버 오류가 발생했습니다.",
        ) from exc
