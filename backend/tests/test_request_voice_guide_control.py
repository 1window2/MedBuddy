# File Name: test_request_voice_guide_control.py
# Role: Verifies medication voice guide text generation.

import sys
import unittest
from pathlib import Path

from fastapi import HTTPException

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.request_voice_guide_control import RequestVoiceGuide  # noqa: E402
from entities.medication_detail_entity import MedicationDetail  # noqa: E402


class RequestVoiceGuideTest(unittest.TestCase):
    def setUp(self) -> None:
        self.control = RequestVoiceGuide()

    def test_request_voice_guide_returns_korean_labeled_text(self) -> None:
        medication_detail = MedicationDetail(
            item_name="Test tablet",
            efficacy="Pain relief",
            use_method="Take after meals",
            warning_message="May cause drowsiness",
            dosage_per_time="1 tablet",
            daily_frequency="3 times daily",
            total_days="3 days",
        )

        response = self.control.request_voice_guide(medication_detail, "ko")

        self.assertTrue(response["success"])
        text = response["data"]["voice_guide_text"]
        self.assertIn("Test tablet", text)
        self.assertIn("Take after meals", text)
        self.assertIn("May cause drowsiness", text)
        self.assertLess(text.index("약 이름"), text.index("복용 방법"))
        self.assertLess(text.index("복용 방법"), text.index("주의사항"))

    def test_request_voice_guide_returns_english_labeled_text(self) -> None:
        medication_detail = MedicationDetail(
            item_name="Test tablet",
            efficacy="Pain relief",
            use_method="Take after meals",
            warning_message="May cause drowsiness",
        )

        response = self.control.requestVoiceGuide(medication_detail, "en")

        self.assertTrue(response["success"])
        text = response["data"]["voice_guide_text"]
        self.assertIn("Medication: Test tablet", text)
        self.assertIn("How to take: Take after meals", text)
        self.assertIn("Warning: May cause drowsiness", text)
        self.assertLess(text.index("Medication"), text.index("How to take"))
        self.assertLess(text.index("How to take"), text.index("Warning"))
        self.assertLess(text.index("Warning"), text.index("Effect"))

    def test_invalid_language_is_rejected(self) -> None:
        medication_detail = MedicationDetail(
            item_name="Test tablet",
            efficacy="Pain relief",
            use_method="Take after meals",
            warning_message="May cause drowsiness",
        )

        with self.assertRaises(HTTPException) as context:
            self.control.request_voice_guide(medication_detail, "jp")

        self.assertEqual(context.exception.status_code, 400)


if __name__ == "__main__":
    unittest.main()
