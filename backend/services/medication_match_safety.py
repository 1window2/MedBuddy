# 파일명: medication_match_safety.py
# 역할: 약명 후보의 함량·농도·제형 충돌을 검사하고 자동 일치 가능한 표기를 제한한다.
"""약명 검색과 OCR 보정이 공유하는 함량·제형 검증. 복용량은 입력하지 않는다."""

import re
import unicodedata
from collections import Counter
from decimal import Decimal

_NUMBER = r"(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?|\.\d+"
_UNIT = r"마이크로그램|마이크로그람|밀리그램|밀리그람|밀리리터|그램|그람|mcg|μg|ug|mg|ml|g|%"
_STRENGTH = re.compile(
    rf"(?P<amount>{_NUMBER})\s*(?P<unit>{_UNIT})(?![a-z])"
    rf"(?:\s*/\s*(?P<denominator>{_NUMBER})?\s*(?P<denunit>ml|밀리리터|g|그램|그람))?",
    re.IGNORECASE,
)
# 복합제에서 마지막 숫자에만 단위를 붙인 표기("5/50mg")의 앞쪽 숫자들.
# 숫자 바로 뒤에 단위가 있는 "5mg/5ml" 같은 농도 표기는 해당하지 않는다.
_UNITLESS_COMPONENTS = re.compile(
    rf"(?<![\d.,])((?:(?:{_NUMBER})\s*/\s*)+)"
    rf"(?=(?:{_NUMBER})\s*(?P<unit>{_UNIT})(?![a-z]))",
    re.IGNORECASE,
)
_UNITS = {
    "g": ("mass", Decimal(1000)), "그램": ("mass", Decimal(1000)),
    "그람": ("mass", Decimal(1000)), "mg": ("mass", Decimal(1)),
    "밀리그램": ("mass", Decimal(1)), "밀리그람": ("mass", Decimal(1)),
    "mcg": ("mass", Decimal("0.001")), "μg": ("mass", Decimal("0.001")),
    "ug": ("mass", Decimal("0.001")), "마이크로그램": ("mass", Decimal("0.001")),
    "마이크로그람": ("mass", Decimal("0.001")),
    "ml": ("volume", Decimal(1)), "밀리리터": ("volume", Decimal(1)),
    "%": ("percent", Decimal(1)),
}


# 함수이름: _text
# 함수역할: 호환 문자와 대소문자 차이를 통일하되 약명 내용은 삭제하지 않는다.
# 매개변수: name (str)은 원본 약명이다.
# 반환값: NFKC 정규화와 casefold를 적용한 str.
def _text(name: str) -> str:
    return unicodedata.normalize("NFKC", name).casefold()


# 함수이름: _strength
# 함수역할: 함량을 공통 질량·부피·백분율 단위로 바꾸고 농도는 분모 단위까지 환산한다.
# 매개변수: match (re.Match)는 _STRENGTH로 찾은 수치·단위 그룹이다.
# 반환값: (단위 종류, Decimal 값). 분모가 0 이하이면 종류를 invalid로 표시한다.
def _strength(match: re.Match) -> tuple[str, Decimal]:
    kind, factor = _UNITS[match['unit'].casefold()]
    value = Decimal(match['amount'].replace(',', '')) * factor
    if match['denunit']:
        denominator_kind, denominator_factor = _UNITS[match['denunit'].casefold()]
        denominator = Decimal((match['denominator'] or '1').replace(',', '')) * denominator_factor
        if denominator <= 0:
            return ('invalid', value)
        return (f'{kind}/{denominator_kind}', value / denominator)
    return kind, value


# 함수이름: strengths
# 함수역할: 명시적으로 단위가 붙은 각 함량을 정규화하고 같은 함량의 출현 횟수를 보존한다.
# 매개변수: name (str)은 검색할 약명이다.
# 반환값: (단위 종류, Decimal 값)의 Counter. 함량이 없으면 빈 Counter다.
def strengths(name: str) -> Counter:
    # 복합제는 일부 성분의 함량만 같다는 이유로 일치시키지 않는다.
    return Counter(_strength(match) for match in _STRENGTH.finditer(_text(name)))


# Function Name: component_strengths
# Description: Expands slash-separated combination strengths with a shared trailing unit before counting every component.
# Parameters: name (str) is the product label; explicit concentrations retain their denominator semantics.
# Returns: Counter of normalized (dimension, Decimal value) pairs, including duplicate components.
def component_strengths(name: str) -> Counter:
    # "5/50mg"을 "5mg 50mg"으로 풀어, 마지막 성분만이 아니라 모든 성분의 함량을 읽는다.
    # Function Name: expand
    # Description: Adds the captured trailing unit to each earlier slash-separated amount.
    # Parameters: match (re.Match) is a _UNITLESS_COMPONENTS match containing amounts and their shared unit.
    # Returns: Space-separated explicitly unit-bearing components for the strength parser.
    def expand(match: re.Match) -> str:
        return ''.join(
            f"{amount.strip()}{match['unit']} "
            for amount in match[1].split('/') if amount.strip()
        )
    expanded = _UNITLESS_COMPONENTS.sub(expand, _text(name))
    return Counter(_strength(match) for match in _STRENGTH.finditer(expanded))


