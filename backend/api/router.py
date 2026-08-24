# File Name: router.py
# Role: Defines medication-related HTTP endpoints for the MedBuddy backend.

import asyncio
import logging

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    HTTPException,
    Query,
    UploadFile,
)
from pydantic import BaseModel, Field

from api.dependencies import (
    get_authenticated_principal,
    get_recently_authenticated_principal,
    verify_app_check_token,
    get_registered_principal,
    get_authorization_control,
    get_check_medication_detail,
    get_check_prescription_change,
    get_check_schedule,
    get_check_saved_medication,
    get_check_today_medication_info,
    get_check_caregiver_medication,
    get_manage_user_setting,
    get_manage_account,
    get_manage_push_token,
    get_identify_pill,
    get_link_patient_caregiver_control,
    get_input_prescription,
    get_check_health_recommendation,
    get_request_voice_guide,
    get_set_caregiver_notification,
    get_set_notification,
    get_push_notification_boundary,
)
from boundaries.firebase_identity_boundary import (
    IdentityDeletionUnavailableError,
)
from boundaries.pill_identification_boundary import (
    MAX_PILL_IMAGE_BYTES,
    PillCatalogUnavailableError,
    PillImageQualityError,
    PillVisionResponseError,
    PillVisionUnavailableError,
)
from controls.check_medication_detail_control import CheckMedicationDetail
from controls.check_prescription_change_control import CheckPrescriptionChange
from controls.authorization_control import AuthorizationControl
from controls.check_schedule_control import CheckSchedule
from controls.check_saved_medication_control import CheckSavedMedication
from controls.check_today_medication_info_control import CheckTodayMedicationInfo
from controls.check_caregiver_medication_control import CheckCaregiverMedication
from controls.input_prescription_control import (
    InputPrescription,
    PrescriptionAnalysisTimeoutError,
)
from controls.identify_pill_control import IdentifyPill
from controls.manage_user_setting_control import ManageUserSetting
from controls.manage_account_control import ManageAccount
from controls.manage_push_token_control import ManagePushToken
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.check_health_recommendation_control import CheckHealthRecommendation
from controls.process_caregiver_alert_outbox_control import (
    ProcessCaregiverAlertOutbox,
)
from controls.request_voice_guide_control import RequestVoiceGuide
from controls.set_caregiver_notification_control import SetCaregiverNotification
from controls.set_notification_control import SetNotification
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from core.database import SessionLocal
from schemas.medication import (
    MedicationRequest,
    MedicationResponse,
    PrescriptionAnalysisResponse,
    MedicationStatusUpdate,
    MedicationAlarmUpdate,
    CaregiverNotificationUpdate,
    PatientCodeCreate,
    PatientCodeRegister,
    PushTokenRegistration,
    SavedMedicationCreate,
    UserSettingUpdate,
    VoiceGuideRequest,
)
from schemas.pill_identification import PillIdentificationResponse
from schemas.prescription_change import (
    PrescriptionChangeRequest,
    PrescriptionChangeResponse,
)

_authenticated_app_dependencies = [
    Depends(verify_app_check_token),
    Depends(get_registered_principal),
]
router = APIRouter(dependencies=_authenticated_app_dependencies)
auth_router = APIRouter(
    prefix="/api/v1/auth",
    tags=["Authentication"],
    dependencies=_authenticated_app_dependencies,
)
logger = logging.getLogger(__name__)


# 클래스명: OCRParseRequest
# 역할:
# - 기기에서 개인정보를 제거한 처방전 OCR 텍스트를 전달받는다.
# 속성:
# - text: 프론트엔드에서 정제한 비식별 OCR 텍스트
class OCRParseRequest(BaseModel):
    text: str = Field(min_length=1, max_length=100_000)


@auth_router.get("/session")
def get_auth_session(
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
) -> dict[str, object]:
    return {
        "authenticated": not principal.authentication_disabled,
        "user_hash": principal.user_hash,
        "email": principal.email,
        "email_verified": principal.email_verified,
        "phone_number": principal.phone_number,
        "sign_in_provider": principal.sign_in_provider,
        "anonymous": principal.anonymous,
    }


