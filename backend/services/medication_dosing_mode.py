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


# Function Name: resolve_dosing_mode
# Description: Honors explicit as-needed mode or frequency instructions; dosage-only as-needed wording applies only when no regular frequency or selected slots exist.
# Parameters: mode, frequency (str | None) are stored/requested instructions; dosages (str | None) are remaining labels; has_slots (bool) indicates a regular slot selection.
# Returns: as_needed or scheduled. General product descriptions are not examined.
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


# Function Name: _has_schedule_slots
# Description: Reads valid slot selections from either stored JSON or an incoming iterable.
# Parameters: value (Any) is schedule_slot_keys; absent values are treated as an empty selection.
# Returns: bool indicating at least one normalized slot; parsing behavior follows the shared slot helpers.
def _has_schedule_slots(value: Any) -> bool:
    if isinstance(value, str):
        return bool(decode_medication_schedule_slot_keys(value))
    return bool(normalize_medication_schedule_slot_keys(value or []))


# Function Name: medication_dosing_mode
# Description: Re-evaluates stored instructions and selected slots so legacy as-needed rows do not become automatic schedules.
# Parameters: medication (Any) exposes optional dosing_mode, daily_frequency, dosage_per_time and schedule_slot_keys attributes.
# Returns: Normalized as_needed or scheduled mode, with absent attributes treated as unspecified.
def medication_dosing_mode(medication: Any) -> str:
    return resolve_dosing_mode(
        getattr(medication, "dosing_mode", None),
        getattr(medication, "daily_frequency", None),
        getattr(medication, "dosage_per_time", None),
        has_slots=_has_schedule_slots(getattr(medication, "schedule_slot_keys", None)),
    )
