# File Name: input_prescription_control.py
# Role: Structures de-identified prescription text and verifies OCR medication names against bounded local catalog choices.

import asyncio
import json
import logging
import math
import re
import secrets
from collections import OrderedDict
from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Any

from google import genai
from google.genai import types
from sqlalchemy import or_
from sqlalchemy.orm import Session, sessionmaker

from boundaries.prescription_ocr_boundary import OCRServiceBoundary
from core.config import settings
from entities.medication_detail_entity import _DrugApprovalInfo, _DrugBasicInfo
from entities.medication_schedule_entity import MedicationSchedule
from entities.prescription_analysis_entity import (
    MedicationCandidateList,
    PrescriptionAnalysisResult,
    PrescriptionText,
)
from services.prescription_parser import (
    INFO_UNAVAILABLE,
    normalize_prescription_candidates,
)

logger = logging.getLogger(__name__)


# Class Name: PrescriptionAnalysisTimeoutError
# Role:
# - Raised when the required external OCR stage exceeds its deadline.
# Responsibilities:
# - Distinguish a required OCR deadline failure from optional name-correction fallback failures.
class PrescriptionAnalysisTimeoutError(RuntimeError):
    """Raised when the required external OCR stage exceeds its deadline."""


# Class Name: _MedicationNameVariant
# Role:
# - Carries one normalized OCR name variant with its derivation source and confidence cap.
# Responsibilities:
# - Retain transformation provenance and confidence as the normalized name enters catalog matching.
# Attributes:
# - normalized_name (str): Whitespace-free lowercase catalog comparison key.
# - source (str): Provenance of the medication value or verification result.
# - confidence (float): Confidence retained with the catalog-name verification evidence.
@dataclass(frozen=True)
class _MedicationNameVariant:
    normalized_name: str
    source: str
    confidence: float


# Class Name: _MedicationNameVerification
# Role:
# - Records the raw and canonical drug name together with verification evidence and confidence.
# Responsibilities:
# - Preserve the original OCR value when no supported correction is available.
# Attributes:
# - raw_name (str): Original medication name extracted from OCR.
# - canonical_name (str): Catalog-confirmed product display name.
# - confidence (float): Confidence retained with the catalog-name verification evidence.
# - source (str): Provenance of the medication value or verification result.
@dataclass(frozen=True)
class _MedicationNameVerification:
    raw_name: str
    canonical_name: str
    confidence: float
    source: str


# Class Name: _CatalogMedicationName
# Role:
# - Pairs a public catalog display name with its normalized lookup key.
# Responsibilities:
# - Keep canonical display spelling separate from whitespace/case-normalized matching.
# Attributes:
# - item_name (str): Public medication product name.
# - normalized_name (str): Whitespace-free lowercase catalog comparison key.
@dataclass(frozen=True)
class _CatalogMedicationName:
    item_name: str
    normalized_name: str


# Class Name: _MedicationNameFallbackRequest
# Role:
# - Associates an unresolved OCR row index with a bounded set of catalog choices for AI selection.
# Responsibilities:
# - Restrict AI corrections to the catalog names permitted for a specific OCR row.
# Attributes:
# - raw_name (str): Original medication name extracted from OCR.
@dataclass(frozen=True)
class _MedicationNameFallbackRequest:
    index: int
    raw_name: str
    candidates: list[_CatalogMedicationName]


_MedicationNameFallbackCacheKey = tuple[str, str, tuple[tuple[str, str], ...]]


