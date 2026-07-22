# File Name: dependencies.py
# Role: Provides FastAPI dependency factories for backend use-case collaborators.

import asyncio
import logging
from threading import Lock

from fastapi import Depends
from sqlalchemy.orm import Session

from boundaries.pill_identification_boundary import (
    MFDSPillCatalogBoundary,
    PillVisionBoundary,
)
from boundaries.public_drug_api_boundary import (
    PillImageAPI,
    PublicDrugLargeAPI,
    PublicDrugSmallAPI,
)
from core.database import get_db
from controls.check_medication_detail_control import (
    CheckMedicationDetail,
    _MedicationDetailCache,
)
from controls.check_prescription_change_control import CheckPrescriptionChange
from controls.check_today_medication_info_control import CheckTodayMedicationInfo
from controls.check_schedule_control import CheckSchedule
from controls.check_saved_medication_control import CheckSavedMedication
from controls.input_prescription_control import InputPrescription
from controls.identify_pill_control import IdentifyPill
from controls.manage_user_setting_control import ManageUserSetting
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.check_health_recommendation_control import CheckHealthRecommendation
from controls.check_caregiver_medication_control import CheckCaregiverMedication
from controls.request_voice_guide_control import RequestVoiceGuide
from controls.set_caregiver_notification_control import SetCaregiverNotification
from controls.set_notification_control import SetNotification

logger = logging.getLogger(__name__)
_medication_detail_cache: _MedicationDetailCache | None = None
_public_drug_small_api = PublicDrugSmallAPI()
_public_drug_large_api = PublicDrugLargeAPI()
_pill_image_api = PillImageAPI()
_pill_boundary_lock = Lock()
_pill_vision_boundary: PillVisionBoundary | None = None
_pill_catalog_boundary: MFDSPillCatalogBoundary | None = None
_pill_ranking_semaphore = asyncio.Semaphore(2)


async def get_medication_detail_cache() -> _MedicationDetailCache:
    global _medication_detail_cache
    if _medication_detail_cache is None:
        _medication_detail_cache = _MedicationDetailCache()
    return _medication_detail_cache


async def close_medication_detail_cache() -> None:
    global _medication_detail_cache
    medication_detail_cache = _medication_detail_cache
    _medication_detail_cache = None
    if medication_detail_cache is None:
        return
    try:
        await medication_detail_cache.close()
    except Exception as exc:
        logger.warning(
            "Medication detail cache shutdown failed: %s",
            type(exc).__name__,
        )


# Function Name: get_input_prescription
# Description:
# - Builds the image prescription analysis control service.
# Returns:
# - InputPrescription instance.
def get_input_prescription(
    db: Session = Depends(get_db),
) -> InputPrescription:
    return InputPrescription(db=db)


def _get_pill_identification_boundaries() -> tuple[
    PillVisionBoundary,
    MFDSPillCatalogBoundary,
]:
    global _pill_vision_boundary, _pill_catalog_boundary
    with _pill_boundary_lock:
        if _pill_vision_boundary is None:
            _pill_vision_boundary = PillVisionBoundary()
        if _pill_catalog_boundary is None:
            _pill_catalog_boundary = MFDSPillCatalogBoundary()
        return _pill_vision_boundary, _pill_catalog_boundary


async def close_pill_identification_boundaries() -> None:
    """Releases reusable external clients and invalidates in-memory catalog data."""

    global _pill_vision_boundary, _pill_catalog_boundary
    with _pill_boundary_lock:
        vision_boundary = _pill_vision_boundary
        catalog_boundary = _pill_catalog_boundary
        _pill_vision_boundary = None
        _pill_catalog_boundary = None
    if catalog_boundary is not None:
        catalog_boundary.invalidateMemoryCache()
    if vision_boundary is None:
        return
    try:
        await vision_boundary.close()
    except Exception as exc:
        logger.warning(
            "Pill identification boundary shutdown failed: %s",
            type(exc).__name__,
        )


def get_identify_pill() -> IdentifyPill:
    """Builds the experimental loose-pill identification control."""

    vision_boundary, catalog_boundary = _get_pill_identification_boundaries()
    return IdentifyPill(
        vision_boundary=vision_boundary,
        catalog_boundary=catalog_boundary,
        ranking_semaphore=_pill_ranking_semaphore,
    )


