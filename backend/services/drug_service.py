#공공DB API 통신 블록
import json
import httpx
import logging
import redis.asyncio as redis
from fastapi import HTTPException
from core.config import settings
from schemas.medication import DrugInfo
from google import genai
from google.genai import types

logger = logging.getLogger(__name__)

class DrugService:
    def __init__(self):
        # 환경 변수 연동
        self.api_key = settings.PUBLIC_DATA_API_KEY
        self.basic_url = settings.BASIC_DRUG_API_BASE_URL
        self.advanced_url = settings.ADVANCED_DRUG_API_BASE_URL

        # Gemini 클라이언트 초기화
        self.ai_client = genai.Client(api_key=settings.GEMINI_API_KEY)

        # Redis 클라이언트 초기화
        self.redis = redis.from_url(settings.REDIS_URL, decode_responses=True)

    async def fetch_drug_info(self, drug_name: str) -> list[DrugInfo]:
        # =================================================================
        # [0단계] Redis Cache Hit Check
        # =================================================================
        cache_key = f"drug_info:{drug_name}"
        try:
            cached_data = await self.redis.get(cache_key)
            if cached_data:
                logger.info(f"[Redis Cache Hit] '{drug_name}' 정보를 cache에서 확인했습니다")
                drugs_dict = json.loads(cached_data)
                
                results = []
                for item in drugs_dict:
                    item['source'] = f"[Cache] {item.get('source', '')}"
                    results.append(DrugInfo(**item))
                return results
            
        except Exception as e:
            logger.warning(f"Redis 조회 실패 (캐시 무시하고 진행): {e}")

        # Cache Miss -> 기존 파이프라인 실행
        results_to_return = []

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
                        results_to_return.append(DrugInfo(
                            item_name=item.get('itemName', '정보 없음'),
                            efficacy=item.get('efcyQesitm', '정보 없음'),
                            use_method=item.get('useMethodQesitm', '정보 없음'),
                            warning_message=item.get('atpnWarnQesitm', '정보 없음'),
                            source="Basic (e약은요)"
                        ))

            # =================================================================
            # 2단계: 1단계 실패 시 ADVANCED API (의약품제품허가정보)로 Fallback
            # =================================================================
            if not results_to_return:
                logger.info(f"[Basic API] 결과 없음. Advanced API로 Fallback 시도: '{drug_name}'")
                
                advanced_params = {
                    "serviceKey": self.api_key,
                    "item_name": drug_name,
                    "type": "json",
                    "numOfRows": 1 # 가장 정확한 1개만
                }
                
                advanced_response = await client.get(self.advanced_url, params=advanced_params)
                
                if advanced_response.status_code != 200:
                    raise HTTPException(status_code=502, detail="공공데이터 API 서버와 통신할 수 없습니다.")
                    
                adv_data = advanced_response.json()
                adv_items = adv_data.get('body', {}).get('items') or []
                
                if not adv_items:
                    logger.warning(f"[{drug_name}] 식약처 DB에 등록되지 않은 약품입니다.")
                    return [] # 아예 검색되지 않는 약이면 빈 리스트 반환 (캐싱 생략)

                # =================================================================
                # 3단계: 복잡한 원문을 Gemini로 요약
                # =================================================================
                adv_item = adv_items[0]
                actual_item_name = adv_item.get('ITEM_NAME', drug_name)
                
                # text만 추출 요약
                raw_efficacy = str(adv_item.get('EE_DOC_DATA', '정보 없음'))[:2000] 
                raw_usage = str(adv_item.get('UD_DOC_DATA', '정보 없음'))[:2000]    
                raw_warning = str(adv_item.get('NB_DOC_DATA', '정보 없음'))[:2000]
                
                prompt = f"""
                당신은 친절한 약사입니다. 아래는 식약처의 전문가용 의약품 허가 정보 원문입니다.
                일반 환자가 이해하기 쉽게 각 항목을 2~3문장 이내로 친절하게 요약해 주세요.
                반드시 아래의 4가지 키 (key)를 가진 JSON 형식으로만 답변해 주세요.
                
                {{
                    "efficacy": "요약된 효능",
                    "use_method": "요약된 용법",
                    "warning_message": "요약된 주의사항",
                    "ai_guide": "친한 동네 약사님처럼 따뜻하고 부드러운 말투(~해요, ~하세요)로 전체적인 복약 가이드 2줄 요약"
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
                    
                    results_to_return = [
                            DrugInfo(
                                item_name=actual_item_name,
                                efficacy=summary_data.get('efficacy', '요약 실패'),
                                use_method=summary_data.get('use_method', '요약 실패'),
                                warning_message=summary_data.get('warning_message', '요약 실패'),
                                source="Advanced (허가정보) + AI 요약",
                                ai_guide=summary_data.get('ai_guide', '요약 실패')
                            )
                        ]
                    
                except Exception as e:
                    logger.error(f"Gemini AI 요약 처리 실패: {str(e)}")
                    raise HTTPException(status_code=500, detail="AI 요약 처리 중 오류가 발생했습니다.")
                
            # =================================================================
            # 3.5단계: Basic API 결과물에 대한 AI 가이드 추가
            # =================================================================
            for drug in results_to_return:
                if not drug.ai_guide: # Advanced 거친 약은 pass
                    logger.info(f"[Gemini] '{drug.item_name}' Basic API 데이터 친절한 약사 말투로 변환 중...")
                    raw_data = f"효능: {drug.efficacy}\n사용법: {drug.use_method}\n주의사항: {drug.warning_message}"
                    
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
                        ai_response = await self.ai_client.aio.models.generate_content(
                            model='gemini-3.1-flash-lite-preview',
                            contents=prompt
                        )
                        drug.ai_guide = ai_response.text
                    except Exception as e:
                        logger.error(f"Gemini API 호출 에러: {e}")
                        drug.ai_guide = "AI 요약을 불러오는 중 일시적인 오류가 발생했어요."
            
        # =================================================================
        # 4단계: 찾은 data를 Redis에 저장
        # =================================================================
        if results_to_return:
            try:
                dict_list = [drug.model_dump() for drug in results_to_return]
                # 7일 = 604800초 (한 번 검색된 약 정보는 7일간 유지)
                await self.redis.setex(cache_key, 604800, json.dumps(dict_list))
                logger.info(f"[Redis Cache Saved] '{drug_name}' 정보를 캐시에 저장했습니다.")
            except Exception as e:
                logger.error(f"Redis 저장 실패: {e}")

        # 최종적으로 찾아낸 결과를 frontend로 return
        return results_to_return