# 함수명: export_account_data
# 역할:
# - 현재 로그인 사용자의 MedBuddy 저장 데이터를 JSON으로 반환한다.
@auth_router.get("/account-data")
def export_account_data(
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    manage_account: ManageAccount = Depends(get_manage_account),
) -> dict[str, object]:
    return manage_account.exportAccountData(principal.user_hash)


# 함수명: delete_account_data
# 역할:
# - 현재 로그인 사용자의 복약정보, 연결, 알림, 캐시를 모두 삭제한다.
@auth_router.delete("/account-data")
def delete_account_data(
    principal: AuthenticatedPrincipal = Depends(
        get_recently_authenticated_principal
    ),
    manage_account: ManageAccount = Depends(get_manage_account),
) -> dict[str, object]:
    try:
        return manage_account.deleteAccountData(
            principal.user_hash,
            external_subject=(
                None if principal.authentication_disabled else principal.subject
            ),
        )
    except IdentityDeletionUnavailableError as exc:
        raise HTTPException(
            status_code=503,
            detail="Account identity deletion is temporarily unavailable.",
            headers={"Retry-After": "5"},
        ) from exc


# 함수명: register_push_token
# 역할:
# - 현재 인증 사용자의 FCM 기기 토큰을 등록하거나 갱신한다.
# 반환값:
# - 토큰 등록 결과
@auth_router.post("/push-token")
def register_push_token(
    request: PushTokenRegistration,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    manage_push_token: ManagePushToken = Depends(get_manage_push_token),
) -> dict[str, object]:
    return manage_push_token.registerPushToken(
        principal.user_hash,
        request.token,
        request.platform,
    )


# 함수명: unregister_push_token
# 역할:
# - 로그아웃하는 현재 기기의 FCM 토큰을 비활성화한다.
# 반환값:
# - 토큰 해제 결과
@auth_router.delete("/push-token")
def unregister_push_token(
    request: PushTokenRegistration,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    manage_push_token: ManagePushToken = Depends(get_manage_push_token),
) -> dict[str, object]:
    return manage_push_token.unregisterPushToken(
        principal.user_hash,
        request.token,
    )


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


# 함수이름: check_prescription_change
# 함수역할:
# - 현재 분석한 처방과 환자의 가장 최근 이전 처방을 비교한다.
# - 의료 판단 없이 약품 구성과 복약 일정 필드의 객관적 차이만 반환한다.
# 매개변수:
# - request: 현재 처방 조제일자와 약품 목록
# - check_prescription_change_control: 처방 변화 비교 Control
# 반환값:
# - 처방 변화 요약과 약품별 변화 목록
@router.post(
    "/prescription/change-radar",
    response_model=PrescriptionChangeResponse,
)
def check_prescription_change(
    request: PrescriptionChangeRequest,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    check_prescription_change_control: CheckPrescriptionChange = Depends(
        get_check_prescription_change
    ),
) -> PrescriptionChangeResponse:
    try:
        authorized_patient_hash = authorization.resolvePatientScope(
            principal,
            request.patient_hash,
        )
        return check_prescription_change_control.request_prescription_change(
            request.model_copy(update={"patient_hash": authorized_patient_hash})
        )
    except HTTPException:
        raise
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        logger.error(
            "Prescription change comparison failed: %s",
            type(exc).__name__,
        )
        raise HTTPException(
            status_code=500,
            detail="처방 변화를 비교하지 못했습니다.",
        ) from exc


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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    check_saved_medication: CheckSavedMedication = Depends(get_check_saved_medication),
) -> dict[str, object]:
    patient_hash = authorization.resolvePatientScope(
        principal,
        medication.patient_hash,
    )
    trusted_medication = medication.model_copy(
        update={"patient_hash": patient_hash},
    )
    return check_saved_medication.saveMedicationDetail(trusted_medication)


