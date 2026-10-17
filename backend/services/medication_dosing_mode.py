# 파일명: medication_dosing_mode.py
# 역할: 처방의 필요시 복용 지시를 정기 일정과 분리한다.

import re
from typing import Any

_AS_NEEDED = re.compile(
    r"필요\s*(?:시|할\s*때|한\s*경우)|(?:통증|발열|증상)\s*(?:시|있을\s*때)"
    r"|\bas\s+needed\b|\bif\s+needed\b|\bp\.?r\.?n\.?\b",
    re.IGNORECASE,
)


# 함수이름: resolve_dosing_mode
# 함수역할: 명시한 필요시 모드와 처방 복용 지시를 확인한다. 일반 약품 설명은 판정하지 않는다.
# 매개변수: mode: 저장 모드, directions: 횟수·1회량에 담긴 처방 지시.
# 반환값: scheduled 또는 as_needed.
def resolve_dosing_mode(mode: str | None, *directions: str | None) -> str:
    if mode == "as_needed" or any(_AS_NEEDED.search(value or "") for value in directions):
        return "as_needed"
    return "scheduled"


# 함수이름: medication_dosing_mode
# 함수역할: 기존 행의 필요시 지시도 확인하여 이전 앱이 저장한 약의 자동 알림을 방지한다.
# 매개변수: medication: 저장 약 또는 같은 필드가 있는 객체.
# 반환값: 정규화된 복용 모드.
def medication_dosing_mode(medication: Any) -> str:
    return resolve_dosing_mode(
        getattr(medication, "dosing_mode", None),
        getattr(medication, "daily_frequency", None),
        getattr(medication, "dosage_per_time", None),
    )
