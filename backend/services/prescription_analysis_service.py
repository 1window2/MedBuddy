# File Name: prescription_analysis_service.py
# Role: Coordinates prescription image preprocessing, Gemini extraction, and masking.

import json
import logging
import re
from typing import Optional

from google import genai
from google.genai import types

from core.config import settings
from schemas.ocr import PrescriptionData
from utils.image_processing import preprocess_prescription_image

logger = logging.getLogger(__name__)


# Class Name: PrescriptionJsonCleaner
# Role: Cleans model responses before JSON decoding.
# Responsibilities:
#   - Remove markdown code fences from Gemini responses.
class PrescriptionJsonCleaner:
    # Function Name: clean
    # Description:
    # - Removes markdown fences and surrounding whitespace from model output.
    # Parameters:
    # - response_text: Raw Gemini response text.
    # Returns:
    # - JSON-only string.
    def clean(self, response_text: str) -> str:
        cleaned_text = response_text.strip()
        if cleaned_text.startswith("```json"):
            cleaned_text = cleaned_text[7:]
        if cleaned_text.startswith("```"):
            cleaned_text = cleaned_text[3:]
        if cleaned_text.endswith("```"):
            cleaned_text = cleaned_text[:-3]
        return cleaned_text.strip()


# Class Name: PrescriptionPrivacyMasker
# Role: Applies secondary privacy masking to extracted prescription data.
# Responsibilities:
#   - Mask resident registration numbers that survived model-level masking.
class PrescriptionPrivacyMasker:
    _RRN_PATTERN = re.compile(r"(\d{6})[-]\d{7}")

    # Function Name: apply
    # Description:
    # - Applies regex-based secondary masking to structured prescription data.
    # Parameters:
    # - data: Decoded prescription dictionary.
    # Returns:
    # - Masked prescription dictionary.
    def apply(self, data: dict) -> dict:
        data_str = json.dumps(data, ensure_ascii=False)
        data_str = self._RRN_PATTERN.sub(r"\1-*******", data_str)
        return json.loads(data_str)


# Class Name: GeminiPrescriptionVisionClient
# Role: Boundary adapter for Gemini Vision prescription extraction.
# Responsibilities:
#   - Send preprocessed prescription images to Gemini.
#   - Request a PrescriptionData-shaped JSON response.
# Attributes:
#   - client: Gemini client.
#   - model_name: Gemini model name.
class GeminiPrescriptionVisionClient:
    def __init__(
        self,
        client: Optional[genai.Client] = None,
        model_name: str = "gemini-3.1-flash-lite",
    ) -> None:
        self.client = client or genai.Client(
            api_key=settings.GEMINI_API_KEY,
            http_options={"api_version": "v1alpha"},
        )
        self.model_name = model_name

    # Function Name: extract
    # Description:
    # - Calls Gemini Vision with an image and strict JSON extraction prompt.
    # Parameters:
    # - processed_image: Preprocessed image bytes.
    # Returns:
    # - Raw Gemini text response.
    async def extract(self, processed_image: bytes) -> str:
        image_part = types.Part.from_bytes(
            data=processed_image,
            mime_type="image/jpeg",
        )
        prompt = """
        당신은 한국의 의료 데이터 추출 전문가입니다.
        첨부된 약봉투 또는 처방전 이미지에서 다음 정보만 정확하게 추출하세요.

        [데이터 보정 규칙]
        - 약품 이름(drug_name) 추출 시, 이미지의 글자가 흐릿하여 오타로 보이더라도, 문맥을 파악하여 실제 한국에서 유통되는 정확한 의약품 명칭으로 자동 교정해서 추출하세요.

        [보안 규칙]
        - 환자 이름은 가운데 글자를 마스킹하세요 (예: 홍길동 -> 홍*동)
        - 주민등록번호가 있다면 뒷자리를 마스킹하세요 (예: [RRN Omitted])
        - 상세 주소가 있다면 동 단위까지만 남기고 나머지는 마스킹하세요.

        반드시 결과만 JSON 형식으로 출력하세요. 추가적인 설명은 절대 하지 마세요.
        """

        response = await self.client.aio.models.generate_content(
            model=self.model_name,
            contents=[prompt, image_part],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=PrescriptionData,
                temperature=0.0,
            ),
        )
        return response.text


# Class Name: InputPrescription
# Role: Control class for prescription image analysis.
# Responsibilities:
#   - Preprocess prescription image bytes.
#   - Extract structured prescription data through Gemini Vision.
#   - Clean, decode, mask, and validate the result as PrescriptionData.
# Attributes:
#   - vision_client: GeminiPrescriptionVisionClient used for extraction.
#   - json_cleaner: PrescriptionJsonCleaner used before JSON decoding.
#   - privacy_masker: PrescriptionPrivacyMasker used after decoding.
class InputPrescription:
    def __init__(
        self,
        vision_client: Optional[GeminiPrescriptionVisionClient] = None,
        json_cleaner: Optional[PrescriptionJsonCleaner] = None,
        privacy_masker: Optional[PrescriptionPrivacyMasker] = None,
    ) -> None:
        self.vision_client = vision_client or GeminiPrescriptionVisionClient()
        self.json_cleaner = json_cleaner or PrescriptionJsonCleaner()
        self.privacy_masker = privacy_masker or PrescriptionPrivacyMasker()

    # Function Name: request_prescription_image
    # Description:
    # - Runs the full prescription image analysis pipeline.
    # Parameters:
    # - image_bytes: Raw image bytes uploaded by the frontend.
    # Returns:
    # - Validated PrescriptionData DTO.
    async def request_prescription_image(self, image_bytes: bytes) -> PrescriptionData:
        processed_image = preprocess_prescription_image(image_bytes)
        response_text = await self.vision_client.extract(processed_image)
        cleaned_text = self.json_cleaner.clean(response_text)

        try:
            raw_data = json.loads(cleaned_text)
        except json.JSONDecodeError as exc:
            logger.error("JSON 파싱 에러. Gemini 원본 응답:\n%s", response_text)
            raise ValueError("AI가 올바른 JSON 형식을 반환하지 않았습니다.") from exc

        safe_data = self.privacy_masker.apply(raw_data)
        return PrescriptionData(**safe_data)