# Function Name: get_saved_medications
# Description:
# - Returns saved medication rows owned by one patient.
# Parameters:
# - patient_hash: Patient ownership key used to scope saved medication lookup.
# - check_saved_medication: CheckSavedMedication injected by FastAPI.
# Returns:
# - API-compatible list dictionary.
@router.get("/list")
def get_saved_medications(
    patient_hash: str | None = None,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    check_saved_medication: CheckSavedMedication = Depends(get_check_saved_medication),
) -> dict[str, object]:
    try:
        authorized_patient_hash = authorization.resolvePatientScope(
            principal,
            patient_hash,
            allow_caregiver=True,
        )
        return check_saved_medication.requestSavedMedicationInfo(
            authorized_patient_hash
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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    check_schedule: CheckSchedule = Depends(get_check_schedule),
) -> dict[str, object]:
    try:
        authorized_patient_hash = authorization.resolvePatientScope(
            principal,
            patient_hash,
            allow_caregiver=True,
        )
        return check_schedule.requestTodayMedicationSchedule(authorized_patient_hash)
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


# Function Name: get_medication_schedule_window
# Description:
# - Returns medication courses overlapping a bounded rolling reminder window.
# Parameters:
# - patient_hash: Patient ownership key used to scope schedule lookup.
# - days: Inclusive number of days beginning today, capped at 14.
# Returns:
# - API-compatible schedule list dictionary.
@router.get("/schedule/window")
def get_medication_schedule_window(
    patient_hash: str | None = None,
    days: int = Query(default=14, ge=1, le=14),
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    check_schedule: CheckSchedule = Depends(get_check_schedule),
) -> dict[str, object]:
    try:
        authorized_patient_hash = authorization.resolvePatientScope(
            principal,
            patient_hash,
            allow_caregiver=True,
        )
        return check_schedule.requestMedicationScheduleWindow(
            authorized_patient_hash,
            days,
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.error(
            "Medication schedule window lookup failed: %s",
            type(exc).__name__,
        )
        raise HTTPException(
            status_code=500,
            detail="복약 알림 일정을 불러오지 못했습니다.",
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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    check_today_medication_info: CheckTodayMedicationInfo = Depends(
        get_check_today_medication_info
    ),
) -> dict[str, object]:
    try:
        authorized_patient_hash = authorization.resolvePatientScope(
            principal,
            patient_hash,
            allow_caregiver=True,
        )
        return check_today_medication_info.requestTodayMedicationInfo(
            authorized_patient_hash
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


# 함수명: _process_caregiver_completion_alert
# 역할:
# - 복약 체크와 함께 저장된 아웃박스 요청을 별도 DB 세션에서 즉시 처리한다.
# - 실패한 요청은 아웃박스 작업자가 다시 처리하므로 여기서는 예외를 격리한다.
def _process_caregiver_completion_alert(
    outbox_id: int,
) -> None:
    db = SessionLocal()
    try:
        ProcessCaregiverAlertOutbox(
            db=db,
            push_boundary=get_push_notification_boundary(),
        ).processOne(outbox_id)
    except Exception as exc:
        logger.warning(
            "Caregiver push background dispatch failed: %s",
            type(exc).__name__,
        )
    finally:
        db.close()


# 함수명: update_medication_status
# 역할:
# - 오늘의 복약 완료 상태를 저장하고 보호자 알림은 응답 이후 작업으로 예약한다.
@router.patch("/schedule/{medication_id}/status")
def update_medication_status(
    medication_id: int,
    request: MedicationStatusUpdate,
    background_tasks: BackgroundTasks,
    patient_hash: str | None = None,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    check_schedule: CheckSchedule = Depends(get_check_schedule),
) -> dict[str, object]:
    authorized_patient_hash = authorization.resolvePatientScope(
        principal,
        patient_hash,
    )
    response = check_schedule.updateMedicationStatus(
        medication_id,
        request.medication_status,
        authorized_patient_hash,
        request.slot_key,
    )
    for completion_event in check_schedule.consumeCompletionEvents():
        background_tasks.add_task(
            _process_caregiver_completion_alert,
            int(completion_event["outbox_id"]),
        )
    return response


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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    set_notification: SetNotification = Depends(get_set_notification),
) -> dict[str, object]:
    authorized_patient_hash = authorization.resolvePatientScope(
        principal,
        patient_hash,
    )
    return set_notification.requestMedicationAlarm(authorized_patient_hash)


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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    set_notification: SetNotification = Depends(get_set_notification),
) -> dict[str, object]:
    authorized_patient_hash = authorization.resolvePatientScope(
        principal,
        patient_hash,
    )
    return set_notification.requestAlarmToggle(authorized_patient_hash, slot_key)


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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    set_notification: SetNotification = Depends(get_set_notification),
) -> dict[str, object]:
    authorized_patient_hash = authorization.resolvePatientScope(
        principal,
        patient_hash,
    )
    return set_notification.saveNotificationSetting(
        authorized_patient_hash,
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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    set_notification: SetNotification = Depends(get_set_notification),
) -> dict[str, object]:
    authorized_patient_hash = authorization.resolvePatientScope(
        principal,
        patient_hash,
    )
    return set_notification.disableAlarmSetting(authorized_patient_hash, slot_key)


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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    manage_user_setting: ManageUserSetting = Depends(get_manage_user_setting),
) -> dict[str, object]:
    authorized_user_hash = authorization.resolveOwnUserHash(principal, user_hash)
    return manage_user_setting.requestUserSetting(authorized_user_hash)


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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    manage_user_setting: ManageUserSetting = Depends(get_manage_user_setting),
) -> dict[str, object]:
    authorized_user_hash = authorization.resolveOwnUserHash(principal, user_hash)
    return manage_user_setting.saveUserSetting(
        authorized_user_hash,
        request.font_size,
        request.reading_speed,
        request.language,
        request.language_mode,
        request.time_format,
        request.medication_notifications_enabled,
        request.caregiver_notifications_enabled,
        request.chat_notifications_enabled,
        request.notification_detail_mode,
        request.default_morning_time,
        request.default_lunch_time,
        request.default_evening_time,
        request.default_bedtime,
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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    check_health_recommendation: CheckHealthRecommendation = Depends(
        get_check_health_recommendation
    ),
) -> dict[str, object]:
    try:
        authorized_patient_hash = authorization.resolvePatientScope(
            principal,
            patient_hash,
            allow_caregiver=True,
        )
        return await check_health_recommendation.requestHealthRecommendation(
            authorized_patient_hash,
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


# 함수명: get_caregiver_notification_settings
# 역할:
# - 연동된 보호자-환자의 모든 시간대별 알림 설정을 한 번에 반환한다.
@router.get("/caregiver-notification/settings/{patient_hash}/slots")
def get_caregiver_notification_settings(
    patient_hash: str,
    caregiver_hash: str | None = None,
    guardian_hash: str | None = None,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    set_caregiver_notification: SetCaregiverNotification = Depends(
        get_set_caregiver_notification
    ),
) -> dict[str, object]:
    requested_caregiver_hash = caregiver_hash or guardian_hash
    requesting_caregiver_hash = authorization.resolveOwnUserHash(
        principal,
        requested_caregiver_hash,
    )
    authorized_patient_hash = authorization.requireLinkedPatient(
        principal,
        patient_hash,
    )
    return set_caregiver_notification.requestCaregiverNotificationSettings(
        requesting_caregiver_hash,
        authorized_patient_hash,
    )


# 함수명: get_caregiver_notification_setting
# 역할:
# - 연동된 보호자-환자의 지정 시간대 알림 설정을 반환한다.
@router.get("/caregiver-notification/settings/{patient_hash}")
@router.get(
    "/guardian-alert/settings/{patient_hash}",
    include_in_schema=False,
)
def get_caregiver_notification_setting(
    patient_hash: str,
    caregiver_hash: str | None = None,
    guardian_hash: str | None = None,
    slot_key: str = "morning",
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    set_caregiver_notification: SetCaregiverNotification = Depends(
        get_set_caregiver_notification
    ),
) -> dict[str, object]:
    requested_caregiver_hash = caregiver_hash or guardian_hash
    requesting_caregiver_hash = authorization.resolveOwnUserHash(
        principal,
        requested_caregiver_hash,
    )
    authorized_patient_hash = authorization.requireLinkedPatient(
        principal,
        patient_hash,
    )
    return set_caregiver_notification.requestCaregiverNotificationSetting(
        requesting_caregiver_hash,
        authorized_patient_hash,
        slot_key,
    )


# 함수명: save_caregiver_notification_setting
# 역할:
# - 연동된 보호자-환자의 지정 시간대 알림 설정만 저장한다.
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
    slot_key: str = "morning",
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    set_caregiver_notification: SetCaregiverNotification = Depends(
        get_set_caregiver_notification
    ),
) -> dict[str, object]:
    requested_caregiver_hash = caregiver_hash or guardian_hash
    requesting_caregiver_hash = authorization.resolveOwnUserHash(
        principal,
        requested_caregiver_hash,
    )
    authorized_patient_hash = authorization.requireLinkedPatient(
        principal,
        patient_hash,
    )
    return set_caregiver_notification.saveCaregiverNotificationSetting(
        requesting_caregiver_hash,
        authorized_patient_hash,
        request.notification_enabled,
        request.notification_type,
        request.deadline_hour,
        request.deadline_minute,
        slot_key=slot_key,
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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    link_patient_caregiver_control: LinkPatientCaregiver = Depends(
        get_link_patient_caregiver_control
    ),
) -> dict[str, object]:
    authorized_user_hash = authorization.resolveOwnUserHash(principal, user_hash)
    return link_patient_caregiver_control.requestLinkScreen(authorized_user_hash)


