# File Name: router.py
# Role: Defines medication-related HTTP endpoints for the MedBuddy backend.

import asyncio
import logging

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel

from api.dependencies import (
    get_check_medication_detail,
    get_check_schedule,
    get_check_saved_medication,
    get_check_today_medication_info,
    get_check_caregiver_medication,
    get_manage_user_setting,
    get_identify_pill,
    get_link_patient_caregiver_control,
    get_input_prescription,
    get_check_health_recommendation,
    get_request_voice_guide,
    get_set_caregiver_notification,
    get_set_notification,
)
from boundaries.pill_identification_boundary import (
    MAX_PILL_IMAGE_BYTES,
    PillCatalogUnavailableError,
    PillImageQualityError,
    PillVisionResponseError,
    PillVisionUnavailableError,
)
from controls.check_medication_detail_control import CheckMedicationDetail
from controls.check_schedule_control import CheckSchedule
from controls.check_saved_medication_control import CheckSavedMedication
from controls.check_today_medication_info_control import CheckTodayMedicationInfo
from controls.check_caregiver_medication_control import CheckCaregiverMedication
from controls.input_prescription_control import (
    MAX_PRESCRIPTION_IMAGE_BYTES,
    InputPrescription,
    PrescriptionAnalysisTimeoutError,
)
from controls.identify_pill_control import IdentifyPill
from controls.manage_user_setting_control import ManageUserSetting
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.check_health_recommendation_control import CheckHealthRecommendation
from controls.request_voice_guide_control import RequestVoiceGuide
from controls.set_caregiver_notification_control import SetCaregiverNotification
from controls.set_notification_control import SetNotification
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH
from schemas.medication import (
    MedicationRequest,
    MedicationResponse,
    MedicationStatusUpdate,
    MedicationAlarmUpdate,
    CaregiverNotificationUpdate,
    PatientCodeCreate,
    PatientCodeRegister,
    SavedMedicationCreate,
    UserSettingUpdate,
    VoiceGuideRequest,
)
from schemas.pill_identification import PillIdentificationResponse

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
        return await check_medication_detail.requestMedicationDetail(
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
    return check_saved_medication.saveMedicationDetail(medication)


# Function Name: get_saved_medications
# Description:
# - Returns saved medication rows owned by one patient.
# Parameters:
# - patient_hash: Patient ownership key used to scope saved medication lookup.
# - check_saved_medication: CheckSavedMedication injected by FastAPI.
# Returns:
# - API-compatible list dictionary.
@router.get("/list")
async def get_saved_medications(
    patient_hash: str | None = None,
    check_saved_medication: CheckSavedMedication = Depends(get_check_saved_medication),
) -> dict[str, object]:
    try:
        return await check_saved_medication.requestSavedMedicationInfoWithImages(
            patient_hash,
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
# - Returns today's active medication schedule for one patient.
# Parameters:
# - patient_hash: Patient ownership key used to scope schedule lookup.
# - check_schedule: CheckSchedule injected by FastAPI.
# Returns:
# - API-compatible schedule list dictionary.
@router.get("/schedule/today")
def get_today_medication_schedule(
    patient_hash: str | None = None,
    check_schedule: CheckSchedule = Depends(get_check_schedule),
) -> dict[str, object]:
    try:
        return check_schedule.requestTodayMedicationSchedule(patient_hash)
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
# - Returns today's medication summary for one patient.
# Parameters:
# - patient_hash: Patient ownership key used to scope summary lookup.
# - check_today_medication_info: CheckTodayMedicationInfo injected by FastAPI.
# Returns:
# - API-compatible today medication summary dictionary.
@router.get("/schedule/today/info")
def get_today_medication_info(
    patient_hash: str | None = None,
    check_today_medication_info: CheckTodayMedicationInfo = Depends(
        get_check_today_medication_info
    ),
) -> dict[str, object]:
    try:
        return check_today_medication_info.requestTodayMedicationInfo(patient_hash)
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
    check_schedule: CheckSchedule = Depends(get_check_schedule),
) -> dict[str, object]:
    return check_schedule.updateMedicationStatus(
        medication_id,
        request.medication_status,
        patient_hash,
        request.slot_key,
    )


# Function Name: get_medication_alarms
# Description:
# - Returns all medication alarm settings for one patient.
# Parameters:
# - patient_hash: Patient ownership key used to scope alarm setting lookup.
# - set_notification: SetNotification injected by FastAPI.
# Returns:
# - API-compatible medication alarm list dictionary.
@router.get("/notification/settings")
def get_medication_alarms(
    patient_hash: str | None = None,
    set_notification: SetNotification = Depends(get_set_notification),
) -> dict[str, object]:
    return set_notification.requestMedicationAlarm(patient_hash)


# Function Name: get_medication_alarm
# Description:
# - Returns one medication alarm status for a schedule slot.
# Parameters:
# - slot_key: Medication schedule time slot from the route path.
# - patient_hash: Patient ownership key used to scope alarm setting lookup.
# - set_notification: SetNotification injected by FastAPI.
# Returns:
# - API-compatible medication alarm dictionary.
@router.get("/notification/settings/{slot_key}")
def get_medication_alarm(
    slot_key: str,
    patient_hash: str | None = None,
    set_notification: SetNotification = Depends(get_set_notification),
) -> dict[str, object]:
    return set_notification.requestAlarmToggle(patient_hash, slot_key)


# Function Name: save_medication_alarm
# Description:
# - Enables or updates one medication alarm setting for a schedule slot.
# Parameters:
# - slot_key: Medication schedule time slot from the route path.
# - request: MedicationAlarmUpdate request DTO.
# - patient_hash: Patient ownership key used to scope alarm setting update.
# - set_notification: SetNotification injected by FastAPI.
# Returns:
# - API-compatible medication alarm dictionary.
@router.put("/notification/settings/{slot_key}")
def save_medication_alarm(
    slot_key: str,
    request: MedicationAlarmUpdate,
    patient_hash: str | None = None,
    set_notification: SetNotification = Depends(get_set_notification),
) -> dict[str, object]:
    return set_notification.saveNotificationSetting(
        patient_hash,
        slot_key,
        request.hour,
        request.minute,
    )


# Function Name: disable_medication_alarm
# Description:
# - Disables one medication alarm setting for a schedule slot.
# Parameters:
# - slot_key: Medication schedule time slot from the route path.
# - patient_hash: Patient ownership key used to scope alarm setting update.
# - set_notification: SetNotification injected by FastAPI.
# Returns:
# - API-compatible medication alarm dictionary.
@router.patch("/notification/settings/{slot_key}/disable")
def disable_medication_alarm(
    slot_key: str,
    patient_hash: str | None = None,
    set_notification: SetNotification = Depends(get_set_notification),
) -> dict[str, object]:
    return set_notification.disableAlarmSetting(patient_hash, slot_key)


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
    return manage_user_setting.requestUserSetting(user_hash)


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
    return manage_user_setting.saveUserSetting(
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
    return request_voice_guide_control.requestVoiceGuide(
        request.to_medication_detail(),
        request.language,
    )


# 함수명: get_health_recommendation
# 함수역할:
# - 현재 복용 중인 약 조합을 바탕으로 AI 건강 관리 추천을 반환한다.
# 매개변수:
# - patient_hash: 추천 조회 범위를 구분하는 환자 해시
# - language: 추천 응답 언어
# - check_health_recommendation: CheckHealthRecommendation injected by FastAPI.
# 반환값:
# - API-compatible health recommendation dictionary.
@router.get("/health/recommendation")
async def get_health_recommendation(
    patient_hash: str | None = None,
    language: str = "ko",
    check_health_recommendation: CheckHealthRecommendation = Depends(
        get_check_health_recommendation
    ),
) -> dict[str, object]:
    try:
        return await check_health_recommendation.requestHealthRecommendation(
            patient_hash,
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


# Function Name: get_caregiver_notification_setting
# Description:
# - Returns the notification setting for one linked caregiver-patient pair.
# Parameters:
# - patient_hash: Patient ownership key monitored by the caregiver.
# - caregiver_hash: Caregiver ownership key requesting notification state.
# - legacy_guardian_hash: Backward-compatible alias for older clients.
# - set_caregiver_notification: SetCaregiverNotification injected by FastAPI.
# Returns:
# - API-compatible caregiver notification setting dictionary.
@router.get("/caregiver-notification/settings/{patient_hash}")
@router.get(
    "/guardian-alert/settings/{patient_hash}",
    include_in_schema=False,
)
def get_caregiver_notification_setting(
    patient_hash: str,
    caregiver_hash: str | None = None,
    guardian_hash: str | None = None,
    set_caregiver_notification: SetCaregiverNotification = Depends(
        get_set_caregiver_notification
    ),
) -> dict[str, object]:
    requesting_caregiver_hash = caregiver_hash or guardian_hash
    if not requesting_caregiver_hash:
        raise HTTPException(status_code=400, detail="Caregiver hash is required.")
    return set_caregiver_notification.requestCaregiverNotificationSetting(
        requesting_caregiver_hash,
        patient_hash,
    )


# Function Name: save_caregiver_notification_setting
# Description:
# - Saves caregiver notification state for one linked pair.
# Parameters:
# - patient_hash: Patient ownership key monitored by the caregiver.
# - caregiver_hash: Caregiver ownership key requesting the update.
# - legacy_guardian_hash: Backward-compatible alias for older clients.
# - request: CaregiverNotificationUpdate request DTO.
# - set_caregiver_notification: SetCaregiverNotification injected by FastAPI.
# Returns:
# - API-compatible caregiver notification setting dictionary.
@router.put("/caregiver-notification/settings/{patient_hash}")
@router.put(
    "/guardian-alert/settings/{patient_hash}",
    include_in_schema=False,
)
def save_caregiver_notification_setting(
    patient_hash: str,
    request: CaregiverNotificationUpdate,
    caregiver_hash: str | None = None,
    guardian_hash: str | None = None,
    set_caregiver_notification: SetCaregiverNotification = Depends(
        get_set_caregiver_notification
    ),
) -> dict[str, object]:
    requesting_caregiver_hash = caregiver_hash or guardian_hash
    if not requesting_caregiver_hash:
        raise HTTPException(status_code=400, detail="Caregiver hash is required.")
    return set_caregiver_notification.saveCaregiverNotificationSetting(
        requesting_caregiver_hash,
        patient_hash,
        request.notification_enabled,
        request.notification_type,
    )


# Function Name: get_patient_caregiver_links
# Description:
# - Returns active patient-caregiver links for a patient or caregiver hash.
# Parameters:
# - user_hash: Patient or caregiver ownership key.
# - link_patient_caregiver_control: LinkPatientCaregiver injected by FastAPI.
# Returns:
# - API-compatible link list dictionary.
@router.get("/link/list")
def get_patient_caregiver_links(
    user_hash: str = DEFAULT_PATIENT_HASH,
    link_patient_caregiver_control: LinkPatientCaregiver = Depends(
        get_link_patient_caregiver_control
    ),
) -> dict[str, object]:
    return link_patient_caregiver_control.requestLinkScreen(user_hash)


# Function Name: get_caregiver_patient_medication_info
# Description:
# - Returns read-only medication information for one explicitly selected linked patient.
@router.get("/caregiver/medications/{patient_hash}")
@router.get(
    "/guardian/medications/{patient_hash}",
    include_in_schema=False,
)
async def get_caregiver_patient_medication_info(
    patient_hash: str,
    caregiver_hash: str | None = None,
    guardian_hash: str | None = None,
    check_caregiver_medication: CheckCaregiverMedication = Depends(
        get_check_caregiver_medication
    ),
) -> dict[str, object]:
    requesting_caregiver_hash = caregiver_hash or guardian_hash
    if not requesting_caregiver_hash:
        raise HTTPException(status_code=400, detail="Caregiver hash is required.")
    return await check_caregiver_medication.requestPatientMedicationInfo(
        requesting_caregiver_hash,
        patient_hash,
    )


# Function Name: create_patient_link_code
# Description:
# - Creates a temporary patient code for UC-6 caregiver registration.
# Parameters:
# - request: PatientCodeCreate request DTO.
# - link_patient_caregiver_control: LinkPatientCaregiver injected by FastAPI.
# Returns:
# - API-compatible patient code dictionary.
@router.post("/link/code")
def create_patient_link_code(
    request: PatientCodeCreate,
    link_patient_caregiver_control: LinkPatientCaregiver = Depends(
        get_link_patient_caregiver_control
    ),
) -> dict[str, object]:
    return link_patient_caregiver_control.generatePatientHash(request.patient_hash)


# Function Name: register_patient_link_code
# Description:
# - Registers a caregiver with a valid temporary patient code.
# Parameters:
# - request: PatientCodeRegister request DTO.
# - link_patient_caregiver_control: LinkPatientCaregiver injected by FastAPI.
# Returns:
# - API-compatible link dictionary.
@router.post("/link/register")
def register_patient_link_code(
    request: PatientCodeRegister,
    link_patient_caregiver_control: LinkPatientCaregiver = Depends(
        get_link_patient_caregiver_control
    ),
) -> dict[str, object]:
    return link_patient_caregiver_control.requestPatientCaregiverLink(
        request.caregiver_hash,
        request.patient_code,
    )


# Function Name: unlink_patient_caregiver
# Description:
# - Removes one active patient-caregiver link for a participating user hash.
# Parameters:
# - link_id: Patient-caregiver link primary key from route path.
# - user_hash: Patient or caregiver ownership key allowed to unlink.
# - link_patient_caregiver_control: LinkPatientCaregiver injected by FastAPI.
# Returns:
# - API-compatible unlink dictionary.
@router.delete("/link/{link_id}")
def unlink_patient_caregiver(
    link_id: int,
    user_hash: str = DEFAULT_PATIENT_HASH,
    link_patient_caregiver_control: LinkPatientCaregiver = Depends(
        get_link_patient_caregiver_control
    ),
) -> dict[str, object]:
    return link_patient_caregiver_control.requestUnlink(
        link_id,
        user_hash,
    )


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
    return check_saved_medication.requestDelete(drug_id, patient_hash)


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
        parsed_data = InputPrescription.parse_prescription_text(
            request.text,
        )
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


# Function Name: identify_loose_pill
# Description:
# - Receives front and optional back photos and returns ranked MFDS candidates.
# Parameters:
# - front: Required front-side pill image.
# - back: Optional reverse-side pill image.
# - identify_pill: IdentifyPill injected by FastAPI.
# Returns:
# - PillIdentificationResponse with mandatory user confirmation.
@router.post(
    "/pill-identification/candidates",
    response_model=PillIdentificationResponse,
)
async def identify_loose_pill(
    front: UploadFile = File(...),
    back: UploadFile | None = File(None),
    identify_pill: IdentifyPill = Depends(get_identify_pill),
) -> PillIdentificationResponse:
    """Returns MFDS candidates for one pill; user confirmation remains mandatory."""

    async def read_bounded(upload: UploadFile) -> bytes:
        content = await upload.read(MAX_PILL_IMAGE_BYTES + 1)
        if len(content) > MAX_PILL_IMAGE_BYTES:
            raise HTTPException(
                status_code=413,
                detail="Each pill image must be 10 MB or smaller.",
            )
        return content

    try:
        uploads = [read_bounded(front)]
        if back is not None:
            uploads.append(read_bounded(back))
        images = await asyncio.gather(*uploads)
        result = await identify_pill.requestPillIdentification(
            images[0],
            images[1] if len(images) > 1 else None,
        )
        return PillIdentificationResponse.from_domain(result)
    except HTTPException:
        raise
    except PillImageQualityError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except PillCatalogUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except PillVisionUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except PillVisionResponseError as exc:
        raise HTTPException(
            status_code=502,
            detail="The pill visual-analysis service returned an invalid response.",
        ) from exc
    except TimeoutError as exc:
        raise HTTPException(
            status_code=504,
            detail="Pill identification timed out. Please try again.",
        ) from exc
    except Exception as exc:
        logger.error(
            "Loose-pill identification failed: %s",
            type(exc).__name__,
        )
        raise HTTPException(
            status_code=500,
            detail="The pill could not be identified due to a server error.",
        ) from exc


# Function Name: upload_and_parse_prescription
# Description:
# - Receives a prescription image and returns structured medication candidates.
# Parameters:
# - file: Uploaded image file.
# - input_prescription: InputPrescription injected by FastAPI.
# Returns:
# - API-compatible prescription analysis dictionary.
@router.post("/upload-prescription")
async def upload_and_parse_prescription(
    file: UploadFile = File(...),
    input_prescription: InputPrescription = Depends(
        get_input_prescription
    ),
) -> dict[str, object]:
    try:
        image_bytes = await file.read(MAX_PRESCRIPTION_IMAGE_BYTES + 1)
        logger.info(
            "Prescription image upload received: content_type=%s, bytes=%d",
            file.content_type,
            len(image_bytes),
        )
        return await input_prescription.requestPrescriptionImage(
            image_bytes
        )
    except PrescriptionAnalysisTimeoutError as exc:
        logger.warning("Prescription OCR request timed out.")
        raise HTTPException(status_code=504, detail=str(exc)) from exc
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
