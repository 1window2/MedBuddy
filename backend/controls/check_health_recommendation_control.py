# File Name: check_health_recommendation_control.py
# Role: Builds and caches medication-based health guidance for the currently active course and requested language.

import json
import logging
import hashlib
from datetime import date

from fastapi import HTTPException
from sqlalchemy.orm import Session

from boundaries.llm_service_boundary import LLMService
from core.application_clock import application_today
from entities.health_recommendation_cache_entity import _HealthRecommendationCache
from entities.health_recommendation_entity import HealthRecommendation
from entities.patient_hash_entity import normalize_patient_hash
from entities.saved_medication_entity import _SavedMedication
from repositories.saved_medication_repository import SavedMedicationRepository
from services.medication_course_policy import MedicationCoursePolicy
from services.saved_medication_retention import SavedMedicationRetentionPolicy

logger = logging.getLogger(__name__)

# 클래스명: CheckHealthRecommendation
# 역할:
# - 오늘 복용 중인 약을 모아 건강 관리 안내를 생성하고 환자별 캐시를 관리한다.
# 주요 책임:
# - 환자 또는 보호자 권한 범위의 현재 복용 약을 조회한다.
# - 복용 기간이 지난 오래된 저장 정보를 정리한다.
# - 같은 약 조합의 추천 결과가 있으면 로컬 캐시를 재사용한다.
# - 캐시가 없으면 현재 복용 약 조합을 AI 추천 생성기로 전달한다.
# 속성:
# - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
# - medication_repository (SavedMedicationRepository): 환자 소유 저장 약품 스냅샷 저장소.
# - llm_service (LLMService): 활성 약품 요약으로 건강 관리 안내를 생성하는 서비스.
# - course_policy (MedicationCoursePolicy): 약 복용 시작·종료·활성 날짜의 공통 판정 정책.
class CheckHealthRecommendation:
    # 함수이름: __init__
    # 함수역할:
    # - 저장 약 조회, 복용 기간 정책, AI 안내 생성과 보관 정책을 준비한다.
    # 매개변수:
    # - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
    # - llm_service (LLMService | None): 활성 약품 요약으로 건강 관리 안내를 생성하는 서비스.
    # - course_policy (MedicationCoursePolicy | None): 약 복용 시작·종료·활성 날짜의 공통 판정 정책.
    # - medication_repository (SavedMedicationRepository | None): 환자 소유 저장 약품 스냅샷 저장소.
    # 반환값:
    # - 없음.
    def __init__(
        self,
        db: Session,
        llm_service: LLMService | None = None,
        course_policy: MedicationCoursePolicy | None = None,
        medication_repository: SavedMedicationRepository | None = None,
    ) -> None:
        self.db = db
        self.medication_repository = (
            medication_repository or SavedMedicationRepository(db)
        )
        self.llm_service = llm_service or LLMService()
        self.course_policy = course_policy or MedicationCoursePolicy()
        self.retention_policy = SavedMedicationRetentionPolicy(self.course_policy)

    # 함수이름: requestHealthRecommendation
    # 함수역할:
    # - 현재 복용 약과 언어로 캐시를 조회하고, 없으면 AI 안내를 생성해 저장한다.
    # 매개변수:
    # - patient_hash (str | None): 건강 추천 조회 범위를 구분하는 환자 해시
    # - language (str): 추천 응답 언어
    # 반환값:
    # - 약품명과 건강 관리 안내를 담은 응답; 복용 중인 약이 없으면 HTTP 404.
    async def requestHealthRecommendation(
        self,
        patient_hash: str | None = None,
        language: str = "ko",
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        active_medications = self._get_active_medications(
            normalized_patient_hash,
            application_today(),
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

    # Function Name: _build_response
    # Description:
    # - Validates generated guidance as a HealthRecommendation and attaches the source medication names.
    # Parameters:
    # - recommendation (dict[str, object]): AI-generated dietary, exercise and caution guidance.
    # - medication_summaries (list[dict[str, str]]): Active medication guidance and course fields used by the AI prompt.
    # - message (str): User-facing operation status message.
    # Returns:
    # - Success envelope containing the serialized recommendation.
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

    # Function Name: _build_recommendation_key
    # Description:
    # - Sorts medication summaries and hashes their JSON together with the normalized language.
    # Parameters:
    # - medication_summaries (list[dict[str, str]]): Active medication guidance and course fields used by the AI prompt.
    # - language (str): Requested Korean or English content language.
    # Returns:
    # - SHA-256 cache key independent of medication input order.
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

    # Function Name: _normalize_language
    # Description:
    # - Selects English for an en-prefixed language and Korean otherwise.
    # Parameters:
    # - language (str): Requested Korean or English content language.
    # Returns:
    # - Supported language code, en or ko.
    def _normalize_language(self, language: str) -> str:
        return "en" if (language or "").strip().lower().startswith("en") else "ko"

    # Function Name: _get_cached_recommendation
    # Description:
    # - Loads the newest patient/key cache entry and ignores malformed or non-object JSON.
    # Parameters:
    # - patient_hash (str): Patient ownership scope for the operation.
    # - recommendation_key (str): Stable hash of medication inputs and response language.
    # Returns:
    # - Cached recommendation dictionary, or None when missing or invalid.
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

    # Function Name: _save_cached_recommendation
    # Description:
    # - Commits a patient-scoped recommendation snapshot; rolls back and logs cache failures without failing the recommendation.
    # Parameters:
    # - patient_hash (str): Patient ownership scope for the operation.
    # - recommendation_key (str): Stable hash of medication inputs and response language.
    # - recommendation (dict[str, object]): AI-generated dietary, exercise and caution guidance.
    # Returns:
    # - None.
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

    # 함수이름: _get_active_medications
    # 함수역할:
    # - 환자 소유 저장 약 중 지정일에 복용 기간이 유효한 약만 선택한다.
    # 매개변수:
    # - patient_hash (str): 작업 대상 환자의 데이터 소유 범위 식별자.
    # - today (date): 복용 기간 판정에 사용할 애플리케이션 현지 날짜.
    # 반환값:
    # - 지정일의 활성 복약 행 목록.
    def _get_active_medications(
        self,
        patient_hash: str,
        today: date,
    ) -> list[_SavedMedication]:
        medications = self.medication_repository.list_by_patient(patient_hash)
        return [
            medication
            for medication in medications
            if self._is_active_today(medication, today)
        ]

    # Function Name: _to_medication_summary
    # Description:
    # - Extracts drug guidance and dosage fields needed by the recommendation prompt.
    # Parameters:
    # - medication (_SavedMedication): Persisted patient-owned medication snapshot and course fields.
    # Returns:
    # - String-valued medication summary with empty values for missing fields.
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

    # Function Name: _is_active_today
    # Description:
    # - Applies the shared medication-course policy to the requested day.
    # Parameters:
    # - medication (_SavedMedication): Persisted patient-owned medication snapshot and course fields.
    # - today (date): Application-local date used to evaluate the medication course.
    # Returns:
    # - True when the medication course includes that day.
    def _is_active_today(self, medication: _SavedMedication, today: date) -> bool:
        return self.course_policy.is_active_on(medication, today)