# Function Name: get_caregiver_patient_medication_info
# Description:
# - Returns read-only medication information for one explicitly selected linked patient.
@router.get("/caregiver/medications/{patient_hash}")
@router.get(
    "/guardian/medications/{patient_hash}",
    include_in_schema=False,
)
def get_caregiver_patient_medication_info(
    patient_hash: str,
    caregiver_hash: str | None = None,
    guardian_hash: str | None = None,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    check_caregiver_medication: CheckCaregiverMedication = Depends(
        get_check_caregiver_medication
    ),
) -> dict[str, object]:
    requested_caregiver_hash = caregiver_hash or guardian_hash
    requesting_caregiver_hash = authorization.resolveOwnUserHash(
        principal,
        requested_caregiver_hash,
    )
    authorized_patient_hash = authorization.requireLinkedPatient(
        principal,
        patient_hash,
    )
    return check_caregiver_medication.requestPatientMedicationInfo(
        requesting_caregiver_hash,
        authorized_patient_hash,
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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    link_patient_caregiver_control: LinkPatientCaregiver = Depends(
        get_link_patient_caregiver_control
    ),
) -> dict[str, object]:
    patient_hash = authorization.resolveOwnUserHash(principal, request.patient_hash)
    return link_patient_caregiver_control.generatePatientHash(patient_hash)


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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    link_patient_caregiver_control: LinkPatientCaregiver = Depends(
        get_link_patient_caregiver_control
    ),
) -> dict[str, object]:
    caregiver_hash = authorization.resolveOwnUserHash(
        principal,
        request.caregiver_hash,
    )
    return link_patient_caregiver_control.requestPatientCaregiverLink(
        caregiver_hash,
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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    link_patient_caregiver_control: LinkPatientCaregiver = Depends(
        get_link_patient_caregiver_control
    ),
) -> dict[str, object]:
    authorized_user_hash = authorization.resolveOwnUserHash(principal, user_hash)
    return link_patient_caregiver_control.requestUnlink(
        link_id,
        authorized_user_hash,
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
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    authorization: AuthorizationControl = Depends(get_authorization_control),
    check_saved_medication: CheckSavedMedication = Depends(get_check_saved_medication),
) -> dict[str, object]:
    authorized_patient_hash = authorization.resolvePatientScope(
        principal,
        patient_hash,
    )
    return check_saved_medication.requestDelete(drug_id, authorized_patient_hash)


# 함수명: analyze_masked_prescription_text
# 역할:
# - 기기에서 개인정보를 제거한 OCR 텍스트를 구조화된 처방 정보로 분석한다.
# 반환값:
# - API 호환 처방 분석 결과
@router.post(
    "/analyze-prescription-text",
    response_model=PrescriptionAnalysisResponse,
)
async def analyze_masked_prescription_text(
    request: OCRParseRequest,
    input_prescription: InputPrescription = Depends(get_input_prescription),
) -> dict[str, object]:
    try:
        return await input_prescription.requestPrescriptionText(request.text)
    except PrescriptionAnalysisTimeoutError as exc:
        logger.warning("De-identified prescription text analysis timed out.")
        raise HTTPException(status_code=504, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        logger.error(
            "De-identified prescription text analysis failed: %s",
            type(exc).__name__,
        )
        raise HTTPException(
            status_code=500,
            detail="비식별 처방전 텍스트 분석 중 서버 오류가 발생했습니다.",
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
