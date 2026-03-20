#API 엔드포인트 관리 블록

from fastapi import APIRouter, Depends, HTTPException
from schemas.medication import MedicationRequest, MedicationResponse
from services.ocr_service import OCRService
from services.drug_service import DrugService

router = APIRouter()


# 의존성 주입을 위한 함수
def get_ocr_service(): return OCRService()


def get_drug_service(): return DrugService()


@router.post("/identify", response_model=MedicationResponse)
async def identify_medication(
        request: MedicationRequest,
        ocr_service: OCRService = Depends(get_ocr_service),
        drug_service: DrugService = Depends(get_drug_service)
):
    if not request.extracted_text:
        raise HTTPException(status_code=400, detail="추출된 텍스트가 없습니다.")

    try:
        # 1. 텍스트 정제 (OCR 서비스 활용)
        search_keyword = ocr_service.process_text(request.extracted_text)

        # 2. DB 검색 (약 정보 API 활용)
        drug_data = await drug_service.fetch_drug_info(search_keyword)

        if not drug_data:
            return MedicationResponse(
                success=False,
                message=f"'{search_keyword}'에 해당하는 약 정보를 찾을 수 없습니다."
            )

        return MedicationResponse(
            success=True,
            message="약 정보 조회 성공",
            data=drug_data
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))