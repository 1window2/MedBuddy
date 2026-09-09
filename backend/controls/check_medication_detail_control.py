# File Name: check_medication_detail_control.py
# Role: Normalizes OCR drug queries and combines local catalogs, Redis and public APIs with image and approval-summary enrichment.

import asyncio
import json
import logging
import math
import re
from difflib import SequenceMatcher
from typing import Any, Callable, TypeVar

import redis.asyncio as redis
from google import genai
from sqlalchemy import or_
from sqlalchemy.orm import Session, sessionmaker

from boundaries.public_drug_api_boundary import (
    PillImageAPI,
    PublicDrugLargeAPI,
    PublicDrugSmallAPI,
    read_public_image_url,
    read_public_item_name,
    read_public_item_sequence,
)
from core.config import settings
from entities.medication_detail_entity import (
    MedicationDetail,
    _DrugApprovalInfo,
    _DrugBasicInfo,
)
from schemas.medication import MedicationResponse

logger = logging.getLogger(__name__)

_CandidateT = TypeVar("_CandidateT")


# 함수이름: _read_text
# 함수역할:
# - 값을 문자열로 정리하고 None 또는 공백뿐인 값에는 표시용 기본 문구를 적용한다.
# 매개변수:
# - value (Any): 공공 약품 필드의 원본 값.
# - default (str): 값이 없거나 비었을 때 표시할 대체 문구.
# 반환값:
# - 공백을 제거한 문자열 또는 default.
def _read_text(value: Any, default: str = "정보 없음") -> str:
    if value is None:
        return default

    text = str(value).strip()
    return text if text else default


# Class Name: _MedicationTextNormalizer
# Role:
# - Internal helper for medication search keyword normalization.
# Responsibilities:
# - Normalize OCR or UI-provided medication text.
# - Strip dosage and dosage-form suffixes from search keywords.
class _MedicationTextNormalizer:
    MAX_SEARCH_KEYWORDS = 24
    _DOSAGE_PATTERN = re.compile(
        r"\d{1,10}(?:\.\d{1,5})?\s{0,5}(?:mg|g|ml|밀리그램|밀리그람|그램|그람|밀리리터)",
        flags=re.IGNORECASE,
    )
    _DOSAGE_FORM_SUFFIX_PATTERN = re.compile(
        r"(?:구강붕해정|필름코팅정|연질캡슐|서방정|장용정|츄어블정|현탁액|점안액|주사액|캡슐|캅셀|크림|시럽|과립|연고|패취|패치|정|액|산|겔|주)$"
    )
    _MANUFACTURER_PREFIXES = (
        "대웅바이오",
        "대웅",
        "종근당",
        "유한",
        "한미",
        "동아",
        "일동",
        "삼진",
        "신풍",
        "휴온스",
        "보령",
        "광동",
        "동화",
        "삼일",
        "명문",
        "한국",
        "국제",
        "환인",
        "대원",
        "중외",
        "일양",
        "경동",
        "영진",
        "하나",
        "알리코",
        "마더스",
        "넥스팜",
    )
    _HANGUL_OCR_VARIANT_PAIRS = (
        ("에", "애"),
        ("레", "래"),
        ("네", "내"),
        ("데", "대"),
        ("게", "개"),
        ("베", "배"),
        ("세", "새"),
        ("메", "매"),
        ("제", "재"),
        ("체", "채"),
        ("페", "패"),
        ("헤", "해"),
        ("케", "캐"),
    )

    # 함수이름: normalize_raw_text
    # 함수역할:
    # - OCR 텍스트의 줄바꿈·연속 공백과 전각·대괄호 표기를 통일한다.
    # 매개변수:
    # - raw_text (str): 약품명 정규화 전의 원본 OCR 텍스트.
    # 반환값:
    # - 검색 후보 생성에 사용할 정리된 약품 텍스트.
    def normalize_raw_text(self, raw_text: str) -> str:
        normalized_text = (
            raw_text.replace("\n", " ")
            .replace("（", "(")
            .replace("）", ")")
            .replace("[", "(")
            .replace("]", ")")
        )
        return " ".join(normalized_text.split()).strip()

    # Function Name: build_search_keywords
    # Description:
    # - Expands the outside text and parenthesized names into bounded, deduplicated OCR search variants.
    # Parameters:
    # - raw_text (str): Source OCR text before medication-name normalization.
    # Returns:
    # - Ordered search keywords up to MAX_SEARCH_KEYWORDS; empty for blank input.
    def build_search_keywords(self, raw_text: str) -> list[str]:
        normalized_text = self.normalize_raw_text(raw_text)
        if not normalized_text:
            return []

        outside_parentheses, parenthesized_candidates = (
            self._split_parenthesized_text(normalized_text)
        )
        raw_candidates = [outside_parentheses, normalized_text]
        raw_candidates.extend(parenthesized_candidates)

        search_keywords: list[str] = []
        for candidate in raw_candidates:
            search_keywords.extend(self._candidate_variants(candidate))

        return self._deduplicate_keywords(search_keywords)[
            : self.MAX_SEARCH_KEYWORDS
        ]

    # Function Name: _split_parenthesized_text
    # Description:
    # - Separates balanced parenthesized names while retaining unmatched parentheses in the outside text.
    # Parameters:
    # - normalized_text (str): OCR text with whitespace and bracket notation already normalized.
    # Returns:
    # - Normalized outside text and inner candidates of 1-80 characters.
    def _split_parenthesized_text(self, normalized_text: str) -> tuple[str, list[str]]:
        outside_chars: list[str] = []
        parenthesized_candidates: list[str] = []
        parenthesized_chars: list[str] | None = None
        parenthesis_depth = 0
        for character in normalized_text:
            if parenthesized_chars is None:
                if character == "(":
                    parenthesized_chars = []
                    parenthesis_depth = 1
                else:
                    outside_chars.append(character)
                continue
            if character == "(":
                parenthesis_depth += 1
                parenthesized_chars.append(character)
                continue
            if character == ")":
                parenthesis_depth -= 1
                if parenthesis_depth > 0:
                    parenthesized_chars.append(character)
                    continue
                inner_text = "".join(parenthesized_chars).strip()
                if 1 <= len(inner_text) <= 80:
                    parenthesized_candidates.append(inner_text)
                parenthesized_chars = None
                continue
            parenthesized_chars.append(character)

        if parenthesized_chars is not None:
            outside_chars.append("(")
            outside_chars.extend(parenthesized_chars)

        return self.normalize_raw_text("".join(outside_chars)), parenthesized_candidates

    # 함수이름: _candidate_variants
    # 함수역할:
    # - 한 약품명 후보에서 용량 제거, 제형 제거, 제조사 제거, OCR 보정 후보를 만든다.
    # 매개변수:
    # - candidate (str): 원본에서 추출한 약품명 후보
    # 반환값:
    # - 검색 시도 순서를 보존한 약품명 후보 목록
    def _candidate_variants(self, candidate: str) -> list[str]:
        normalized_candidate = self.normalize_raw_text(candidate)
        if not normalized_candidate:
            return []

        parts = self._DOSAGE_PATTERN.split(normalized_candidate)
        dosage_trimmed_candidate = parts[0].strip() if parts else normalized_candidate
        structural_keywords: list[str] = []
        for base_keyword in [dosage_trimmed_candidate, normalized_candidate]:
            structural_keywords.extend(self._structural_variants(base_keyword))

        ocr_keywords: list[str] = []
        for keyword in structural_keywords:
            ocr_keywords.extend(self._hangul_ocr_variants(keyword))

        return self._deduplicate_keywords([*structural_keywords, *ocr_keywords])

    # 함수이름: _structural_variants
    # 함수역할:
    # - 공백 제거, 제형 제거, 제조사 접두어 제거를 적용한 구조적 검색 후보를 만든다.
    # 매개변수:
    # - keyword (str): 보정 전 검색어
    # 반환값:
    # - 구조적으로 단순화된 검색어 후보 목록
    def _structural_variants(self, keyword: str) -> list[str]:
        spacing_keywords = [keyword]
        compact_keyword = keyword.replace(" ", "")
        if compact_keyword != keyword:
            spacing_keywords.append(compact_keyword)

        structural_keywords: list[str] = []
        for spacing_keyword in spacing_keywords:
            structural_keywords.append(spacing_keyword)
            dosage_form_stripped = self._strip_dosage_form(spacing_keyword)
            structural_keywords.append(dosage_form_stripped)
            structural_keywords.append(self._strip_manufacturer_prefix(spacing_keyword))
            structural_keywords.append(
                self._strip_manufacturer_prefix(dosage_form_stripped)
            )

        return self._deduplicate_keywords(structural_keywords)

    # 함수이름: _strip_dosage_form
    # 함수역할:
    # - 검색 폭을 넓히기 위해 약품명 끝의 정/캡슐 같은 제형 표기를 제거한다.
    # 매개변수:
    # - keyword (str): 제형 표기가 포함될 수 있는 검색어
    # 반환값:
    # - 제형 표기를 제거한 검색어
    def _strip_dosage_form(self, keyword: str) -> str:
        return self._DOSAGE_FORM_SUFFIX_PATTERN.sub("", keyword).strip()

    # 함수이름: _strip_manufacturer_prefix
    # 함수역할:
    # - 제조사명이 앞에 붙은 제품명에서 성분명 중심 후보를 만든다.
    # 매개변수:
    # - keyword (str): 제조사 접두어가 포함될 수 있는 검색어
    # 반환값:
    # - 알려진 제조사 접두어를 제거한 검색어
    def _strip_manufacturer_prefix(self, keyword: str) -> str:
        for prefix in self._MANUFACTURER_PREFIXES:
            if keyword.startswith(prefix) and len(keyword) > len(prefix) + 1:
                return keyword[len(prefix) :].strip()
        return keyword

    # 함수이름: _hangul_ocr_variants
    # 함수역할:
    # - 에/애, 레/래처럼 OCR에서 자주 뒤바뀌는 한글 모음 후보를 추가한다.
    # 매개변수:
    # - keyword (str): 원본 검색어 후보
    # 반환값:
    # - 한글 OCR 보정 검색어 후보 목록
    def _hangul_ocr_variants(self, keyword: str) -> list[str]:
        variants: list[str] = []
        for source, target in self._HANGUL_OCR_VARIANT_PAIRS:
            if source in keyword:
                variants.append(keyword.replace(source, target))
            if target in keyword:
                variants.append(keyword.replace(target, source))
        return variants

    # 함수이름: _deduplicate_keywords
    # 함수역할:
    # - 검색어 후보의 순서를 유지하면서 중복과 빈 문자열을 제거한다.
    # 매개변수:
    # - keywords (list[str]): 정리 전 검색어 후보 목록
    # 반환값:
    # - 중복이 제거된 검색어 후보 목록
    def _deduplicate_keywords(self, keywords: list[str]) -> list[str]:
        seen_keywords = set()
        deduplicated_keywords: list[str] = []
        for keyword in keywords:
            normalized_keyword = keyword.strip()
            if not normalized_keyword or normalized_keyword in seen_keywords:
                continue
            seen_keywords.add(normalized_keyword)
            deduplicated_keywords.append(normalized_keyword)
        return deduplicated_keywords


