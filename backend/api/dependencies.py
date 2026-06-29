# File Name: dependencies.py
# Role: Provides FastAPI dependency factories for backend use-case collaborators.

from fastapi import Depends
from sqlalchemy.orm import Session

from core.database import get_db
from controls.check_medication_detail_control import CheckMedicationDetail
from controls.check_schedule_control import CheckSchedule
from controls.check_saved_medication_control import CheckSavedMedication
from controls.input_prescription_control import InputPrescription
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.request_health_recommendation_control import RequestHealthRecommendation


# Function Name: get_input_prescription
# Description:
# - Builds the image prescription analysis control service.
# Returns:
# - InputPrescription instance.
def get_input_prescription() -> InputPrescription:
    return InputPrescription()


# Function Name: get_check_medication_detail
# Description:
# - Builds the medication detail lookup control service with optional local DB access.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - CheckMedicationDetail instance.
def get_check_medication_detail(
    db: Session = Depends(get_db),
) -> CheckMedicationDetail:
    return CheckMedicationDetail(db=db)


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
    return CheckSavedMedication(db=db)


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


# 함수명: get_request_health_recommendation
# 함수역할:
# - 요청 단위 DB 세션을 포함한 건강 관리 추천 control 서비스를 생성한다.
# 매개변수:
# - db: FastAPI 의존성 주입으로 전달된 SQLAlchemy 세션
# 반환값:
# - RequestHealthRecommendation instance.
def get_request_health_recommendation(
    db: Session = Depends(get_db),
) -> RequestHealthRecommendation:
    return RequestHealthRecommendation(db=db)


# Function Name: get_link_patient_caregiver
# Description:
# - Builds the patient-caregiver link control service with a request-scoped DB session.
# Parameters:
# - db: SQLAlchemy session supplied by FastAPI dependency injection.
# Returns:
# - LinkPatientCaregiver instance.
def get_link_patient_caregiver(
    db: Session = Depends(get_db),
) -> LinkPatientCaregiver:
    return LinkPatientCaregiver(db=db)