# Function Name: get_check_medication_detail
# Description:
# - Builds the medication detail lookup control service with optional local DB access.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - CheckMedicationDetail instance.
def get_check_medication_detail(
    db: Session = Depends(get_db),
    medication_cache: _MedicationDetailCache = Depends(
        get_medication_detail_cache
    ),
) -> CheckMedicationDetail:
    return CheckMedicationDetail(
        db=db,
        medication_cache=medication_cache,
        public_drug_small_api=_public_drug_small_api,
        public_drug_large_api=_public_drug_large_api,
        pill_image_api=_pill_image_api,
    )


# 함수이름: get_check_prescription_change
# 함수역할:
# - 요청 단위 DB 세션을 포함한 처방 변화 비교 Control을 생성한다.
# 매개변수:
# - db: FastAPI 의존성 주입으로 전달된 SQLAlchemy 세션
# 반환값:
# - CheckPrescriptionChange 인스턴스
def get_check_prescription_change(
    db: Session = Depends(get_db),
) -> CheckPrescriptionChange:
    return CheckPrescriptionChange(db=db)


# Function Name: get_check_saved_medication
# Description:
# - Builds the saved medication control service with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - CheckSavedMedication instance.
def get_check_saved_medication(
    db: Session = Depends(get_db),
) -> CheckSavedMedication:
    return CheckSavedMedication(
        db=db,
        medication_image_lookup=_pill_image_api,
    )


# Function Name: get_check_schedule
# Description:
# - Builds the medication schedule control service with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - CheckSchedule instance.
def get_check_schedule(
    db: Session = Depends(get_db),
) -> CheckSchedule:
    return CheckSchedule(db=db)


# Function Name: get_check_today_medication_info
# Description:
# - Builds the today medication summary control with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - CheckTodayMedicationInfo instance.
def get_check_today_medication_info(
    db: Session = Depends(get_db),
) -> CheckTodayMedicationInfo:
    return CheckTodayMedicationInfo(db=db)


# Function Name: get_check_health_recommendation
# 함수역할:
# - 요청 단위 DB 세션을 포함한 건강 관리 추천 control 서비스를 생성한다.
# 매개변수:
# - db: FastAPI 의존성 주입으로 전달된 SQLAlchemy 세션
# 반환값:
# - CheckHealthRecommendation instance.
def get_check_health_recommendation(
    db: Session = Depends(get_db),
) -> CheckHealthRecommendation:
    return CheckHealthRecommendation(db=db)


# Function Name: get_link_patient_caregiver_control
# Description:
# - Builds the patient-caregiver link control with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - LinkPatientCaregiver instance.
def get_link_patient_caregiver_control(
    db: Session = Depends(get_db),
) -> LinkPatientCaregiver:
    return LinkPatientCaregiver(db=db)


# Function Name: get_check_caregiver_medication
# Description:
# - Builds the read-only caregiver medication control for one request.
def get_check_caregiver_medication(
    db: Session = Depends(get_db),
) -> CheckCaregiverMedication:
    return CheckCaregiverMedication(db=db)


# Function Name: get_set_notification
# Description:
# - Builds the medication alarm control with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - SetNotification instance.
def get_set_notification(
    db: Session = Depends(get_db),
) -> SetNotification:
    return SetNotification(db=db)


# Function Name: get_set_caregiver_notification
# Description:
# - Builds the caregiver notification control with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - SetCaregiverNotification instance.
def get_set_caregiver_notification(
    db: Session = Depends(get_db),
) -> SetCaregiverNotification:
    return SetCaregiverNotification(db=db)


# Function Name: get_manage_user_setting
# Description:
# - Builds the user setting control with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - ManageUserSetting instance.
def get_manage_user_setting(
    db: Session = Depends(get_db),
) -> ManageUserSetting:
    return ManageUserSetting(db=db)


# Function Name: get_request_voice_guide
# Description:
# - Builds the medication voice guide text control.
# Returns:
# - RequestVoiceGuide instance.
def get_request_voice_guide() -> RequestVoiceGuide:
    return RequestVoiceGuide()
