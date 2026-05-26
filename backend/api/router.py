# File Name: router.py
# Role: Defines medication-related HTTP endpoints for the MedBuddy backend.

import logging

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel

from api.dependencies import (
    get_check_medication_detail,
    get_check_saved_medication,
    get_input_prescription,
    get_ocr_service,
)
from schemas.medication import MedicationRequest, MedicationResponse, SavedMedicationCreate
from schemas.ocr import PrescriptionData
from services.medication_identification_service import CheckMedicationDetail
from services.ocr_service import OCRService
from services.prescription_analysis_service import InputPrescription
from services.saved_medication_service import CheckSavedMedication

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
        logger.error("Identify API 내부 에러 발생: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=f"서버 내부 오류: {exc}") from exc


# Function Name: save_medication
# Description:
# - Saves selected medication information into the user's pillbox.
# Parameters:
# - medication: SavedMedicationCreate request DTO.
# - check_saved_medication: CheckSavedMedication injected by FastAPI.
# Returns:
# - API-compatible success dictionary.
@router.post("/save")
async def save_medication(
    medication: SavedMedicationCreate,
    check_saved_medication: CheckSavedMedication = Depends(get_check_saved_medication),
) -> dict[str, object]:
    return check_saved_medication.save_medication_detail(medication)


# Function Name: get_saved_medications
# Description:
# - Returns all saved medication rows.
# Parameters:
# - check_saved_medication: CheckSavedMedication injected by FastAPI.
# Returns:
# - API-compatible list dictionary.
@router.get("/list")
async def get_saved_medications(
    check_saved_medication: CheckSavedMedication = Depends(get_check_saved_medication),
) -> dict[str, object]:
    try:
        return check_saved_medication.request_saved_medication_info()
    except Exception as exc:
        logger.error("DB 불러오기 에러: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=f"불러오기 실패: {exc}") from exc


# Function Name: delete_medication
# Description:
# - Deletes a saved medication by id.
# Parameters:
# - drug_id: Saved medication primary key from route path.
# - check_saved_medication: CheckSavedMedication injected by FastAPI.
# Returns:
# - API-compatible delete success dictionary.
@router.delete("/delete/{drug_id}")
async def delete_medication(
    drug_id: int,
    check_saved_medication: CheckSavedMedication = Depends(get_check_saved_medication),
) -> dict[str, object]:
    return check_saved_medication.request_delete(drug_id)


# Function Name: parse_prescription_endpoint
# Description:
# - Parses OCR text into a structured prescription dictionary.
# Parameters:
# - request: OCRParseRequest containing raw OCR text.
# - ocr_service: OCRService facade injected by FastAPI.
# Returns:
# - API-compatible parse result dictionary.
@router.post("/parse-prescription")
async def parse_prescription_endpoint(
    request: OCRParseRequest,
    ocr_service: OCRService = Depends(get_ocr_service),
) -> dict[str, object]:
    if not request.text:
        raise HTTPException(status_code=400, detail="OCR 텍스트가 없습니다.")

    try:
        parsed_data = ocr_service.parse_prescription_text(request.text)
        return {
            "success": True,
            "message": "처방전 파싱 성공",
            "parsed": parsed_data,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"처방전 파싱 실패: {exc}") from exc


# Function Name: upload_and_parse_prescription
# Description:
# - Receives a prescription image and returns structured medication candidates.
# Parameters:
# - file: Uploaded image file.
# - input_prescription: InputPrescription injected by FastAPI.
# Returns:
# - PrescriptionData DTO.
@router.post("/upload-prescription", response_model=PrescriptionData)
async def upload_and_parse_prescription(
    file: UploadFile = File(...),
    input_prescription: InputPrescription = Depends(get_input_prescription),
) -> PrescriptionData:
    try:
        image_bytes = await file.read()
        logger.info(
            "Prescription image upload received: filename=%s, content_type=%s, bytes=%d",
            file.filename,
            file.content_type,
            len(image_bytes),
        )
        return await input_prescription.request_prescription_image(image_bytes)
    except ValueError as exc:
        logger.warning("Prescription image upload rejected: %s", exc, exc_info=True)
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        logger.error("이미지 파싱 에러: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail="데이터 추출 중 서버 오류가 발생했습니다.",
        ) from exc
