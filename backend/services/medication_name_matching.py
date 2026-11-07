# File Name: medication_name_matching.py
# Role: Normalizes bounded medication-name search variants and ranks candidates without I/O.

import re
from difflib import SequenceMatcher
from typing import Callable, Literal, TypeVar

from services.medication_match_safety import can_auto_match, match_conflict, strengths

_CandidateT = TypeVar("_CandidateT")


# 클래스명: MedicationTextNormalizer
# 역할: OCR·입력 약명에서 제한된 검색 키워드와 표기 변형을 생성한다.
# 주요 책임: 공백·괄호를 정리하고 함량·제형·제조사·알려진 OCR 변형을 이용해 후보 검색을 지원한다.
# 속성: MAX_SEARCH_KEYWORDS·SEARCH_KEYWORD_LIMITS는 개수 상한, 함량·제형 정규식과 제조사·한글 쌍은 명시적 변형 규칙이다.
# 비고: 검색 변형은 동일 제품임을 보장하지 않으며 안전성·확정 판정은 별도로 수행한다.
class MedicationTextNormalizer:
    MAX_SEARCH_KEYWORDS = 24
    SEARCH_KEYWORD_LIMITS = {'fast': 2, 'balanced': 4, 'thorough': 8}
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

    # Function Name: normalize_raw_text
    # Description: Converts newlines to spaces, harmonizes full-width/square brackets with parentheses and collapses whitespace.
    # Parameters: raw_text (str) is OCR or user-provided medication text.
    # Returns: Trimmed normalized text without guessing product identity.
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
    # - Prioritizes direct original/outside/inside names and structural searches before OCR variants.
    # Parameters:
    # - raw_text (str): Source OCR text before medication-name normalization.
    # - search_mode: Optional lookup strategy; omitted for the full candidate-matching vocabulary.
    # Returns:
    # - Up to 2/4/8 lookup keywords, or MAX_SEARCH_KEYWORDS for matching; empty for blank input.
    def build_search_keywords(
        self, raw_text: str, *,
        search_mode: Literal['fast', 'balanced', 'thorough'] | None = None,
    ) -> list[str]:
        if search_mode is not None and search_mode not in self.SEARCH_KEYWORD_LIMITS:
            raise ValueError("Invalid medication search mode.")
        normalized_text = self.normalize_raw_text(raw_text)
        if not normalized_text:
            return []

        outside_parentheses, parenthesized_candidates = (
            self._split_parenthesized_text(normalized_text)
        )
        raw_candidates = [normalized_text, outside_parentheses]
        if search_mode == 'fast':
            return self._deduplicate_keywords(raw_candidates)[:2]
        raw_candidates.extend(parenthesized_candidates)
        raw_candidates = self._deduplicate_keywords(raw_candidates)

        # 직접 검색어를 먼저 확보해 원문 변형이 제품명·성분명 검색을 밀어내지 못하게 한다.
        structural_keywords = list(raw_candidates)
        for candidate in raw_candidates:
            structural_keywords.extend(self._candidate_structural_variants(candidate))
        structural_keywords = self._deduplicate_keywords(structural_keywords)

        limit = self.SEARCH_KEYWORD_LIMITS.get(search_mode, self.MAX_SEARCH_KEYWORDS)
        keywords = structural_keywords[:limit]
        # 제한에 도달하면 남은 검색어의 OCR 변형은 만들지 않는다.
        for keyword in structural_keywords:
            if len(keywords) >= limit:
                break
            keywords = self._deduplicate_keywords(
                [*keywords, *self._hangul_ocr_variants(keyword)],
            )
        return keywords[:limit]

    # 함수이름: _split_parenthesized_text
    # 함수역할: 중첩 괄호 깊이를 추적해 바깥 약명과 닫힌 괄호 후보를 분리하고 잘린 괄호 뒤 텍스트는 보조 후보에서 제외한다.
    # 매개변수: normalized_text (str)는 공백·괄호 표기가 정리된 텍스트다.
    # 반환값: 정리된 바깥 str과 1~80자 괄호 후보 목록. 원본 검색·함량 검증용 입력 자체는 바꾸지 않는다.
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

        # 잘린 괄호 뒤 설명은 보조 검색어에서만 제외한다. 원문 검색과 함량·제형 검증은 그대로 유지한다.
        outside_text = self.normalize_raw_text("".join(outside_chars)).rstrip(" _.-…")
        return outside_text, parenthesized_candidates

    # 함수이름: _candidate_structural_variants
    # 함수역할:
    # - 한 약품명 후보에서 용량·제형·제조사 제거 후보를 만들며 OCR 변형은 뒤로 미룬다.
    # 매개변수:
    # - candidate (str): 원본에서 추출한 약품명 후보
    # 반환값:
    # - 검색 시도 순서를 보존한 약품명 후보 목록
    def _candidate_structural_variants(self, candidate: str) -> list[str]:
        normalized_candidate = self.normalize_raw_text(candidate)
        if not normalized_candidate:
            return []

        parts = self._DOSAGE_PATTERN.split(normalized_candidate)
        dosage_trimmed_candidate = parts[0].strip() if parts else normalized_candidate
        structural_keywords: list[str] = []
        for base_keyword in [normalized_candidate, dosage_trimmed_candidate]:
            structural_keywords.extend(self._structural_variants(base_keyword))

        return self._deduplicate_keywords(structural_keywords)

    # Function Name: _structural_variants
    # Description: Produces spacing, dosage-form and known manufacturer-prefix variants for broader candidate retrieval, retaining first-seen order.
    # Parameters: keyword (str) is the current search candidate.
    # Returns: Deduplicated nonblank variant list; these variants are not proof of product equivalence.
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

    # Function Name: _strip_dosage_form
    # Description: Removes one recognized trailing dosage-form label to broaden search.
    # Parameters: keyword (str) is the candidate name.
    # Returns: Trimmed text without the matched suffix, otherwise the trimmed original.
    def _strip_dosage_form(self, keyword: str) -> str:
        return self._DOSAGE_FORM_SUFFIX_PATTERN.sub("", keyword).strip()

    # Function Name: _strip_manufacturer_prefix
    # Description: Removes the first recognized leading manufacturer only when at least two product-name characters remain.
    # Parameters: keyword (str) is the candidate name.
    # Returns: Remaining trimmed name, or unchanged input when no eligible prefix matches.
    def _strip_manufacturer_prefix(self, keyword: str) -> str:
        for prefix in self._MANUFACTURER_PREFIXES:
            if keyword.startswith(prefix) and len(keyword) > len(prefix) + 1:
                return keyword[len(prefix) :].strip()
        return keyword

    # Function Name: _hangul_ocr_variants
    # Description: Creates independent bidirectional substitutions for configured Korean vowel-confusion pairs.
    # Parameters: keyword (str) is the original candidate.
    # Returns: Variant list; replacements affect all occurrences of one pair at a time and are not combined across pairs.
    def _hangul_ocr_variants(self, keyword: str) -> list[str]:
        variants: list[str] = []
        for source, target in self._HANGUL_OCR_VARIANT_PAIRS:
            if source in keyword:
                variants.append(keyword.replace(source, target))
            if target in keyword:
                variants.append(keyword.replace(target, source))
        return variants

    # Function Name: _deduplicate_keywords
    # Description: Trims keywords, drops blanks and keeps only the first occurrence of each remaining exact string.
    # Parameters: keywords (list[str]) is the ordered candidate list.
    # Returns: Nonblank deduplicated list preserving input priority.
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