# 함수이름: dosage_form
# 함수역할: 공백을 제거한 약명에서 방출 특성과 끝부분 제형을 추출하고 알려진 제형 별칭을 통일한다.
# 매개변수: name (str)은 원본 약명이다.
# 반환값: (방출 특성, 기본 제형) str 쌍. 알 수 없는 요소는 빈 문자열이며 장용 표기는 서방보다 우선한다.
def dosage_form(name: str) -> tuple[str, str]:
    value = re.sub(r"[\s_]+", "", _text(name))
    release = 'extended' if re.search(r'서방|(?<![a-z])(?:sr|er|cr|xr)(?![a-z])', value) else ''
    if '장용' in value:
        release = 'enteric'
    form = re.search(r'(캡슐|캅셀|주사액|시럽|연고|크림|패취|패치|정|액|주)(?=$|[\d(])', value)
    base = form.group(1) if form else ''
    base = {'캅셀': '캡슐', '패취': '패치', '주사액': '주'}.get(base, base)
    return release, base


# 함수이름: match_conflict
# 함수역할: 명시 함량·복합제 구성·농도·제형을 순서대로 비교해 첫 충돌을 알린다.
# 매개변수: original, candidate (str)는 원본과 후보, allow_unknown_strength (bool)는 후보 함량 누락만 허용한다.
# 반환값: strength_unknown, strength_mismatch, form_mismatch 또는 충돌이 없을 때 None. None이 동일 제품임을 보장하지는 않는다.
def match_conflict(
    original: str, candidate: str, *, allow_unknown_strength: bool = False,
) -> str | None:
    expected, actual = strengths(original), strengths(candidate)
    # 수동 확인 후보에만 누락된 함량을 허용한다. 명시된 함량 충돌·제형 검사는 생략하지 않는다.
    if expected and not actual and not allow_unknown_strength:
        return 'strength_unknown'
    if expected and actual and expected != actual:
        return 'strength_mismatch'
    # 위 비교는 "5/50mg"에서 50mg만 읽는다. 앞 성분이 다른 복합제를 여기서 추가로 걸러 낸다.
    # 추가 검사이므로 기존에 충돌로 판정하던 쌍의 결과는 바뀌지 않는다.
    if expected and actual and component_strengths(original) != component_strengths(candidate):
        return 'strength_mismatch'
    if any(kind == 'invalid' for kind, _ in expected | actual):
        return 'strength_unknown'
    left, right = dosage_form(original), dosage_form(candidate)
    if left[0] != right[0] and (left[0] or left[1]):
        return 'form_mismatch'
    if left[1] and right[1] and left[1] != right[1]:
        return 'form_mismatch'
    return None


# 함수이름: normalized_product_name
# 함수역할: 함량의 단위·소수 표기를 통일한 뒤 문자·숫자만 남겨 제품명 비교 키를 만든다.
# 매개변수: name (str)은 비교할 약명이다.
# 반환값: 영문 소문자·숫자·한글로 구성된 str이며 유사어 보정은 하지 않는다.
def normalized_product_name(name: str) -> str:
    # 함수이름: replace
    # 함수역할: 정규식으로 찾은 함량을 공통 단위 종류와 정규화 수치로 치환한다.
    # 매개변수: match (re.Match)는 _STRENGTH의 수치·단위 일치다.
    # 반환값: 지수 표기와 불필요한 소수점 0이 없는 비교용 str.
    def replace(match: re.Match) -> str:
        kind, amount = _strength(match)
        return f'{kind}{format(amount.normalize(), "f")}'
    return re.sub(r'[^a-z0-9가-힣]', '', _STRENGTH.sub(replace, _text(name)))


# 함수이름: can_auto_match
# 함수역할: 안전성 충돌이 없고 정규화 제품명이 정확히 같을 때만 자동 일치를 허용한다.
# 매개변수: original, candidate (str)는 원본 약명과 검색 후보다.
# 반환값: bool. 단위·띄어쓰기 외의 제품명 차이는 False로 남겨 사용자 확인을 요구한다.
def can_auto_match(original: str, candidate: str) -> bool:
    # 유사도는 후보 찾기에만 사용한다. 단위·띄어쓰기 외의 보정은 사용자가 확인한다.
    return not match_conflict(original, candidate) and (
        normalized_product_name(original) == normalized_product_name(candidate)
    )
