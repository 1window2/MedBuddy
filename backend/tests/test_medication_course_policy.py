# File Name: test_medication_course_policy.py
# Role: Verifies shared medication course date and duration rules.

import unittest
from datetime import date, timedelta
from pathlib import Path
import sys
from types import SimpleNamespace

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from services.medication_course_policy import MedicationCoursePolicy


class MedicationCoursePolicyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.policy = MedicationCoursePolicy()

    def test_is_active_on_uses_prescription_date_and_total_days(self) -> None:
        medication = SimpleNamespace(
            prescription_date=date(2026, 1, 1),
            created_date=date(2025, 12, 20),
            total_days="3 days",
        )

        self.assertTrue(self.policy.is_active_on(medication, date(2026, 1, 3)))
        self.assertFalse(self.policy.is_active_on(medication, date(2026, 1, 4)))

    def test_missing_total_days_keeps_medication_active_after_start(self) -> None:
        medication = SimpleNamespace(
            prescription_date=None,
            created_date=date(2026, 1, 1),
            total_days="",
        )

        self.assertTrue(self.policy.is_active_on(medication, date(2026, 1, 10)))

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

    def test_read_frequency_count_parses_daily_frequency_label(self) -> None:
        self.assertEqual(self.policy.read_frequency_count("3 times a day"), 3)
        self.assertEqual(self.policy.read_frequency_count("1일 3회"), 3)
        self.assertEqual(self.policy.read_frequency_count("하루 2번"), 2)


if __name__ == "__main__":
    unittest.main()