# Class Name: MedicationNameMatcher
# Role: Scores normalized medication names and ranks candidates under length-sensitive confidence thresholds.
# Responsibilities: Combines exact, containment and sequence similarity with strength/form safety checks; short names require stronger matches.
# Attributes: text_normalizer generates comparison variants; score constants and _NON_NAME_CHARACTER_PATTERN define matching policy.
class MedicationNameMatcher:
    _NON_NAME_CHARACTER_PATTERN = re.compile(r"[^0-9a-z가-힣]+", re.IGNORECASE)
    _LONG_NAME_MIN_SCORE = 0.76
    _MEDIUM_NAME_MIN_SCORE = 0.84
    _SHORT_NAME_MIN_SCORE = 0.96

    # Function Name: __init__
    # Description: Binds the supplied text normalizer or creates the default variant generator.
    # Parameters: text_normalizer (MedicationTextNormalizer | None) overrides normalization.
    # Returns: None; no matching occurs during construction.
    def __init__(
        self,
        text_normalizer: MedicationTextNormalizer | None = None,
    ) -> None:
        self.text_normalizer = text_normalizer or MedicationTextNormalizer()

    # 함수이름: calculate_score
    # 함수역할: 함량·제형 충돌을 먼저 배제한 뒤 직접·변형 이름 점수를 비교하고 확인된 함량 일치에만 가산점을 준다.
    # 매개변수: search_text·candidate_name (str)은 원본과 후보, allow_unknown_strength (bool)는 수동 확인용 후보의 함량 누락만 허용한다.
    # 반환값: 0~1 float. 충돌은 0, 안전한 정규화 동일 제품은 1이며 변형 점수만으로 확정 일치를 보장하지 않는다.
    def calculate_score(
        self, search_text: str, candidate_name: str, *,
        allow_unknown_strength: bool = False,
    ) -> float:
        if match_conflict(
            search_text, candidate_name, allow_unknown_strength=allow_unknown_strength,
        ):
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
    # 함수역할: 길이별 최소 점수를 통과한 후보를 점수 내림차순으로 정렬하고 동점이면 원래 순서를 유지한다.
    # 매개변수: search_text (str)는 검색어, candidates (list)는 원본 후보, name_reader (Callable)는 이름 추출기, limit (int)은 반환 상한이다.
    #   allow_unknown_strength (bool)는 후보 함량 누락 허용 여부이며 명시적 함량·제형 충돌은 여전히 제외한다.
    # 반환값: 상한까지의 원본 후보 목록. 이름 추출기·점수 계산 오류는 전달한다.
    def rank_candidates(
        self,
        search_text: str,
        candidates: list[_CandidateT],
        name_reader: Callable[[_CandidateT], str],
        limit: int,
        *,
        allow_unknown_strength: bool = False,
    ) -> list[_CandidateT]:
        ranked_candidates: list[tuple[float, int, _CandidateT]] = []
        required_score = self._required_score(search_text)
        for candidate_index, candidate in enumerate(candidates):
            score = self.calculate_score(
                search_text, name_reader(candidate),
                allow_unknown_strength=allow_unknown_strength,
            )
            if score < required_score:
                continue
            ranked_candidates.append((score, candidate_index, candidate))

        ranked_candidates.sort(key=lambda item: (-item[0], item[1]))
        return [item[2] for item in ranked_candidates[:limit]]

    # Function Name: _build_match_keys
    # Description: Normalizes generated search variants into comparison keys, removing empty and duplicate keys.
    # Parameters: value (str) is the original medication name.
    # Returns: Ordered unique keys without punctuation or spacing.
    def _build_match_keys(self, value: str) -> list[str]:
        raw_candidates = self.text_normalizer.build_search_keywords(value)
        normalized_keys = [
            self._normalize_match_key(candidate) for candidate in raw_candidates
        ]
        return list(dict.fromkeys(key for key in normalized_keys if key))

    # Function Name: _normalize_match_key
    # Description: Removes characters outside ASCII letters/digits and Korean syllables, then folds case.
    # Parameters: value (str) is a product-name representation.
    # Returns: Compact comparison string; an unsupported-only label becomes empty.
    @classmethod
    def _normalize_match_key(cls, value: str) -> str:
        return cls._NON_NAME_CHARACTER_PATTERN.sub("", value).casefold()

    # Function Name: _calculate_pair_score
    # Description: Combines exact match, sufficiently long substring containment and SequenceMatcher similarity without automatic junk filtering.
    # Parameters: left, right (str) are normalized keys.
    # Returns: Score in [0, 1], with 0 for an empty key and 1 for exact equality.
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

    # Function Name: _required_score
    # Description: Selects stricter acceptance thresholds for short normalized search names.
    # Parameters: search_text (str) is the query label.
    # Returns: Short-name threshold through length 3, medium through 5, otherwise the long-name threshold.
    def _required_score(self, search_text: str) -> float:
        normalized_search = self._normalize_match_key(search_text)
        if len(normalized_search) <= 3:
            return self._SHORT_NAME_MIN_SCORE
        if len(normalized_search) <= 5:
            return self._MEDIUM_NAME_MIN_SCORE
        return self._LONG_NAME_MIN_SCORE

    # Function Name: _adjust_dosage_score
    # Description: Adds 0.03 only when the query has explicit strengths equal to the candidate's normalized strengths; earlier safety checks handle conflicts.
    # Parameters: name_score (float) is the prior score; search_text and candidate_name (str) supply strength labels.
    # Returns: Boosted score capped at 1.0, or unchanged score when strengths are absent/different.
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
