# File Name: prescription_ocr_boundary.py
# Role: Boundary classes for prescription OCR extraction.

from typing import Any

from google import genai
from google.genai import types

from utils.image_processing import preprocess_prescription_image


class ImageProcessingBoundary:
    # Function Name: preprocessPrescriptionImage
    # Description:
    # - Class-diagram boundary for OCR image preprocessing.
    def preprocessPrescriptionImage(self, image: bytes) -> bytes:
        return preprocess_prescription_image(image)


class GeminiVisionAPI:
    # Function Name: requestStructuredExtraction
    # Description:
    # - Class-diagram boundary for Gemini Vision structured OCR extraction.
    async def requestStructuredExtraction(
        self,
        *,
        client: genai.Client,
        model_name: str,
        prompt: str,
        processed_image: bytes,
        response_schema: dict[str, Any],
    ) -> str:
        image_part = types.Part.from_bytes(
            data=processed_image,
            mime_type="image/jpeg",
        )
        response = await client.aio.models.generate_content(
            model=model_name,
            contents=[prompt, image_part],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=response_schema,
                temperature=0.0,
            ),
        )
        response_text = response.text
        if not response_text or not response_text.strip():
            raise ValueError("OCR service returned an empty response.")
        return response_text


class OCRServiceBoundary:
    def __init__(
        self,
        *,
        client: genai.Client,
        model_name: str,
        response_schema: dict[str, Any],
        image_processing_boundary: ImageProcessingBoundary | None = None,
        gemini_vision_api: GeminiVisionAPI | None = None,
    ) -> None:
        self.client = client
        self.model_name = model_name
        self.response_schema = response_schema
        self.image_processing_boundary = (
            image_processing_boundary or ImageProcessingBoundary()
        )
        self.gemini_vision_api = gemini_vision_api or GeminiVisionAPI()

    # Function Name: extractText
    # Description:
    # - Coordinates preprocessing and Gemini Vision extraction.
    async def extractText(self, image: bytes) -> str:
        processed_image = self.image_processing_boundary.preprocessPrescriptionImage(
            image
        )
        return await self.gemini_vision_api.requestStructuredExtraction(
            client=self.client,
            model_name=self.model_name,
            prompt=self._prescription_extraction_prompt(),
            processed_image=processed_image,
            response_schema=self.response_schema,
        )

    # Function Name: extractPrescriptionData
    # Description:
    # - Class-diagram compatible alias for the OCR extraction boundary.
    async def extractPrescriptionData(self, image: bytes) -> str:
        return await self.extractText(image)

    @staticmethod
    def _prescription_extraction_prompt() -> str:
        return """
        당신은 한국어 의료 데이터 추출 전문가입니다.
        첨부된 약봉투 또는 처방전 이미지에서 조제일자, 약품명, 1회 복용량,
        1일 복용 횟수, 총 복용 일수를 정확히 추출하세요.

        추출 규칙:
        1. 조제일자, 조제일, 처방일자, 처방일처럼 표시된 날짜를 prescription_date에 넣으세요.
        2. 표 또는 목록에 있는 약품 행을 위에서 아래로 모두 읽고 생략하지 마세요.
        3. 약품명 열의 텍스트만 drug_name에 넣고, 효능/제조원/복약 안내 문구는 제외하세요.
        4. 약품명이 여러 줄로 보이면 하나의 약품명으로 이어 붙이세요.
        5. 괄호 안 성분명이 보이면 제품명 뒤에 그대로 포함하세요.
        6. 1회 투약량, 1일 횟수, 총 일수는 같은 행의 숫자 열과 정확히 매칭하세요.
        7. 에/애, 레/래처럼 헷갈리는 한글은 임의로 삭제하지 말고 보이는 글자를 보존하세요.
        8. 읽기 어려운 약품도 누락하지 말고 보이는 범위에서 최대한 drug_name을 채우세요.

        개인정보는 마스킹하고 반드시 JSON 형식만 반환하세요.
        """
