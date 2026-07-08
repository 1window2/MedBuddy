# File Name: prescription_parser.py
# Role: Deterministic parser and normalizer for prescription OCR output.

import re
from typing import Any


INFO_UNAVAILABLE = "\uc815\ubcf4 \uc5c6\uc74c"

DATE_PATTERN = re.compile(r"(\d{4})[./-](\d{1,2})[./-](\d{1,2})")
MED_LINE_PATTERN = re.compile(r"(.+?)\s+(\d+(?:\.\d+)?)\s+(\d+)\s+(\d+)$")
LEADING_MARKER_PATTERN = re.compile(r"^\s*(?:[-*]|\d+[.)])\s*")

UNKNOWN_TEXTS = {
    "",
    "-",
    "--",
    "?",
    "none",
    "null",
    "n/a",
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
    return f"{int(year):04d}-{int(month):02d}-{int(day):02d}"


def extract_patient_name(line: str) -> str | None:
    normalized_line = normalize_text(line)
    for label in ("\ud658\uc790\uba85", "patient name", "patient"):
        if label not in normalized_line.lower():
            continue
        cleaned = re.sub(label, "", normalized_line, flags=re.IGNORECASE)
        cleaned = cleaned.strip(": ").strip()
        return cleaned if cleaned else None
    return None


def extract_prescription_date(line: str) -> str | None:
    normalized_line = normalize_text(line)
    lowered_line = normalized_line.lower()
    if not any(
        label in lowered_line
        for label in ("\ucc98\ubc29", "\uc870\uc81c", "prescription", "dispense")
    ):
        return None
    return normalize_date(normalized_line)


def parse_medication_line(line: str) -> dict[str, Any] | None:
    normalized_line = normalize_text(line)
    match = MED_LINE_PATTERN.match(normalized_line)
    if not match:
        return None

    name, dose_raw, frequency_raw, days_raw = match.groups()
    cleaned_name = _clean_medication_name(name)
    if _is_unknown(cleaned_name):
        return None

    dose = _parse_number(dose_raw)
    frequency_per_day = _parse_int(frequency_raw)
    duration_days = _parse_int(days_raw)
    if dose is None or frequency_per_day is None or duration_days is None:
        return None

    dosage_text = _format_numeric_text(dose_raw)
    frequency_text = _format_numeric_text(frequency_raw)
    days_text = _format_numeric_text(days_raw)
    return {
        "name": cleaned_name,
        "drug_name": cleaned_name,
        "dose_per_time": dose,
        "dosage_per_time": dosage_text,
        "frequency_per_day": frequency_per_day,
        "daily_frequency": frequency_text,
        "duration_days": duration_days,
        "total_days": days_text,
    }


def parse_prescription(lines: list[str]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "patient_name": None,
        "prescription_date": None,
        "medicines": [],
        "medications": [],
    }

    for raw_line in lines:
        line = normalize_text(raw_line)
        if not line:
            continue

        patient_name = extract_patient_name(line)
        if patient_name:
            result["patient_name"] = patient_name
            continue

        prescription_date = extract_prescription_date(line)
        if prescription_date:
            result["prescription_date"] = prescription_date
            continue

        medication = parse_medication_line(line)
        if medication:
            result["medicines"].append(medication)
            result["medications"].append(
                {
                    "drug_name": medication["drug_name"],
                    "dosage_per_time": medication["dosage_per_time"],
                    "daily_frequency": medication["daily_frequency"],
                    "total_days": medication["total_days"],
                }
            )

    return result


def normalize_prescription_payload(data: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise ValueError("Prescription analysis response must be a JSON object.")

    prescription_date = _read_first_text(data, PRESCRIPTION_DATE_KEYS)
    normalized_date = normalize_date(prescription_date or "")
    raw_items = _read_first_list(data, MEDICATION_LIST_KEYS)
    normalized_medications = [
        medication
        for raw_item in raw_items
        if (medication := normalize_prescription_medication(raw_item)) is not None
    ]
    deduplicated_medications = _deduplicate_medications(normalized_medications)

    return {
        "hospital_name": _read_first_text(
            data,
            HOSPITAL_NAME_KEYS,
            default=INFO_UNAVAILABLE,
        ),
        "prescription_date": normalized_date
        or _read_first_text(data, PRESCRIPTION_DATE_KEYS, default=INFO_UNAVAILABLE),
        "medications": deduplicated_medications,
        "raw_medication_count": len(raw_items),
        "parsed_medication_count": len(deduplicated_medications),
        "skipped_medication_count": len(raw_items) - len(deduplicated_medications),
    }


def normalize_prescription_medication(raw_item: Any) -> dict[str, str] | None:
    if not isinstance(raw_item, dict):
        return None

    drug_name = _clean_medication_name(_read_first_text(raw_item, DRUG_NAME_KEYS))
    if _is_unknown(drug_name):
        return None

    return {
        "drug_name": drug_name,
        "dosage_per_time": _read_first_text(raw_item, DOSAGE_KEYS),
        "daily_frequency": _read_first_text(raw_item, DAILY_FREQUENCY_KEYS),
        "total_days": _read_first_text(raw_item, TOTAL_DAYS_KEYS),
    }


def _read_first_list(data: dict[str, Any], keys: tuple[str, ...]) -> list[Any]:
    for key in keys:
        value = data.get(key)
        if isinstance(value, list):
            return value
    return []


def _deduplicate_medications(
    medications: list[dict[str, str]],
) -> list[dict[str, str]]:
    deduplicated_medications: list[dict[str, str]] = []
    seen_keys = set()
    for medication in medications:
        medication_key = (
            medication["drug_name"],
            medication["dosage_per_time"],
            medication["daily_frequency"],
            medication["total_days"],
        )
        if medication_key in seen_keys:
            continue
        seen_keys.add(medication_key)
        deduplicated_medications.append(medication)
    return deduplicated_medications


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
    if number.is_integer():
        return str(int(number))
    return str(number).rstrip("0").rstrip(".")


def _parse_number(value: Any) -> int | float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if number.is_integer():
        return int(number)
    return number


def _parse_int(value: Any) -> int | None:
    parsed_value = _parse_number(value)
    if isinstance(parsed_value, int):
        return parsed_value
    return None


def _clean_medication_name(name: str) -> str:
    cleaned_name = LEADING_MARKER_PATTERN.sub("", normalize_text(name))
    for label in (
        "\uc57d\ud488\uba85",
        "\uc81c\ud488\uba85",
        "drug name",
        "medication name",
        "medicine name",
    ):
        cleaned_name = re.sub(label, "", cleaned_name, flags=re.IGNORECASE)
    return cleaned_name.strip(": ").strip()


def _is_unknown(value: str) -> bool:
    return normalize_text(value).lower() in UNKNOWN_TEXTS
