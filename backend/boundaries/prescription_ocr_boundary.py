# 파일명: prescription_ocr_boundary.py
# 역할: 기기에서 비식별 처리한 처방전 텍스트의 Gemini 구조화 경계를 정의한다.

import asyncio
import logging
import time
from typing import Any

from google import genai
from google.genai import types

logger = logging.getLogger(__name__)

# 클래스명: GeminiPrescriptionTextClient
# 역할: 비식별 처방전 OCR 텍스트를 Gemini에 전달한다.
# 주요 책임:
# - 텍스트 구조화 요청 형식과 응답 스키마를 구성한다.
# - 비어 있는 응답을 오류로 변환한다.
class GeminiPrescriptionTextClient:
    # 함수명: generate_text_content
    # 역할:
    # - 기기에서 개인정보를 제거한 OCR 텍스트를 구조화된 처방 정보로 변환한다.
    # 매개변수:
    # - client: Gemini API 클라이언트
    # - model_name: 구조화 분석에 사용할 Gemini 모델명
    # - prompt: 처방전 추출 지시문
    # - masked_text: 기기에서 민감정보를 제거한 OCR 텍스트
    # - response_schema: 구조화 응답 JSON 스키마
    # 반환값:
    # - Gemini가 반환한 JSON 문자열
    async def generate_text_content(
        self,
        *,
        client: genai.Client,
        model_name: str,
        prompt: str,
        masked_text: str,
        response_schema: dict[str, Any],
    ) -> str:
        response = await client.aio.models.generate_content(
            model=model_name,
            contents=[prompt, masked_text],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=response_schema,
                temperature=0.0,
                thinking_config=types.ThinkingConfig(
                    thinking_level=types.ThinkingLevel.MINIMAL,
                ),
                max_output_tokens=2048,
            ),
        )
        response_text = response.text
        if not response_text or not response_text.strip():
            raise ValueError("OCR text service returned an empty response.")
        return response_text


# 클래스명: OCRServiceBoundary
# 역할: 비식별 처방전 텍스트의 Gemini 구조화 흐름을 조정한다.
# 주요 책임:
# - 원본 이미지가 이 경계를 통과하지 않도록 텍스트 입력만 허용한다.
# - 구조화 요청 시간 제한과 처리 시간을 관리한다.
class OCRServiceBoundary:
    def __init__(
        self,
        *,
        client: genai.Client,
        model_name: str,
        response_schema: dict[str, Any],
        gemini_text_client: GeminiPrescriptionTextClient | None = None,
        request_timeout_seconds: float = 30.0,
    ) -> None:
        if request_timeout_seconds <= 0:
            raise ValueError("OCR request timeout must be greater than zero.")
        self.client = client
        self.model_name = model_name
        self.response_schema = response_schema
        self.request_timeout_seconds = request_timeout_seconds
        self.gemini_text_client = (
            gemini_text_client or GeminiPrescriptionTextClient()
        )

    # 함수명: extractPrescriptionTextData
    # 역할:
    # - 기기에서 비식별 처리한 OCR 텍스트만 Gemini 구조화 분석에 전달한다.
    # 매개변수:
    # - masked_text: 환자 식별정보가 제거된 처방전 OCR 텍스트
    # 반환값:
    # - 구조화된 처방 정보 JSON 문자열
    async def extractPrescriptionTextData(self, masked_text: str) -> str:
        normalized_text = masked_text.strip()
        if not normalized_text:
            raise ValueError("Masked prescription text is empty.")
        extraction_started_at = time.perf_counter()
        try:
            response = await asyncio.wait_for(
                self.gemini_text_client.generate_text_content(
                    client=self.client,
                    model_name=self.model_name,
                    prompt=self._masked_text_extraction_prompt(),
                    masked_text=normalized_text,
                    response_schema=self.response_schema,
                ),
                timeout=self.request_timeout_seconds,
            )
        except TimeoutError as exc:
            raise TimeoutError("Prescription OCR text service timed out.") from exc
        logger.info(
            "De-identified prescription text analysis completed: "
            "input_characters=%d, extraction_seconds=%.2f",
            len(normalized_text),
            time.perf_counter() - extraction_started_at,
        )
        return response

    @staticmethod
    def _masked_text_extraction_prompt() -> str:
        return """
        당신은 한국어 처방전 OCR 텍스트 구조화 전문가입니다.
        다음 입력은 사용자의 기기에서 OCR한 뒤 환자 식별정보를 제거한 텍스트입니다.
        원본 이미지나 제거된 개인정보를 추측하지 말고, 입력에 남은 복약 정보만 사용하세요.

        추출 규칙:
        1. 조제일자, 조제일, 처방일자, 처방일에 해당하는 날짜를 prescription_date에 넣으세요.
        2. 약품명과 같은 행 또는 가까운 숫자 열의 1회 투약량, 1일 횟수, 총 일수를 연결하세요.
        3. 약품명이 여러 줄로 분리되었으면 문맥에 맞게 이어 붙이되 임의의 약을 만들지 마세요.
        4. 괄호 안 성분명은 보이는 경우에만 제품명 뒤에 포함하세요.
        5. 효능, 제조원, 병원명, 복약 안내 문구는 drug_name에서 제외하세요.
        6. 읽기 어려운 항목도 삭제하지 말고 입력에 보이는 범위에서 최대한 보존하세요.
        7. 반드시 지정된 JSON 스키마로만 반환하세요.
        """
