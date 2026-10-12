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

    # Function Name: test_read_end_date_is_start_plus_duration_minus_one
    # Description:
    # - Returns the last course day from the prescription date, then the created date, then
    #   the fallback; an unknown duration, or no date without a fallback, has no end date.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_read_end_date_is_start_plus_duration_minus_one(self) -> None:
        fallback = date(2026, 3, 1)
        cases = [
            (
                SimpleNamespace(
                    prescription_date=date(2026, 1, 1),
                    created_date=date(2026, 1, 5),
                    total_days="7 days",
                ),
                date(2026, 1, 7),
            ),
            (
                SimpleNamespace(
                    prescription_date=None,
                    created_date="2026-01-05",
                    total_days="1",
                ),
                date(2026, 1, 5),
            ),
            (
                SimpleNamespace(
                    prescription_date=None,
                    created_date=None,
                    total_days="3 days",
                ),
                date(2026, 3, 3),
            ),
            (
                SimpleNamespace(
                    prescription_date="not-a-date",
                    created_date=None,
                    total_days="3 days",
                ),
                date(2026, 3, 3),
            ),
            (
                SimpleNamespace(
                    prescription_date=date(2026, 1, 1),
                    created_date=None,
                    total_days="",
                ),
                None,
            ),
            (
                SimpleNamespace(
                    prescription_date=date(2026, 1, 1),
                    created_date=None,
                    total_days="0 days",
                ),
                None,
            ),
        ]

        for medication, expected in cases:
            with self.subTest(medication=medication):
                self.assertEqual(
                    self.policy.read_end_date(medication, fallback),
                    expected,
                )
        self.assertIsNone(
            self.policy.read_end_date(
                SimpleNamespace(
                    prescription_date=None,
                    created_date=None,
                    total_days="3 days",
                )
            )
        )
        self.assertEqual(
            self.policy.read_end_date(
                SimpleNamespace(
                    prescription_date=date(2026, 1, 1),
                    created_date=None,
                    total_days="7 days",
                )
            ),
            date(2026, 1, 7),
        )

    # Function Name: test_read_end_date_bounds_the_active_and_retention_rules
    # Description:
    # - The end date is the last active day, the last day that overlaps a window, and the
    #   day the retention period starts counting from.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_read_end_date_bounds_the_active_and_retention_rules(self) -> None:
        medication = SimpleNamespace(
            prescription_date=date(2026, 1, 1),
            created_date=None,
            total_days="7 days",
        )
        end_date = self.policy.read_end_date(medication)
        day_after = end_date + timedelta(days=1)

        self.assertEqual(end_date, date(2026, 1, 7))
        self.assertTrue(self.policy.is_active_on(medication, end_date))
        self.assertFalse(self.policy.is_active_on(medication, day_after))
        self.assertTrue(self.policy.is_active_during(medication, end_date, day_after))
        self.assertFalse(
            self.policy.is_active_during(
                medication,
                day_after,
                day_after + timedelta(days=5),
            )
        )
        self.assertFalse(
            self.policy.is_expired_after(
                medication,
                end_date + timedelta(days=29),
                retention_days=30,
            )
        )
        self.assertTrue(
            self.policy.is_expired_after(
                medication,
                end_date + timedelta(days=30),
                retention_days=30,
            )
        )

    # Function Name: test_read_slot_keys_prefers_confirmed_slots_over_frequency
    # Description:
    # - Uses the stored confirmed slots in schedule order and falls back to the slots implied
    #   by the daily frequency when the stored value is empty, invalid or holds no valid key.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_read_slot_keys_prefers_confirmed_slots_over_frequency(self) -> None:
        cases = [
            ('["evening","morning"]', "3 times", ("morning", "evening")),
            ('["bedtime"]', None, ("bedtime",)),
            ("[]", "3 times", ("morning", "lunch", "evening")),
            (None, "하루 2번", ("morning", "evening")),
            ("", "4 times", ("morning", "lunch", "evening", "bedtime")),
            ("not-json", "1 time", ("morning",)),
            ('["snack"]', "2 times", ("morning", "evening")),
            ('{"morning": true}', "2 times", ("morning", "evening")),
            ("[]", None, ("morning",)),
            ("[]", "as needed", ("morning",)),
        ]

        for raw_slot_keys, raw_frequency, expected in cases:
            with self.subTest(raw_slot_keys=raw_slot_keys, raw_frequency=raw_frequency):
                self.assertEqual(
                    self.policy.read_slot_keys(raw_slot_keys, raw_frequency),
                    expected,
                )

    # Function Name: test_non_daily_medication_is_due_only_on_its_dose_days
    # Description:
    # - A weekly medication is due on the first day of the course and every seventh day after
    #   it, never on the days between, and not after the course has ended; a daily medication
    #   and a non-daily one without a recorded start date are due every day of the course.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_non_daily_medication_is_due_only_on_its_dose_days(self) -> None:
        start = date(2026, 10, 7)
        weekly = SimpleNamespace(
            prescription_date=start, created_date=None,
            total_days="4주", daily_frequency="주 1회",
        )
        due = [
            offset for offset in range(35)
            if self.policy.is_due_on(weekly, start + timedelta(days=offset))
        ]
        self.assertEqual(due, [0, 7, 14, 21])
        self.assertTrue(self.policy.is_active_on(weekly, start + timedelta(days=3)))
        self.assertFalse(self.policy.is_due_on(weekly, start - timedelta(days=7)))

        daily = SimpleNamespace(
            prescription_date=start, created_date=None,
            total_days="3", daily_frequency="1일 3회",
        )
        self.assertEqual(
            [self.policy.is_due_on(daily, start + timedelta(days=offset)) for offset in range(4)],
            [True, True, True, False],
        )
        undated = SimpleNamespace(
            prescription_date=None, created_date=None,
            total_days="", daily_frequency="격일",
        )
        self.assertTrue(self.policy.is_due_on(undated, start + timedelta(days=1)))

    # Function Name: test_dose_cycle_fields_describe_the_dose_days_for_clients
    # Description:
    # - The response fields carry the cycle, its dose days and day 0: the course start for
    #   intervals, the Monday of the starting week for named weekdays, and a one-day cycle
    #   without an anchor for daily medications.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_dose_cycle_fields_describe_the_dose_days_for_clients(self) -> None:
        # Function Name: fields
        # Description: Reads the response fields for a label on a course starting Wednesday.
        # Parameters: frequency (str) - Frequency label.
        # Returns: The dose cycle response fields.
        def fields(frequency: str) -> dict[str, object]:
            return self.policy.dose_cycle_fields(SimpleNamespace(
                prescription_date=date(2026, 10, 7), created_date=None,
                total_days="30", daily_frequency=frequency,
            ))

        self.assertEqual(fields("1일 2회"), {
            "dose_cycle_days": 1, "dose_cycle_offsets": [0], "dose_cycle_anchor": None,
        })
        self.assertEqual(fields("격일"), {
            "dose_cycle_days": 2, "dose_cycle_offsets": [0], "dose_cycle_anchor": "2026-10-07",
        })
        self.assertEqual(fields("월수금"), {
            "dose_cycle_days": 7, "dose_cycle_offsets": [0, 2, 4],
            "dose_cycle_anchor": "2026-10-05",
        })

    # Function Name: test_frequency_and_duration_labels_are_not_misread_as_daily_counts
    # Description:
    # - A weekly count is one dose on a dose day, an hour interval is the doses that fit a day,
    #   and week or month durations are converted to days.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_frequency_and_duration_labels_are_not_misread_as_daily_counts(self) -> None:
        self.assertEqual(self.policy.read_frequency_count("주 3회"), 1)
        self.assertEqual(self.policy.read_frequency_count("주 3회, 1일 2회"), 2)
        self.assertEqual(self.policy.read_frequency_count("8시간마다"), 3)
        self.assertEqual(self.policy.read_frequency_count("4시간마다"), MAX_DAILY_FREQUENCY)
        self.assertEqual(self.policy.read_slot_keys(None, "주 1회"), ("morning",))
        self.assertEqual(self.policy.read_total_days("2주"), 14)
        self.assertEqual(self.policy.read_total_days("1개월"), 30)
        self.assertEqual(self.policy.read_total_days("7일분 (1주)"), 7)


if __name__ == "__main__":
    unittest.main()
