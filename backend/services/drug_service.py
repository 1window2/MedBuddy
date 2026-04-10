#공공DB API 통신 블록
import json
import httpx
import logging
from fastapi import HTTPException
from core.config import settings
from schemas.medication import DrugInfo
import xml.etree.ElementTree as ET
from google import genai

logger = logging.getLogger(__name__)

class DrugService:
    def __init__(self):
        # 환경 변수 연동
        self.api_key = settings.PUBLIC_DATA_API_KEY
        self.basic_url = settings.BASIC_DRUG_API_BASE_URL
        self.advanced_url = settings.ADVANCED_DRUG_API_BASE_URL

        # Gemini 클라이언트 초기화
        self.ai_client = genai.Client(api_key=settings.GEMINI_API_KEY)

    async def fetch_drug_info(self, drug_name: str) -> list[DrugInfo]:
        async with httpx.AsyncClient(timeout=15.0) as client:
            
            # =================================================================
            # 1단계: BASIC API (e약은요) 탐색
            # =================================================================
            basic_params = {
                "serviceKey": self.api_key,
                "itemName": drug_name,
                "type": "json",
                "numOfRows": 3
            }
            
            basic_response = await client.get(self.basic_url, params=basic_params)
            
            if basic_response.status_code == 200:
                data = basic_response.json()
                items = data.get('body', {}).get('items') or []
                
                if items:
                    logger.info(f"[Basic API] '{drug_name}' 검색 성공 ({len(items)}건)")
                    results = []
                    for item in items:
                        results.append(DrugInfo(
                            item_name=item.get('itemName', '정보 없음'),
                            efficacy=item.get('efcyQesitm', '정보 없음'),
                            use_method=item.get('useMethodQesitm', '정보 없음'),
                            warning_message=item.get('atpnWarnQesitm', '정보 없음'),
                            source="Basic (e약은요)"
                        ))
                    return results

            # =================================================================
            # 2단계: 1단계 실패 시 ADVANCED API (의약품제품허가정보)로 Fallback
            # =================================================================
            logger.info(f"[Basic API] 결과 없음. Advanced API로 Fallback 시도: '{drug_name}'")
            
            advanced_params = {
                "serviceKey": self.api_key,
                "item_name": drug_name,
                "type": "json",
                "numOfRows": 1 # 가장 정확한 1개만 추출
            }
            
            advanced_response = await client.get(self.advanced_url, params=advanced_params)
            
            if advanced_response.status_code != 200:
                raise HTTPException(status_code=502, detail="공공데이터 API 서버와 통신할 수 없습니다.")
                
            adv_data = advanced_response.json()
            adv_items = adv_data.get('body', {}).get('items') or []
            
            if not adv_items:
                logger.warning(f"[{drug_name}] 식약처 DB에 등록되지 않은 약품입니다.")
                raise HTTPException(status_code=404, detail="식약처 DB에 등록되지 않은 약품입니다.")

            # =================================================================
            # 3단계: 복잡한 원문을 Gemini로 요약
            # =================================================================
            adv_item = adv_items[0]
            actual_item_name = adv_item.get('ITEM_NAME', drug_name)
            
            # text만 추출 요약
            raw_efficacy = adv_item.get('ee_doc_data', '정보 없음') 
            raw_usage = adv_item.get('ud_doc_data', '정보 없음')    
            raw_warning = adv_item.get('nb_doc_data', '정보 없음')  
            
            prompt = f"""
            당신은 친절한 약사입니다. 아래는 식약처의 전문가용 의약품 허가 정보 원문입니다.
            일반 환자가 이해하기 쉽게 각 항목을 2~3문장 이내로 친절하게 요약해 주세요.
            반드시 아래의 3가지 키 (key)를 가진 JSON 형식으로만 답변해 주세요.
            
            {{
                "efficacy": "요약된 효능",
                "use_method": "요약된 용법",
                "warning_message": "요약된 주의사항"
            }}
            
            [원문 데이터]
            - 효능: {raw_efficacy}
            - 용법: {raw_usage}
            - 주의: {raw_warning}
            """
            
            logger.info(f"[Gemini] '{actual_item_name}' 허가정보 AI 요약 요청 중...")
            
            try:
                # 비동기 AI 호출
                ai_response = await self.ai_client.aio.models.generate_content(
                    model='gemini-3.1-flash-lite-preview',
                    contents=prompt,
                    config={'response_mime_type': 'application/json'} 
                )
                
                summary_data = json.loads(ai_response.text)
                
                return [
                    DrugInfo(
                        item_name=actual_item_name,
                        efficacy=summary_data.get('efficacy', '요약 실패'),
                        use_method=summary_data.get('use_method', '요약 실패'),
                        warning_message=summary_data.get('warning_message', '요약 실패'),
                        source="Advanced (허가정보) + AI 요약"
                    )
                ]
                
            except Exception as e:
                logger.error(f"Gemini AI 요약 처리 실패: {str(e)}")
                raise HTTPException(status_code=500, detail="AI 요약 처리 중 오류가 발생했습니다.")