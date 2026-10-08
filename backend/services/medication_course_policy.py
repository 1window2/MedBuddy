# File Name: medication_course_policy.py
# Role: Defines shared medication course date and duration rules.

from datetime import date, timedelta
import re
from typing import Any

from entities.medication_schedule_entity import (
    decode_medication_schedule_slot_keys,
    medication_schedule_slot_keys_for_frequency,
)

_SCHEDULE_COUNT_PATTERN = re.compile(r"-?\d+")
_FREQUENCY_COUNT_PATTERN = re.compile(
    r"(?<!\d)"
    r"(-?\d+)\s*(?:회|번|times?|x)",
    re.IGNORECASE,
)

MAX_MEDICATION_COURSE_DAYS = 3650
MAX_DAILY_FREQUENCY = 4


# Class Name: MedicationCoursePolicy
# Role:
# - Centralizes active-course and retention date calculations.
# Responsibilities:
# - Read a saved medication start date from prescription or created date.
# - Extract count values from prescription-derived schedule labels.
# - Own the course end date and the dose-slot derivation shared by schedule and chat.
# - Decide whether a medication is active on a requested date.
# - Decide whether a medication has passed a retention window.
class MedicationCoursePolicy:
    # Function Name: is_active_during
    # Description:
    # - Checks whether a saved medication overlaps an inclusive date window.
    # Parameters:
    # - medication (Any): Saved medication-like object with date and total_days fields.
    # - window_start (date): First date in the requested schedule window.
    # - window_end (date): Last date in the requested schedule window.
    # Returns:
    # - True when any day of the medication course overlaps the window.
    def is_active_during(
        self,
        medication: Any,
        window_start: date,
        window_end: date,
    ) -> bool:
        if window_end < window_start:
            return False

        course_start = self.read_start_date(medication, window_start)
        course_end = self.read_end_date(medication, window_start)
        if course_end is None:
            return course_start <= window_end

        return course_start <= window_end and course_end >= window_start

    # Function Name: is_active_on
    # Description:
    # - Checks whether a saved medication should be visible for a schedule date.
    # Parameters:
    # - medication (Any): Saved medication-like object with date and total_days fields.
    # - target_date (date): Date used for active-course evaluation.
    # Returns:
    # - True when the medication course includes the target date.
    def is_active_on(self, medication: Any, target_date: date) -> bool:
        start_date = self.read_start_date(medication, target_date)
        end_date = self.read_end_date(medication, target_date)
        if end_date is None:
            return start_date <= target_date

        return start_date <= target_date <= end_date

    # Function Name: is_expired_after
    # Description:
    # - Check whether a dated medication course has reached its configured post-course deletion date.
    # Parameters:
    # - medication (Any): Saved medication-like object with date and total_days fields.
    # - target_date (date): Date used for retention evaluation.
    # - retention_days (int): Number of days to keep a medication after course end.
    # Returns:
    # - True on or after course end plus retention_days; False when no positive duration can be read.
    def is_expired_after(
        self,
        medication: Any,
        target_date: date,
        retention_days: int,
    ) -> bool:
        end_date = self.read_end_date(medication, target_date)
        if end_date is None:
            return False

        delete_after_date = end_date + timedelta(days=retention_days)
        return target_date >= delete_after_date

    # Function Name: read_start_date
    # Description:
    # - Prefers prescription_date and falls back to created_date.
    # Parameters:
    # - medication (Any): Saved medication-like object.
    # - fallback_date (date): Date used when no valid date exists.
    # Returns:
    # - Parsed medication course start date.
    def read_start_date(self, medication: Any, fallback_date: date) -> date:
        recorded_date = self._read_recorded_start_date(medication)
        return fallback_date if recorded_date is None else recorded_date

    # Function Name: read_end_date
    # Description:
    # - Returns the last day of a medication course: start date plus total_days minus one.
    # - Single owner of the course-end rule behind the active, window and retention checks.
    # Parameters:
    # - medication (Any): Saved medication-like object with date and total_days fields.
    # - fallback (date | None): Start date assumed when the row holds no valid date.
    # Returns:
    # - Course end date; None when no positive duration can be read, or when the row
    #   holds no valid date and no fallback is given.
    def read_end_date(
        self,
        medication: Any,
        fallback: date | None = None,
    ) -> date | None:
        total_days = self.read_total_days(getattr(medication, "total_days", None))
        if total_days <= 0:
            return None
        start_date = self._read_recorded_start_date(medication)
        if start_date is None:
            start_date = fallback
        if start_date is None:
            return None
        return start_date + timedelta(days=total_days - 1)

    # Function Name: read_slot_keys
    # Description:
    # - Resolves the dose slots of a medication: the slots the user confirmed, otherwise
    #   the slots implied by the daily frequency label.
    # Parameters:
    # - raw_slot_keys (str | None): Stored JSON list of confirmed slot keys.
    # - raw_frequency (str | None): Raw label such as "3 times" or "1일 3회".
    # Returns:
    # - Ordered slot keys; never empty, because an unreadable frequency means one morning dose.
    def read_slot_keys(
        self,
        raw_slot_keys: str | None,
        raw_frequency: str | None,
    ) -> tuple[str, ...]:
        confirmed_slot_keys = decode_medication_schedule_slot_keys(raw_slot_keys)
        if confirmed_slot_keys:
            return tuple(confirmed_slot_keys)
        return tuple(
            medication_schedule_slot_keys_for_frequency(
                self.read_frequency_count(raw_frequency)
            )
        )

    # Function Name: read_total_days
    # Description:
    # - Extracts the first integer duration from a total_days or frequency label.
    # Parameters:
    # - raw_total_days (str | None): Raw label such as "7 days" or "3 times".
    # Returns:
    # - Positive duration capped at MAX_MEDICATION_COURSE_DAYS, or 0 for absent or nonpositive counts.
    def read_total_days(self, raw_total_days: str | None) -> int:
        return self._read_schedule_count(
            raw_total_days,
            maximum=MAX_MEDICATION_COURSE_DAYS,
        )

    # Function Name: read_frequency_count
    # Description:
    # - Extracts the dose count from a daily_frequency label.
    # Parameters:
    # - raw_frequency (str | None): Raw label such as "3 times" or "1일 3회".
    # Returns:
    # - Positive daily frequency capped at MAX_DAILY_FREQUENCY, or 0 when no valid count is found.
    def read_frequency_count(self, raw_frequency: str | None) -> int:
        if not raw_frequency:
            return 0
        frequency_match = _FREQUENCY_COUNT_PATTERN.search(raw_frequency)
        if frequency_match is not None:
            return self._bounded_positive_count(
                frequency_match.group(1),
                MAX_DAILY_FREQUENCY,
            )

        matches = _SCHEDULE_COUNT_PATTERN.findall(raw_frequency)
        if not matches:
            return 0
        return self._bounded_positive_count(matches[-1], MAX_DAILY_FREQUENCY)

    # Function Name: _read_recorded_start_date
    # Description:
    # - Reads the start date stored on the row, preferring prescription_date over created_date.
    # Parameters:
    # - medication (Any): Saved medication-like object.
    # Returns:
    # - Parsed date, or None when neither field holds a valid date.
    def _read_recorded_start_date(self, medication: Any) -> date | None:
        raw_date = (
            getattr(medication, "prescription_date", None)
            or getattr(medication, "created_date", None)
        )
        if isinstance(raw_date, date):
            return raw_date
        if isinstance(raw_date, str) and raw_date.strip():
            try:
                return date.fromisoformat(raw_date.strip())
            except ValueError:
                return None
        return None

    # Function Name: _read_schedule_count
    # Description:
    # - Extract the first signed integer in a schedule label and enforce a positive upper-bounded count.
    # Parameters:
    # - raw_value (str | None): Prescription-derived duration or count label.
    # - maximum (int): Largest positive schedule count permitted by the caller.
    # Returns:
    # - The capped positive count, or 0 for missing text, no match or a nonpositive number.
    def _read_schedule_count(
        self,
        raw_value: str | None,
        *,
        maximum: int,
    ) -> int:
        if not raw_value:
            return 0
        match = _SCHEDULE_COUNT_PATTERN.search(raw_value)
        if match is None:
            return 0
        return self._bounded_positive_count(match.group(0), maximum)

    # Function Name: _bounded_positive_count
    # Description:
    # - Parse integer text, reject nonpositive values and clamp valid counts to the domain maximum.
    # Parameters:
    # - raw_value (str): Integer text extracted from a schedule label.
    # - maximum (int): Largest permitted count.
    # Returns:
    # - A positive bounded count, or 0 if parsing fails or the value is nonpositive.
    @staticmethod
    def _bounded_positive_count(raw_value: str, maximum: int) -> int:
        try:
            parsed_value = int(raw_value)
        except ValueError:
            return 0
        if parsed_value <= 0:
            return 0
        return min(parsed_value, maximum)
