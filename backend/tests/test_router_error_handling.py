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

from api.router import (  # noqa: E402
    get_saved_medications,
    get_today_medication_schedule,
    upload_and_parse_prescription,
)
from controls.input_prescription_control import (  # noqa: E402
    MAX_PRESCRIPTION_IMAGE_BYTES,
)


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


class _FailingSavedMedicationControl:
    def request_saved_medication_info(
        self,
        patient_hash: str | None,
        user_hash: str | None,
        role: str,
    ) -> dict[str, object]:
        raise RuntimeError("sensitive database details")


class _RecordingUploadFile:
    filename = "prescription.jpg"
    content_type = "image/jpeg"

    def __init__(self) -> None:
        self.requested_size: int | None = None

    async def read(self, size: int = -1) -> bytes:
        self.requested_size = size
        return b"image"


class _RecordingPrescriptionAnalysisControl:
    async def request_prescription_image(
        self,
        image_bytes: bytes,
    ) -> dict[str, object]:
        return {"received_bytes": len(image_bytes)}


class RouterErrorHandlingTest(unittest.IsolatedAsyncioTestCase):
    def test_saved_medication_lookup_preserves_control_http_error(self) -> None:
        with self.assertRaises(HTTPException) as context:
            get_saved_medications(
                user_hash="guardian-missing",
                role="guardian",
                check_saved_medication=_MissingGuardianSavedMedicationControl(),
            )

        self.assertEqual(context.exception.status_code, 404)

    def test_today_schedule_lookup_preserves_control_http_error(self) -> None:
        with self.assertRaises(HTTPException) as context:
            get_today_medication_schedule(
                user_hash="guardian-missing",
                role="guardian",
                check_schedule=_MissingGuardianScheduleControl(),
            )

        self.assertEqual(context.exception.status_code, 404)

    def test_saved_medication_lookup_hides_internal_exception_details(
        self,
    ) -> None:
        with self.assertRaises(HTTPException) as context:
            get_saved_medications(
                check_saved_medication=_FailingSavedMedicationControl(),
            )

        self.assertEqual(context.exception.status_code, 500)
        self.assertNotIn("sensitive", str(context.exception.detail))

    async def test_prescription_upload_reads_only_the_validated_size_window(
        self,
    ) -> None:
        upload_file = _RecordingUploadFile()

        with self.assertLogs("api.router", level="INFO") as captured_logs:
            response = await upload_and_parse_prescription(
                file=upload_file,
                prescription_analysis_control=_RecordingPrescriptionAnalysisControl(),
            )

        self.assertEqual(
            upload_file.requested_size,
            MAX_PRESCRIPTION_IMAGE_BYTES + 1,
        )
        self.assertEqual(response["received_bytes"], 5)
        self.assertNotIn(upload_file.filename, "\n".join(captured_logs.output))


if __name__ == "__main__":
    unittest.main()
