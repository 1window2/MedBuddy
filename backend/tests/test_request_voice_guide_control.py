# File Name: test_request_voice_guide_control.py
# Role: Regression coverage for localized voice-guide content, field ordering, and unsupported
#   languages.

import sys
import unittest
from pathlib import Path

from fastapi import HTTPException

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.request_voice_guide_control import RequestVoiceGuide  # noqa: E402
from entities.medication_detail_entity import MedicationDetail  # noqa: E402


# Class Name: RequestVoiceGuideTest
# Role: Voice-guide tests verifying concise Korean/English narration from medication details.
# Responsibilities:
# - Orders Korean medication, usage, and warning labels while excluding efficacy and
#   dose-schedule fields from narration.
# - Orders English Medication, How to take, and Warning sections without efficacy or
#   additional-guide content.
# - Rejects unsupported voice-guide languages with HTTP 400.
# Attributes:
# - control (RequestVoiceGuide): Use-case control under test, isolated from production state.
class RequestVoiceGuideTest(unittest.TestCase):
    # Function Name: setUp
    # Description:
    # - Creates a voice-guide control for each localization case.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def setUp(self) -> None:
        self.control = RequestVoiceGuide()

    # Function Name: test_request_voice_guide_returns_korean_labeled_text
    # Description:
    # - Orders Korean medication, usage, and warning labels while excluding efficacy and
    #   dose-schedule fields from narration.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

        response = self.control.requestVoiceGuide(medication_detail, "ko")

        self.assertTrue(response["success"])
        text = response["data"]["voice_guide_text"]
        self.assertIn("Test tablet", text)
        self.assertIn("Take after meals", text)
        self.assertIn("May cause drowsiness", text)
        self.assertNotIn("Pain relief", text)
        self.assertNotIn("1 tablet", text)
        self.assertNotIn("3 times daily", text)
        self.assertNotIn("3 days", text)
        self.assertLess(text.index("약 이름"), text.index("복용 방법"))
        self.assertLess(text.index("복용 방법"), text.index("주의사항"))

    # Function Name: test_request_voice_guide_returns_english_labeled_text
    # Description:
    # - Orders English Medication, How to take, and Warning sections without efficacy or
    #   additional-guide content.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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
        self.assertNotIn("Pain relief", text)
        self.assertNotIn("Effect", text)
        self.assertNotIn("Additional guide", text)
        self.assertLess(text.index("Medication"), text.index("How to take"))
        self.assertLess(text.index("How to take"), text.index("Warning"))

    # Function Name: test_invalid_language_is_rejected
    # Description:
    # - Rejects unsupported voice-guide languages with HTTP 400.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_invalid_language_is_rejected(self) -> None:
        medication_detail = MedicationDetail(
            item_name="Test tablet",
            efficacy="Pain relief",
            use_method="Take after meals",
            warning_message="May cause drowsiness",
        )

        with self.assertRaises(HTTPException) as context:
            self.control.requestVoiceGuide(medication_detail, "jp")

        self.assertEqual(context.exception.status_code, 400)


if __name__ == "__main__":
    unittest.main()
