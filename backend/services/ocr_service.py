#OCR 처리 로직
from typing import List, Dict, Any
from services.prescription_parser import parse_prescription
import json
import re
import google.generativeai as genai
from utils.image_processing import preprocess_prescription_image
from schemas.ocr import PrescriptionData

class OCRService:
    def __init__(self): # 임시 테스트용으로 넣은 모델. 추후 변경
        self.model = genai.GenerativeModel('gemini-1.5-flash')

    def process_text(self, raw_text: str) -> str:
        """
        클라이언트에서 ML Kit로 추출해 보낸 텍스트의 노이즈를 제거하고
        실제 약 이름 후보군만 정제하는 로직이 들어가는 곳이야.
        """
        # 예: "처방전... 타이레놀정 500mg ... 식후 30분" -> "타이레놀" 추출
        refined_keyword = raw_text.replace("\n", " ").strip()
        return refined_keyword

    # 함수명: split_lines
    # 함수역할:
    # - OCR 전체 문자열을 줄 단위 리스트로 분리
    # 변수명: raw_text
    # 변수역할:
    # - 프론트에서 보낸 OCR 전체 문자열
    def split_lines(self, raw_text: str) -> List[str]:
        if not raw_text:
            return []

        # 변수명: lines
        # 변수역할:
        # - 공백 제거 후 남긴 줄 리스트
        lines = [line.strip() for line in raw_text.splitlines()]
        lines = [line for line in lines if line]
        return lines

    # 함수명: parse_prescription_text
    # 함수역할:
    # - OCR 전체 문자열을 줄 단위로 나눈 뒤 prescription_parser로 넘겨
    #   구조화된 JSON(dict) 형태로 반환
    # 변수명: raw_text
    # 변수역할:
    # - 프론트에서 보낸 OCR 전체 문자열
    def parse_prescription_text(self, raw_text: str) -> Dict[str, Any]:
        # 변수명: lines
        # 변수역할:
        # - 줄 단위로 분리된 OCR 텍스트
        lines = self.split_lines(raw_text)

        # 변수명: parsed_result
        # 변수역할:
        # - 파서가 만든 최종 구조화 결과
        parsed_result = parse_prescription(lines)
        return parsed_result
    
    ### 04/07 신규 추가
    async def extract_prescription_data(self, image_bytes: bytes) -> PrescriptionData:
        """전처리된 이미지를 Gemini에 보내서 JSON 데이터로 추출하고 마스킹을 적용합니다."""
        # 1. 이미지 전처리
        processed_image = preprocess_prescription_image(image_bytes)

        image_part = {
            "mime_type": "image/jpeg",
            "data": processed_image
        }

        # 2. 강력한 시스템 프롬프트 (1차 마스킹 명령 포함)
        prompt = """
        당신은 한국의 의료 데이터 추출 전문가입니다. 
        첨부된 약봉투 또는 처방전 이미지에서 다음 정보만 정확하게 추출하세요.
        
        [보안 규칙]
        - 환자 이름은 가운데 글자를 마스킹하세요 (예: 홍길동 -> 홍*동)
        - 주민등록번호가 있다면 뒷자리를 마스킹하세요 (예: 900101-*******)
        - 상세 주소가 있다면 동 단위까지만 남기고 나머지는 마스킹하세요.
        
        반드시 결과만 JSON 형식으로 출력하세요. 추가적인 설명은 절대 하지 마세요.
        """

        # 3. 제미나이 API 호출
        response = await self.model.generate_content_async(
            [prompt, image_part],
            generation_config=genai.GenerationConfig(
                response_mime_type="application/json",
                response_schema=PrescriptionData 
            )
        )

        # 4. JSON 파싱 및 2차 보안 마스킹 적용
        raw_data = json.loads(response.text)
        safe_data = self._apply_secondary_masking(raw_data)

        return PrescriptionData(**safe_data)

    def _apply_secondary_masking(self, data: dict) -> dict:
        """정규식을 활용한 2차 철통 마스킹"""
        data_str = json.dumps(data, ensure_ascii=False)
        # 주민번호 패턴 강제 마스킹
        data_str = re.sub(r'(\d{6})[-]\d{7}', r'\1-*******', data_str)
        return json.loads(data_str)
