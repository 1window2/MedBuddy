# 파일명: medication_dosing_mode.py
# 역할: 처방의 필요시 복용 지시를 정기 일정과 분리한다.

import re
from typing import Any

from entities.medication_schedule_entity import (
    decode_medication_schedule_slot_keys,
    normalize_medication_schedule_slot_keys,
)

_AS_NEEDED = re.compile(
    r"필요\s*(?:시|할\s*때|한\s*경우)|(?:통증|발열|증상)\s*(?:시|있을\s*때)"
    r"|\bas\s+needed\b|\bif\s+needed\b|\bp\.?r\.?n\.?\b",
    re.IGNORECASE,
)


# 함수이름: resolve_dosing_mode
# 함수역할: 명시한 필요시 모드와 처방 복용 지시를 확인한다. 일반 약품 설명은 판정하지 않는다.
#           복용 횟수의 필요시 지시("필요시 1회", "1일 3회 필요시")는 필요시로 본다. 1회량에만 있는
#           필요시 표현("1정 (통증 시 2정)")은 정기 횟수나 선택한 시간대가 없을 때만 필요시로 본다.
#           정기 복용약의 추가 복용 안내 때문에 일정·알림·미복용 알림이 사라지지 않게 한다.
# 매개변수: mode: 저장 모드, frequency: 복용 횟수 지시, dosages: 1회량 등 나머지 지시,
#           has_slots: 사용자가 정기 복용 시간대를 고른 경우 True.
# 반환값: scheduled 또는 as_needed.
def resolve_dosing_mode(
    mode: str | None,
    frequency: str | None = None,
    *dosages: str | None,
    has_slots: bool = False,
) -> str:
    if mode == "as_needed" or _AS_NEEDED.search(frequency or ""):
        return "as_needed"
    regular = bool((frequency or "").strip()) or has_slots
    if not regular and any(_AS_NEEDED.search(value or "") for value in dosages):
        return "as_needed"
    return "scheduled"


# 함수이름: _has_schedule_slots
# 함수역할: 저장 행의 JSON 문자열과 요청의 목록 중 어느 형식이든 정기 시간대 선택 여부를 읽는다.
# 매개변수: value: schedule_slot_keys 값. 반환값: 유효한 시간대가 하나 이상인지 여부.
def _has_schedule_slots(value: Any) -> bool:
    if isinstance(value, str):
        return bool(decode_medication_schedule_slot_keys(value))
    return bool(normalize_medication_schedule_slot_keys(value or []))


# 함수이름: medication_dosing_mode
# 함수역할: 기존 행의 필요시 지시도 확인하여 이전 앱이 저장한 약의 자동 알림을 방지한다.
# 매개변수: medication: 저장 약 또는 같은 필드가 있는 객체.
# 반환값: 정규화된 복용 모드.
def medication_dosing_mode(medication: Any) -> str:
    return resolve_dosing_mode(
        getattr(medication, "dosing_mode", None),
        getattr(medication, "daily_frequency", None),
        getattr(medication, "dosage_per_time", None),
        has_slots=_has_schedule_slots(getattr(medication, "schedule_slot_keys", None)),
    )
