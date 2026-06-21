# 파일명: router.py
# 역할: MedBuddy 백엔드의 약품 관련 HTTP endpoint를 정의한다.

import logging

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel

from api.dependencies import (
    get_check_medication_detail,
    get_check_schedule,
    get_check_saved_medication,
    get_input_prescription,
    get_link_patient_caregiver,
    get_request_health_recommendation,
)
from controls.check_medication_detail_control import CheckMedicationDetail
from controls.check_schedule_control import CheckSchedule
from controls.check_saved_medication_control import CheckSavedMedication
from controls.input_prescription_control import InputPrescription
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.request_health_recommendation_control import RequestHealthRecommendation
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH
from schemas.medication import (
    MedicationRequest,
    MedicationResponse,
    MedicationStatusUpdate,
    PatientCodeCreate,
    PatientCodeRegister,
    SavedMedicationCreate,
)
from services.prescription_parser import parse_prescription

router = APIRouter()
logger = logging.getLogger(__name__)


# 클래스명: OCRParseRequest
# 역할: 기존 OCR 텍스트 파싱 endpoint용 요청 DTO이다.
# 속성:
#   - text: 프론트엔드에서 전달한 OCR 원본 텍스트
class OCRParseRequest(BaseModel):
    text: str


# 함수명: identify_medication
# 함수역할:
# - Receives raw medication text and returns public drug information with AI guide.
# 매개변수:
# - request: MedicationRequest containing extracted text.
# - check_medication_detail: CheckMedicationDetail injected by FastAPI.
# 반환값:
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
        logger.error("Identify API internal error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=f"서버 내부 오류: {exc}") from exc


# 함수명: save_medication
# 함수역할:
# - Saves selected medication information into the user's pillbox.
# 매개변수:
# - medication: SavedMedicationCreate request DTO.
# - check_saved_medication: CheckSavedMedication injected by FastAPI.
# 반환값:
# - API-compatible success dictionary.
@router.post("/save")
async def save_medication(
    medication: SavedMedicationCreate,
    check_saved_medication: CheckSavedMedication = Depends(get_check_saved_medication),
) -> dict[str, object]:
    return check_saved_medication.save_medication_detail(medication)


# 함수명: get_saved_medications
# 함수역할:
# - 환자 또는 연동 보호자 권한 범위의 저장 복약 정보를 반환한다.
# 매개변수:
# - patient_hash: 저장 복약 정보 조회 범위를 구분하는 환자 해시
# - user_hash: Requesting user hash. Used for guardian role resolution.
# - role: Requesting user role such as patient or guardian.
# - check_saved_medication: CheckSavedMedication injected by FastAPI.
# 반환값:
# - API-compatible list dictionary.
@router.get("/list")
async def get_saved_medications(
    patient_hash: str = DEFAULT_PATIENT_HASH,
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
    except Exception as exc:
        logger.error("Saved medication lookup failed: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail=f"불러오기 실패: {exc}") from exc


# 함수명: get_today_medication_schedule
# 함수역할:
# - 환자 또는 연동 보호자 권한 범위의 오늘 활성 복약 일정을 반환한다.
# 매개변수:
# - patient_hash: 복약 일정 조회 범위를 구분하는 환자 해시
# - user_hash: Requesting user hash. Used for guardian role resolution.
# - role: Requesting user role such as patient or guardian.
# - check_schedule: CheckSchedule injected by FastAPI.
# 반환값:
# - API-compatible schedule list dictionary.
@router.get("/schedule/today")
async def get_today_medication_schedule(
    patient_hash: str = DEFAULT_PATIENT_HASH,
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
    except Exception as exc:
        logger.error("Today medication schedule lookup failed: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Schedule lookup failed: {exc}",
        ) from exc


# 함수명: update_medication_status
# 함수역할:
# - 저장된 약 하나의 오늘 복약 완료 상태를 변경한다.
# 매개변수:
# - medication_id: Saved medication primary key from route path.
# - request: MedicationStatusUpdate request DTO.
# - patient_hash: 복약 상태 변경 범위를 구분하는 환자 해시
# - check_schedule: CheckSchedule injected by FastAPI.
# 반환값:
# - API-compatible status update dictionary.
@router.patch("/schedule/{medication_id}/status")
async def update_medication_status(
    medication_id: int,
    request: MedicationStatusUpdate,
    patient_hash: str = DEFAULT_PATIENT_HASH,
    check_schedule: CheckSchedule = Depends(get_check_schedule),
) -> dict[str, object]:
    return check_schedule.update_medication_status(
        medication_id,
        request.medication_status,
        patient_hash,
    )


# 함수명: get_health_recommendation
# 함수역할:
# - 현재 복용 중인 약 조합을 바탕으로 AI 건강 관리 추천을 반환한다.
# 매개변수:
# - patient_hash: 추천 조회 범위를 구분하는 환자 해시
# - user_hash: 보호자 요청자의 사용자 해시
# - role: 요청자 역할
# - request_health_recommendation: RequestHealthRecommendation injected by FastAPI.
# 반환값:
# - API-compatible health recommendation dictionary.
@router.get("/health/recommendation")
async def get_health_recommendation(
    patient_hash: str = DEFAULT_PATIENT_HASH,
    user_hash: str | None = None,
    role: str = "patient",
    language: str = "ko",
    request_health_recommendation: RequestHealthRecommendation = Depends(
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
        logger.error("Health recommendation failed: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"건강 관리 추천 생성 실패: {exc}",
        ) from exc


# 함수명: get_patient_caregiver_links
# 함수역할:
# - 환자 또는 보호자 해시 기준의 활성 연동 목록을 반환한다.
# 매개변수:
# - user_hash: 환자 또는 보호자 권한을 구분하는 해시
# - link_patient_caregiver: LinkPatientCaregiver injected by FastAPI.
# 반환값:
# - API-compatible link list dictionary.
@router.get("/link/list")
async def get_patient_caregiver_links(
    user_hash: str = DEFAULT_PATIENT_HASH,
    link_patient_caregiver: LinkPatientCaregiver = Depends(
        get_link_patient_caregiver
    ),
) -> dict[str, object]:
    return link_patient_caregiver.request_link_page(user_hash)


# 함수명: create_patient_link_code
# 함수역할:
# - UC-6 보호자 등록에 사용할 임시 환자 코드를 생성한다.
# 매개변수:
# - request: PatientCodeCreate request DTO.
# - link_patient_caregiver: LinkPatientCaregiver injected by FastAPI.
# 반환값:
# - API-compatible patient code dictionary.
@router.post("/link/code")
async def create_patient_link_code(
    request: PatientCodeCreate,
    link_patient_caregiver: LinkPatientCaregiver = Depends(
        get_link_patient_caregiver
    ),
) -> dict[str, object]:
    return link_patient_caregiver.request_patient_code(request.patient_hash)


# 함수명: register_patient_link_code
# 함수역할:
# - Registers a caregiver with a valid temporary patient code.
# 매개변수:
# - request: PatientCodeRegister request DTO.
# - link_patient_caregiver: LinkPatientCaregiver injected by FastAPI.
# 반환값:
# - API-compatible link dictionary.
@router.post("/link/register")
async def register_patient_link_code(
    request: PatientCodeRegister,
    link_patient_caregiver: LinkPatientCaregiver = Depends(
        get_link_patient_caregiver
    ),
) -> dict[str, object]:
    return link_patient_caregiver.register_patient_code(
        request.caregiver_hash,
        request.patient_code,
    )


# 함수명: unlink_patient_caregiver
# 함수역할:
# - Removes one active patient-caregiver link for a participating user hash.
# 매개변수:
# - link_id: 경로에서 받은 환자-보호자 연동 기본키
# - user_hash: 연동 해제를 요청할 수 있는 환자 또는 보호자 해시
# - link_patient_caregiver: LinkPatientCaregiver injected by FastAPI.
# 반환값:
# - API-compatible unlink dictionary.
@router.delete("/link/{link_id}")
async def unlink_patient_caregiver(
    link_id: int,
    user_hash: str = DEFAULT_PATIENT_HASH,
    link_patient_caregiver: LinkPatientCaregiver = Depends(
        get_link_patient_caregiver
    ),
) -> dict[str, object]:
    return link_patient_caregiver.request_unlink(link_id, user_hash)


# 함수명: delete_medication
# 함수역할:
# - Deletes a saved medication by id.
# 매개변수:
# - drug_id: Saved medication primary key from route path.
# - patient_hash: 삭제 범위를 구분하는 환자 해시
# - check_saved_medication: CheckSavedMedication injected by FastAPI.
# 반환값:
# - API-compatible delete success dictionary.
@router.delete("/delete/{drug_id}")
async def delete_medication(
    drug_id: int,
    patient_hash: str = DEFAULT_PATIENT_HASH,
    check_saved_medication: CheckSavedMedication = Depends(get_check_saved_medication),
) -> dict[str, object]:
    return check_saved_medication.request_delete(drug_id, patient_hash)


# 함수명: parse_prescription_endpoint
# 함수역할:
# - Parses OCR text into a structured prescription dictionary.
# 매개변수:
# - request: OCRParseRequest containing raw OCR text.
# 반환값:
# - API-compatible parse result dictionary.
@router.post("/parse-prescription")
async def parse_prescription_endpoint(
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
        raise HTTPException(status_code=500, detail=f"처방전 파싱 실패: {exc}") from exc


# 함수명: upload_and_parse_prescription
# 함수역할:
# - Receives a prescription image and returns structured medication candidates.
# 매개변수:
# - file: Uploaded image file.
# - input_prescription: InputPrescription injected by FastAPI.
# 반환값:
# - API-compatible prescription analysis dictionary.
@router.post("/upload-prescription")
async def upload_and_parse_prescription(
    file: UploadFile = File(...),
    input_prescription: InputPrescription = Depends(get_input_prescription),
) -> dict[str, object]:
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
        logger.error("Prescription image parsing failed: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=500,
            detail="데이터 추출 중 서버 오류가 발생했습니다.",
        ) from exc
