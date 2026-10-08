# File Name: medication_name_matching.py
# Role: Normalizes bounded medication-name search variants and ranks candidates without I/O.

import re
from difflib import SequenceMatcher
from typing import Callable, TypeVar

from services.medication_match_safety import can_auto_match, match_conflict, strengths

_CandidateT = TypeVar("_CandidateT")


# Class Name: MedicationTextNormalizer
# Role:
# - Reusable pure helper for medication search keyword normalization.
# Responsibilities:
# - Normalize OCR or UI-provided medication text.
# - Strip dosage and dosage-form suffixes from search keywords.
class MedicationTextNormalizer:
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
        raw_candidates = [normalized_text, outside_parentheses]
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
        for base_keyword in [normalized_candidate, dosage_trimmed_candidate]:
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


# 클래스명: MedicationNameMatcher
# 역할:
# - OCR 검색어와 약품 후보 이름의 유사도를 계산하고 신뢰 가능한 후보를 선별한다.
# 주요 책임:
# - 기존 검색어 정규화 결과를 비교 가능한 문자열 키로 변환한다.
# - 완전 일치, 포함 관계, 문자열 유사도를 조합해 이름 점수를 계산한다.
# - 짧은 약 이름에는 더 엄격한 임계값을 적용해 오탐을 줄인다.
# 속성:
# - text_normalizer (MedicationTextNormalizer): OCR 특성을 반영한 약품명 정규화·변형 생성기.
class MedicationNameMatcher:
    _NON_NAME_CHARACTER_PATTERN = re.compile(r"[^0-9a-z가-힣]+", re.IGNORECASE)
    _LONG_NAME_MIN_SCORE = 0.76
    _MEDIUM_NAME_MIN_SCORE = 0.84
    _SHORT_NAME_MIN_SCORE = 0.96

    # 함수이름: __init__
    # 함수역할:
    # - 비교 키 생성에 사용할 약품명 정규화기를 주입하거나 기본 생성한다.
    # 매개변수:
    # - text_normalizer (MedicationTextNormalizer | None): OCR 특성을 반영한 약품명 정규화·변형 생성기.
    # 반환값:
    # - 없음.
    def __init__(
        self,
        text_normalizer: MedicationTextNormalizer | None = None,
    ) -> None:
        self.text_normalizer = text_normalizer or MedicationTextNormalizer()

    # 함수이름: calculate_score
    # 함수역할:
    # - OCR 검색어와 공공데이터 약품명의 가장 높은 이름 유사도를 계산한다.
    # 매개변수:
    # - search_text (str): OCR 보정 과정을 거친 검색어
    # - candidate_name (str): DB 또는 공공데이터 API가 반환한 약품명
    # 반환값:
    # - 0.0 이상 1.0 이하의 이름 유사도 점수
    def calculate_score(self, search_text: str, candidate_name: str) -> float:
        if match_conflict(search_text, candidate_name):
            return 0.0
        if can_auto_match(search_text, candidate_name):
            return 1.0
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
    # - 검색어의 함량이 후보의 함량과 같다고 확인되면 이름 점수에 0.03을 더한다.
    # - 함량 비교는 medication_match_safety의 정규화 규칙을 그대로 사용한다. 함량이 다르거나
    #   후보에서 확인되지 않으면 calculate_score가 이 함수에 앞서 0점으로 제외하므로 감점은 두지 않는다.
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
        search_strengths = strengths(search_text)
        if search_strengths and search_strengths == strengths(candidate_name):
            return min(1.0, name_score + 0.03)
        return name_score
