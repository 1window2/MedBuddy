# 파일명: prescription_similarity.py
# 역할: 두 처방의 약품 구성과 치료 맥락 유사도를 계산한다.

import math
import re
from collections import Counter
from dataclasses import dataclass


PRESCRIPTION_COMPARISON_WINDOW_DAYS = 90


# 클래스명: PrescriptionSimilarityMedication
# 역할: 처방 관련성 판정에 필요한 최소 약품 정보를 표현한다.
# 속성:
#   - item_seq: 공공데이터 품목 식별자
#   - item_name: 약품명
#   - efficacy: 치료 맥락 추출에 사용할 효능 문구
#   - main_ingredient: 로컬 허가정보에서 조회한 주성분
@dataclass(frozen=True)
class PrescriptionSimilarityMedication:
    item_seq: str = ""
    item_name: str = ""
    efficacy: str = ""
    main_ingredient: str = ""


# 클래스명: PrescriptionSimilarityResult
# 역할: 두 처방의 관련 여부와 판정 근거를 표현한다.
# 속성:
#   - is_related: 비교 가능한 관련 처방인지 여부
#   - score: 후보 선택에 사용할 유사도 점수
#   - match_basis: 가장 강한 관련성 판정 근거
@dataclass(frozen=True)
class PrescriptionSimilarityResult:
    is_related: bool
    score: float
    match_basis: str = ""


