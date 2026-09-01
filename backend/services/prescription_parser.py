# File Name: prescription_parser.py
# Role: Deterministic normalizer for structured prescription analysis output.

import math
import re
from datetime import date
from typing import Any

from entities.prescription_analysis_entity import (
    MedicationCandidate,
    MedicationCandidateList,
)


INFO_UNAVAILABLE = "\uc815\ubcf4 \uc5c6\uc74c"
MAX_MEDICATION_NAME_LENGTH = 200

DATE_PATTERN = re.compile(r"(\d{4})[./-](\d{1,2})[./-](\d{1,2})")
LEADING_MARKER_PATTERN = re.compile(r"^\s*(?:[-*]|\d+[.)])\s*")

UNKNOWN_TEXTS = {
    "",
    "-",
    "--",
    "?",
    "none",
    "null",
    "n/a",
    "nan",
    "inf",
    "+inf",
    "-inf",
    "infinity",
    "+infinity",
    "-infinity",
    "unknown",
    INFO_UNAVAILABLE,
}

HOSPITAL_NAME_KEYS = (
    "hospital_name",
    "hospitalName",
    "pharmacy_name",
    "pharmacyName",
    "clinic_name",
    "clinicName",
)
PRESCRIPTION_DATE_KEYS = (
    "prescription_date",
    "prescriptionDate",
    "dispense_date",
    "dispenseDate",
    "date",
)
MEDICATION_LIST_KEYS = (
    "medications",
    "medicines",
    "medicine_list",
    "medicineList",
    "drugs",
    "items",
)
DRUG_NAME_KEYS = (
    "drug_name",
    "drugName",
    "medication_name",
    "medicationName",
    "medicine_name",
    "medicineName",
    "item_name",
    "itemName",
    "product_name",
    "productName",
    "name",
)
DOSAGE_KEYS = (
    "dosage_per_time",
    "dosagePerTime",
    "dose_per_time",
    "dosePerTime",
    "dosage",
    "dose",
)
DAILY_FREQUENCY_KEYS = (
    "daily_frequency",
    "dailyFrequency",
    "frequency_per_day",
    "frequencyPerDay",
    "daily_count",
    "dailyCount",
    "intake_time",
    "intakeTime",
    "frequency",
)
TOTAL_DAYS_KEYS = (
    "total_days",
    "totalDays",
    "duration_days",
    "durationDays",
    "medication_time",
    "medicationTime",
    "days",
    "duration",
)


def normalize_text(text: str) -> str:
    text = str(text or "").strip()
    text = text.replace(":", " ")
    return " ".join(text.split())


def normalize_date(text: str) -> str | None:
    match = DATE_PATTERN.search(str(text or ""))
    if not match:
        return None

    year, month, day = match.groups()
    try:
        return date(int(year), int(month), int(day)).isoformat()
    except ValueError:
        return None


def normalize_prescription_candidates(
    data: dict[str, Any],
) -> tuple[str, str, MedicationCandidateList, int]:
    if not isinstance(data, dict):
        raise ValueError("Prescription analysis response must be a JSON object.")

    prescription_date = _read_first_text(data, PRESCRIPTION_DATE_KEYS)
    normalized_date = normalize_date(prescription_date or "")
    raw_items = _read_first_list(data, MEDICATION_LIST_KEYS)
    medication_candidate_list = MedicationCandidateList()
    for raw_item in raw_items:
        medication_candidate = normalize_prescription_medication(raw_item)
        if medication_candidate is not None:
            medication_candidate_list.addCandidate(medication_candidate)

    return (
        _read_first_text(
            data,
            HOSPITAL_NAME_KEYS,
            default=INFO_UNAVAILABLE,
        ),
        normalized_date or INFO_UNAVAILABLE,
        medication_candidate_list.deduplicated(),
        len(raw_items),
    )


def normalize_prescription_medication(raw_item: Any) -> MedicationCandidate | None:
    if not isinstance(raw_item, dict):
        return None

    drug_name = _clean_medication_name(_read_first_text(raw_item, DRUG_NAME_KEYS))
    if _is_unknown(drug_name) or len(drug_name) > MAX_MEDICATION_NAME_LENGTH:
        return None

    return MedicationCandidate(
        drug_name=drug_name,
        dosage_per_time=_read_first_text(raw_item, DOSAGE_KEYS),
        daily_frequency=_read_first_text(raw_item, DAILY_FREQUENCY_KEYS),
        total_days=_read_first_text(raw_item, TOTAL_DAYS_KEYS),
    )


def _read_first_list(data: dict[str, Any], keys: tuple[str, ...]) -> list[Any]:
    for key in keys:
        value = data.get(key)
        if isinstance(value, list):
            return value
    return []


def _read_first_text(
    data: dict[str, Any],
    keys: tuple[str, ...],
    default: str = "",
) -> str:
    for key in keys:
        value = data.get(key)
        text = _format_value(value)
        if not _is_unknown(text):
            return text
    return default


def _format_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, float):
        return _format_numeric_text(value)
    return normalize_text(str(value))


def _format_numeric_text(value: Any) -> str:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return normalize_text(str(value or ""))
    if not math.isfinite(number):
        return ""
    if number.is_integer():
        return str(int(number))
    return str(number).rstrip("0").rstrip(".")


def _clean_medication_name(name: str) -> str:
    cleaned_name = LEADING_MARKER_PATTERN.sub("", normalize_text(name))
    for label in (
        "\uc57d\ud488\uba85",
        "\uc81c\ud488\uba85",
        "drug name",
        "medication name",
        "medicine name",
    ):
        cleaned_name = _remove_literal_case_insensitive(cleaned_name, label)
    return normalize_text(cleaned_name).strip(": ").strip()


def _remove_literal_case_insensitive(text: str, literal: str) -> str:
    """Remove ASCII/Korean labels without transformed-string index drift."""

    if not literal:
        return text
    literal_length = len(literal)
    folded_literal = literal.casefold()
    output: list[str] = []
    cursor = 0
    while cursor < len(text):
        candidate = text[cursor : cursor + literal_length]
        if len(candidate) == literal_length and candidate.casefold() == folded_literal:
            cursor += literal_length
            continue
        output.append(text[cursor])
        cursor += 1
    return "".join(output)


def _is_unknown(value: str) -> bool:
    return normalize_text(value).lower() in UNKNOWN_TEXTS
