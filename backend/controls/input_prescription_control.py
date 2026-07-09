# File Name: input_prescription_control.py
# Role: Control class for prescription image analysis.

import json
import logging
import re
from collections import OrderedDict
from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Any, ClassVar

from google import genai
from google.genai import types
from sqlalchemy.orm import Session

from core.config import settings
from entities.medication_detail_entity import _DrugApprovalInfo, _DrugBasicInfo
from entities.medication_schedule_entity import MedicationSchedule
from services.prescription_parser import normalize_prescription_payload
from utils.image_processing import preprocess_prescription_image

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class _MedicationNameCandidate:
    normalized_name: str
    source: str
    confidence: float


@dataclass(frozen=True)
class _MedicationNameVerification:
    raw_name: str
    canonical_name: str
    confidence: float
    source: str


@dataclass(frozen=True)
class _CatalogMedicationName:
    item_name: str
    normalized_name: str


@dataclass(frozen=True)
class _MedicationNameFallbackRequest:
    index: int
    raw_name: str
    candidates: list[_CatalogMedicationName]


# Class Name: _PrescriptionMedicationNameVerifier
# Role: Internal collaborator for prescription medication name canonicalization.
# Responsibilities:
#   - Verify extracted medication names against the local medication catalog.
#   - Generate bounded Korean OCR vowel variants before AI fallback.
#   - Ask Gemini to choose only from local catalog candidates when needed.
#   - Return conservative correction metadata for downstream UI decisions.
class _PrescriptionMedicationNameVerifier:
    _WHITESPACE_PATTERN = re.compile(r"\s+")
    _MAX_CANDIDATES = 48
    _MAX_AI_CATALOG_CANDIDATES = 8
    _MAX_AI_FALLBACK_CACHE_ENTRIES = 256
    _MAX_FRAGMENT_QUERY_ROWS = 24
    _MIN_FUZZY_SCORE = 0.45
    _AI_CONFIDENCE_THRESHOLD = 0.86
    _AI_CONFIDENCE_CAP = 0.89
    _HANGUL_BASE = 0xAC00
    _HANGUL_LAST = 0xD7A3
    _HANGUL_MEDIAL_COUNT = 21
    _HANGUL_FINAL_COUNT = 28
    _HANGUL_BLOCK_SIZE = _HANGUL_MEDIAL_COUNT * _HANGUL_FINAL_COUNT
    _OCR_VOWEL_GROUPS = (
        (4, 20),  # eo/i: ㅓ, ㅣ
        (4, 5),  # eo/e: ㅓ, ㅔ
        (8, 13, 18),  # o/u/eu: ㅗ, ㅜ, ㅡ
        (0, 4),  # a/eo: ㅏ, ㅓ
        (8, 12),  # o/yo: ㅗ, ㅛ
        (13, 17),  # u/yu: ㅜ, ㅠ
    )

    _AI_FALLBACK_CACHE: ClassVar[
        OrderedDict[
            tuple[str, tuple[str, ...]],
            tuple[_CatalogMedicationName, float] | None,
        ]
    ] = OrderedDict()

    def __init__(self, db: Session | None = None) -> None:
        self.db = db

    @classmethod
    def clear_ai_fallback_cache(cls) -> None:
        cls._AI_FALLBACK_CACHE.clear()

    async def verify_many(
        self,
        raw_names: list[str],
        ai_client: genai.Client,
        model_name: str,
    ) -> list[_MedicationNameVerification]:
        verifications = [self.verify(raw_name) for raw_name in raw_names]
        fallback_requests = self._build_fallback_requests(raw_names, verifications)
        if not fallback_requests:
            return verifications

        corrections, uncached_fallback_requests = self._resolve_cached_fallbacks(
            fallback_requests,
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

    def _resolve_cached_fallbacks(
        self,
        fallback_requests: list[_MedicationNameFallbackRequest],
    ) -> tuple[
        dict[int, tuple[_CatalogMedicationName, float]],
        list[_MedicationNameFallbackRequest],
    ]:
        corrections: dict[int, tuple[_CatalogMedicationName, float]] = {}
        uncached_fallback_requests: list[_MedicationNameFallbackRequest] = []
        cache = type(self)._AI_FALLBACK_CACHE

        for request in fallback_requests:
            cache_key = self._ai_fallback_cache_key(request)
            if cache_key not in cache:
                uncached_fallback_requests.append(request)
                continue

            cached_correction = cache.pop(cache_key)
            cache[cache_key] = cached_correction
            if cached_correction is not None:
                corrections[request.index] = cached_correction

        return corrections, uncached_fallback_requests

    def _cache_ai_fallback_results(
        self,
        fallback_requests: list[_MedicationNameFallbackRequest],
        corrections: dict[int, tuple[_CatalogMedicationName, float]],
    ) -> None:
        cache = type(self)._AI_FALLBACK_CACHE
        for request in fallback_requests:
            cache_key = self._ai_fallback_cache_key(request)
            cache[cache_key] = corrections.get(request.index)
            cache.move_to_end(cache_key)

        while len(cache) > self._MAX_AI_FALLBACK_CACHE_ENTRIES:
            cache.popitem(last=False)

    def _ai_fallback_cache_key(
        self,
        request: _MedicationNameFallbackRequest,
    ) -> tuple[str, tuple[str, ...]]:
        return (
            self._normalize_name(request.raw_name),
            tuple(candidate.item_name for candidate in request.candidates),
        )

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
            response = await ai_client.aio.models.generate_content(
                model=model_name,
                contents=[prompt],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=self._ai_correction_response_schema(),
                    temperature=0.0,
                ),
            )
            response_data = json.loads(self._clean_json_response(response.text))
        except Exception as exc:
            logger.warning("Medication name AI fallback failed: %s", exc)
            return None

        if not isinstance(response_data, dict):
            return None

        return self._select_ai_verified_corrections(
            response_data,
            fallback_requests,
        )

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

    def _build_candidates(
        self,
        normalized_name: str,
    ) -> list[_MedicationNameCandidate]:
        candidates = [
            _MedicationNameCandidate(
                normalized_name=normalized_name,
                source="local_catalog_exact",
                confidence=1.0,
            )
        ]
        for variant in self._hangul_vowel_variants(normalized_name):
            candidates.append(
                _MedicationNameCandidate(
                    normalized_name=variant,
                    source="local_catalog_ocr_vowel_variant",
                    confidence=0.92,
                )
            )

        deduplicated_candidates: list[_MedicationNameCandidate] = []
        seen_names = set()
        for candidate in candidates:
            if candidate.normalized_name in seen_names:
                continue
            seen_names.add(candidate.normalized_name)
            deduplicated_candidates.append(candidate)
            if len(deduplicated_candidates) >= self._MAX_CANDIDATES:
                break
        return deduplicated_candidates

    def _find_catalog_match(
        self,
        candidates: list[_MedicationNameCandidate],
    ) -> tuple[_MedicationNameCandidate, str] | None:
        normalized_names = [candidate.normalized_name for candidate in candidates]
        basic_matches = {
            row.normalized_item_name: row.item_name
            for row in (
                self.db.query(_DrugBasicInfo)
                .filter(_DrugBasicInfo.normalized_item_name.in_(normalized_names))
                .order_by(_DrugBasicInfo.item_name.asc())
                .all()
            )
        }
        approval_matches = {
            row.normalized_item_name: row.item_name
            for row in (
                self.db.query(_DrugApprovalInfo)
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
        return None

    def _find_similar_catalog_names(
        self,
        normalized_name: str,
    ) -> list[_CatalogMedicationName]:
        catalog_candidates_by_name: dict[str, _CatalogMedicationName] = {}
        for fragment in self._candidate_fragments(normalized_name):
            for model in (_DrugBasicInfo, _DrugApprovalInfo):
                for row in (
                    self.db.query(model)
                    .filter(
                        model.normalized_item_name.like(
                            self._like_pattern(fragment),
                            escape="\\",
                        )
                    )
                    .order_by(model.item_name.asc())
                    .limit(self._MAX_FRAGMENT_QUERY_ROWS)
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

    def _candidate_fragments(self, normalized_name: str) -> list[str]:
        if not normalized_name:
            return []

        window_size = 3 if len(normalized_name) >= 3 else len(normalized_name)
        fragments = [
            normalized_name[index : index + window_size]
            for index in range(0, len(normalized_name) - window_size + 1)
        ]
        fragments.sort(key=lambda fragment: (-len(fragment), fragment))
        deduplicated_fragments: list[str] = []
        seen_fragments = set()
        for fragment in fragments:
            if fragment in seen_fragments:
                continue
            seen_fragments.add(fragment)
            deduplicated_fragments.append(fragment)
        return deduplicated_fragments

    def _like_pattern(self, fragment: str) -> str:
        escaped_fragment = (
            fragment.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        )
        return f"%{escaped_fragment}%"

    def _name_similarity(self, left: str, right: str) -> float:
        return SequenceMatcher(None, left, right).ratio()

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

    def _hangul_medial_index(self, character: str) -> int | None:
        code_point = ord(character)
        if code_point < self._HANGUL_BASE or code_point > self._HANGUL_LAST:
            return None

        syllable_index = code_point - self._HANGUL_BASE
        return (syllable_index % self._HANGUL_BLOCK_SIZE) // self._HANGUL_FINAL_COUNT

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

    def _normalize_name(self, name: str) -> str:
        return self._WHITESPACE_PATTERN.sub("", name or "").strip().lower()

    def _clean_json_response(self, response_text: str) -> str:
        cleaned_text = response_text.strip()
        if cleaned_text.startswith("```json"):
            cleaned_text = cleaned_text[7:]
        if cleaned_text.startswith("```"):
            cleaned_text = cleaned_text[3:]
        if cleaned_text.endswith("```"):
            cleaned_text = cleaned_text[:-3]
        return cleaned_text.strip()

    def _safe_float(self, value: Any) -> float:
        try:
            return float(value)
        except (TypeError, ValueError):
            return 0.0

    def _safe_int(self, value: Any) -> int:
        try:
            return int(value)
        except (TypeError, ValueError):
            return -1

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
        db: Session | None = None,
        medication_name_verifier: _PrescriptionMedicationNameVerifier | None = None,
    ) -> None:
        self.client = client or genai.Client(
            api_key=settings.GEMINI_API_KEY,
            http_options={"api_version": "v1alpha"},
        )
        self.model_name = model_name
        self.medication_name_verifier = (
            medication_name_verifier or _PrescriptionMedicationNameVerifier(db=db)
        )

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

        safe_data = normalize_prescription_payload(
            self._apply_secondary_masking(raw_data),
        )
        prescription_date = safe_data.get("prescription_date", "정보 없음")
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
            "hospital_name": safe_data.get("hospital_name", "정보 없음"),
            "prescription_date": prescription_date,
            "medications": medication_schedules,
            "raw_medication_count": safe_data.get(
                "raw_medication_count",
                len(medication_schedules),
            ),
            "parsed_medication_count": len(medication_schedules),
            "skipped_medication_count": safe_data.get("skipped_medication_count", 0),
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

    async def _to_verified_medication_schedules(
        self,
        items: list[dict[str, Any]],
    ) -> list[tuple[MedicationSchedule, _MedicationNameVerification]]:
        medication_schedules = [
            MedicationSchedule(**item).getAnalysisResult() for item in items
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

    async def _to_verified_medication_schedule(
        self,
        item: dict[str, Any],
    ) -> tuple[MedicationSchedule, _MedicationNameVerification]:
        verified_schedules = await self._to_verified_medication_schedules([item])
        return verified_schedules[0]

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