# 클래스명: _MedicationNameMatcher
# 역할:
# - OCR 검색어와 약품 후보 이름의 유사도를 계산하고 신뢰 가능한 후보를 선별한다.
# 주요 책임:
# - 기존 검색어 정규화 결과를 비교 가능한 문자열 키로 변환한다.
# - 완전 일치, 포함 관계, 문자열 유사도를 조합해 이름 점수를 계산한다.
# - 짧은 약 이름에는 더 엄격한 임계값을 적용해 오탐을 줄인다.
# 속성:
# - text_normalizer (_MedicationTextNormalizer): OCR 특성을 반영한 약품명 정규화·변형 생성기.
class _MedicationNameMatcher:
    _NON_NAME_CHARACTER_PATTERN = re.compile(r"[^0-9a-z가-힣]+", re.IGNORECASE)
    _DOSAGE_VALUE_PATTERN = re.compile(
        r"(\d+(?:\.\d+)?)\s*(mg|g|ml|밀리그램|밀리그람|그램|그람|밀리리터)",
        re.IGNORECASE,
    )
    _LONG_NAME_MIN_SCORE = 0.76
    _MEDIUM_NAME_MIN_SCORE = 0.84
    _SHORT_NAME_MIN_SCORE = 0.96

    # 함수이름: __init__
    # 함수역할:
    # - 비교 키 생성에 사용할 약품명 정규화기를 주입하거나 기본 생성한다.
    # 매개변수:
    # - text_normalizer (_MedicationTextNormalizer | None): OCR 특성을 반영한 약품명 정규화·변형 생성기.
    # 반환값:
    # - 없음.
    def __init__(
        self,
        text_normalizer: _MedicationTextNormalizer | None = None,
    ) -> None:
        self.text_normalizer = text_normalizer or _MedicationTextNormalizer()

    # 함수이름: calculate_score
    # 함수역할:
    # - OCR 검색어와 공공데이터 약품명의 가장 높은 이름 유사도를 계산한다.
    # 매개변수:
    # - search_text (str): OCR 보정 과정을 거친 검색어
    # - candidate_name (str): DB 또는 공공데이터 API가 반환한 약품명
    # 반환값:
    # - 0.0 이상 1.0 이하의 이름 유사도 점수
    def calculate_score(self, search_text: str, candidate_name: str) -> float:
        direct_search_key = self._normalize_match_key(search_text)
        direct_candidate_key = self._normalize_match_key(candidate_name)
        direct_score = self._calculate_pair_score(
            direct_search_key,
            direct_candidate_key,
        )
        search_keys = self._build_match_keys(search_text)
        candidate_keys = self._build_match_keys(candidate_name)
        if not search_keys or not candidate_keys:
            return direct_score

        variant_score = max(
            self._calculate_pair_score(search_key, candidate_key)
            for search_key in search_keys
            for candidate_key in candidate_keys
        )
        name_score = max(direct_score, min(variant_score, 0.92))
        return self._adjust_dosage_score(
            name_score,
            search_text,
            candidate_name,
        )

    # 함수이름: is_confident_match
    # 함수역할:
    # - 검색어 길이에 따른 최소 점수를 적용해 후보를 사용할 수 있는지 판정한다.
    # 매개변수:
    # - search_text (str): OCR 보정 과정을 거친 검색어
    # - candidate_name (str): DB 또는 공공데이터 API가 반환한 약품명
    # 반환값:
    # - 신뢰 가능한 이름 후보이면 True, 아니면 False
    def is_confident_match(self, search_text: str, candidate_name: str) -> bool:
        score = self.calculate_score(search_text, candidate_name)
        return score >= self._required_score(search_text)

    # 함수이름: rank_candidates
    # 함수역할:
    # - 여러 약품 후보 중 최소 유사도를 통과한 항목만 점수순으로 정렬한다.
    # 매개변수:
    # - search_text (str): OCR 보정 과정을 거친 검색어
    # - candidates (list[_CandidateT]): DB 또는 API에서 조회한 원본 후보 목록
    # - name_reader (Callable[[_CandidateT], str]): 후보 객체에서 약품명을 읽는 함수
    # - limit (int): 반환할 최대 후보 수
    # 반환값:
    # - 신뢰도 점수가 높은 순서로 정렬된 후보 목록
    def rank_candidates(
        self,
        search_text: str,
        candidates: list[_CandidateT],
        name_reader: Callable[[_CandidateT], str],
        limit: int,
    ) -> list[_CandidateT]:
        ranked_candidates: list[tuple[float, int, _CandidateT]] = []
        required_score = self._required_score(search_text)
        for candidate_index, candidate in enumerate(candidates):
            score = self.calculate_score(search_text, name_reader(candidate))
            if score < required_score:
                continue
            ranked_candidates.append((score, candidate_index, candidate))

        ranked_candidates.sort(key=lambda item: (-item[0], item[1]))
        return [item[2] for item in ranked_candidates[:limit]]

    # 함수이름: _build_match_keys
    # 함수역할:
    # - 괄호, 용량, 제형, 제조사와 OCR 변형을 반영한 비교 키를 생성한다.
    # 매개변수:
    # - value (str): 비교할 원본 약품명
    # 반환값:
    # - 중복과 기호가 제거된 이름 비교 키 목록
    def _build_match_keys(self, value: str) -> list[str]:
        raw_candidates = self.text_normalizer.build_search_keywords(value)
        normalized_keys = [
            self._normalize_match_key(candidate) for candidate in raw_candidates
        ]
        return list(dict.fromkeys(key for key in normalized_keys if key))

    # 함수이름: _normalize_match_key
    # 함수역할:
    # - 약품명에서 공백과 기호를 제거하고 영문 대소문자를 통일한다.
    # 매개변수:
    # - value (str): 정규화할 약품명
    # 반환값:
    # - 숫자, 영문, 한글만 남긴 비교 문자열
    @classmethod
    def _normalize_match_key(cls, value: str) -> str:
        return cls._NON_NAME_CHARACTER_PATTERN.sub("", value).casefold()

    # 함수이름: _calculate_pair_score
    # 함수역할:
    # - 두 비교 키의 완전 일치, 포함 관계, 문자열 배열 유사도를 계산한다.
    # 매개변수:
    # - left (str): 첫 번째 이름 비교 키
    # - right (str): 두 번째 이름 비교 키
    # 반환값:
    # - 0.0 이상 1.0 이하의 두 문자열 유사도
    @staticmethod
    def _calculate_pair_score(left: str, right: str) -> float:
        if not left or not right:
            return 0.0
        if left == right:
            return 1.0

        shorter_length = min(len(left), len(right))
        longer_length = max(len(left), len(right))
        containment_score = 0.0
        if shorter_length >= 4 and (left in right or right in left):
            containment_score = 0.90 + (0.10 * shorter_length / longer_length)

        sequence_score = SequenceMatcher(
            None,
            left,
            right,
            autojunk=False,
        ).ratio()
        return max(containment_score, sequence_score)

    # 함수이름: _required_score
    # 함수역할:
    # - 짧은 약품명의 오탐을 줄이기 위해 검색어 길이별 최소 점수를 선택한다.
    # 매개변수:
    # - search_text (str): OCR 보정 과정을 거친 검색어
    # 반환값:
    # - 해당 검색어에 적용할 최소 유사도 점수
    def _required_score(self, search_text: str) -> float:
        normalized_search = self._normalize_match_key(search_text)
        if len(normalized_search) <= 3:
            return self._SHORT_NAME_MIN_SCORE
        if len(normalized_search) <= 5:
            return self._MEDIUM_NAME_MIN_SCORE
        return self._LONG_NAME_MIN_SCORE

    # 함수이름: _adjust_dosage_score
    # 함수역할:
    # - 이름이 비슷한 다른 함량 제품보다 OCR 함량과 같은 후보를 우선한다.
    # 매개변수:
    # - name_score (float): 약품명 문자열만으로 계산한 유사도
    # - search_text (str): OCR 보정 과정을 거친 검색어
    # - candidate_name (str): DB 또는 공공데이터 API가 반환한 약품명
    # 반환값:
    # - 함량 일치 여부를 반영해 0.0 이상 1.0 이하로 보정한 점수
    def _adjust_dosage_score(
        self,
        name_score: float,
        search_text: str,
        candidate_name: str,
    ) -> float:
        search_dosages = self._extract_dosage_values(search_text)
        candidate_dosages = self._extract_dosage_values(candidate_name)
        if not search_dosages or not candidate_dosages:
            return name_score
        if search_dosages & candidate_dosages:
            return min(1.0, name_score + 0.03)
        return max(0.0, name_score - 0.08)

    # 함수이름: _extract_dosage_values
    # 함수역할:
    # - 영문과 한글 함량 단위를 공통 형식으로 바꿔 비교 가능한 값으로 추출한다.
    # 매개변수:
    # - value (str): 함량 표기가 포함될 수 있는 약품명
    # 반환값:
    # - 숫자와 표준화된 단위를 결합한 함량 값 집합
    def _extract_dosage_values(self, value: str) -> set[str]:
        unit_aliases = {
            "밀리그램": "mg",
            "밀리그람": "mg",
            "그램": "g",
            "그람": "g",
            "밀리리터": "ml",
        }
        dosage_values: set[str] = set()
        for amount, raw_unit in self._DOSAGE_VALUE_PATTERN.findall(value):
            normalized_unit = unit_aliases.get(raw_unit.casefold(), raw_unit.casefold())
            dosage_values.add(f"{amount}:{normalized_unit}")
        return dosage_values


