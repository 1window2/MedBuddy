# File Name: medication_summary_boundary.py
# Role: Maps optional medication-detail text and requests bounded summaries of public approval documents.

import asyncio
import json
import logging
import math
from typing import Any

from google import genai

from boundaries.public_drug_api_boundary import (
    read_public_image_url,
    read_public_item_name,
    read_public_item_sequence,
)
from core.config import settings
from entities.medication_detail_entity import MedicationDetail

logger = logging.getLogger(__name__)

# Text earlier versions wrote into a summary field the AI had not returned. The generator no
# longer writes it; the detail cache treats a stored snapshot that still holds it as a miss.
FAILED_SUMMARY_TEXT = "요약 실패"

# Display text of a detail field without content. A summary field the AI left out reads this.
MISSING_DETAIL_TEXT = "정보 없음"


# 함수이름: read_medication_detail_text
# 함수역할:
# - 값을 문자열로 정리하고 None 또는 공백뿐인 값에는 표시용 기본 문구를 적용한다.
# 매개변수:
# - value (Any): 공공 약품 필드의 원본 값.
# - default (str): 값이 없거나 비었을 때 표시할 대체 문구.
# 반환값:
# - 공백을 제거한 문자열 또는 default.
def read_medication_detail_text(value: Any, default: str = MISSING_DETAIL_TEXT) -> str:
    if value is None:
        return default

    text = str(value).strip()
    return text if text else default


# Class Name: MedicationSummaryGenerator
# Role:
# - Produces patient-facing summaries from detailed drug-approval documents through a bounded AI request.
# Responsibilities:
# - Summarize advanced approval documents into MedicationDetail fields.
# Attributes:
# - ai_client (genai.Client): Gemini client for bounded external text generation.
# - model_name (str): Configured AI model identifier.
class MedicationSummaryGenerator:
    # Function Name: __init__
    # Description:
    # - Validates a finite positive summary timeout and binds the AI client and model.
    # Parameters:
    # - ai_client (genai.Client | None): Gemini client for bounded external text generation.
    # - model_name (str): Configured AI model identifier.
    # - timeout_seconds (float | None): Maximum allowed external operation duration in seconds.
    # Returns:
    # - None.
    def __init__(
        self,
        ai_client: genai.Client | None = None,
        model_name: str = "gemini-3.1-flash-lite",
        timeout_seconds: float | None = None,
    ) -> None:
        resolved_timeout = (
            timeout_seconds
            if timeout_seconds is not None
            else settings.MEDICATION_SUMMARY_TIMEOUT_SECONDS
        )
        if not math.isfinite(resolved_timeout) or resolved_timeout <= 0:
            raise ValueError(
                "Medication summary timeout must be finite and positive."
            )
        self.ai_client = ai_client or genai.Client(api_key=settings.GEMINI_API_KEY)
        self.model_name = model_name
        self.timeout_seconds = resolved_timeout

    # Function Name: summarize_advanced_item
    # Description:
    # - Converts advanced approval API raw documents into patient-facing MedicationDetail.
    # - An answer that is not a JSON object or has none of the three summaries is a failed
    #   request, never a result; when only one or two are missing, those read "정보 없음".
    # Parameters:
    # - drug_name (str): Original search keyword; names the product only when the item has no name.
    # - advanced_item (dict[str, Any]): Raw item from the advanced public API or local approval DB.
    # Returns:
    # - MedicationDetail generated from Gemini summary output; raises RuntimeError for a timeout,
    #   a failed request or an unusable answer.
    async def summarize_advanced_item(
        self,
        drug_name: str,
        advanced_item: dict[str, Any],
    ) -> MedicationDetail:
        actual_item_name = read_public_item_name(advanced_item) or drug_name
        raw_efficacy = read_medication_detail_text(advanced_item.get("EE_DOC_DATA"))[:2000]
        raw_usage = read_medication_detail_text(advanced_item.get("UD_DOC_DATA"))[:2000]
        raw_warning = read_medication_detail_text(advanced_item.get("NB_DOC_DATA"))[:2000]

        prompt = f"""
        당신은 복약 정보를 환자에게 설명하는 AI 약사입니다.
        아래는 식약처 허가 정보 원문입니다.
        일반 환자가 이해하기 쉽게 각 항목을 2~3문장 이내로 명확하게 요약해 주세요.
        반드시 아래 3가지 키를 가진 JSON 형식으로만 응답해 주세요.

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

        logger.info("[Gemini] requesting advanced approval summary.")

        try:
            ai_response = await asyncio.wait_for(
                self.ai_client.aio.models.generate_content(
                    model=self.model_name,
                    contents=prompt,
                    config={"response_mime_type": "application/json"},
                ),
                timeout=self.timeout_seconds,
            )
            summary_data = json.loads(ai_response.text)
            if not isinstance(summary_data, dict):
                raise ValueError("Medication summary is not a JSON object.")
            efficacy = read_medication_detail_text(summary_data.get("efficacy"), "")
            usage_method = read_medication_detail_text(summary_data.get("use_method"), "")
            warning = read_medication_detail_text(summary_data.get("warning_message"), "")
            if not (efficacy or usage_method or warning):
                raise ValueError("Medication summary has no summary text.")
        except TimeoutError as exc:
            logger.warning("Gemini medication summary timed out.")
            raise RuntimeError("Medication summary generation timed out.") from exc
        except Exception as exc:
            logger.error("Gemini AI summary failed: %s", type(exc).__name__)
            raise RuntimeError("AI 요약 처리 중 오류가 발생했습니다.") from exc

        return MedicationDetail(
            item_seq=read_public_item_sequence(advanced_item),
            item_name=actual_item_name,
            manufacturer=read_medication_detail_text(advanced_item.get("ENTP_NAME") or advanced_item.get("entpName")),
            efficacy=read_medication_detail_text(efficacy),
            usage_method=read_medication_detail_text(usage_method),
            warning=read_medication_detail_text(warning),
            image_url=read_public_image_url(advanced_item),
            source="Advanced (허가정보) + AI 요약",
            ai_guide="",
        )
