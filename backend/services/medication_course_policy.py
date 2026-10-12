# File Name: medication_course_policy.py
# Role: Defines shared medication course date and duration rules.

from datetime import date, timedelta
import re
from typing import Any

from entities.medication_schedule_entity import (
    decode_medication_schedule_slot_keys,
    medication_schedule_slot_keys_for_frequency,
)
from services.medication_dose_rhythm import (
    DoseCycle,
    read_dose_cycle,
    read_doses_per_dose_day,
    read_duration_days,
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

    # Function Name: is_due_on
    # Description:
    # - Checks whether a dose of the medication is due on a date: the course includes the date
    #   and, for a medication that is not taken every day ("주 1회", "격일"), the date is one of
    #   its dose days counted from the start of the course.
    # - A non-daily medication without a recorded start date has no day to count from and is
    #   treated as daily, as it was before dose days were read.
    # Parameters:
    # - medication (Any): Saved medication-like object with date, total_days and daily_frequency.
    # - target_date (date): Date asked about.
    # Returns:
    # - True when the medication belongs on that day's schedule.
    def is_due_on(self, medication: Any, target_date: date) -> bool:
        if not self.is_active_on(medication, target_date):
            return False
        cycle = self.read_dose_cycle(medication)
        if cycle.is_daily:
            return True
        start_date = self._read_recorded_start_date(medication)
        if start_date is None:
            return True
        return cycle.includes(start_date, target_date)

    # Function Name: read_dose_cycle
    # Description:
    # - Reads the dose days of a medication from its frequency label.
    # Parameters:
    # - medication (Any): Saved medication-like object with a daily_frequency label.
    # Returns:
    # - The dose cycle; the daily cycle for every label that names no other rhythm.
    def read_dose_cycle(self, medication: Any) -> DoseCycle:
        return read_dose_cycle(getattr(medication, "daily_frequency", None))

    # Function Name: dose_cycle_fields
    # Description:
    # - Describes the dose days for API responses so that clients schedule reminders on the same
    #   days without reading the label themselves: a date D is a dose day when the number of
    #   days from dose_cycle_anchor to D, modulo dose_cycle_days, is in dose_cycle_offsets.
    # Parameters:
    # - medication (Any): Saved medication-like object.
    # Returns:
    # - The three response fields; a daily medication has a one-day cycle and no anchor.
    def dose_cycle_fields(self, medication: Any) -> dict[str, object]:
        cycle = self.read_dose_cycle(medication)
        start_date = self._read_recorded_start_date(medication)
        if cycle.is_daily or start_date is None:
            return {
                "dose_cycle_days": 1,
                "dose_cycle_offsets": [0],
                "dose_cycle_anchor": None,
            }
        return {
            "dose_cycle_days": cycle.cycle_days,
            "dose_cycle_offsets": list(cycle.offsets),
            "dose_cycle_anchor": cycle.anchor(start_date).isoformat(),
        }

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
    # - Reads the course length in days from the first number of a total_days label and its
    #   unit: "7 days" is 7, "2주" is 14 and "1개월" is 30.
    # Parameters:
    # - raw_total_days (str | None): Raw label such as "7 days" or "2주".
    # Returns:
    # - Positive duration capped at MAX_MEDICATION_COURSE_DAYS, or 0 for absent or nonpositive counts.
    def read_total_days(self, raw_total_days: str | None) -> int:
        return min(read_duration_days(raw_total_days), MAX_MEDICATION_COURSE_DAYS)

    # Function Name: read_frequency_count
    # Description:
    # - Extracts the number of doses on a dose day from a daily_frequency label.
    # - A count that is per week or month ("주 3회") is one dose on each dose day, and an hour
    #   interval ("8시간마다") is the number of doses that fit into a day.
    # Parameters:
    # - raw_frequency (str | None): Raw label such as "3 times" or "1일 3회".
    # Returns:
    # - Positive daily frequency capped at MAX_DAILY_FREQUENCY, or 0 when no valid count is found.
    def read_frequency_count(self, raw_frequency: str | None) -> int:
        if not raw_frequency:
            return 0
        doses_per_dose_day = read_doses_per_dose_day(raw_frequency)
        if doses_per_dose_day is not None:
            return min(doses_per_dose_day, MAX_DAILY_FREQUENCY)
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
