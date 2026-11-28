# 파일명: medication_ingredients.py
# 역할: 허가정보 주성분 문자열을 성분 코드별로 읽고 품목별 주성분·품목명을 좁은 열로 조회한다.

import re
from collections.abc import Iterable

from sqlalchemy.orm import Session

from entities.medication_detail_entity import _DrugApprovalInfo

# 복합제는 "[M040702]포도당|[M040426]염화나트륨"처럼 성분마다 코드를 붙여 |로 잇는다.
# 성분명 안의 |를 자르지 않도록 다음 코드가 시작하는 위치에서만 나눈다.
_INGREDIENT_PART_SEPARATOR = re.compile(r"\|(?=\[)")
_CODED_INGREDIENT_PATTERN = re.compile(r"^\[([A-Z]\d+)\](.*)$")


# Function Name: parse_ingredient_codes
# Description:
# - Reads a drug_approval_infos.main_ingredient value into ingredient codes and names.
# - Splits only where the next part starts with a code, ignores parts without a code, and keeps
#   the first non-empty name of a code that appears more than once.
# Parameters:
# - text (str | None): Raw main-ingredient value such as "[M040702]포도당|[M040426]염화나트륨".
# Returns:
# - dict[str, str]: Codes in their first order of appearance, each with its name or "" when no
#   part named it; an empty mapping for empty text or text without codes.
def parse_ingredient_codes(text: str | None) -> dict[str, str]:
    ingredients: dict[str, str] = {}
    for part in _INGREDIENT_PART_SEPARATOR.split((text or "").strip()):
        match = _CODED_INGREDIENT_PATTERN.match(part.strip())
        if match is None:
            continue
        code = match.group(1)
        name = match.group(2).strip()
        if not ingredients.get(code):
            ingredients[code] = name
    return ingredients


# Function Name: load_main_ingredients
# Description:
# - Fetches only product identifiers and main ingredients from the local approval catalog;
#   source documents and raw_json are never read.
# Parameters:
# - db (Session): Request session.
# - item_sequences (Iterable[str]): Product identifiers; blank values are ignored.
# Returns:
# - dict[str, str]: Main ingredient by nonempty item sequence, or an empty mapping when no
#   identifier was given; database errors propagate.
def load_main_ingredients(db: Session, item_sequences: Iterable[str]) -> dict[str, str]:
    sequences = {sequence.strip() for sequence in item_sequences if (sequence or "").strip()}
    if not sequences:
        return {}

    # 주성분만 필요하므로 원문 문서와 raw_json 열은 읽지 않는다.
    rows = (
        db.query(
            _DrugApprovalInfo.item_seq,
            _DrugApprovalInfo.main_ingredient,
        )
        .filter(_DrugApprovalInfo.item_seq.in_(sequences))
        .all()
    )
    return {
        str(row.item_seq).strip(): str(row.main_ingredient or "").strip()
        for row in rows
        if str(row.item_seq or "").strip()
    }


# Function Name: load_catalog_item_names
# Description:
# - Fetches only product identifiers and approved product names from the local approval catalog.
# Parameters:
# - db (Session): Request session.
# - item_sequences (Iterable[str]): Product identifiers; blank values are ignored.
# Returns:
# - dict[str, str]: Approved product name by item sequence, or an empty mapping without
#   identifiers; database errors propagate.
def load_catalog_item_names(db: Session, item_sequences: Iterable[str]) -> dict[str, str]:
    sequences = {sequence.strip() for sequence in item_sequences if (sequence or "").strip()}
    if not sequences:
        return {}

    rows = (
        db.query(_DrugApprovalInfo.item_seq, _DrugApprovalInfo.item_name)
        .filter(_DrugApprovalInfo.item_seq.in_(sequences))
        .all()
    )
    return {
        str(row.item_seq).strip(): str(row.item_name or "").strip()
        for row in rows
        if str(row.item_seq or "").strip()
    }
