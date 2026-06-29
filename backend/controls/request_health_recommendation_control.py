# 파일명: request_health_recommendation_control.py
# 역할: 현재 복용 중인 약 조합을 바탕으로 건강 관리 추천을 생성한다.

import json
import logging
import re
import hashlib
from datetime import date, timedelta
from typing import Any

from fastapi import HTTPException
from google import genai
from sqlalchemy.orm import Session

from controls.link_patient_caregiver_control import LinkPatientCaregiver
from core.config import settings
from entities.health_recommendation_cache_entity import _HealthRecommendationCache
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH, normalize_patient_hash
from entities.saved_medication_entity import _SavedMedication
from services.saved_medication_retention import SavedMedicationRetentionPolicy

logger = logging.getLogger(__name__)

_TOTAL_DAYS_PATTERN = re.compile(r"\d+")
_GUARDIAN_ROLES = {"guardian", "caregiver"}


# 클래스명: HealthRecommendationGenerator
# 역할: Gemini를 사용해 복용 약 조합 기반 건강 관리 추천 문장을 생성한다.
# 주요 책임:
#   - 현재 복용 약 정보를 AI 프롬프트로 변환한다.
#   - AI 응답을 식사 추천, 운동 추천, 주의사항 구조로 정규화한다.
#   - 진단 표현 대신 참고용 관리 조언으로 제한한다.
class HealthRecommendationGenerator:
    def __init__(
        self,
        ai_client: genai.Client | None = None,
        model_name: str = "gemini-3.1-flash-lite",
    ) -> None:
        self.ai_client = ai_client or genai.Client(api_key=settings.GEMINI_API_KEY)
        self.model_name = model_name

    # 함수명: generate
    # 함수역할:
    # - 약 조합 정보를 Gemini에 전달하고 건강 관리 추천을 생성한다.
    # 매개변수:
    # - medication_summaries: 현재 복용 중인 약 정보 요약 목록
    # 반환값:
    # - 식사 추천, 운동 추천, 주의사항이 담긴 dictionary
    async def generate(
        self,
        medication_summaries: list[dict[str, str]],
        language: str = "ko",
    ) -> dict[str, object]:
        prompt = self._build_prompt(medication_summaries, language)

        try:
            ai_response = await self.ai_client.aio.models.generate_content(
                model=self.model_name,
                contents=prompt,
                config={"response_mime_type": "application/json"},
            )
            raw_data = json.loads(ai_response.text)
        except Exception as exc:
            logger.error("Gemini health recommendation failed: %s", exc)
            raise RuntimeError("건강 관리 추천 생성 중 오류가 발생했습니다.") from exc

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
            raise RuntimeError("건강 관리 추천 응답 형식이 올바르지 않습니다.")

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

    def _read_text(self, value: Any, fallback: str) -> str:
        text = "" if value is None else str(value).strip()
        return text or fallback

    def _is_english(self, language: str) -> bool:
        return (language or "").strip().lower().startswith("en")