# Class Name: _MedicationDetailCache
# Role:
# - Internal Redis cache boundary for medication detail lookup.
# Responsibilities:
# - Read cached MedicationDetail lists.
# - Save MedicationDetail lists without failing the main use case on Redis errors.
# Attributes:
# - redis_client (redis.Redis): Async Redis client used as optional cache storage.
class _MedicationDetailCache:
    CACHE_TTL_SECONDS = 604800

    # 함수이름: __init__
    # 함수역할:
    # - Redis 약품 상세 캐시 연결을 준비하고 사용 가능 상태로 시작한다.
    # 매개변수:
    # - redis_client (redis.Redis | None): 직렬화된 약품 상세를 저장·조회할 Redis 연결.
    # 반환값:
    # - 없음.
    def __init__(self, redis_client: redis.Redis | None = None) -> None:
        self.redis_client = redis_client or redis.from_url(
            settings.REDIS_URL,
            decode_responses=True,
        )
        self._is_available = True

    # Function Name: get
    # Description:
    # - Attempts to load MedicationDetail values from Redis.
    # - Cache failures are treated as misses to preserve service availability.
    # Parameters:
    # - drug_name (str): Search keyword used as cache key suffix.
    # Returns:
    # - Cached MedicationDetail list, or None when missing/unavailable.
    async def get(self, drug_name: str) -> list[MedicationDetail] | None:
        if not self._is_available:
            return None

        try:
            cached_data = await self.redis_client.get(self._cache_key(drug_name))
            if not cached_data:
                return None

            logger.info("[Redis] medication detail cache hit.")
            cached_items = json.loads(cached_data)
            if not isinstance(cached_items, list):
                return None

            return [
                MedicationDetail(
                    **{
                        **item,
                        "source": f"[Cache] {item.get('source', '')}",
                    }
                )
                for item in cached_items
                if isinstance(item, dict)
            ]
        except Exception as exc:
            self._disable_cache("lookup", exc)
            return None

    # Function Name: set
    # Description:
    # - Stores MedicationDetail values in Redis.
    # - Cache failures are logged but do not fail the use case.
    # Parameters:
    # - drug_name (str): Search keyword used as cache key suffix.
    # - medication_details (list[MedicationDetail]): MedicationDetail list to cache.
    # Returns:
    # - None.
    async def set(
        self,
        drug_name: str,
        medication_details: list[MedicationDetail],
    ) -> None:
        if not self._is_available or not medication_details:
            return

        try:
            payload = [
                detail.getMedicationDetail()
                for detail in medication_details
            ]
            await self.redis_client.setex(
                self._cache_key(drug_name),
                self.CACHE_TTL_SECONDS,
                json.dumps(payload, ensure_ascii=False),
            )
            logger.info("[Redis] medication detail cached.")
        except Exception as exc:
            self._disable_cache("save", exc)

    # Function Name: close
    # Description:
    # - Closes the Redis client and its reusable connections.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def close(self) -> None:
        await self.redis_client.aclose()

    # Function Name: _cache_key
    # Description:
    # - Places a medication query in the drug_info Redis namespace.
    # Parameters:
    # - drug_name (str): Medication name to search or serialize.
    # Returns:
    # - Redis key for the supplied drug name.
    def _cache_key(self, drug_name: str) -> str:
        return f"drug_info:{drug_name}"

    # Function Name: _disable_cache
    # Description:
    # - Disables Redis use for this process after an operation failure and logs only the exception type.
    # Parameters:
    # - operation (str): Cache operation name included in the failure log.
    # - exc (Exception): Caught failure whose type is logged without its payload.
    # Returns:
    # - None.
    def _disable_cache(self, operation: str, exc: Exception) -> None:
        self._is_available = False
        logger.warning(
            "Redis %s failed; disabling medication cache for this process: %s",
            operation,
            type(exc).__name__,
        )


