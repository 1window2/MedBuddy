# 파일명: check_health_recommendation_control.py
# 역할: 현재 복용 중인 약 조합을 바탕으로 건강 관리 추천을 생성한다.

import json
import logging
import hashlib
from datetime import date

from fastapi import HTTPException
from sqlalchemy.orm import Session

from boundaries.llm_service_boundary import LLMService
from entities.health_recommendation_cache_entity import _HealthRecommendationCache
from entities.health_recommendation_entity import HealthRecommendation
from entities.patient_hash_entity import normalize_patient_hash
from entities.saved_medication_entity import _SavedMedication
from services.medication_course_policy import MedicationCoursePolicy
from services.saved_medication_retention import SavedMedicationRetentionPolicy

logger = logging.getLogger(__name__)

# 클래스명: CheckHealthRecommendation
# 역할: 건강 관리 추천 조회 유스케이스를 조정한다.
# 주요 책임:
#   - 환자 또는 보호자 권한 범위의 현재 복용 약을 조회한다.
#   - 복용 기간이 지난 오래된 저장 정보를 정리한다.
#   - 같은 약 조합의 추천 결과가 있으면 로컬 캐시를 재사용한다.
#   - 캐시가 없으면 현재 복용 약 조합을 AI 추천 생성기로 전달한다.
class CheckHealthRecommendation:
    def __init__(
        self,
        db: Session,
        llm_service: LLMService | None = None,
        course_policy: MedicationCoursePolicy | None = None,
    ) -> None:
        self.db = db
        self.llm_service = llm_service or LLMService()
        self.course_policy = course_policy or MedicationCoursePolicy()
        self.retention_policy = SavedMedicationRetentionPolicy(self.course_policy)

    # 함수명: requestHealthRecommendation
    # 함수역할:
    # - 오늘 복용 중인 약 조합을 바탕으로 건강 관리 추천을 반환한다.
    # 매개변수:
    # - patient_hash: 건강 추천 조회 범위를 구분하는 환자 해시
    # - language: 추천 응답 언어
    # 반환값:
    # - API 호환 건강 관리 추천 dictionary
    async def requestHealthRecommendation(
        self,
        patient_hash: str | None = None,
        language: str = "ko",
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
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

        recommendation = await self.llm_service.requestHealthRecommendation(
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
        health_recommendation = HealthRecommendation.from_payload(
            recommendation,
            medication_names=[
                summary["item_name"] for summary in medication_summaries
            ],
        )
        return {
            "success": True,
            "message": message,
            "data": health_recommendation.model_dump(),
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
            logger.warning(
                "Health recommendation cache save failed: %s",
                type(exc).__name__,
            )

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
        return self.course_policy.is_active_on(medication, today)