# 클래스명: RequestHealthRecommendation
# 역할: 건강 관리 추천 조회 유스케이스를 조정한다.
# 주요 책임:
#   - 환자 또는 보호자 권한 범위의 현재 복용 약을 조회한다.
#   - 복용 기간이 지난 오래된 저장 정보를 정리한다.
#   - 같은 약 조합의 추천 결과가 있으면 로컬 캐시를 재사용한다.
#   - 캐시가 없으면 현재 복용 약 조합을 AI 추천 생성기로 전달한다.
class RequestHealthRecommendation:
    def __init__(
        self,
        db: Session,
        recommendation_generator: HealthRecommendationGenerator | None = None,
    ) -> None:
        self.db = db
        self.recommendation_generator = (
            recommendation_generator or HealthRecommendationGenerator()
        )

    # 함수명: request_health_recommendation
    # 함수역할:
    # - 오늘 복용 중인 약 조합을 바탕으로 건강 관리 추천을 반환한다.
    # 매개변수:
    # - patient_hash: 건강 추천 조회 범위를 구분하는 환자 해시
    # - user_hash: 보호자 요청자의 사용자 해시
    # - role: 요청자 역할
    # 반환값:
    # - API 호환 건강 관리 추천 dictionary
    async def request_health_recommendation(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
        language: str = "ko",
    ) -> dict[str, object]:
        normalized_patient_hash = self._resolve_patient_hash(
            patient_hash,
            user_hash,
            role,
        )
        SavedMedicationRetentionPolicy().cleanup_expired_medications(
            self.db,
            normalized_patient_hash,
        )

        active_medications = self._get_active_medications(
            normalized_patient_hash,
            date.today(),
        )
        if not active_medications:
            raise HTTPException(
                status_code=404,
                detail="오늘 복용 중인 약 정보가 없습니다.",
            )

        medication_summaries = [
            self._to_medication_summary(medication)
            for medication in active_medications
        ]
        recommendation_key = self._build_recommendation_key(
            medication_summaries,
            language,
        )
        cached_recommendation = self._get_cached_recommendation(
            normalized_patient_hash,
            recommendation_key,
        )
        if cached_recommendation is not None:
            return self._build_response(
                cached_recommendation,
                medication_summaries,
                "Health recommendation loaded from cache.",
            )

        recommendation = await self.recommendation_generator.generate(
            medication_summaries,
            language,
        )
        self._save_cached_recommendation(
            normalized_patient_hash,
            recommendation_key,
            recommendation,
        )
        return self._build_response(
            recommendation,
            medication_summaries,
            "Health recommendation generated.",
        )

    def _build_response(
        self,
        recommendation: dict[str, object],
        medication_summaries: list[dict[str, str]],
        message: str,
    ) -> dict[str, object]:
        return {
            "success": True,
            "message": message,
            "data": {
                **recommendation,
                "medication_names": [
                    summary["item_name"] for summary in medication_summaries
                ],
            },
        }

    def _build_recommendation_key(
        self,
        medication_summaries: list[dict[str, str]],
        language: str,
    ) -> str:
        normalized_summaries = sorted(
            medication_summaries,
            key=lambda item: (
                item.get("item_name", ""),
                item.get("dosage_per_time", ""),
                item.get("daily_frequency", ""),
                item.get("total_days", ""),
            ),
        )
        raw_key = json.dumps(
            {
                "language": self._normalize_language(language),
                "medications": normalized_summaries,
            },
            ensure_ascii=False,
            sort_keys=True,
        )
        return hashlib.sha256(raw_key.encode("utf-8")).hexdigest()

    def _normalize_language(self, language: str) -> str:
        return "en" if (language or "").strip().lower().startswith("en") else "ko"

    def _get_cached_recommendation(
        self,
        patient_hash: str,
        recommendation_key: str,
    ) -> dict[str, object] | None:
        cached_row = (
            self.db.query(_HealthRecommendationCache)
            .filter(
                _HealthRecommendationCache.patient_hash == patient_hash,
                _HealthRecommendationCache.recommendation_key == recommendation_key,
            )
            .order_by(_HealthRecommendationCache.id.desc())
            .first()
        )
        if cached_row is None:
            return None

        try:
            cached_payload = json.loads(cached_row.payload)
        except json.JSONDecodeError:
            return None

        if not isinstance(cached_payload, dict):
            return None
        return cached_payload

    def _save_cached_recommendation(
        self,
        patient_hash: str,
        recommendation_key: str,
        recommendation: dict[str, object],
    ) -> None:
        try:
            cached_row = _HealthRecommendationCache(
                patient_hash=patient_hash,
                recommendation_key=recommendation_key,
                payload=json.dumps(recommendation, ensure_ascii=False),
            )
            self.db.add(cached_row)
            self.db.commit()
        except Exception as exc:
            self.db.rollback()
            logger.warning("Health recommendation cache save failed: %s", exc)

    def _resolve_patient_hash(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> str:
        normalized_role = (role or "patient").strip().lower()
        if normalized_role in _GUARDIAN_ROLES:
            return LinkPatientCaregiver(self.db).get_linked_patient_hash(
                user_hash or patient_hash,
                patient_hash,
            )
        return normalize_patient_hash(user_hash or patient_hash)

    def _get_active_medications(
        self,
        patient_hash: str,
        today: date,
    ) -> list[_SavedMedication]:
        medications = (
            self.db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == patient_hash)
            .order_by(_SavedMedication.id.asc())
            .all()
        )
        return [
            medication
            for medication in medications
            if self._is_active_today(medication, today)
        ]

    def _to_medication_summary(
        self,
        medication: _SavedMedication,
    ) -> dict[str, str]:
        return {
            "item_name": medication.item_name or "",
            "efficacy": medication.efficacy or "",
            "use_method": medication.use_method or "",
            "warning_message": medication.warning_message or "",
            "dosage_per_time": medication.dosage_per_time or "",
            "daily_frequency": medication.daily_frequency or "",
            "total_days": medication.total_days or "",
        }

    def _is_active_today(self, medication: _SavedMedication, today: date) -> bool:
        start_date = self._read_schedule_start_date(medication, today)
        total_days = self._read_total_days(medication.total_days)
        if total_days <= 0:
            return start_date <= today

        end_date = start_date + timedelta(days=total_days - 1)
        return start_date <= today <= end_date

    def _read_schedule_start_date(
        self,
        medication: _SavedMedication,
        fallback_date: date,
    ) -> date:
        raw_date = medication.prescription_date or medication.created_date
        if isinstance(raw_date, date):
            return raw_date
        if isinstance(raw_date, str) and raw_date.strip():
            try:
                return date.fromisoformat(raw_date.strip())
            except ValueError:
                return fallback_date
        return fallback_date

    def _read_total_days(self, raw_total_days: str | None) -> int:
        if not raw_total_days:
            return 0
        match = _TOTAL_DAYS_PATTERN.search(raw_total_days)
        if match is None:
            return 0
        return int(match.group(0))