# Class Name: _MedicationSummaryGenerator
# Role:
# - Produces patient-facing summaries from detailed drug-approval documents through a bounded AI request.
# Responsibilities:
# - Summarize advanced approval documents into MedicationDetail fields.
# Attributes:
# - ai_client (genai.Client): Gemini client for bounded external text generation.
# - model_name (str): Configured AI model identifier.
class _MedicationSummaryGenerator:
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
    # Parameters:
    # - drug_name (str): Original search keyword.
    # - advanced_item (dict[str, Any]): Raw item from the advanced public API or local approval DB.
    # Returns:
    # - MedicationDetail generated from Gemini summary output.
    async def summarize_advanced_item(
        self,
        drug_name: str,
        advanced_item: dict[str, Any],
    ) -> MedicationDetail:
        actual_item_name = _read_text(advanced_item.get("ITEM_NAME"), drug_name)
        raw_efficacy = _read_text(advanced_item.get("EE_DOC_DATA"))[:2000]
        raw_usage = _read_text(advanced_item.get("UD_DOC_DATA"))[:2000]
        raw_warning = _read_text(advanced_item.get("NB_DOC_DATA"))[:2000]

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
        except TimeoutError as exc:
            logger.warning("Gemini medication summary timed out.")
            raise RuntimeError("Medication summary generation timed out.") from exc
        except Exception as exc:
            logger.error("Gemini AI summary failed: %s", type(exc).__name__)
            raise RuntimeError("AI 요약 처리 중 오류가 발생했습니다.") from exc

        return MedicationDetail(
            item_seq=read_public_item_sequence(advanced_item),
            item_name=actual_item_name,
            efficacy=_read_text(summary_data.get("efficacy"), "요약 실패"),
            usage_method=_read_text(summary_data.get("use_method"), "요약 실패"),
            warning=_read_text(summary_data.get("warning_message"), "요약 실패"),
            image_url=read_public_image_url(advanced_item),
            source="Advanced (허가정보) + AI 요약",
            ai_guide="",
        )


