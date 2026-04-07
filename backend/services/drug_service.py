#공공DB API 통신 블록

import httpx
from core.config import settings
from schemas.medication import DrugInfo
import xml.etree.ElementTree as ET


class DrugService:
    def __init__(self):
        self.api_key = settings.DRUG_API_KEY
        self.base_url = settings.DRUG_API_BASE_URL

    async def fetch_drug_info(self, drug_name: str) -> list[DrugInfo]:
        # 공공데이터포털 요청 파라미터 셋업
        params = {
            "serviceKey": self.api_key,
            "itemName": drug_name,
            "type": "json",  # JSON 응답 요청
            "numOfRows": 3  # 유사 검색 결과 개수 제한
        }

        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(self.base_url, params=params)

            # 식약처 API 응답 체크 디버깅용
            # print(f"식약처 API 응답 결과: {response.text}")

            if response.status_code != 200:
                raise Exception("공공데이터 API 서버와 통신할 수 없습니다.")

            data = response.json()
            results = []

            # 응답 데이터 파싱 (e약은요 API의 실제 JSON 응답 구조에 맞춰 조정 필요)
            items = data.get('body', {}).get('items', [])
            for item in items:
                drug_info = DrugInfo(
                    item_name=item.get('itemName', '정보 없음'),
                    efficacy=item.get('efcyQesitm', '정보 없음'),  # 효능
                    use_method=item.get('useMethodQesitm', '정보 없음'),  # 사용법
                    warning_message=item.get('atpnWarnQesitm', '정보 없음')  # 주의사항 경고
                )
                results.append(drug_info)

            return results