"""LLM boundary for medication-aware health recommendations."""

import asyncio
import json
import logging
import math
from typing import Any

from google import genai

from core.config import settings

logger = logging.getLogger(__name__)


class LLMService:
    """UML external service for generating health recommendations."""

    def __init__(
        self,
        ai_client: genai.Client | None = None,
        model_name: str = "gemini-3.1-flash-lite",
        timeout_seconds: float | None = None,
    ) -> None:
        resolved_timeout = (
            timeout_seconds
            if timeout_seconds is not None
            else settings.HEALTH_RECOMMENDATION_TIMEOUT_SECONDS
        )
        if not math.isfinite(resolved_timeout) or resolved_timeout <= 0:
            raise ValueError(
                "Health recommendation timeout must be finite and positive."
            )
        self.ai_client = ai_client or genai.Client(api_key=settings.GEMINI_API_KEY)
        self.model_name = model_name
        self.timeout_seconds = resolved_timeout

    async def requestHealthRecommendation(
        self,
        medication_summaries: list[dict[str, str]],
        language: str = "ko",
    ) -> dict[str, object]:
        prompt = self._build_prompt(medication_summaries, language)
        try:
            ai_response = await asyncio.wait_for(
                self.ai_client.aio.models.generate_content(
                    model=self.model_name,
                    contents=prompt,
                    config={"response_mime_type": "application/json"},
                ),
                timeout=self.timeout_seconds,
            )
            raw_data = json.loads(ai_response.text)
        except TimeoutError as exc:
            logger.warning("Gemini health recommendation timed out.")
            raise RuntimeError("Health recommendation generation timed out.") from exc
        except Exception as exc:
            logger.error(
                "Gemini health recommendation failed: %s",
                type(exc).__name__,
            )
            raise RuntimeError("Health recommendation generation failed.") from exc

        return self._normalize_response(raw_data, language)

    def _build_prompt(
        self,
        medication_summaries: list[dict[str, str]],
        language: str,
    ) -> str:
        medication_json = json.dumps(medication_summaries, ensure_ascii=False)
        if self._is_english(language):
            return f"""
            You are an AI health assistant who gives lifestyle guidance based on
            the user's current medication information.
            Use the medication combination below to provide clear, plain English guidance.

            Rules:
            - Do not diagnose a specific disease.
            - Use cautious wording such as "may be helpful" or "can support".
            - Do not tell the user to stop medication or change dosage.
            - Exclude overly generic habits such as "drink more water" or "sleep regularly".
            - Write only diet recommendation, exercise recommendation, and cautions.
            - Keep each recommendation within 2 sentences.
            - Write 3 to 5 caution bullet items.
            - Return only JSON with the keys below.

            {{
              "diet_recommendation": "Diet recommendation",
              "exercise_recommendation": "Exercise recommendation",
              "caution_items": ["Caution 1", "Caution 2", "Caution 3"]
            }}

            [Current medication information]
            {medication_json}
            """

        return f"""
        당신은 환자의 복약 정보를 바탕으로 생활 관리 팁을 제공하는 AI 건강 도우미입니다.
        아래 약 조합과 복약 정보를 참고해 사용자가 이해하기 쉬운 한국어로 답해 주세요.

        제한 사항:
        - 특정 질병을 확정 진단하지 마세요.
        - "가능성이 있습니다", "관련 관리에 도움이 됩니다"처럼 조심스럽게 표현하세요.
        - 약 복용을 중단하거나 용량을 바꾸라고 안내하지 마세요.
        - 물 많이 마시기, 규칙적 수면처럼 너무 일반적인 생활습관 항목은 제외하세요.
        - 식사 추천, 운동 추천, 주의사항만 작성하세요.
        - 각 추천은 2문장 이내로 짧고 구체적으로 작성하세요.
        - 주의사항은 사용자가 바로 확인할 수 있는 3~5개의 bullet 문장으로 작성하세요.
        - 반드시 아래 JSON 키만 사용하세요.

        {{
          "diet_recommendation": "식사 추천",
          "exercise_recommendation": "운동 추천",
          "caution_items": ["주의사항 1", "주의사항 2", "주의사항 3"]
        }}

        [현재 복용 약 정보]
        {medication_json}
        """

    def _normalize_response(
        self,
        raw_data: Any,
        language: str = "ko",
    ) -> dict[str, object]:
        if not isinstance(raw_data, dict):
            raise RuntimeError("The health recommendation response is invalid.")

        caution_items = raw_data.get("caution_items")
        if not isinstance(caution_items, list):
            caution_items = []
        normalized_cautions = [
            str(item).strip()
            for item in caution_items
            if str(item).strip()
        ][:5]

        if self._is_english(language):
            return {
                "diet_recommendation": self._read_text(
                    raw_data.get("diet_recommendation"),
                    "Diet recommendation could not be generated.",
                ),
                "exercise_recommendation": self._read_text(
                    raw_data.get("exercise_recommendation"),
                    "Exercise recommendation could not be generated.",
                ),
                "caution_items": normalized_cautions
                or ["If you feel unusual symptoms, contact a healthcare professional."],
            }

        return {
            "diet_recommendation": self._read_text(
                raw_data.get("diet_recommendation"),
                "식사 추천 정보를 생성하지 못했습니다.",
            ),
            "exercise_recommendation": self._read_text(
                raw_data.get("exercise_recommendation"),
                "운동 추천 정보를 생성하지 못했습니다.",
            ),
            "caution_items": normalized_cautions
            or ["몸에 이상 반응이 느껴지면 의료진과 상담하세요."],
        }

    @staticmethod
    def _read_text(value: Any, fallback: str) -> str:
        text = "" if value is None else str(value).strip()
        return text or fallback

    @staticmethod
    def _is_english(language: str) -> bool:
        return (language or "").strip().lower().startswith("en")
