#API 엔드포인트 관리 블록
import logging
import re
import google.generativeai as genai
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from schemas.medication import MedicationRequest, MedicationResponse
from services.ocr_service import OCRService
from services.drug_service import DrugService
from sqlalchemy.orm import Session
from core.database import get_db
from models.db_models import SavedMedication
from schemas.medication import SavedMedicationCreate
from pydantic import BaseModel
from schemas.ocr import PrescriptionData

router = APIRouter()

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)

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
        # 텍스트 정제(OCR)
        raw_text = request.extracted_text[:50]
        search_keyword = ocr_service.process_text(raw_text)

        # 용량 단위 앞부분만 추출
        parts = re.split(r'[0-9.]+\s*(?:mg|g|ml)', search_keyword, flags=re.IGNORECASE)
        search_keyword = parts[0]
        
        # 제형 및 공백 제거
        search_keyword = search_keyword.replace('정', '').replace('캡슐', '')
        search_keyword = search_keyword.strip()

        # DB 검색 (공공 API 활용)
        drug_data = await drug_service.fetch_drug_info(search_keyword)

        if not drug_data:
            return MedicationResponse(
                success=False,
                message=f"'{search_keyword}'에 해당하는 약 정보를 찾을 수 없습니다."
            )
        
        # AI 활용하여 데이터 가공, 요약
        model = genai.GenerativeModel('gemini-2.5-flash')
        
        for drug in drug_data:
            # 식약처 원본 데이터
            raw_data = f"효능: {drug.efficacy}\n사용법: {drug.use_method}\n주의사항: {drug.warning_message}"
            
            # AI 프롬프트
            prompt = f"""
            너는 환자의 건강을 챙겨주는 친절하고 다정한 AI 약사야.
            다음은 식약처에서 제공하는 어려운 약품 설명서야:
            {raw_data}

            이 내용을 일반인이 이해하기 쉽게 다음 규칙에 따라 설명해줘:
            1. 가장 핵심적인 효능과 복용법을 1~2줄로 요약할 것.
            2. 주의해야 할 부작용을 친절하게 당부할 것.
            3. "친한 동네 약사님"처럼 따뜻하고 부드러운 말투(~해요, ~하세요)를 사용할 것.
            """
            
            try:
                # API를 호출해서 답변을 받아옴
                ai_response = await model.generate_content_async(prompt)
                drug.ai_guide = ai_response.text
            except Exception as e:
                # AI 서버가 응답하지 않을 경우
                logger.error(f"Gemini API 호출 에러: {e}")
                drug.ai_guide = "AI 요약을 불러오는 중 일시적인 오류가 발생했어요."

        return MedicationResponse(
            success=True,
            message="약 정보 조회 성공",
            data=drug_data
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    

@router.post("/save")
async def save_medication(
    medication: SavedMedicationCreate,
    db: Session = Depends(get_db)
):
    try:
        # Pydantic으로 받은 데이터를 DB 테이블 모델로 변환
        db_med = SavedMedication(
            item_name=medication.item_name,
            efficacy=medication.efficacy,
            use_method=medication.use_method,
            warning_message=medication.warning_message,
            ai_guide=medication.ai_guide
        )
        
        # DB 저장소에 commit
        db.add(db_med)
        db.commit()
        db.refresh(db_med) # 방금 생성된 데이터 갱신해서 가져옴
        
        return {
            "success": True, 
            "message": f"'{db_med.item_name}'이(가) 약통에 무사히 저장되었습니다!", 
            "id": db_med.id
        }
    
    except Exception as e:
        db.rollback() # 에러 시 롤백
        raise HTTPException(status_code=500, detail=f"저장 실패: {str(e)}")
    
@router.get("/list")
async def get_saved_medications(db: Session = Depends(get_db)):
    try:
        # DB에서 저장된 모든 약 데이터 가져옴
        saved_drugs = db.query(SavedMedication).all()
        return {
            "success": True, 
            "message": "약통 목록 조회 성공", 
            "data": saved_drugs
        }
    except Exception as e:
        logger.error(f"DB 불러오기 에러: {e}")
        raise HTTPException(status_code=500, detail=f"불러오기 실패: {str(e)}")

@router.delete("/delete/{drug_id}")
async def delete_medication(drug_id: int, db: Session = Depends(get_db)):
    try:
        # DB에서 해당 ID를 가진 약 찾기
        drug = db.query(SavedMedication).filter(SavedMedication.id == drug_id).first()
        if not drug:
            raise HTTPException(status_code=404, detail="약을 찾을 수 없습니다.")
        
        # 찾으면 삭제
        db.delete(drug)
        db.commit()
        return {"success": True, "message": "약통에서 삭제되었습니다."}
    except Exception as e:
        db.rollback()
        logger.error(f"삭제 에러: {e}")
        raise HTTPException(status_code=500, detail=f"삭제 실패: {str(e)}")

# 클래스명: OCRParseRequest
# 클래스역할:
# - 프론트엔드가 보낸 OCR 텍스트를 받기 위한 요청 바디 모델
# 변수명: text
# 변수역할:
# - OCR로 읽은 전체 문자열
class OCRParseRequest(BaseModel):
    text: str


# 함수명: parse_prescription_endpoint
# 함수역할:
# - 프론트엔드에서 보낸 OCR 문자열을 받아
#   처방전 구조화 JSON으로 변환 후 반환
# 변수명: request
# 변수역할:
# - 프론트가 보낸 요청 바디
# 변수명: ocr_service
# 변수역할:
# - OCR 문자열 분리 및 파싱을 담당하는 서비스 객체
@router.post("/parse-prescription")
async def parse_prescription_endpoint(
    request: OCRParseRequest,
    ocr_service: OCRService = Depends(get_ocr_service),
):
    if not request.text:
        raise HTTPException(status_code=400, detail="OCR 텍스트가 없습니다.")

    try:
        # 변수명: parsed_data
        # 변수역할:
        # - 파서가 반환한 최종 구조화 결과
        parsed_data = ocr_service.parse_prescription_text(request.text)

        return {
            "success": True,
            "message": "처방전 파싱 성공",
            "parsed": parsed_data,
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"처방전 파싱 실패: {str(e)}")

@router.post("/upload-prescription", response_model=PrescriptionData)
async def upload_and_parse_prescription(
    file: UploadFile = File(...),
    ocr_service: OCRService = Depends(get_ocr_service) # 의존성 주입
):
    """
    약봉투 image 업로드 -> 노이즈 전처리 -> AI 추출 -> 구조화 -> 마스킹 -> 반환
    """
    #if not file.content_type.startswith("image/"):
    #    raise HTTPException(status_code=400, detail="이미지 파일만 업로드 가능합니다.")
    
    try:
        # image bytes read
        image_bytes = await file.read()
        
        # service logic call
        extracted_data = await ocr_service.extract_prescription_data(image_bytes)
        
        return extracted_data
        
    except ValueError as ve:
        # image corrupt 등으로 발생한 처리 오류
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as e:
        logger.error(f"이미지 파싱 에러: {e}")
        raise HTTPException(status_code=500, detail="데이터 추출 중 서버 오류가 발생했습니다.")