# 클래스명: _PrescriptionMedicationNameVerifier
# 역할:
# - 로컬 카탈로그와 OCR 변형으로 약품명을 검증하고 제한된 후보 내에서만 AI 보정을 허용한다.
# 주요 책임:
# - DB 세션 제약을 지키며 일치·접두어·유사 후보를 검증하고 AI 선택의 목록 포함 여부와 신뢰도 상한을 확인한다.
# 속성:
# - db (Session | None): 현재 작업에 사용할 SQLAlchemy 세션.
# - ai_timeout_seconds (float): 카탈로그 후보 내 AI 보정의 최대 허용 시간(초).
class _PrescriptionMedicationNameVerifier:
    _WHITESPACE_PATTERN = re.compile(r"\s+")
    _MAX_CANDIDATES = 48
    _MAX_AI_CATALOG_CANDIDATES = 8
    _MAX_AI_FALLBACK_CACHE_ENTRIES = 256
    _MAX_CANDIDATE_FRAGMENTS = 16
    _MAX_CATALOG_QUERY_ROWS = 96
    _MIN_FUZZY_SCORE = 0.45
    _AI_CONFIDENCE_THRESHOLD = 0.86
    _AI_CONFIDENCE_CAP = 0.89
    _PREFIX_CONFIDENCE_CAP = 0.95
    _STRENGTH_UNIT_CONFIDENCE_CAP = 0.94
    _HANGUL_BASE = 0xAC00
    _HANGUL_LAST = 0xD7A3
    _HANGUL_MEDIAL_COUNT = 21
    _HANGUL_FINAL_COUNT = 28
    _HANGUL_BLOCK_SIZE = _HANGUL_MEDIAL_COUNT * _HANGUL_FINAL_COUNT
    _OCR_VOWEL_GROUPS = (
        (1, 5),  # ae/e: 애/에
        (4, 20),  # eo/i: ㅓ, ㅣ
        (4, 5),  # eo/e: ㅓ, ㅔ
        (8, 13, 18),  # o/u/eu: ㅗ, ㅜ, ㅡ
        (0, 4),  # a/eo: ㅏ, ㅓ
        (8, 12),  # o/yo: ㅗ, ㅛ
        (13, 17),  # u/yu: ㅜ, ㅠ
    )

    _STRENGTH_UNIT_VARIANTS = (
        ("mg", "밀리그램"),
        ("mg", "밀리그람"),
        ("㎎", "밀리그램"),
        ("㎎", "밀리그람"),
    )

    # Function Name: __init__
    # Description:
    # - Validates the AI fallback timeout and prepares a bounded least-recently-used correction cache.
    # Parameters:
    # - db (Session | None): SQLAlchemy session for this unit of work.
    # - ai_timeout_seconds (float): Maximum duration of the catalog-constrained AI fallback.
    # Returns:
    # - None.
    def __init__(
        self,
        db: Session | None = None,
        ai_timeout_seconds: float = 8.0,
    ) -> None:
        if ai_timeout_seconds <= 0:
            raise ValueError("AI fallback timeout must be greater than zero.")
        self.db = db
        self.ai_timeout_seconds = ai_timeout_seconds
        self._ai_fallback_cache: OrderedDict[
            _MedicationNameFallbackCacheKey,
            tuple[_CatalogMedicationName, float] | None,
        ] = OrderedDict()

    # 함수이름: verify_many
    # 함수역할:
    # - 로컬 검증 후 미확정 이름만 캐시·AI 후보 선택으로 보완하며 원래 항목 순서를 유지한다.
    # 매개변수:
    # - raw_names (list[str]): 처방 순서대로 나열한 원본 OCR 약품명.
    # - ai_client (genai.Client): 제한 시간 내 외부 텍스트 생성에 사용할 Gemini 클라이언트.
    # - model_name (str): 사용할 AI 모델 식별자.
    # 반환값:
    # - 입력 약품명 순서의 검증 결과 목록.
    async def verify_many(
        self,
        raw_names: list[str],
        ai_client: genai.Client,
        model_name: str,
    ) -> list[_MedicationNameVerification]:
        if self._requires_current_thread_session():
            verifications, fallback_requests = self._prepare_verifications(raw_names)
        else:
            verifications, fallback_requests = await asyncio.to_thread(
                self._prepare_verifications_with_isolated_session,
                raw_names,
            )
        if not fallback_requests:
            return verifications

        corrections, uncached_fallback_requests = self._resolve_cached_fallbacks(
            fallback_requests,
            model_name,
        )
        if uncached_fallback_requests:
            ai_corrections = await self._request_ai_catalog_choices(
                uncached_fallback_requests,
                ai_client,
                model_name,
            )
            if ai_corrections is not None:
                self._cache_ai_fallback_results(
                    uncached_fallback_requests,
                    ai_corrections,
                    model_name,
                )
                corrections.update(ai_corrections)

        if not corrections:
            return verifications

        corrected_verifications = list(verifications)
        for index, correction in corrections.items():
            if index < 0 or index >= len(corrected_verifications):
                continue
            catalog_candidate, confidence = correction
            corrected_verifications[index] = _MedicationNameVerification(
                raw_name=raw_names[index],
                canonical_name=catalog_candidate.item_name,
                confidence=confidence,
                source="llm_catalog_candidate",
            )
        return corrected_verifications

    # 함수이름: _prepare_verifications
    # 함수역할:
    # - 동기 SQLAlchemy 카탈로그 조회와 AI 보완 후보 생성을 한 작업 스레드에서 처리한다.
    # - FastAPI 이벤트 루프가 로컬 DB 조회 동안 다른 요청을 계속 처리할 수 있게 한다.
    # 매개변수:
    # - raw_names (list[str]): OCR에서 추출한 원본 약명 목록
    # 반환값:
    # - 로컬 검증 결과와 AI 보완이 필요한 후보 요청 목록
    def _prepare_verifications(
        self,
        raw_names: list[str],
    ) -> tuple[
        list[_MedicationNameVerification],
        list[_MedicationNameFallbackRequest],
    ]:
        verifications = [self.verify(raw_name) for raw_name in raw_names]
        return verifications, self._build_fallback_requests(
            raw_names,
            verifications,
        )

    # 함수이름: _requires_current_thread_session
    # 함수역할:
    # - 별도 연결에서 데이터가 사라지는 인메모리 SQLite 테스트인지 확인한다.
    # - 실제 파일 DB와 PostgreSQL은 독립 작업 세션을 사용하게 한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - DB 세션이 없거나 별도 스레드 연결로 옮길 수 없는 인메모리 SQLite 세션이면 True.
    def _requires_current_thread_session(self) -> bool:
        if self.db is None:
            return True
        bind = self.db.get_bind()
        return bind.dialect.name == "sqlite" and bind.url.database in {
            None,
            "",
            ":memory:",
        }

    # 함수이름: _prepare_verifications_with_isolated_session
    # 함수역할:
    # - 작업 스레드 안에서 새 SQLAlchemy 세션을 생성하여 스레드 간 세션 공유를 막는다.
    # 매개변수:
    # - raw_names (list[str]): OCR에서 추출한 원본 약명 목록
    # 반환값:
    # - 로컬 검증 결과와 AI 보완 후보 요청 목록
    def _prepare_verifications_with_isolated_session(
        self,
        raw_names: list[str],
    ) -> tuple[
        list[_MedicationNameVerification],
        list[_MedicationNameFallbackRequest],
    ]:
        if self.db is None:
            return self._prepare_verifications(raw_names)
        worker_session_factory = sessionmaker(bind=self.db.get_bind())
        worker_db = worker_session_factory()
        try:
            worker = _PrescriptionMedicationNameVerifier(
                db=worker_db,
                ai_timeout_seconds=self.ai_timeout_seconds,
            )
            return worker._prepare_verifications(raw_names)
        finally:
            worker_db.close()

    # Function Name: _resolve_cached_fallbacks
    # Description:
    # - Reuses positive and negative AI choices and promotes accessed entries in the LRU cache.
    # Parameters:
    # - fallback_requests (list[_MedicationNameFallbackRequest]): Unresolved OCR rows with their allowed catalog choices.
    # - model_name (str): Configured AI model identifier.
    # Returns:
    # - Cached corrections by row index and requests that still need AI lookup.
    def _resolve_cached_fallbacks(
        self,
        fallback_requests: list[_MedicationNameFallbackRequest],
        model_name: str,
    ) -> tuple[
        dict[int, tuple[_CatalogMedicationName, float]],
        list[_MedicationNameFallbackRequest],
    ]:
        corrections: dict[int, tuple[_CatalogMedicationName, float]] = {}
        uncached_fallback_requests: list[_MedicationNameFallbackRequest] = []
        cache = self._ai_fallback_cache

        for request in fallback_requests:
            cache_key = self._ai_fallback_cache_key(request, model_name)
            if cache_key not in cache:
                uncached_fallback_requests.append(request)
                continue

            cached_correction = cache.pop(cache_key)
            cache[cache_key] = cached_correction
            if cached_correction is not None:
                corrections[request.index] = cached_correction

        return corrections, uncached_fallback_requests

    # Function Name: _cache_ai_fallback_results
    # Description:
    # - Caches catalog corrections or negative choices and evicts the oldest entries beyond the configured bound.
    # Parameters:
    # - fallback_requests (list[_MedicationNameFallbackRequest]): Unresolved OCR rows with their allowed catalog choices.
    # - corrections (dict[int, tuple[_CatalogMedicationName, float]]): Verified catalog choices and confidence keyed by OCR row index.
    # - model_name (str): Configured AI model identifier.
    # Returns:
    # - None.
    def _cache_ai_fallback_results(
        self,
        fallback_requests: list[_MedicationNameFallbackRequest],
        corrections: dict[int, tuple[_CatalogMedicationName, float]],
        model_name: str,
    ) -> None:
        cache = self._ai_fallback_cache
        for request in fallback_requests:
            cache_key = self._ai_fallback_cache_key(request, model_name)
            cache[cache_key] = corrections.get(request.index)
            cache.move_to_end(cache_key)

        while len(cache) > self._MAX_AI_FALLBACK_CACHE_ENTRIES:
            cache.popitem(last=False)

    # Function Name: _ai_fallback_cache_key
    # Description:
    # - Includes model, normalized OCR name and ordered catalog choices in the fallback cache identity.
    # Parameters:
    # - request (_MedicationNameFallbackRequest): Unresolved OCR row and its permitted catalog choices.
    # - model_name (str): Configured AI model identifier.
    # Returns:
    # - Immutable key that invalidates when either the model or candidate set changes.
    def _ai_fallback_cache_key(
        self,
        request: _MedicationNameFallbackRequest,
        model_name: str,
    ) -> _MedicationNameFallbackCacheKey:
        return (
            model_name,
            self._normalize_name(request.raw_name),
            tuple(
                (candidate.item_name, candidate.normalized_name)
                for candidate in request.candidates
            ),
        )

    # Function Name: verify
    # Description:
    # - Resolves an OCR name through bounded local variants, retaining the original when no catalog match is found.
    # Parameters:
    # - raw_name (str): Original medication name extracted from OCR.
    # Returns:
    # - Name verification with canonical name, confidence and source.
    def verify(self, raw_name: str) -> _MedicationNameVerification:
        normalized_raw_name = self._normalize_name(raw_name)
        if self.db is None or not normalized_raw_name:
            return _MedicationNameVerification(
                raw_name=raw_name,
                canonical_name=raw_name,
                confidence=0.0,
                source="unverified",
            )

        candidates = self._build_candidates(normalized_raw_name)
        catalog_match = self._find_catalog_match(candidates)
        if catalog_match is None:
            return _MedicationNameVerification(
                raw_name=raw_name,
                canonical_name=raw_name,
                confidence=0.0,
                source="unverified",
            )

        candidate, item_name = catalog_match
        return _MedicationNameVerification(
            raw_name=raw_name,
            canonical_name=item_name,
            confidence=candidate.confidence,
            source=candidate.source,
        )

    # Function Name: _build_fallback_requests
    # Description:
    # - Selects unverified nonblank OCR names that have local fuzzy catalog choices for bounded AI review.
    # Parameters:
    # - raw_names (list[str]): Original OCR medication names in prescription order.
    # - verifications (list[_MedicationNameVerification]): Local name-verification results in OCR row order.
    # Returns:
    # - Indexed fallback requests, or an empty list without a database or usable candidates.
    def _build_fallback_requests(
        self,
        raw_names: list[str],
        verifications: list[_MedicationNameVerification],
    ) -> list[_MedicationNameFallbackRequest]:
        if self.db is None:
            return []

        fallback_requests: list[_MedicationNameFallbackRequest] = []
        for index, verification in enumerate(verifications):
            if verification.source != "unverified":
                continue
            normalized_name = self._normalize_name(raw_names[index])
            if not normalized_name:
                continue
            candidates = self._find_similar_catalog_names(normalized_name)
            if not candidates:
                continue
            fallback_requests.append(
                _MedicationNameFallbackRequest(
                    index=index,
                    raw_name=raw_names[index],
                    candidates=candidates,
                )
            )
        return fallback_requests

    # Function Name: _request_ai_catalog_choices
    # Description:
    # - Requests deterministic JSON choices limited to supplied catalog names and treats timeout, decoding or response-shape failures as unavailable fallback.
    # Parameters:
    # - fallback_requests (list[_MedicationNameFallbackRequest]): Unresolved OCR rows with their allowed catalog choices.
    # - ai_client (genai.Client): Gemini client for bounded external text generation.
    # - model_name (str): Configured AI model identifier.
    # Returns:
    # - Verified corrections by OCR index, or None when the AI fallback fails.
    async def _request_ai_catalog_choices(
        self,
        fallback_requests: list[_MedicationNameFallbackRequest],
        ai_client: genai.Client,
        model_name: str,
    ) -> dict[int, tuple[_CatalogMedicationName, float]] | None:
        request_payload = [
            {
                "index": request.index,
                "raw_name": request.raw_name,
                "candidate_names": [
                    candidate.item_name for candidate in request.candidates
                ],
            }
            for request in fallback_requests
        ]
        prompt = (
            "You verify OCR-extracted Korean medication names. "
            "For each item, choose corrected_name only from candidate_names. "
            "Use an empty corrected_name and confidence 0 when none is a "
            "high-confidence OCR correction. Do not invent medication names. "
            "Return JSON only.\n\n"
            f"items={json.dumps(request_payload, ensure_ascii=False)}"
        )

        try:
            response = await asyncio.wait_for(
                ai_client.aio.models.generate_content(
                    model=model_name,
                    contents=[prompt],
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        response_schema=self._ai_correction_response_schema(),
                        temperature=0.0,
                        thinking_config=types.ThinkingConfig(
                            thinking_level=types.ThinkingLevel.MINIMAL,
                        ),
                        max_output_tokens=1024,
                    ),
                ),
                timeout=self.ai_timeout_seconds,
            )
            response_data = json.loads(self._clean_json_response(response.text))
        except Exception as exc:
            logger.warning(
                "Medication name AI fallback failed: %s",
                type(exc).__name__,
            )
            return None

        if not isinstance(response_data, dict):
            return None
        if not isinstance(response_data.get("corrections"), list):
            return None

        return self._select_ai_verified_corrections(
            response_data,
            fallback_requests,
        )

    # Function Name: _select_ai_verified_corrections
    # Description:
    # - Rejects unknown row indexes, low confidence and names outside the supplied candidates, then caps accepted confidence.
    # Parameters:
    # - response_data (dict[str, Any]): Decoded AI corrections object awaiting catalog membership checks.
    # - fallback_requests (list[_MedicationNameFallbackRequest]): Unresolved OCR rows with their allowed catalog choices.
    # Returns:
    # - Catalog-backed corrections at confidence 0.86 or above, capped at 0.89.
    def _select_ai_verified_corrections(
        self,
        response_data: dict[str, Any],
        fallback_requests: list[_MedicationNameFallbackRequest],
    ) -> dict[int, tuple[_CatalogMedicationName, float]]:
        fallback_requests_by_index = {
            request.index: request for request in fallback_requests
        }
        corrections: dict[int, tuple[_CatalogMedicationName, float]] = {}
        raw_corrections = response_data.get("corrections")
        if not isinstance(raw_corrections, list):
            return corrections

        for raw_correction in raw_corrections:
            if not isinstance(raw_correction, dict):
                continue
            index = self._safe_int(raw_correction.get("index"))
            request = fallback_requests_by_index.get(index)
            if request is None:
                continue

            confidence = self._safe_float(raw_correction.get("confidence"))
            if confidence < self._AI_CONFIDENCE_THRESHOLD:
                continue

            selected_name = str(raw_correction.get("corrected_name") or "").strip()
            selected_candidate = self._find_selected_candidate(
                selected_name,
                request.candidates,
            )
            if selected_candidate is None:
                continue

            corrections[index] = (
                selected_candidate,
                min(confidence, self._AI_CONFIDENCE_CAP),
            )
        return corrections

    # Function Name: _build_candidates
    # Description:
    # - Generates exact, OCR-vowel and strength-unit variants, preserving priority while limiting unique names.
    # Parameters:
    # - normalized_name (str): Whitespace-free lowercase catalog comparison key.
    # Returns:
    # - Ordered unique name variants up to the configured candidate bound.
    def _build_candidates(
        self,
        normalized_name: str,
    ) -> list[_MedicationNameVariant]:
        candidates = [
            _MedicationNameVariant(
                normalized_name=normalized_name,
                source="local_catalog_exact",
                confidence=1.0,
            )
        ]
        for variant in self._hangul_vowel_variants(normalized_name):
            candidates.append(
                _MedicationNameVariant(
                    normalized_name=variant,
                    source="local_catalog_ocr_vowel_variant",
                    confidence=0.92,
                )
            )
        candidates.extend(self._strength_unit_variants(candidates))

        deduplicated_candidates: list[_MedicationNameVariant] = []
        seen_names = set()
        for candidate in candidates:
            if candidate.normalized_name in seen_names:
                continue
            seen_names.add(candidate.normalized_name)
            deduplicated_candidates.append(candidate)
            if len(deduplicated_candidates) >= self._MAX_CANDIDATES:
                break
        return deduplicated_candidates

    # Function Name: _find_catalog_match
    # Description:
    # - Checks exact variants across basic and approval catalogs before considering a unique name prefix.
    # Parameters:
    # - candidates (list[_MedicationNameVariant]): Normalized OCR name variant with source and confidence.
    # Returns:
    # - Matched variant and canonical name, or None for missing or ambiguous matches.
    def _find_catalog_match(
        self,
        candidates: list[_MedicationNameVariant],
    ) -> tuple[_MedicationNameVariant, str] | None:
        normalized_names = [candidate.normalized_name for candidate in candidates]
        basic_matches = {
            row.normalized_item_name: row.item_name
            for row in (
                self.db.query(
                    _DrugBasicInfo.normalized_item_name,
                    _DrugBasicInfo.item_name,
                )
                .filter(_DrugBasicInfo.normalized_item_name.in_(normalized_names))
                .order_by(_DrugBasicInfo.item_name.asc())
                .all()
            )
        }
        approval_matches = {
            row.normalized_item_name: row.item_name
            for row in (
                self.db.query(
                    _DrugApprovalInfo.normalized_item_name,
                    _DrugApprovalInfo.item_name,
                )
                .filter(_DrugApprovalInfo.normalized_item_name.in_(normalized_names))
                .order_by(_DrugApprovalInfo.item_name.asc())
                .all()
            )
        }

        for candidate in candidates:
            item_name = basic_matches.get(candidate.normalized_name)
            if item_name:
                return candidate, item_name
            item_name = approval_matches.get(candidate.normalized_name)
            if item_name:
                return candidate, item_name

        for candidate in candidates:
            item_name = self._find_unique_catalog_prefix_match(
                candidate.normalized_name
            )
            if item_name:
                return self._prefix_match_candidate(candidate), item_name
        return None

    # Function Name: _find_unique_catalog_prefix_match
    # Description:
    # - Uses an indexed prefix range and rejects prefixes mapping to more than one distinct product name.
    # Parameters:
    # - normalized_name (str): Whitespace-free lowercase catalog comparison key.
    # Returns:
    # - Sole matching catalog name, or None when absent or ambiguous.
    def _find_unique_catalog_prefix_match(self, normalized_name: str) -> str | None:
        if not normalized_name:
            return None

        prefix_upper_bound = self._prefix_upper_bound(normalized_name)
        matching_item_names: set[str] = set()
        for model in (_DrugBasicInfo, _DrugApprovalInfo):
            for row in (
                self.db.query(model.item_name)
                .filter(
                    model.normalized_item_name >= normalized_name,
                    model.normalized_item_name < prefix_upper_bound,
                )
                .distinct()
                .order_by(model.item_name.asc())
                .limit(2)
                .all()
            ):
                if row.item_name:
                    matching_item_names.add(row.item_name)
                if len(matching_item_names) > 1:
                    return None

        if len(matching_item_names) != 1:
            return None
        return next(iter(matching_item_names))

    # Function Name: _prefix_match_candidate
    # Description:
    # - Caps prefix-based confidence and marks exact-derived variants as prefix evidence.
    # Parameters:
    # - candidate (_MedicationNameVariant): Normalized OCR name variant with source and confidence.
    # Returns:
    # - Name variant with prefix-appropriate source and confidence.
    def _prefix_match_candidate(
        self,
        candidate: _MedicationNameVariant,
    ) -> _MedicationNameVariant:
        if candidate.source == "local_catalog_exact":
            return _MedicationNameVariant(
                normalized_name=candidate.normalized_name,
                source="local_catalog_prefix",
                confidence=min(candidate.confidence, self._PREFIX_CONFIDENCE_CAP),
            )
        return _MedicationNameVariant(
            normalized_name=candidate.normalized_name,
            source=candidate.source,
            confidence=min(candidate.confidence, self._PREFIX_CONFIDENCE_CAP),
        )

    # Function Name: _find_similar_catalog_names
    # Description:
    # - Searches bounded name fragments in both catalogs and ranks distinct names by string similarity.
    # Parameters:
    # - normalized_name (str): Whitespace-free lowercase catalog comparison key.
    # Returns:
    # - Highest-scoring catalog choices for the AI fallback prompt.
    def _find_similar_catalog_names(
        self,
        normalized_name: str,
    ) -> list[_CatalogMedicationName]:
        fragments = self._candidate_fragments(normalized_name)
        if not fragments:
            return []

        catalog_candidates_by_name: dict[str, _CatalogMedicationName] = {}
        for model in (_DrugBasicInfo, _DrugApprovalInfo):
            fragment_filters = [
                model.normalized_item_name.like(
                    self._like_pattern(fragment),
                    escape="\\",
                )
                for fragment in fragments
            ]
            for row in (
                self.db.query(
                    model.normalized_item_name,
                    model.item_name,
                )
                .filter(or_(*fragment_filters))
                .order_by(model.item_name.asc())
                .limit(self._MAX_CATALOG_QUERY_ROWS)
                .all()
            ):
                if not row.item_name or not row.normalized_item_name:
                    continue
                catalog_candidates_by_name.setdefault(
                    row.normalized_item_name,
                    _CatalogMedicationName(
                        item_name=row.item_name,
                        normalized_name=row.normalized_item_name,
                    ),
                )

        scored_candidates = [
            (self._name_similarity(normalized_name, candidate.normalized_name), candidate)
            for candidate in catalog_candidates_by_name.values()
        ]
        scored_candidates = [
            item for item in scored_candidates if item[0] >= self._MIN_FUZZY_SCORE
        ]
        scored_candidates.sort(key=lambda item: (-item[0], item[1].item_name))
        return [
            candidate
            for _, candidate in scored_candidates[: self._MAX_AI_CATALOG_CANDIDATES]
        ]

    # Function Name: _candidate_fragments
    # Description:
    # - Builds unique sliding name fragments and evenly samples them when the query bound is exceeded.
    # Parameters:
    # - normalized_name (str): Whitespace-free lowercase catalog comparison key.
    # Returns:
    # - Bounded three-character fragments, or shorter fragments for short names.
    def _candidate_fragments(self, normalized_name: str) -> list[str]:
        if not normalized_name:
            return []

        window_size = 3 if len(normalized_name) >= 3 else len(normalized_name)
        fragments = [
            normalized_name[index : index + window_size]
            for index in range(0, len(normalized_name) - window_size + 1)
        ]
        deduplicated_fragments: list[str] = []
        seen_fragments = set()
        for fragment in fragments:
            if fragment in seen_fragments:
                continue
            seen_fragments.add(fragment)
            deduplicated_fragments.append(fragment)
        if len(deduplicated_fragments) <= self._MAX_CANDIDATE_FRAGMENTS:
            return deduplicated_fragments

        last_index = len(deduplicated_fragments) - 1
        sample_divisor = self._MAX_CANDIDATE_FRAGMENTS - 1
        return [
            deduplicated_fragments[round(index * last_index / sample_divisor)]
            for index in range(self._MAX_CANDIDATE_FRAGMENTS)
        ]

    # Function Name: _like_pattern
    # Description:
    # - Escapes SQL LIKE metacharacters before surrounding a name fragment with substring wildcards.
    # Parameters:
    # - fragment (str): Literal catalog-name substring to match.
    # Returns:
    # - Literal-fragment substring pattern.
    def _like_pattern(self, fragment: str) -> str:
        escaped_fragment = (
            fragment.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        )
        return f"%{escaped_fragment}%"

    # Function Name: _prefix_upper_bound
    # Description:
    # - Increments the last incrementable Unicode code point to bound a catalog prefix range.
    # Parameters:
    # - normalized_name (str): Whitespace-free lowercase catalog comparison key.
    # Returns:
    # - Exclusive upper bound, or ValueError when no bound can be formed.
    def _prefix_upper_bound(self, normalized_name: str) -> str:
        for index in range(len(normalized_name) - 1, -1, -1):
            code_point = ord(normalized_name[index])
            if code_point < 0x10FFFF:
                return normalized_name[:index] + chr(code_point + 1)
        raise ValueError("Medication name cannot define a prefix range.")

    # Function Name: _name_similarity
    # Description:
    # - Compares normalized medication names with SequenceMatcher.
    # Parameters:
    # - left (str): First normalized string in the similarity comparison.
    # - right (str): Second normalized string in the similarity comparison.
    # Returns:
    # - Name similarity ratio from 0.0 to 1.0.
    def _name_similarity(self, left: str, right: str) -> float:
        return SequenceMatcher(None, left, right).ratio()

    # Function Name: _find_selected_candidate
    # Description:
    # - Restricts an AI-selected name to an exact or normalized match in the supplied catalog choices.
    # Parameters:
    # - selected_name (str): Product name returned by the catalog-constrained AI choice.
    # - candidates (list[_CatalogMedicationName]): Canonical catalog name and normalized comparison key.
    # Returns:
    # - Existing catalog candidate, or None for an unrecognized selection.
    def _find_selected_candidate(
        self,
        selected_name: str,
        candidates: list[_CatalogMedicationName],
    ) -> _CatalogMedicationName | None:
        if not selected_name:
            return None

        for candidate in candidates:
            if selected_name == candidate.item_name:
                return candidate

        normalized_selected_name = self._normalize_name(selected_name)
        for candidate in candidates:
            if normalized_selected_name == candidate.normalized_name:
                return candidate
        return None

    # Function Name: _hangul_vowel_variants
    # Description:
    # - Substitutes commonly confused Hangul medial vowels while preserving the remaining name characters.
    # Parameters:
    # - normalized_name (str): Whitespace-free lowercase catalog comparison key.
    # Returns:
    # - OCR-vowel alternatives for catalog matching.
    def _hangul_vowel_variants(self, normalized_name: str) -> list[str]:
        variants: list[str] = []
        for index, character in enumerate(normalized_name):
            medial_index = self._hangul_medial_index(character)
            if medial_index is None:
                continue

            for group in self._OCR_VOWEL_GROUPS:
                if medial_index not in group:
                    continue
                for replacement_medial_index in group:
                    if replacement_medial_index == medial_index:
                        continue
                    variants.append(
                        normalized_name[:index]
                        + self._replace_hangul_medial(
                            character,
                            replacement_medial_index,
                        )
                        + normalized_name[index + 1 :]
                    )
        return variants

    # Function Name: _strength_unit_variants
    # Description:
    # - Expands milligram spellings and caps the confidence of converted strength-unit variants.
    # Parameters:
    # - candidates (list[_MedicationNameVariant]): Normalized OCR name variant with source and confidence.
    # Returns:
    # - Additional name variants with source evidence retained.
    def _strength_unit_variants(
        self,
        candidates: list[_MedicationNameVariant],
    ) -> list[_MedicationNameVariant]:
        variants: list[_MedicationNameVariant] = []
        for candidate in candidates:
            for source_unit, target_unit in self._STRENGTH_UNIT_VARIANTS:
                if source_unit not in candidate.normalized_name:
                    continue
                variants.append(
                    _MedicationNameVariant(
                        normalized_name=candidate.normalized_name.replace(
                            source_unit,
                            target_unit,
                        ),
                        source=(
                            candidate.source
                            if candidate.source != "local_catalog_exact"
                            else "local_catalog_strength_unit_variant"
                        ),
                        confidence=min(
                            candidate.confidence,
                            self._STRENGTH_UNIT_CONFIDENCE_CAP,
                        ),
                    )
                )
        return variants

    # Function Name: _hangul_medial_index
    # Description:
    # - Decodes the medial-vowel index of a precomposed Hangul syllable.
    # Parameters:
    # - character (str): Single source character used for Hangul syllable decomposition.
    # Returns:
    # - Medial index, or None for a non-Hangul-syllable character.
    def _hangul_medial_index(self, character: str) -> int | None:
        code_point = ord(character)
        if code_point < self._HANGUL_BASE or code_point > self._HANGUL_LAST:
            return None

        syllable_index = code_point - self._HANGUL_BASE
        return (syllable_index % self._HANGUL_BLOCK_SIZE) // self._HANGUL_FINAL_COUNT

    # Function Name: _replace_hangul_medial
    # Description:
    # - Rebuilds a Hangul syllable with a new medial vowel while retaining its initial and final consonants.
    # Parameters:
    # - character (str): Single source character used for Hangul syllable decomposition.
    # - replacement_medial_index (int): Hangul medial-vowel index to substitute.
    # Returns:
    # - Reconstructed Hangul character.
    def _replace_hangul_medial(
        self,
        character: str,
        replacement_medial_index: int,
    ) -> str:
        syllable_index = ord(character) - self._HANGUL_BASE
        initial_index = syllable_index // self._HANGUL_BLOCK_SIZE
        final_index = syllable_index % self._HANGUL_FINAL_COUNT
        return chr(
            self._HANGUL_BASE
            + (
                initial_index * self._HANGUL_MEDIAL_COUNT
                + replacement_medial_index
            )
            * self._HANGUL_FINAL_COUNT
            + final_index
        )

    # Function Name: _normalize_name
    # Description:
    # - Removes whitespace and lowercases OCR/catalog names for stable matching.
    # Parameters:
    # - name (str): Medication name before catalog-key normalization.
    # Returns:
    # - Normalized medication name, or an empty string for missing input.
    def _normalize_name(self, name: str) -> str:
        return self._WHITESPACE_PATTERN.sub("", name or "").strip().lower()

    # Function Name: _clean_json_response
    # Description:
    # - Removes optional Markdown JSON fences from an AI correction response.
    # Parameters:
    # - response_text (str): Raw AI response text before JSON fence removal and decoding.
    # Returns:
    # - Trimmed JSON text ready for decoding.
    def _clean_json_response(self, response_text: str) -> str:
        cleaned_text = response_text.strip()
        if cleaned_text.startswith("```json"):
            cleaned_text = cleaned_text[7:]
        if cleaned_text.startswith("```"):
            cleaned_text = cleaned_text[3:]
        if cleaned_text.endswith("```"):
            cleaned_text = cleaned_text[:-3]
        return cleaned_text.strip()

    # Function Name: _safe_float
    # Description:
    # - Coerces numeric confidence while rejecting non-finite or unparseable values.
    # Parameters:
    # - value (Any): Untrusted numeric confidence from the AI response.
    # Returns:
    # - Finite float, or 0.0 for invalid input.
    def _safe_float(self, value: Any) -> float:
        try:
            number = float(value)
        except (TypeError, ValueError):
            return 0.0
        return number if math.isfinite(number) else 0.0

    # Function Name: _safe_int
    # Description:
    # - Coerces an AI row index while keeping invalid values outside the valid zero-based range.
    # Parameters:
    # - value (Any): Untrusted row-index value from the AI response.
    # Returns:
    # - Parsed integer, or -1 when conversion fails.
    def _safe_int(self, value: Any) -> int:
        try:
            return int(value)
        except (TypeError, ValueError):
            return -1

    # Function Name: _ai_correction_response_schema
    # Description:
    # - Constrains AI output to indexed corrected names and numeric confidence values.
    # Parameters:
    # - None.
    # Returns:
    # - JSON response schema requiring a corrections array.
    def _ai_correction_response_schema(self) -> dict[str, Any]:
        return {
            "type": "OBJECT",
            "required": ["corrections"],
            "properties": {
                "corrections": {
                    "type": "ARRAY",
                    "items": {
                        "type": "OBJECT",
                        "required": ["index", "corrected_name", "confidence"],
                        "properties": {
                            "index": {"type": "INTEGER"},
                            "corrected_name": {"type": "STRING"},
                            "confidence": {"type": "NUMBER"},
                        },
                    },
                },
            },
        }


