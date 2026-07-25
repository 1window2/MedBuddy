# 파일명: prescription_ocr_boundary.py
# 역할: 처방전 이미지 전처리와 Gemini OCR 요청 경계를 정의한다.

import asyncio
import logging
import time
from typing import Any

from google import genai
from google.genai import types

from utils.image_processing import preprocess_prescription_image

logger = logging.getLogger(__name__)


# 클래스명: PrescriptionImageProcessor
# 역할: OCR 입력 이미지 전처리 함수를 제어 계층에 제공한다.
# 주요 책임:
# - 원본 이미지의 촬영 방향을 보정하고 OCR용 이미지로 변환한다.
class PrescriptionImageProcessor:
    # 함수이름: preprocess_prescription_image
    # 함수역할:
    # - 원본 이미지 바이트를 OCR에 적합한 이미지 바이트로 전처리한다.
    # 매개변수:
    # - image: 사용자가 촬영하거나 선택한 원본 이미지 바이트
    # 반환값:
    # - 방향 보정과 이진화를 마친 JPEG 이미지 바이트
    def preprocess_prescription_image(self, image: bytes) -> bytes:
        return preprocess_prescription_image(image)


# 클래스명: GeminiVisionClient
# 역할: 전처리된 처방전 이미지를 Gemini Vision에 전달한다.
# 주요 책임:
# - OCR 요청 형식과 응답 스키마를 구성한다.
# - 비어 있는 OCR 응답을 오류로 변환한다.
class GeminiVisionClient:
    # 함수이름: generate_content
    # 함수역할:
    # - 전처리 이미지에서 구조화된 처방 정보를 추출하도록 Gemini에 요청한다.
    # 매개변수:
    # - client: Gemini API 클라이언트
    # - model_name: OCR에 사용할 Gemini 모델명
    # - prompt: 처방전 추출 지시문
    # - processed_image: 전처리된 처방전 이미지 바이트
    # - response_schema: 구조화 응답 JSON 스키마
    # 반환값:
    # - Gemini가 반환한 JSON 문자열
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


# 클래스명: OCRServiceBoundary
# 역할: 처방전 OCR 전처리와 Gemini 추출 흐름을 조정한다.
# 주요 책임:
# - 이미지 전처리를 별도 작업 스레드에서 실행한다.
# - OCR 요청 시간 제한과 처리 시간을 관리한다.
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

    # 함수이름: extractPrescriptionData
    # 함수역할:
    # - 이미지 전처리와 Gemini Vision 추출을 순서대로 수행한다.
    # 매개변수:
    # - image: 사용자가 입력한 처방전 이미지 바이트
    # 반환값:
    # - 구조화된 처방 정보 JSON 문자열
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
        9. 조제일자 글자와 각 drug_name 글자, 환자 민감정보의 위치를
           recognized_regions에 넣으세요.
           box_2d는 [ymin, xmin, ymax, xmax] 순서이며 이미지 전체를 0~1000으로 정규화한 정수 좌표입니다.
        10. recognized_regions의 category는 prescription_date, medication_name,
            sensitive_info 중 하나만 사용하세요.
        11. medication_name의 box_2d는 약품 행 전체가 아니라 drug_name으로
            추출한 글자만 여백 없이 최대한 촘촘하게 감싸야 합니다.
            효능 문구, 약품 사진, 투약량·횟수·일수 열은 포함하지 마세요.
        12. 환자명, 주민등록번호, 생년월일, 전화번호, 주소, 환자번호처럼
            개인을 식별할 수 있는 모든 영역은 sensitive_info로 분류하세요.
            sensitive_info의 text는 실제 문구를 적지 말고 반드시 빈 문자열로 반환하세요.

        개인정보는 마스킹하고 반드시 JSON 형식만 반환하세요.
        """
