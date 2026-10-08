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


def _text(name: str) -> str:
    return unicodedata.normalize("NFKC", name).casefold()


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


def strengths(name: str) -> Counter:
    # 복합제는 일부 성분의 함량만 같다는 이유로 일치시키지 않는다.
    return Counter(_strength(match) for match in _STRENGTH.finditer(_text(name)))


def component_strengths(name: str) -> Counter:
    # "5/50mg"을 "5mg 50mg"으로 풀어, 마지막 성분만이 아니라 모든 성분의 함량을 읽는다.
    def expand(match: re.Match) -> str:
        return ''.join(
            f"{amount.strip()}{match['unit']} "
            for amount in match[1].split('/') if amount.strip()
        )
    expanded = _UNITLESS_COMPONENTS.sub(expand, _text(name))
    return Counter(_strength(match) for match in _STRENGTH.finditer(expanded))


def dosage_form(name: str) -> tuple[str, str]:
    value = re.sub(r"\s+", "", _text(name))
    release = 'extended' if re.search(r'서방|(?<![a-z])(?:sr|er|cr|xr)(?![a-z])', value) else ''
    if '장용' in value:
        release = 'enteric'
    form = re.search(r'(캡슐|캅셀|주사액|시럽|연고|크림|패취|패치|정|액|주)(?=$|[\d(])', value)
    base = form.group(1) if form else ''
    base = {'캅셀': '캡슐', '패취': '패치', '주사액': '주'}.get(base, base)
    return release, base


def match_conflict(original: str, candidate: str) -> str | None:
    expected, actual = strengths(original), strengths(candidate)
    if expected and not actual:
        return 'strength_unknown'
    if expected and expected != actual:
        return 'strength_mismatch'
    # 위 비교는 "5/50mg"에서 50mg만 읽는다. 앞 성분이 다른 복합제를 여기서 추가로 걸러 낸다.
    # 추가 검사이므로 기존에 충돌로 판정하던 쌍의 결과는 바뀌지 않는다.
    if expected and component_strengths(original) != component_strengths(candidate):
        return 'strength_mismatch'
    if any(kind == 'invalid' for kind, _ in expected | actual):
        return 'strength_unknown'
    left, right = dosage_form(original), dosage_form(candidate)
    if left[0] != right[0] and (left[0] or left[1]):
        return 'form_mismatch'
    if left[1] and right[1] and left[1] != right[1]:
        return 'form_mismatch'
    return None


def normalized_product_name(name: str) -> str:
    def replace(match: re.Match) -> str:
        kind, amount = _strength(match)
        return f'{kind}{format(amount.normalize(), "f")}'
    return re.sub(r'[^a-z0-9가-힣]', '', _STRENGTH.sub(replace, _text(name)))


def can_auto_match(original: str, candidate: str) -> bool:
    # 유사도는 후보 찾기에만 사용한다. 단위·띄어쓰기 외의 보정은 사용자가 확인한다.
    return not match_conflict(original, candidate) and (
        normalized_product_name(original) == normalized_product_name(candidate)
    )