# 클래스명: _LocalMedicationCatalog
# 역할:
# - 로컬 약품 카탈로그에서 이름이 일치하는 기본 정보와 허가 정보 요약을 조회한다.
# 주요 책임:
# - 기본·허가 카탈로그 후보의 이름 신뢰도를 비교하고 저장 요약을 재사용하거나 새 요약을 보관한다.
# 속성:
# - db (Session | None): 현재 작업에 사용할 SQLAlchemy 세션.
# - summary_generator (_MedicationSummaryGenerator): 상세 허가 문서의 AI 요약 생성기.
class _LocalMedicationCatalog:
    _WHITESPACE_PATTERN = re.compile(r"\s+")
    _FUZZY_ANCHOR_LENGTH = 3
    _FUZZY_CANDIDATE_LIMIT = 30

    # 함수이름: __init__
    # 함수역할:
    # - 약품 조회 세션, 이름 일치 판정기와 허가 문서 요약기를 연결한다.
    # 매개변수:
    # - db (Session | None): 현재 작업에 사용할 SQLAlchemy 세션.
    # - summary_generator (_MedicationSummaryGenerator): 상세 허가 문서의 AI 요약 생성기.
    # - name_matcher (_MedicationNameMatcher | None): 약품명 유사도 점수 계산과 신뢰도 필터.
    # 반환값:
    # - 없음.
    def __init__(
        self,
        db: Session | None,
        summary_generator: _MedicationSummaryGenerator,
        name_matcher: _MedicationNameMatcher | None = None,
    ) -> None:
        self.db = db
        self.summary_generator = summary_generator
        self.name_matcher = name_matcher or _MedicationNameMatcher()

    # 함수이름: fetch_drug_info
    # 함수역할:
    # - 로컬 기본 정보를 우선 반환하고, 없으면 가장 가까운 허가 정보의 요약을 사용한다.
    # 매개변수:
    # - drug_name (str): 검색 또는 직렬화할 약품명.
    # 반환값:
    # - 약품 상세 목록; DB나 일치 결과가 없으면 빈 목록.
    async def fetch_drug_info(self, drug_name: str) -> list[MedicationDetail]:
        if self.db is None:
            return []

        basic_items, approval_items = await self._search_catalog(drug_name)
        if basic_items:
            logger.info(
                "[Local DB] e약은요 lookup succeeded (%s items).",
                len(basic_items),
            )
            return await self._build_basic_details(basic_items)

        if not approval_items:
            return []

        logger.info("[Local DB] approval lookup succeeded.")
        return [await self._build_approval_detail(drug_name, approval_items[0])]

    # 함수이름: _search_catalog
    # 함수역할:
    # - 로컬 카탈로그 조회를 이벤트 루프 밖의 독립 DB 세션에서 처리한다.
    # - 연결별 DB가 분리되는 인메모리 SQLite에서는 현재 테스트 세션을 사용한다.
    # 매개변수:
    # - drug_name (str): 검색 또는 직렬화할 약품명.
    # 반환값:
    # - 이름 신뢰도 기준을 통과한 기본 카탈로그 행과 허가 카탈로그 행의 쌍.
    async def _search_catalog(
        self,
        drug_name: str,
    ) -> tuple[list[_DrugBasicInfo], list[_DrugApprovalInfo]]:
        if self.db is None:
            return [], []
        bind = self.db.get_bind()
        uses_memory_sqlite = bind.dialect.name == "sqlite" and bind.url.database in {
            None,
            "",
            ":memory:",
        }
        if uses_memory_sqlite:
            basic_items = self._search_basic(drug_name)
            return basic_items, [] if basic_items else self._search_approval(drug_name)
        return await asyncio.to_thread(
            self._search_catalog_with_isolated_session,
            drug_name,
        )

    # 함수이름: _search_catalog_with_isolated_session
    # 함수역할:
    # - 작업 스레드 안에서 별도 세션을 만들고 기본·허가 카탈로그를 순서대로 조회한다.
    # 매개변수:
    # - drug_name (str): 검색 또는 직렬화할 약품명.
    # 반환값:
    # - 독립 세션에서 읽은 기본·허가 카탈로그 후보 목록의 쌍.
    def _search_catalog_with_isolated_session(
        self,
        drug_name: str,
    ) -> tuple[list[_DrugBasicInfo], list[_DrugApprovalInfo]]:
        if self.db is None:
            return [], []
        worker_session_factory = sessionmaker(bind=self.db.get_bind())
        worker_db = worker_session_factory()
        try:
            worker = _LocalMedicationCatalog(
                db=worker_db,
                summary_generator=self.summary_generator,
                name_matcher=self.name_matcher,
            )
            basic_items = worker._search_basic(drug_name)
            return basic_items, [] if basic_items else worker._search_approval(drug_name)
        finally:
            worker_db.close()

    # 함수이름: _search_basic
    # 함수역할:
    # - 로컬 e약은요 DB에서 완전 일치를 우선 조회하고 유사 후보를 점수화한다.
    # 매개변수:
    # - drug_name (str): OCR 보정 검색어
    # - limit (int): 반환할 최대 후보 수
    # 반환값:
    # - 이름 유사도 임계값을 통과한 e약은요 후보 목록
    def _search_basic(self, drug_name: str, limit: int = 3) -> list[_DrugBasicInfo]:
        keyword = self._normalize_name(drug_name)
        if not keyword:
            return []

        exact_matches = (
            self.db.query(_DrugBasicInfo)
            .filter(_DrugBasicInfo.normalized_item_name == keyword)
            .limit(limit)
            .all()
        )
        if exact_matches:
            return exact_matches

        candidates = (
            self.db.query(_DrugBasicInfo)
            .filter(self._build_fuzzy_filter(_DrugBasicInfo, keyword))
            .limit(self._FUZZY_CANDIDATE_LIMIT)
            .all()
        )
        return self.name_matcher.rank_candidates(
            drug_name,
            candidates,
            lambda item: item.item_name,
            limit,
        )

    # 함수이름: _search_approval
    # 함수역할:
    # - 로컬 허가정보 DB에서 완전 일치를 우선 조회하고 유사 후보를 점수화한다.
    # 매개변수:
    # - drug_name (str): OCR 보정 검색어
    # - limit (int): 반환할 최대 후보 수
    # 반환값:
    # - 이름 유사도 임계값을 통과한 허가정보 후보 목록
    def _search_approval(
        self,
        drug_name: str,
        limit: int = 1,
    ) -> list[_DrugApprovalInfo]:
        keyword = self._normalize_name(drug_name)
        if not keyword:
            return []

        exact_matches = (
            self.db.query(_DrugApprovalInfo)
            .filter(_DrugApprovalInfo.normalized_item_name == keyword)
            .limit(limit)
            .all()
        )
        if exact_matches:
            return exact_matches

        candidates = (
            self.db.query(_DrugApprovalInfo)
            .filter(self._build_fuzzy_filter(_DrugApprovalInfo, keyword))
            .limit(self._FUZZY_CANDIDATE_LIMIT)
            .all()
        )
        return self.name_matcher.rank_candidates(
            drug_name,
            candidates,
            lambda item: item.item_name,
            limit,
        )

    # 함수이름: _build_fuzzy_filter
    # 함수역할:
    # - 전체 검색어와 부분 앵커 중 하나를 포함하는 로컬 DB 조회 조건을 만든다.
    # 매개변수:
    # - model (type[_DrugBasicInfo] | type[_DrugApprovalInfo]): 조회할 로컬 약품 SQLAlchemy 모델
    # - keyword (str): 공백을 제거한 검색어
    # 반환값:
    # - SQLAlchemy OR 검색 조건
    def _build_fuzzy_filter(
        self,
        model: type[_DrugBasicInfo] | type[_DrugApprovalInfo],
        keyword: str,
    ) -> Any:
        search_fragments = [keyword, *self._build_fuzzy_anchors(keyword)]
        return or_(
            *(
                model.normalized_item_name.like(
                    self._like_pattern(fragment, prefix="%", suffix="%"),
                    escape="\\",
                )
                for fragment in search_fragments
            )
        )

    # 함수이름: _build_fuzzy_anchors
    # 함수역할:
    # - 한두 글자 OCR 오류가 있어도 후보를 찾도록 검색어 앞·중간·뒤 조각을 만든다.
    # 매개변수:
    # - keyword (str): 공백을 제거한 검색어
    # 반환값:
    # - 중복이 제거된 세 글자 검색 조각 목록
    def _build_fuzzy_anchors(self, keyword: str) -> list[str]:
        if len(keyword) < self._FUZZY_ANCHOR_LENGTH + 2:
            return []

        anchor_length = self._FUZZY_ANCHOR_LENGTH
        middle_start = max(0, (len(keyword) - anchor_length) // 2)
        anchors = [
            keyword[:anchor_length],
            keyword[middle_start : middle_start + anchor_length],
            keyword[-anchor_length:],
        ]
        return list(dict.fromkeys(anchor for anchor in anchors if anchor))

    # Function Name: _build_basic_details
    # Description:
    # - Maps stored basic drug records to patient-facing details while preserving safety guidance and image provenance.
    # Parameters:
    # - basic_items (list[_DrugBasicInfo]): Basic drug records with public product and guidance fields.
    # Returns:
    # - MedicationDetail objects in the input record order.
    async def _build_basic_details(
        self,
        basic_items: list[_DrugBasicInfo],
    ) -> list[MedicationDetail]:
        enriched_details = []
        for item in basic_items:
            medication_detail = MedicationDetail(
                item_seq=item.item_seq or "",
                item_name=item.item_name,
                efficacy=item.efficacy or "정보 없음",
                usage_method=item.use_method or "정보 없음",
                warning=item.warning_message or "정보 없음",
                interaction=item.interaction or "",
                side_effect=item.side_effect or "",
                storage_method=item.deposit_method or "",
                image_url=self._read_basic_image_url(item),
                source="Local DB (e약은요)",
            )

            enriched_details.append(medication_detail)

        return enriched_details

    # 함수이름: _build_approval_detail
    # 함수역할:
    # - 저장된 허가 요약을 재사용하거나 원문을 AI로 요약한 뒤 결과를 캐시에 저장한다.
    # 매개변수:
    # - drug_name (str): 검색 또는 직렬화할 약품명.
    # - approval_item (_DrugApprovalInfo): 원문 문서와 선택적 생성 요약을 가진 저장된 허가 정보 행.
    # 반환값:
    # - 로컬 허가 자료 출처를 표시한 약품 상세 정보.
    async def _build_approval_detail(
        self,
        drug_name: str,
        approval_item: _DrugApprovalInfo,
    ) -> MedicationDetail:
        cached_summary = self._build_cached_approval_summary(approval_item)
        if cached_summary is not None:
            return cached_summary

        raw_item = self._load_raw_approval_item(approval_item)
        medication_detail = await self.summary_generator.summarize_advanced_item(
            drug_name,
            raw_item,
        )
        medication_detail = medication_detail.model_copy(
            update={"source": "Local DB (허가정보) + AI 요약"}
        )
        self._save_approval_summary(approval_item, medication_detail)
        return medication_detail

    # Function Name: _build_cached_approval_summary
    # Description:
    # - Reuses an approval summary only when efficacy, usage and warning fields are all populated.
    # Parameters:
    # - approval_item (_DrugApprovalInfo): Stored approval record with raw documents and optional generated summary.
    # Returns:
    # - MedicationDetail with stored guidance, or None when the summary is incomplete.
    def _build_cached_approval_summary(
        self,
        approval_item: _DrugApprovalInfo,
    ) -> MedicationDetail | None:
        if not (
            approval_item.summary_efficacy
            and approval_item.summary_use_method
            and approval_item.summary_warning_message
        ):
            return None

        return MedicationDetail(
            item_seq=approval_item.item_seq or "",
            item_name=approval_item.item_name,
            efficacy=approval_item.summary_efficacy,
            usage_method=approval_item.summary_use_method,
            warning=approval_item.summary_warning_message,
            image_url=read_public_image_url(
                self._load_raw_approval_item(approval_item)
            ),
            source="Local DB (허가정보) + 저장된 AI 요약",
            ai_guide=approval_item.ai_guide,
        )

    # Function Name: _load_raw_approval_item
    # Description:
    # - Decodes the stored approval payload and falls back to database columns when JSON or document fields are unusable.
    # Parameters:
    # - approval_item (_DrugApprovalInfo): Stored approval record with raw documents and optional generated summary.
    # Returns:
    # - Approval document dictionary suitable for summarization.
    def _load_raw_approval_item(
        self,
        approval_item: _DrugApprovalInfo,
    ) -> dict[str, Any]:
        try:
            raw_item = json.loads(approval_item.raw_json)
            if isinstance(raw_item, dict):
                normalized_item = self._normalize_raw_approval_item(
                    raw_item,
                    approval_item,
                )
                if normalized_item is not None:
                    return normalized_item
        except json.JSONDecodeError:
            logger.warning("Local approval raw_json decode failed.")

        return self._approval_columns_to_raw_item(approval_item)

    # Function Name: _normalize_raw_approval_item
    # Description:
    # - Harmonizes basic/approval API field aliases and fills missing identifiers or documents from the stored row.
    # Parameters:
    # - raw_item (dict[str, Any]): Original approval API payload used for field-alias lookup.
    # - approval_item (_DrugApprovalInfo): Stored approval record with raw documents and optional generated summary.
    # Returns:
    # - Canonical approval fields, or None if every guidance document is empty.
    def _normalize_raw_approval_item(
        self,
        raw_item: dict[str, Any],
        approval_item: _DrugApprovalInfo,
    ) -> dict[str, Any] | None:
        normalized_item = {
            "ITEM_SEQ": read_public_item_sequence(raw_item)
            or approval_item.item_seq
            or "",
            "ITEM_NAME": read_public_item_name(raw_item) or approval_item.item_name,
            "EE_DOC_DATA": self._read_first_raw_text(
                raw_item,
                ["EE_DOC_DATA", "efcyQesitm"],
            )
            or approval_item.efficacy_doc,
            "UD_DOC_DATA": self._read_first_raw_text(
                raw_item,
                ["UD_DOC_DATA", "useMethodQesitm"],
            )
            or approval_item.use_method_doc,
            "NB_DOC_DATA": self._read_first_raw_text(
                raw_item,
                ["NB_DOC_DATA", "atpnWarnQesitm"],
            )
            or approval_item.warning_doc,
            "ITEM_IMAGE": read_public_image_url(raw_item),
        }
        if any(
            normalized_item[key]
            for key in ("EE_DOC_DATA", "UD_DOC_DATA", "NB_DOC_DATA")
        ):
            return normalized_item
        return None

    # Function Name: _approval_columns_to_raw_item
    # Description:
    # - Reconstructs an approval API-shaped payload from persisted document columns.
    # Parameters:
    # - approval_item (_DrugApprovalInfo): Stored approval record with raw documents and optional generated summary.
    # Returns:
    # - Product identifiers and efficacy, usage and warning documents with display fallbacks.
    def _approval_columns_to_raw_item(
        self,
        approval_item: _DrugApprovalInfo,
    ) -> dict[str, Any]:
        return {
            "ITEM_SEQ": approval_item.item_seq or "",
            "ITEM_NAME": approval_item.item_name,
            "EE_DOC_DATA": approval_item.efficacy_doc or "정보 없음",
            "UD_DOC_DATA": approval_item.use_method_doc or "정보 없음",
            "NB_DOC_DATA": approval_item.warning_doc or "정보 없음",
        }

    # Function Name: _read_first_raw_text
    # Description:
    # - Searches field aliases in order, including case-insensitive keys, and skips blank values.
    # Parameters:
    # - raw_item (dict[str, Any]): Original approval API payload used for field-alias lookup.
    # - keys (list[str]): Field aliases searched in priority order.
    # Returns:
    # - First nonblank trimmed field value, or an empty string.
    def _read_first_raw_text(
        self,
        raw_item: dict[str, Any],
        keys: list[str],
    ) -> str:
        lowered_items = {
            str(existing_key).lower(): existing_value
            for existing_key, existing_value in raw_item.items()
        }
        for key in keys:
            value = raw_item.get(key)
            if value is None:
                value = lowered_items.get(key.lower())
            if value is not None and str(value).strip():
                return str(value).strip()
        return ""

    # Function Name: _read_basic_image_url
    # Description:
    # - Reads a public medication image from stored basic-catalog JSON.
    # Parameters:
    # - basic_info (_DrugBasicInfo): Stored basic public-drug record including its raw payload.
    # Returns:
    # - Accepted image URL, or an empty string for invalid JSON or absent images.
    def _read_basic_image_url(self, basic_info: _DrugBasicInfo) -> str:
        try:
            raw_item = json.loads(basic_info.raw_json)
        except json.JSONDecodeError:
            return ""

        if not isinstance(raw_item, dict):
            return ""

        return read_public_image_url(raw_item)

    # Function Name: _save_approval_summary
    # Description:
    # - Commits generated guidance onto the approval row; rolls back and logs persistence failures.
    # Parameters:
    # - approval_info (_DrugApprovalInfo): Stored approval record with raw documents and optional generated summary.
    # - medication_detail (MedicationDetail): Patient-facing medication guidance and product metadata.
    # Returns:
    # - None.
    def _save_approval_summary(
        self,
        approval_info: _DrugApprovalInfo,
        medication_detail: MedicationDetail,
    ) -> None:
        try:
            approval_info.summary_efficacy = medication_detail.efficacy
            approval_info.summary_use_method = medication_detail.usage_method
            approval_info.summary_warning_message = medication_detail.warning
            approval_info.ai_guide = medication_detail.ai_guide
            self.db.commit()
        except Exception as exc:
            self.db.rollback()
            logger.warning(
                "Failed to persist local approval summary: %s",
                type(exc).__name__,
            )

    # Function Name: _normalize_name
    # Description:
    # - Removes all whitespace and lowercases medication names for indexed local lookup.
    # Parameters:
    # - name (str): Medication name before catalog-key normalization.
    # Returns:
    # - Normalized catalog name.
    @classmethod
    def _normalize_name(cls, name: str) -> str:
        return cls._WHITESPACE_PATTERN.sub("", name).strip().lower()

    # Function Name: _like_pattern
    # Description:
    # - Escapes client wildcard characters before adding caller-selected SQL LIKE prefixes and suffixes.
    # Parameters:
    # - keyword (str): Literal medication-name fragment for a database search.
    # - prefix (str): Caller-selected SQL LIKE prefix wildcard.
    # - suffix (str): Caller-selected SQL LIKE suffix wildcard.
    # Returns:
    # - Escaped LIKE pattern for literal medication-name matching.
    def _like_pattern(
        self,
        keyword: str,
        prefix: str = "",
        suffix: str = "",
    ) -> str:
        escaped_keyword = (
            keyword.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        )
        return f"{prefix}{escaped_keyword}{suffix}"


# 클래스명: CheckMedicationDetail
# 역할:
# - 약품명 후보를 정규화해 로컬·캐시·공공 API를 조회하고 부족한 이미지와 허가 요약을 보완한다.
# 주요 책임:
# - 검색어 길이와 이름 신뢰도를 검증하고 로컬·Redis·기본 API·허가 API 순서로 상세 정보를 보완한다.
# 속성:
# - text_normalizer (_MedicationTextNormalizer): OCR 특성을 반영한 약품명 정규화·변형 생성기.
# - medication_cache (_MedicationDetailCache): 약품 상세 결과를 보관하는 공유 Redis 캐시.
# - public_drug_small_api (PublicDrugSmallAPI): 기본 공공 약품 정보 API 경계.
# - public_drug_large_api (PublicDrugLargeAPI): 상세 약품 허가 문서 API 경계.
# - pill_image_api (PillImageAPI): 공공 약품 이미지 조회 API 경계.
# - summary_generator (_MedicationSummaryGenerator): 상세 허가 문서의 AI 요약 생성기.
# - local_medication_catalog (_LocalMedicationCatalog): 문서 요약 캐시를 포함한 로컬 기본·허가 정보 조회기.
class CheckMedicationDetail:
    MAX_KEYWORD_LENGTH = 100

    # 함수이름: __init__
    # 함수역할:
    # - 이름 보정·유사도 비교, Redis 캐시, 공공 약품·이미지 API와 로컬 카탈로그를 연결한다.
    # 매개변수:
    # - db (Session | None): 현재 작업에 사용할 SQLAlchemy 세션.
    # - text_normalizer (_MedicationTextNormalizer | None): OCR 특성을 반영한 약품명 정규화·변형 생성기.
    # - medication_cache (_MedicationDetailCache | None): 약품 상세 결과를 보관하는 공유 Redis 캐시.
    # - public_drug_small_api (PublicDrugSmallAPI | None): 기본 공공 약품 정보 API 경계.
    # - public_drug_large_api (PublicDrugLargeAPI | None): 상세 약품 허가 문서 API 경계.
    # - pill_image_api (PillImageAPI | None): 공공 약품 이미지 조회 API 경계.
    # - summary_generator (_MedicationSummaryGenerator | None): 상세 허가 문서의 AI 요약 생성기.
    # - local_medication_catalog (_LocalMedicationCatalog | None): 문서 요약 캐시를 포함한 로컬 기본·허가 정보 조회기.
    # - name_matcher (_MedicationNameMatcher | None): 약품명 유사도 점수 계산과 신뢰도 필터.
    # 반환값:
    # - 없음.
    def __init__(
        self,
        db: Session | None = None,
        text_normalizer: _MedicationTextNormalizer | None = None,
        medication_cache: _MedicationDetailCache | None = None,
        public_drug_small_api: PublicDrugSmallAPI | None = None,
        public_drug_large_api: PublicDrugLargeAPI | None = None,
        pill_image_api: PillImageAPI | None = None,
        summary_generator: _MedicationSummaryGenerator | None = None,
        local_medication_catalog: _LocalMedicationCatalog | None = None,
        name_matcher: _MedicationNameMatcher | None = None,
    ) -> None:
        self.text_normalizer = text_normalizer or _MedicationTextNormalizer()
        self.name_matcher = name_matcher or _MedicationNameMatcher(
            self.text_normalizer
        )
        self.medication_cache = medication_cache or _MedicationDetailCache()
        self.public_drug_small_api = public_drug_small_api or PublicDrugSmallAPI()
        self.public_drug_large_api = public_drug_large_api or PublicDrugLargeAPI()
        self.pill_image_api = pill_image_api or PillImageAPI()
        self.summary_generator = summary_generator or _MedicationSummaryGenerator()
        self.local_medication_catalog = local_medication_catalog or _LocalMedicationCatalog(
            db=db,
            summary_generator=self.summary_generator,
            name_matcher=self.name_matcher,
        )

    # Function Name: requestMedicationDetail
    # Description:
    # - Normalizes medication text and fetches detailed drug information.
    # Parameters:
    # - raw_text (str): Raw medication text supplied by the frontend.
    # Returns:
    # - MedicationResponse with success flag and MedicationDetail list.
    async def requestMedicationDetail(self, raw_text: str) -> MedicationResponse:
        normalized_text = self.text_normalizer.normalize_raw_text(raw_text)
        self._validate_lookup_text(normalized_text)

        search_keywords = self.text_normalizer.build_search_keywords(normalized_text)
        if not search_keywords:
            raise ValueError("Extracted medication text is empty.")

        logger.info("Medication lookup generated %s candidate(s).", len(search_keywords))

        medication_details: list[MedicationDetail] = []
        for search_keyword in search_keywords:
            medication_details = await self._fetch_drug_info(search_keyword)
            if medication_details:
                break

        if not medication_details:
            return MedicationResponse(
                success=False,
                message=f"No medication information found for '{search_keywords[0]}'.",
                data=[],
            )

        return MedicationResponse(
            success=True,
            message="Medication information lookup succeeded.",
            data=medication_details,
        )

    # Function Name: _validate_lookup_text
    # Description:
    # - Rejects blank medication queries and queries exceeding the 100-character lookup limit.
    # Parameters:
    # - text (str): Extracted medication query to validate before lookup.
    # Returns:
    # - None.
    def _validate_lookup_text(self, text: str) -> None:
        if not text:
            raise ValueError("Extracted medication text is empty.")
        if len(text) > self.MAX_KEYWORD_LENGTH:
            raise ValueError("Medication lookup text is too long.")

    # 함수이름: _fetch_drug_info
    # 함수역할:
    # - 로컬 조회를 우선하고 신뢰 가능한 캐시 후보를 확인한 뒤 공공 API 결과를 캐시에 저장한다.
    # 매개변수:
    # - drug_name (str): 검색 또는 직렬화할 약품명.
    # 반환값:
    # - 이미지가 보완된 약품 상세 목록; 일치 약품이 없으면 빈 목록.
    async def _fetch_drug_info(self, drug_name: str) -> list[MedicationDetail]:
        local_drugs = await self.local_medication_catalog.fetch_drug_info(drug_name)
        if local_drugs:
            return await self._enrich_missing_image_urls(local_drugs)

        cached_drugs = await self.medication_cache.get(drug_name)
        if cached_drugs is not None:
            ranked_cached_drugs = self.name_matcher.rank_candidates(
                drug_name,
                cached_drugs,
                lambda item: item.item_name,
                limit=3,
            )
            if ranked_cached_drugs:
                return await self._enrich_missing_image_urls(ranked_cached_drugs)

        medication_details = await self._fetch_public_drug_info(drug_name)
        await self.medication_cache.set(drug_name, medication_details)
        return medication_details

    # 함수이름: _enrich_missing_image_urls
    # 함수역할:
    # - 기존 이미지는 유지하고 이미지가 없는 약품만 공공 이미지 API로 병렬 보완한다.
    # 매개변수:
    # - medication_details (list[MedicationDetail]): 누락 이미지를 보완할 약품 상세 객체 목록.
    # 반환값:
    # - 입력 순서를 유지한 약품 상세 목록.
    async def _enrich_missing_image_urls(
        self,
        medication_details: list[MedicationDetail],
    ) -> list[MedicationDetail]:
        # 함수이름: enrich_detail
        # 함수역할:
        # - 이미지가 없는 약품에 한해 품목 식별자·이름으로 이미지를 찾아 복사본에 추가한다.
        # 매개변수:
        # - medication_detail (MedicationDetail): 환자에게 표시할 약품 안내와 품목 정보.
        # 반환값:
        # - 이미지가 추가된 상세 복사본 또는 변경 없는 원본.
        async def enrich_detail(
            medication_detail: MedicationDetail,
        ) -> MedicationDetail:
            if medication_detail.image_url.strip():
                return medication_detail

            image_url = await self.pill_image_api.searchMedicationImage(
                medication_detail.item_name,
                medication_detail.item_seq,
            )
            if not image_url:
                return medication_detail

            return medication_detail.model_copy(
                update={"image_url": image_url}
            )

        return list(
            await asyncio.gather(
                *(enrich_detail(detail) for detail in medication_details),
            )
        )

    # 함수이름: _fetch_public_drug_info
    # 함수역할:
    # - 기본 API의 상위 후보를 우선 사용하고 없으면 허가 API 최상위 후보를 요약한다.
    # 매개변수:
    # - drug_name (str): 검색 또는 직렬화할 약품명.
    # 반환값:
    # - 신뢰도 기준을 통과한 상세 목록; 두 API 모두 일치하지 않으면 빈 목록.
    async def _fetch_public_drug_info(
        self,
        drug_name: str,
    ) -> list[MedicationDetail]:
        basic_items = await self.public_drug_small_api.searchMedication(drug_name)
        basic_items = self.name_matcher.rank_candidates(
            drug_name,
            basic_items,
            read_public_item_name,
            limit=3,
        )
        if basic_items:
            logger.info(
                "[Basic API] search succeeded (%s items)",
                len(basic_items),
            )
            basic_details = await self._build_basic_drug_infos(basic_items)
            return await self._enrich_missing_image_urls(basic_details)

        logger.info("[Basic API] no result. Trying Advanced API fallback.")
        advanced_items = await self.public_drug_large_api.searchMedication(drug_name)
        advanced_items = self.name_matcher.rank_candidates(
            drug_name,
            advanced_items,
            read_public_item_name,
            limit=1,
        )
        if not advanced_items:
            logger.warning("No drug information found in public drug databases.")
            return []

        advanced_item = dict(advanced_items[0])
        if not read_public_image_url(advanced_item):
            image_url = await self.pill_image_api.searchMedicationImage(
                read_public_item_name(advanced_item) or drug_name,
                read_public_item_sequence(advanced_item),
            )
            if image_url:
                advanced_item["ITEM_IMAGE"] = image_url

        advanced_drug = await self.summary_generator.summarize_advanced_item(
            drug_name,
            advanced_item,
        )
        return [advanced_drug]

    # 함수이름: _build_basic_drug_infos
    # 함수역할:
    # - 기본 API 응답의 효능·복용법·주의사항과 이미지를 상세 엔티티로 변환한다.
    # 매개변수:
    # - basic_items (list[dict[str, Any]]): 공공 품목·안내 필드를 포함한 기본 약품 기록 목록.
    # 반환값:
    # - 응답 순서의 약품 상세 목록.
    async def _build_basic_drug_infos(
        self,
        basic_items: list[dict[str, Any]],
    ) -> list[MedicationDetail]:
        medication_details = [
            MedicationDetail(
                item_seq=read_public_item_sequence(item),
                item_name=_read_text(item.get("itemName")),
                efficacy=_read_text(item.get("efcyQesitm")),
                usage_method=_read_text(item.get("useMethodQesitm")),
                warning=_read_text(item.get("atpnWarnQesitm")),
                interaction=_read_text(item.get("intrcQesitm")),
                side_effect=_read_text(item.get("seQesitm")),
                storage_method=_read_text(item.get("depositMethodQesitm")),
                image_url=read_public_image_url(item),
                source="Basic (e약은요)",
            )
            for item in basic_items
        ]

        return medication_details
