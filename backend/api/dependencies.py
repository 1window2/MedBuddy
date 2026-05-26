# File Name: dependencies.py
# Role: Provides FastAPI dependency factories for backend boundary classes.

from fastapi import Depends
from sqlalchemy.orm import Session

from core.database import get_db
from repositories.saved_medication_repository import SavedMedicationRepository
from services.drug_service import DrugService
from services.medication_identification_service import CheckMedicationDetail
from services.medication_text_service import MedicationTextService
from services.ocr_service import OCRService
from services.prescription_analysis_service import InputPrescription
from services.saved_medication_service import CheckSavedMedication


# Function Name: get_ocr_service
# Description:
# - Builds the OCR facade used by text parsing compatibility endpoints.
# Returns:
# - OCRService instance.
def get_ocr_service() -> OCRService:
    return OCRService()


# Function Name: get_input_prescription
# Description:
# - Builds the image prescription analysis control service.
# Returns:
# - InputPrescription instance.
def get_input_prescription() -> InputPrescription:
    return InputPrescription()


# Function Name: get_check_medication_detail
# Description:
# - Builds the medication detail lookup control service.
# Returns:
# - CheckMedicationDetail instance.
def get_check_medication_detail() -> CheckMedicationDetail:
    return CheckMedicationDetail(
        text_service=MedicationTextService(),
        drug_service=DrugService(),
    )


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
        repository=SavedMedicationRepository(db),
    )
