# File Name: medication_course_policy.py
# Role: Defines shared medication course date and duration rules.

from datetime import date, timedelta
import re
from typing import Any

_SCHEDULE_COUNT_PATTERN = re.compile(r"\d+")


# Class Name: MedicationCoursePolicy
# Role: Centralizes active-course and retention date calculations.
# Responsibilities:
#   - Read a saved medication start date from prescription or created date.
    #   - Extract count values from prescription-derived schedule labels.
#   - Decide whether a medication is active on a requested date.
#   - Decide whether a medication has passed a retention window.
class MedicationCoursePolicy:
    # Function Name: is_active_on
    # Description:
    # - Checks whether a saved medication should be visible for a schedule date.
    # Parameters:
    # - medication: Saved medication-like object with date and total_days fields.
    # - target_date: Date used for active-course evaluation.
    # Returns:
    # - True when the medication course includes the target date.
    def is_active_on(self, medication: Any, target_date: date) -> bool:
        start_date = self.read_start_date(medication, target_date)
        total_days = self.read_total_days(getattr(medication, "total_days", None))
        if total_days <= 0:
            return start_date <= target_date

        end_date = start_date + timedelta(days=total_days - 1)
        return start_date <= target_date <= end_date

    # Function Name: is_expired_after
    # Description:
    # - Checks whether a medication course ended more than retention_days ago.
    # Parameters:
    # - medication: Saved medication-like object with date and total_days fields.
    # - target_date: Date used for retention evaluation.
    # - retention_days: Number of days to keep a medication after course end.
    # Returns:
    # - True when the medication is past the retention window.
    def is_expired_after(
        self,
        medication: Any,
        target_date: date,
        retention_days: int,
    ) -> bool:
        total_days = self.read_total_days(getattr(medication, "total_days", None))
        if total_days <= 0:
            return False

        start_date = self.read_start_date(medication, target_date)
        end_date = start_date + timedelta(days=total_days - 1)
        delete_after_date = end_date + timedelta(days=retention_days)
        return target_date >= delete_after_date

    # Function Name: read_start_date
    # Description:
    # - Prefers prescription_date and falls back to created_date.
    # Parameters:
    # - medication: Saved medication-like object.
    # - fallback_date: Date used when no valid date exists.
    # Returns:
    # - Parsed medication course start date.
    def read_start_date(self, medication: Any, fallback_date: date) -> date:
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
                return fallback_date
        return fallback_date

    # Function Name: read_total_days
    # Description:
    # - Extracts the first integer duration from a total_days or frequency label.
    # Parameters:
    # - raw_total_days: Raw label such as "7 days" or "3 times".
    # Returns:
    # - Parsed integer, or 0 when no number is available.
    def read_total_days(self, raw_total_days: str | None) -> int:
        return self._read_schedule_count(raw_total_days)

    # Function Name: read_frequency_count
    # Description:
    # - Extracts the first integer from a daily_frequency label.
    # Parameters:
    # - raw_frequency: Raw label such as "3 times".
    # Returns:
    # - Parsed integer, or 0 when no number is available.
    def read_frequency_count(self, raw_frequency: str | None) -> int:
        return self._read_schedule_count(raw_frequency)

    def _read_schedule_count(self, raw_value: str | None) -> int:
        if not raw_value:
            return 0
        match = _SCHEDULE_COUNT_PATTERN.search(raw_value)
        if match is None:
            return 0
        return int(match.group(0))
