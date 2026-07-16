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
    identify_loose_pill,
    upload_and_parse_prescription,
)
from boundaries.pill_identification_boundary import (  # noqa: E402
    MAX_PILL_IMAGE_BYTES,
    PillImageQualityError,
    PillVisionUnavailableError,
)
from controls.input_prescription_control import (  # noqa: E402
    MAX_PRESCRIPTION_IMAGE_BYTES,
    PrescriptionAnalysisTimeoutError,
)


class _MissingSavedMedicationControl:
    async def requestSavedMedicationInfoWithImages(
        self,
        patient_hash: str | None,
    ) -> dict[str, object]:
        raise HTTPException(status_code=404, detail="Patient medication was not found.")


class _MissingScheduleControl:
    def requestTodayMedicationSchedule(
        self,
        patient_hash: str | None,
    ) -> dict[str, object]:
        raise HTTPException(status_code=404, detail="Patient schedule was not found.")


class _FailingSavedMedicationControl:
    async def requestSavedMedicationInfoWithImages(
        self,
        patient_hash: str | None,
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


class _RecordingInputPrescription:
    async def requestPrescriptionImage(
        self,
        image_bytes: bytes,
    ) -> dict[str, object]:
        return {"received_bytes": len(image_bytes)}


class _TimedOutInputPrescription:
    async def requestPrescriptionImage(
        self,
        image_bytes: bytes,
    ) -> dict[str, object]:
        raise PrescriptionAnalysisTimeoutError("OCR request timed out.")


class _RecordingPillIdentificationControl:
    def __init__(self, error: Exception | None = None) -> None:
        self.error = error

    async def requestPillIdentification(
        self,
        _front_image: bytes,
        _back_image: bytes | None = None,
    ) -> object:
        if self.error is not None:
            raise self.error
        raise AssertionError("This fake is only used for error mapping.")


class RouterErrorHandlingTest(unittest.IsolatedAsyncioTestCase):
    async def test_saved_medication_lookup_preserves_control_http_error(self) -> None:
        with self.assertRaises(HTTPException) as context:
            await get_saved_medications(
                patient_hash="patient-missing",
                check_saved_medication=_MissingSavedMedicationControl(),
            )

        self.assertEqual(context.exception.status_code, 404)

    def test_today_schedule_lookup_preserves_control_http_error(self) -> None:
        with self.assertRaises(HTTPException) as context:
            get_today_medication_schedule(
                patient_hash="patient-missing",
                check_schedule=_MissingScheduleControl(),
            )

        self.assertEqual(context.exception.status_code, 404)

    async def test_saved_medication_lookup_hides_internal_exception_details(
        self,
    ) -> None:
        with self.assertRaises(HTTPException) as context:
            await get_saved_medications(
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
                input_prescription=_RecordingInputPrescription(),
            )

        self.assertEqual(
            upload_file.requested_size,
            MAX_PRESCRIPTION_IMAGE_BYTES + 1,
        )
        self.assertEqual(response["received_bytes"], 5)
        self.assertNotIn(upload_file.filename, "\n".join(captured_logs.output))

    async def test_prescription_upload_maps_ocr_timeout_to_gateway_timeout(
        self,
    ) -> None:
        with self.assertRaises(HTTPException) as context:
            await upload_and_parse_prescription(
                file=_RecordingUploadFile(),
                input_prescription=_TimedOutInputPrescription(),
            )

        self.assertEqual(context.exception.status_code, 504)
        self.assertEqual(context.exception.detail, "OCR request timed out.")

    async def test_pill_upload_reads_only_the_validated_size_window(self) -> None:
        upload_file = _RecordingUploadFile()

        with self.assertRaises(HTTPException) as context:
            await identify_loose_pill(
                front=upload_file,
                back=None,
                identify_pill=_RecordingPillIdentificationControl(
                    PillImageQualityError("Retake the pill photo.")
                ),
            )

        self.assertEqual(upload_file.requested_size, MAX_PILL_IMAGE_BYTES + 1)
        self.assertEqual(context.exception.status_code, 422)
        self.assertEqual(context.exception.detail, "Retake the pill photo.")

    async def test_pill_upload_maps_visual_outage_to_service_unavailable(
        self,
    ) -> None:
        with self.assertRaises(HTTPException) as context:
            await identify_loose_pill(
                front=_RecordingUploadFile(),
                back=None,
                identify_pill=_RecordingPillIdentificationControl(
                    PillVisionUnavailableError(
                        "The pill visual analysis service is temporarily unavailable."
                    )
                ),
            )

        self.assertEqual(context.exception.status_code, 503)
        self.assertNotIn("private", str(context.exception.detail))


if __name__ == "__main__":
    unittest.main()