# Class Name: InputPrescription
# Role:
# - Coordinates de-identified prescription text structuring and validation.
# Responsibilities:
# - Accept only prescription text already de-identified on the user's device.
# - Request structured prescription extraction from Gemini.
# - Clean, decode, mask, and validate extracted prescription data.
# Attributes:
# - client (genai.Client): Gemini client used for prescription text analysis.
# - model_name (str): Gemini model name.
class InputPrescription:
    _PRESCRIPTION_RESPONSE_SCHEMA = {
        "type": "OBJECT",
        "required": [
            "hospital_name",
            "prescription_date",
            "medications",
        ],
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

    # Function Name: __init__
    # Description:
    # - Binds the Gemini client, bounded OCR analysis boundary and catalog-backed name verifier.
    # Parameters:
    # - client (genai.Client | None): Gemini client shared by prescription OCR and name verification.
    # - model_name (str): Configured AI model identifier.
    # - db (Session | None): SQLAlchemy session for this unit of work.
    # - medication_name_verifier (_PrescriptionMedicationNameVerifier | None): Catalog-constrained OCR medication-name verifier.
    # - ocr_service_boundary (OCRServiceBoundary | None): Bounded external OCR-text analysis boundary.
    # Returns:
    # - None.
    def __init__(
        self,
        client: genai.Client | None = None,
        model_name: str = "gemini-3.1-flash-lite",
        db: Session | None = None,
        medication_name_verifier: _PrescriptionMedicationNameVerifier | None = None,
        ocr_service_boundary: OCRServiceBoundary | None = None,
    ) -> None:
        self.client = client or genai.Client(
            api_key=settings.GEMINI_API_KEY,
            http_options={"api_version": "v1alpha"},
        )
        self.model_name = model_name
        self.ocr_service_boundary = ocr_service_boundary or OCRServiceBoundary(
            client=self.client,
            model_name=self.model_name,
            response_schema=self._PRESCRIPTION_RESPONSE_SCHEMA,
            request_timeout_seconds=settings.PRESCRIPTION_OCR_TIMEOUT_SECONDS,
        )
        self.medication_name_verifier = (
            medication_name_verifier
            or _PrescriptionMedicationNameVerifier(
                db=db,
                ai_timeout_seconds=(
                    settings.PRESCRIPTION_NAME_FALLBACK_TIMEOUT_SECONDS
                ),
            )
        )

    # 함수이름: requestPrescriptionText
    # 함수역할:
    # - 기기에서 개인정보를 제거한 OCR 텍스트를 구조화 처방 정보로 변환한다.
    # - 개인정보 보호 경계상 원본 처방전 이미지는 백엔드에서 받지 않는다.
    # 매개변수:
    # - masked_text (str): 기기 내 OCR과 민감정보 제거가 끝난 처방전 텍스트
    # 반환값:
    # - API 호환 복약 일정 분석 결과
    async def requestPrescriptionText(
        self,
        masked_text: str,
    ) -> dict[str, object]:
        normalized_text = masked_text.strip()
        if not normalized_text:
            raise ValueError("Masked prescription text is empty.")
        if len(normalized_text) > 100_000:
            raise ValueError("Masked prescription text exceeds 100,000 characters.")
        try:
            response_text = await self.ocr_service_boundary.extractPrescriptionTextData(
                normalized_text
            )
        except TimeoutError as exc:
            raise PrescriptionAnalysisTimeoutError(
                "처방전 인식 서비스 응답 시간이 초과되었습니다. 잠시 후 다시 시도해주세요."
            ) from exc
        return await self._build_prescription_response(response_text)

    # Function Name: _build_prescription_response
    # Description:
    # - Parses AI JSON, applies secondary privacy masking and normalization, then verifies medication names and assigns a new prescription batch.
    # Parameters:
    # - response_text (str): Raw AI response text before JSON fence removal and decoding.
    # Returns:
    # - Safe prescription metadata, verified medication rows and parsing counts.
    async def _build_prescription_response(
        self,
        response_text: str,
    ) -> dict[str, object]:
        cleaned_text = self._clean_response_text(response_text)

        try:
            raw_data = json.loads(cleaned_text)
        except json.JSONDecodeError as exc:
            logger.error(
                "Prescription analysis JSON decoding failed: response_length=%d",
                len(response_text),
            )
            raise ValueError("AI returned an invalid JSON response.") from exc

        masked_data = self._apply_secondary_masking(raw_data)
        (
            hospital_name,
            prescription_date,
            medication_candidates,
            raw_medication_count,
        ) = normalize_prescription_candidates(masked_data)
        safe_data = self.buildAnalysisResult(
            medication_candidates,
            hospital_name=hospital_name,
            prescription_date=prescription_date,
        ).to_payload(raw_medication_count=raw_medication_count)
        prescription_date = safe_data.get("prescription_date", INFO_UNAVAILABLE)
        verified_medication_schedules = await self._to_verified_medication_schedules(
            safe_data.get("medications", []),
        )
        medication_schedules = [
            self._to_prescription_medication_payload(
                medication_schedule,
                verification,
                prescription_date,
            )
            for medication_schedule, verification in verified_medication_schedules
        ]
        return {
            "hospital_name": safe_data.get("hospital_name", INFO_UNAVAILABLE),
            "prescription_date": prescription_date,
            "prescription_batch_id": secrets.token_urlsafe(18),
            "medications": medication_schedules,
            "raw_medication_count": safe_data.get(
                "raw_medication_count",
                len(medication_schedules),
            ),
            "parsed_medication_count": len(medication_schedules),
            "skipped_medication_count": safe_data.get("skipped_medication_count", 0),
        }

    # Function Name: buildAnalysisResult
    # Description:
    # - Class diagram compatible operation for promoting candidates into a prescription analysis result entity.
    # Parameters:
    # - candidates (MedicationCandidateList): MedicationCandidateList extracted from a prescription.
    # - hospital_name (str): Hospital name retained in the normalized prescription.
    # - prescription_date (str): Prescription dispensing date, if available.
    # Returns:
    # - PrescriptionAnalysisResult entity.
    def buildAnalysisResult(
        self,
        candidates: MedicationCandidateList,
        *,
        hospital_name: str = INFO_UNAVAILABLE,
        prescription_date: str = INFO_UNAVAILABLE,
    ) -> PrescriptionAnalysisResult:
        analysis_result = PrescriptionAnalysisResult(
            hospital_name=hospital_name,
            prescription_date=prescription_date,
        )
        for candidate in candidates.candidates:
            analysis_result.addMedicationCandidate(candidate)
        return analysis_result

    # Function Name: _clean_response_text
    # Description:
    # - Removes markdown fences and surrounding whitespace from model output.
    # Parameters:
    # - response_text (str): Raw Gemini response text.
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
    # - data (dict[str, Any]): Decoded prescription dictionary.
    # Returns:
    # - Masked prescription dictionary.
    def _apply_secondary_masking(self, data: dict[str, Any]) -> dict[str, Any]:
        data_str = json.dumps(data, ensure_ascii=False)
        return json.loads(self.maskSensitiveInfo(data_str))

    # Function Name: maskSensitiveInfo
    # Description:
    # - Class diagram compatible operation for removing sensitive identifiers.
    # Parameters:
    # - rawText (str): Raw prescription text or serialized extraction payload.
    # Returns:
    # - Text with sensitive identifiers masked.
    def maskSensitiveInfo(self, rawText: str) -> str:
        return PrescriptionText(raw_text=rawText).removeSensitiveInfoByRegex()

    # Function Name: _to_verified_medication_schedules
    # Description:
    # - Verifies candidate names in one batch and copies schedules only when their canonical names change.
    # Parameters:
    # - items (list[dict[str, Any]]): Normalized prescription medication dictionaries.
    # Returns:
    # - Ordered pairs of schedule entities and name-verification evidence.
    async def _to_verified_medication_schedules(
        self,
        items: list[dict[str, Any]],
    ) -> list[tuple[MedicationSchedule, _MedicationNameVerification]]:
        medication_schedules = [
            MedicationSchedule(**item) for item in items
        ]
        verifications = await self.medication_name_verifier.verify_many(
            [
                medication_schedule.medication_name
                for medication_schedule in medication_schedules
            ],
            self.client,
            self.model_name,
        )

        verified_schedules: list[tuple[MedicationSchedule, _MedicationNameVerification]] = []
        for medication_schedule, verification in zip(
            medication_schedules,
            verifications,
        ):
            if verification.canonical_name != medication_schedule.medication_name:
                medication_schedule = medication_schedule.model_copy(
                    update={"medication_name": verification.canonical_name},
                )
            verified_schedules.append((medication_schedule, verification))
        return verified_schedules

    # Function Name: _to_prescription_medication_payload
    # Description:
    # - Converts a MedicationSchedule entity into the API payload expected by the current Flutter analysis-result flow.
    # Parameters:
    # - medication_schedule (MedicationSchedule): Validated MedicationSchedule entity.
    # - verification (_MedicationNameVerification): Canonical name, source and confidence for one OCR medication.
    # - prescription_date (str): Prescription dispensing date, if available.
    # Returns:
    # - Dictionary containing only prescription-analysis response fields.
    def _to_prescription_medication_payload(
        self,
        medication_schedule: MedicationSchedule,
        verification: _MedicationNameVerification,
        prescription_date: str,
    ) -> dict[str, object]:
        return {
            "prescription_date": prescription_date,
            "drug_name": medication_schedule.medication_name,
            "raw_drug_name": verification.raw_name,
            "name_confidence": verification.confidence,
            "name_correction_source": verification.source,
            "dosage_per_time": medication_schedule.dosage,
            "daily_frequency": medication_schedule.intake_time,
            "total_days": medication_schedule.medication_time,
        }
