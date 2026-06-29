import os
import sys
import unittest
from pathlib import Path

from fastapi import HTTPException

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from api.router import get_saved_medications, get_today_medication_schedule  # noqa: E402


class _MissingGuardianSavedMedicationControl:
    def request_saved_medication_info(
        self,
        patient_hash: str,
        user_hash: str | None,
        role: str,
    ) -> dict[str, object]:
        raise HTTPException(status_code=404, detail="Linked patient was not found.")


class _MissingGuardianScheduleControl:
    def request_today_medication_schedule(
        self,
        patient_hash: str,
        user_hash: str | None,
        role: str,
    ) -> dict[str, object]:
        raise HTTPException(status_code=404, detail="Linked patient was not found.")


class RouterErrorHandlingTest(unittest.IsolatedAsyncioTestCase):
    async def test_saved_medication_lookup_preserves_control_http_error(self) -> None:
        with self.assertRaises(HTTPException) as context:
            await get_saved_medications(
                user_hash="guardian-missing",
                role="guardian",
                check_saved_medication=_MissingGuardianSavedMedicationControl(),
            )

        self.assertEqual(context.exception.status_code, 404)

    async def test_today_schedule_lookup_preserves_control_http_error(self) -> None:
        with self.assertRaises(HTTPException) as context:
            await get_today_medication_schedule(
                user_hash="guardian-missing",
                role="guardian",
                check_schedule=_MissingGuardianScheduleControl(),
            )

        self.assertEqual(context.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