# 클래스명: PrescriptionSimilarityService
# 역할: 외부 API 호출 없이 저장된 약품 정보만으로 처방 관련성을 판정한다.
# 주요 책임:
#   - 동일 품목과 동일 성분의 처방 간 겹침을 계산한다.
#   - 효능 문구를 치료 맥락으로 변환해 완전히 교체된 처방을 보조 판정한다.
#   - 보수적인 임계값을 사용해 무관한 처방의 잘못된 비교를 방지한다.
class PrescriptionSimilarityService:
    _NON_KEY_PATTERN = re.compile(r"[^0-9a-z가-힣]")
    _DOSAGE_PATTERN = re.compile(
        r"\d+(?:\.\d+)?\s*(?:mg|g|mcg|㎍|ml|mL|정|캡슐|밀리그램|그램)",
        re.IGNORECASE,
    )
    _INGREDIENT_SEPARATOR_PATTERN = re.compile(r"[,;/+]|\s{2,}")
    _PARENTHETICAL_PATTERN = re.compile(r"\(([^()]*)\)")

    _MIN_PRODUCT_DICE = 0.30
    _MIN_INGREDIENT_DICE = 0.40
    _MIN_CONTEXT_COSINE = 0.65

    _THERAPEUTIC_KEYWORDS = {
        "respiratory": (
            "감기",
            "기침",
            "가래",
            "콧물",
            "비염",
            "기관지",
            "인후염",
            "호흡기",
            "천식",
        ),
        "gastrointestinal": (
            "위염",
            "위산",
            "역류",
            "속쓰림",
            "소화",
            "구토",
            "설사",
            "변비",
            "복통",
            "장염",
            "위장",
        ),
        "infection": (
            "감염",
            "항생",
            "세균",
            "항균",
            "폐렴",
            "중이염",
            "편도염",
        ),
        "pain_inflammation": (
            "통증",
            "진통",
            "해열",
            "염증",
            "두통",
            "근육통",
            "관절염",
        ),
        "cardiovascular": (
            "고혈압",
            "혈압",
            "심혈관",
            "협심증",
            "부정맥",
            "심부전",
        ),
        "metabolic": (
            "당뇨",
            "혈당",
            "고지혈",
            "콜레스테롤",
            "중성지방",
        ),
        "allergy_skin": (
            "알레르기",
            "두드러기",
            "피부염",
            "습진",
            "가려움",
        ),
        "neurologic_psychiatric": (
            "불면",
            "우울",
            "불안",
            "간질",
            "경련",
            "파킨슨",
            "치매",
        ),
        "musculoskeletal": (
            "골다공증",
            "관절",
            "척추",
            "골절",
            "류마티스",
        ),
        "urinary": (
            "방광염",
            "전립선",
            "배뇨",
            "요로",
            "신장",
        ),
    }

    # 함수이름: compare
    # 함수역할:
    # - 동일 품목, 동일 성분, 치료 맥락 순서로 두 처방의 관련성을 계산한다.
    # 매개변수:
    # - previous: 비교 후보인 이전 처방 약품 목록
    # - current: 현재 분석한 처방 약품 목록
    # 반환값:
    # - 관련 여부, 유사도 점수, 가장 강한 판정 근거
    def compare(
        self,
        previous: list[PrescriptionSimilarityMedication],
        current: list[PrescriptionSimilarityMedication],
    ) -> PrescriptionSimilarityResult:
        product_score = self._dice_similarity(
            self._product_keys(previous),
            self._product_keys(current),
        )
        ingredient_score = self._dice_similarity(
            self._ingredient_keys(previous),
            self._ingredient_keys(current),
        )
        context_score = self._context_cosine(previous, current)

        weighted_scores = {
            "same_medication": product_score,
            "same_ingredient": ingredient_score * 0.95,
            "same_therapeutic_context": context_score * 0.70,
        }
        match_basis, score = max(
            weighted_scores.items(),
            key=lambda item: item[1],
        )
        is_related = (
            product_score >= self._MIN_PRODUCT_DICE
            or ingredient_score >= self._MIN_INGREDIENT_DICE
            or context_score >= self._MIN_CONTEXT_COSINE
        )
        return PrescriptionSimilarityResult(
            is_related=is_related,
            score=round(score, 4),
            match_basis=match_basis if is_related else "",
        )

    # 함수이름: _product_keys
    # 함수역할:
    # - 품목 식별자와 정규화한 약품명으로 동일 약품 비교 키를 만든다.
    # 매개변수:
    # - medications: 비교 키를 생성할 처방 약품 목록
    # 반환값:
    # - 품목 식별자와 약품명 키 집합
    def _product_keys(
        self,
        medications: list[PrescriptionSimilarityMedication],
    ) -> set[str]:
        keys: set[str] = set()
        for medication in medications:
            item_seq = medication.item_seq.strip()
            if item_seq:
                keys.add(f"seq:{item_seq}")
            normalized_name = self._normalize_key(medication.item_name)
            if normalized_name:
                keys.add(f"name:{normalized_name}")
        return keys

    # 함수이름: _ingredient_keys
    # 함수역할:
    # - 허가정보 주성분과 약품명 괄호의 성분명으로 비교 키를 만든다.
    # 매개변수:
    # - medications: 성분 비교 키를 생성할 처방 약품 목록
    # 반환값:
    # - 정규화된 성분 키 집합
    def _ingredient_keys(
        self,
        medications: list[PrescriptionSimilarityMedication],
    ) -> set[str]:
        keys: set[str] = set()
        for medication in medications:
            ingredient_source = medication.main_ingredient.strip()
            if ingredient_source:
                keys.update(self._split_ingredient_keys(ingredient_source))
            keys.update(self._parenthetical_ingredient_keys(medication.item_name))
        return keys

    # 함수이름: _split_ingredient_keys
    # 함수역할:
    # - 복합 주성분 문자열을 용량이 제거된 개별 성분 키로 나눈다.
    # 매개변수:
    # - value: 허가정보에서 읽은 주성분 문자열
    # 반환값:
    # - 개별 성분 비교 키 집합
    def _split_ingredient_keys(self, value: str) -> set[str]:
        without_dosage = self._DOSAGE_PATTERN.sub("", value)
        return {
            normalized
            for part in self._INGREDIENT_SEPARATOR_PATTERN.split(without_dosage)
            if (normalized := self._normalize_key(part))
        }

    # 함수이름: _parenthetical_ingredient_keys
    # 함수역할:
    # - 약품명 괄호 안에 표기된 성분명을 보조 비교 키로 추출한다.
    # 매개변수:
    # - item_name: 원본 약품명
    # 반환값:
    # - 괄호에서 추출한 성분 키 집합
    def _parenthetical_ingredient_keys(self, item_name: str) -> set[str]:
        return {
            normalized
            for value in self._PARENTHETICAL_PATTERN.findall(item_name)
            if (normalized := self._normalize_key(self._DOSAGE_PATTERN.sub("", value)))
        }

    # 함수이름: _context_cosine
    # 함수역할:
    # - 두 처방의 치료 맥락 빈도 벡터 간 코사인 유사도를 계산한다.
    # 매개변수:
    # - previous: 이전 처방 약품 목록
    # - current: 현재 처방 약품 목록
    # 반환값:
    # - 0부터 1 사이의 치료 맥락 유사도
    def _context_cosine(
        self,
        previous: list[PrescriptionSimilarityMedication],
        current: list[PrescriptionSimilarityMedication],
    ) -> float:
        previous_context = self._context_counts(previous)
        current_context = self._context_counts(current)
        if not previous_context or not current_context:
            return 0.0

        common_keys = set(previous_context) & set(current_context)
        numerator = sum(
            previous_context[key] * current_context[key] for key in common_keys
        )
        previous_norm = math.sqrt(sum(value**2 for value in previous_context.values()))
        current_norm = math.sqrt(sum(value**2 for value in current_context.values()))
        if previous_norm == 0 or current_norm == 0:
            return 0.0
        return numerator / (previous_norm * current_norm)

    # 함수이름: _context_counts
    # 함수역할:
    # - 약품명과 효능 문구에서 치료 맥락별 출현 횟수를 집계한다.
    # 매개변수:
    # - medications: 치료 맥락을 읽을 처방 약품 목록
    # 반환값:
    # - 치료 맥락별 출현 횟수
    def _context_counts(
        self,
        medications: list[PrescriptionSimilarityMedication],
    ) -> Counter[str]:
        counts: Counter[str] = Counter()
        for medication in medications:
            source = f"{medication.item_name} {medication.efficacy}".lower()
            matched_contexts = {
                context
                for context, keywords in self._THERAPEUTIC_KEYWORDS.items()
                if any(keyword in source for keyword in keywords)
            }
            counts.update(matched_contexts)
        return counts

    # 함수이름: _dice_similarity
    # 함수역할:
    # - 두 키 집합의 겹침 정도를 다이스 유사도로 계산한다.
    # 매개변수:
    # - left: 첫 번째 비교 키 집합
    # - right: 두 번째 비교 키 집합
    # 반환값:
    # - 0부터 1 사이의 집합 유사도
    @staticmethod
    def _dice_similarity(left: set[str], right: set[str]) -> float:
        if not left or not right:
            return 0.0
        return (2 * len(left & right)) / (len(left) + len(right))

    # 함수이름: _normalize_key
    # 함수역할:
    # - 비교 문자열에서 공백과 구두점을 제거해 소문자 키로 변환한다.
    # 매개변수:
    # - value: 정규화할 원본 문자열
    # 반환값:
    # - 약품과 성분 비교에 사용할 문자열 키
    def _normalize_key(self, value: str) -> str:
        return self._NON_KEY_PATTERN.sub("", value.strip().lower())
