# File Name: dependencies.py
# Role: Provides FastAPI dependency factories for backend use-case collaborators.

from fastapi import Depends
from sqlalchemy.orm import Session

from core.database import get_db
from controls.check_medication_detail_control import CheckMedicationDetail
from controls.check_saved_medication_control import CheckSavedMedication
from controls.input_prescription_control import InputPrescription


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
