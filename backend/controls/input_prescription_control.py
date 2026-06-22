# File Name: input_prescription_control.py
# Role: Control class for prescription image analysis.

import json
import logging
import re
from typing import Any

from google import genai
from google.genai import types

from core.config import settings
from entities.medication_schedule_entity import MedicationSchedule
from utils.image_processing import preprocess_prescription_image

logger = logging.getLogger(__name__)


# Class Name: InputPrescription
# Role: Coordinates prescription image preprocessing and structured extraction.
# Responsibilities:
#   - Preprocess prescription image bytes.
#   - Request structured prescription extraction from Gemini Vision.
#   - Clean, decode, mask, and validate extracted prescription data.
# Attributes:
#   - client: Gemini client used for prescription image analysis.
#   - model_name: Gemini model name.
class InputPrescription:
    _RRN_PATTERN = re.compile(r"(\d{6})[-]\d{7}")
    _PRESCRIPTION_RESPONSE_SCHEMA = {
        "type": "OBJECT",
        "required": ["hospital_name", "prescription_date", "medications"],
        "properties": {
            "hospital_name": {
                "type": "STRING",
                "description": "Hospital or pharmacy name. Use '정보 없음' when unavailable.",
            },
            "prescription_date": {
                "type": "STRING",
                "description": "약봉투나 처방전에 적힌 조제일자 또는 처방일자를 YYYY-MM-DD 형식으로 추출한다. 없으면 '정보 없음'을 사용한다.",
            },
            "medications": {
                "type": "ARRAY",
                "description": "Extracted medication list.",
                "items": {
                    "type": "OBJECT",
                    "required": [
                        "drug_name",
                        "dosage_per_time",
                        "daily_frequency",
                        "total_days",
                    ],
                    "properties": {
                        "drug_name": {
                            "type": "STRING",
                            "description": "약품명",
                        },
                        "dosage_per_time": {
                            "type": "STRING",
                            "description": "Dose per administration, for example '1정'.",
                        },
                        "daily_frequency": {
                            "type": "STRING",
                            "description": "Daily frequency, for example '3회'.",
                        },
                        "total_days": {
                            "type": "STRING",
                            "description": "Total duration, for example '7일'.",
                        },
                    },
                },
            },
        },
    }

    def __init__(
        self,
        client: genai.Client | None = None,
        model_name: str = "gemini-3.1-flash-lite",
    ) -> None:
        self.client = client or genai.Client(
            api_key=settings.GEMINI_API_KEY,
            http_options={"api_version": "v1alpha"},
        )
        self.model_name = model_name

    # Function Name: request_prescription_image
    # Description:
    # - Runs the full prescription image analysis pipeline.
    # Parameters:
    # - image_bytes: Raw image bytes uploaded by the frontend.
    # Returns:
    # - API-compatible dictionary containing medication schedule data.
    async def request_prescription_image(self, image_bytes: bytes) -> dict[str, object]:
        processed_image = preprocess_prescription_image(image_bytes)
        response_text = await self._extract_prescription_text(processed_image)
        cleaned_text = self._clean_response_text(response_text)

        try:
            raw_data = json.loads(cleaned_text)
        except json.JSONDecodeError as exc:
            logger.error("Prescription analysis JSON decoding failed:\n%s", response_text)
            raise ValueError("AI returned an invalid JSON response.") from exc

        safe_data = self._apply_secondary_masking(raw_data)
        prescription_date = safe_data.get("prescription_date", "정보 없음")
        medication_schedules = [
            self._to_prescription_medication_payload(
                MedicationSchedule(**item).getAnalysisResult(),
                prescription_date,
            )
            for item in safe_data.get("medications", [])
        ]
        return {
            "hospital_name": safe_data.get("hospital_name", "정보 없음"),
            "prescription_date": prescription_date,
            "medications": medication_schedules,
        }

    # Function Name: requestPrescriptionImage
    # Description:
    # - Class diagram compatible wrapper for request_prescription_image.
    # Parameters:
    # - image_bytes: Raw image bytes uploaded by the frontend.
    # Returns:
    # - API-compatible prescription analysis dictionary.
    async def requestPrescriptionImage(self, image_bytes: bytes) -> dict[str, object]:
        return await self.request_prescription_image(image_bytes)

    # Function Name: _extract_prescription_text
    # Description:
    # - Calls Gemini Vision with an image and strict JSON extraction prompt.
    # Parameters:
    # - processed_image: Preprocessed image bytes.
    # Returns:
    # - Raw Gemini text response.
    async def _extract_prescription_text(self, processed_image: bytes) -> str:
        image_part = types.Part.from_bytes(
            data=processed_image,
            mime_type="image/jpeg",
        )
        prompt = """
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
        response = await self.client.aio.models.generate_content(
            model=self.model_name,
            contents=[prompt, image_part],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=self._PRESCRIPTION_RESPONSE_SCHEMA,
                temperature=0.0,
            ),
        )
        return response.text

    # Function Name: _clean_response_text
    # Description:
    # - Removes markdown fences and surrounding whitespace from model output.
    # Parameters:
    # - response_text: Raw Gemini response text.
    # Returns:
    # - JSON-only string.
    def _clean_response_text(self, response_text: str) -> str:
        cleaned_text = response_text.strip()
        if cleaned_text.startswith("```json"):
            cleaned_text = cleaned_text[7:]
        if cleaned_text.startswith("```"):
            cleaned_text = cleaned_text[3:]
        if cleaned_text.endswith("```"):
            cleaned_text = cleaned_text[:-3]
        return cleaned_text.strip()

    # Function Name: _apply_secondary_masking
    # Description:
    # - Applies regex-based secondary masking to structured prescription data.
    # Parameters:
    # - data: Decoded prescription dictionary.
    # Returns:
    # - Masked prescription dictionary.
    def _apply_secondary_masking(self, data: dict[str, Any]) -> dict[str, Any]:
        data_str = json.dumps(data, ensure_ascii=False)
        data_str = self._RRN_PATTERN.sub(r"\1-*******", data_str)
        return json.loads(data_str)

    # Function Name: _to_prescription_medication_payload
    # Description:
    # - Converts a MedicationSchedule entity into the API payload expected by
    #   the current Flutter analysis-result flow.
    # Parameters:
    # - medication_schedule: Validated MedicationSchedule entity.
    # Returns:
    # - Dictionary containing only prescription-analysis response fields.
    def _to_prescription_medication_payload(
        self,
        medication_schedule: MedicationSchedule,
        prescription_date: str,
    ) -> dict[str, str]:
        return {
            "prescription_date": prescription_date,
            "drug_name": medication_schedule.medication_name,
            "dosage_per_time": medication_schedule.dosage,
            "daily_frequency": medication_schedule.intake_time,
            "total_days": medication_schedule.medication_time,
        }
