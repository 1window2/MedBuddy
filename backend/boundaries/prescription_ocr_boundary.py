# File Name: prescription_ocr_boundary.py
# Role: Boundary classes for prescription OCR extraction.

import asyncio
import logging
import time
from typing import Any

from google import genai
from google.genai import types

from utils.image_processing import preprocess_prescription_image

logger = logging.getLogger(__name__)


class PrescriptionImageProcessor:
    # Function Name: preprocess_prescription_image
    # Description:
    # - Class-diagram boundary for OCR image preprocessing.
    def preprocess_prescription_image(self, image: bytes) -> bytes:
        return preprocess_prescription_image(image)


class GeminiVisionClient:
    # Function Name: generate_content
    # Description:
    # - Class-diagram boundary for Gemini Vision structured OCR extraction.
    async def generate_content(
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
                thinking_config=types.ThinkingConfig(
                    thinking_level=types.ThinkingLevel.MINIMAL,
                ),
                media_resolution=types.MediaResolution.MEDIA_RESOLUTION_HIGH,
                max_output_tokens=2048,
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
        prescription_image_processor: PrescriptionImageProcessor | None = None,
        gemini_vision_client: GeminiVisionClient | None = None,
        request_timeout_seconds: float = 30.0,
    ) -> None:
        if request_timeout_seconds <= 0:
            raise ValueError("OCR request timeout must be greater than zero.")
        self.client = client
        self.model_name = model_name
        self.response_schema = response_schema
        self.request_timeout_seconds = request_timeout_seconds
        self.prescription_image_processor = (
            prescription_image_processor or PrescriptionImageProcessor()
        )
        self.gemini_vision_client = gemini_vision_client or GeminiVisionClient()

    # Function Name: extractPrescriptionData
    # Description:
    # - Coordinates preprocessing and Gemini Vision extraction.
    async def extractPrescriptionData(self, image: bytes) -> str:
        preprocessing_started_at = time.perf_counter()
        processed_image = await asyncio.to_thread(
            self.prescription_image_processor.preprocess_prescription_image,
            image,
        )
        preprocessing_seconds = time.perf_counter() - preprocessing_started_at
        extraction_started_at = time.perf_counter()
        try:
            response = await asyncio.wait_for(
                self.gemini_vision_client.generate_content(
                    client=self.client,
                    model_name=self.model_name,
                    prompt=self._prescription_extraction_prompt(),
                    processed_image=processed_image,
                    response_schema=self.response_schema,
                ),
                timeout=self.request_timeout_seconds,
            )
        except TimeoutError as exc:
            raise TimeoutError("Prescription OCR service timed out.") from exc

        logger.info(
            "Prescription OCR completed: model=%s, input_bytes=%d, "
            "processed_bytes=%d, preprocessing_seconds=%.2f, "
            "extraction_seconds=%.2f",
            self.model_name,
            len(image),
            len(processed_image),
            preprocessing_seconds,
            time.perf_counter() - extraction_started_at,
        )
        return response

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
