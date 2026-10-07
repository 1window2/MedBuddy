# File Name: test_medication_course_policy.py
# Role: Regression coverage for medication course windows, retention, and bounded dose-frequency
#   parsing.

import unittest
from datetime import date, timedelta
from pathlib import Path
import sys
from types import SimpleNamespace

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from services.medication_course_policy import (
    MAX_DAILY_FREQUENCY,
    MAX_MEDICATION_COURSE_DAYS,
    MedicationCoursePolicy,
    _FREQUENCY_COUNT_PATTERN,
)


# Class Name: MedicationCoursePolicyTest
# Role: Tests of course-date eligibility and safe parsing of treatment days and daily dose
#   counts.
# Responsibilities:
# - Requires the frequency regex to guard against restarting a match inside a longer digit
#   sequence.
# - Includes a future course only when the queried rolling window reaches its start date.
# - Maps negative counts to zero and caps excessive treatment-day and daily-frequency values at
#   their policy limits.
# Attributes:
# - policy (MedicationCoursePolicy): Medication course and frequency policy under test.
class MedicationCoursePolicyTest(unittest.TestCase):
    # Function Name: test_frequency_pattern_does_not_restart_inside_digit_runs
    # Description:
    # - Requires the frequency regex to guard against restarting a match inside a longer
    #   digit sequence.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_frequency_pattern_does_not_restart_inside_digit_runs(self) -> None:
        self.assertTrue(_FREQUENCY_COUNT_PATTERN.pattern.startswith(r"(?<!\d)"))

    # Function Name: setUp
    # Description:
    # - Creates a fresh medication course policy for each parsing and date-window case.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def setUp(self) -> None:
        self.policy = MedicationCoursePolicy()

    # Function Name: test_is_active_on_uses_prescription_date_and_total_days
    # Description:
    # - Includes the final prescribed treatment day and excludes the following day.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_is_active_on_uses_prescription_date_and_total_days(self) -> None:
        medication = SimpleNamespace(
            prescription_date=date(2026, 1, 1),
            created_date=date(2025, 12, 20),
            total_days="3 days",
        )

        self.assertTrue(self.policy.is_active_on(medication, date(2026, 1, 3)))
        self.assertFalse(self.policy.is_active_on(medication, date(2026, 1, 4)))

    # Function Name: test_missing_total_days_keeps_medication_active_after_start
    # Description:
    # - Keeps a started medication active when its treatment duration is unknown.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_missing_total_days_keeps_medication_active_after_start(self) -> None:
        medication = SimpleNamespace(
            prescription_date=None,
            created_date=date(2026, 1, 1),
            total_days="",
        )

        self.assertTrue(self.policy.is_active_on(medication, date(2026, 1, 10)))

    # Function Name: test_future_course_overlaps_rolling_schedule_window
    # Description:
    # - Includes a future course only when the queried rolling window reaches its start
    #   date.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_future_course_overlaps_rolling_schedule_window(self) -> None:
        medication = SimpleNamespace(
            prescription_date=date(2026, 1, 10),
            created_date=None,
            total_days="3 days",
        )

        self.assertTrue(
            self.policy.is_active_during(
                medication,
                date(2026, 1, 1),
                date(2026, 1, 14),
            )
        )
        self.assertFalse(
            self.policy.is_active_during(
                medication,
                date(2026, 1, 1),
                date(2026, 1, 9),
            )
        )

    # Function Name: test_is_expired_after_applies_retention_window
    # Description:
    # - Expires ended medication history only after the configured retention window.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_is_expired_after_applies_retention_window(self) -> None:
        medication = SimpleNamespace(
            prescription_date=date.today() - timedelta(days=40),
            created_date=None,
            total_days="7 days",
        )

        self.assertTrue(
            self.policy.is_expired_after(
                medication,
                date.today(),
                retention_days=30,
            )
        )

    # Function Name: test_read_frequency_count_parses_daily_frequency_label
    # Description:
    # - Parses English and Korean daily-frequency labels into their expected dose counts.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_read_frequency_count_parses_daily_frequency_label(self) -> None:
        self.assertEqual(self.policy.read_frequency_count("3 times a day"), 3)
        self.assertEqual(self.policy.read_frequency_count("1일 3회"), 3)
        self.assertEqual(self.policy.read_frequency_count("하루 2번"), 2)

    # Function Name: test_schedule_counts_are_positive_and_bounded
    # Description:
    # - Maps negative counts to zero and caps excessive treatment-day and daily-frequency
    #   values at their policy limits.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_schedule_counts_are_positive_and_bounded(self) -> None:
        self.assertEqual(self.policy.read_total_days("-5 days"), 0)
        self.assertEqual(
            self.policy.read_total_days("999999999999999999 days"),
            MAX_MEDICATION_COURSE_DAYS,
        )
        self.assertEqual(self.policy.read_frequency_count("-2 times"), 0)
        self.assertEqual(
            self.policy.read_frequency_count("12 times"),
            MAX_DAILY_FREQUENCY,
        )


if __name__ == "__main__":
    unittest.main()
