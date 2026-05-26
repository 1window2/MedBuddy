# File Name: drug_guide_service.py
# Role: Generates patient-facing medication guidance with Gemini.

import json
import logging
from typing import Optional

from fastapi import HTTPException
from google import genai

from core.config import settings
from schemas.medication import MedicationDetail

logger = logging.getLogger(__name__)


# Class Name: DrugGuideService
# Role: Boundary adapter for Gemini text generation used in medication guidance.
# Responsibilities:
#   - Generate a patient-facing guide for basic public API drug data.
#   - Summarize advanced approval documents into MedicationDetail.
# Attributes:
#   - ai_client: Gemini client.
#   - model_name: Gemini model name.
class DrugGuideService:
    def __init__(
        self,
        ai_client: Optional[genai.Client] = None,
        model_name: str = "gemini-3.1-flash-lite",
    ) -> None:
        self.ai_client = ai_client or genai.Client(api_key=settings.GEMINI_API_KEY)
        self.model_name = model_name

    # Function Name: add_basic_guide
    # Description:
    # - Adds an AI guide to a MedicationDetail built from the basic public API.
    # - On Gemini failure, keeps the medication result and inserts a fallback message.
    # Parameters:
    # - medication_detail: MedicationDetail that needs an ai_guide.
    # Returns:
    # - MedicationDetail with ai_guide populated.
    async def add_basic_guide(
        self,
        medication_detail: MedicationDetail,
    ) -> MedicationDetail:
        if medication_detail.ai_guide:
            return medication_detail

        raw_data = (
            f"효능: {medication_detail.efficacy}\n"
            f"사용법: {medication_detail.use_method}\n"
            f"주의사항: {medication_detail.warning_message}"
        )
        prompt = f"""
        당신은 환자가 이해하기 쉬운 복약 정보를 제공하는 AI 약사입니다.
        다음 식약처 약품 설명서를 일반 사용자가 이해할 수 있도록 정리해 주세요.
        {raw_data}

        작성 규칙:
        1. 핵심 효능과 복용법을 1~2줄로 요약합니다.
        2. 주의해야 할 부작용 또는 복약 주의사항을 명확히 안내합니다.
        3. 전문성을 유지하되 부드러운 존댓말을 사용합니다.
        """

        try:
            ai_response = await self.ai_client.aio.models.generate_content(
                model=self.model_name,
                contents=prompt,
            )
            medication_detail.ai_guide = ai_response.text
        except Exception as exc:
            logger.error("Gemini API 호출 에러: %s", exc)
            medication_detail.ai_guide = "AI 요약을 불러오는 중 일시적인 오류가 발생했습니다."

        return medication_detail

    # Function Name: summarize_advanced_item
    # Description:
    # - Converts advanced approval API raw documents into patient-facing MedicationDetail.
    # Parameters:
    # - drug_name: Original search keyword.
    # - advanced_item: Raw item from the advanced public API.
    # Returns:
    # - MedicationDetail generated from Gemini summary output.
    async def summarize_advanced_item(
        self,
        drug_name: str,
        advanced_item: dict,
    ) -> MedicationDetail:
        actual_item_name = advanced_item.get("ITEM_NAME", drug_name)
        raw_efficacy = str(advanced_item.get("EE_DOC_DATA", "정보 없음"))[:2000]
        raw_usage = str(advanced_item.get("UD_DOC_DATA", "정보 없음"))[:2000]
        raw_warning = str(advanced_item.get("NB_DOC_DATA", "정보 없음"))[:2000]

        prompt = f"""
        당신은 복약 정보를 환자에게 설명하는 약사입니다. 아래는 식약처의 전문가용 의약품 허가 정보 원문입니다.
        일반 환자가 이해하기 쉽게 각 항목을 2~3문장 이내로 명확하게 요약해 주세요.
        반드시 아래의 4가지 키 (key)를 가진 JSON 형식으로만 답변해 주세요.

        {{
            "efficacy": "요약된 효능",
            "use_method": "요약된 용법",
            "warning_message": "요약된 주의사항",
            "ai_guide": "전문성을 유지하되 부드러운 존댓말로 작성한 전체 복약 가이드 2줄 요약"
        }}

        [원문 데이터]
        - 효능: {raw_efficacy}
        - 용법: {raw_usage}
        - 주의: {raw_warning}
        """

        logger.info("[Gemini] '%s' 허가정보 AI 요약 요청 중...", actual_item_name)

        try:
            ai_response = await self.ai_client.aio.models.generate_content(
                model=self.model_name,
                contents=prompt,
                config={"response_mime_type": "application/json"},
            )
            summary_data = json.loads(ai_response.text)
        except Exception as exc:
            logger.error("Gemini AI 요약 처리 실패: %s", exc)
            raise HTTPException(
                status_code=500,
                detail="AI 요약 처리 중 오류가 발생했습니다.",
            ) from exc

        return MedicationDetail(
            item_name=actual_item_name,
            efficacy=summary_data.get("efficacy", "요약 실패"),
            use_method=summary_data.get("use_method", "요약 실패"),
            warning_message=summary_data.get("warning_message", "요약 실패"),
            source="Advanced (허가정보) + AI 요약",
            ai_guide=summary_data.get("ai_guide", "요약 실패"),
        )
