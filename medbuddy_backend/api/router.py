#API 엔드포인트 관리 블록
from fastapi import APIRouter, Depends, HTTPException
from schemas.medication import MedicationRequest, MedicationResponse
from services.ocr_service import OCRService
from services.drug_service import DrugService

# Gemini 라이브러리 임포트
import google.generativeai as genai

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
        # 텍스트 정제(OCR)
        search_keyword = ocr_service.process_text(request.extracted_text)

        # DB 검색 (공공 API 활용)
        drug_data = await drug_service.fetch_drug_info(search_keyword)

        if not drug_data:
            return MedicationResponse(
                success=False,
                message=f"'{search_keyword}'에 해당하는 약 정보를 찾을 수 없습니다."
            )
        
        # AI 활용하여 데이터 가공, 요약
        model = genai.GenerativeModel('gemini-1.5-flash')
        
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
                drug.ai_guide = "AI 요약을 불러오는 중 일시적인 오류가 발생했어요."

        return MedicationResponse(
            success=True,
            message="약 정보 조회 성공",
            data=drug_data
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))