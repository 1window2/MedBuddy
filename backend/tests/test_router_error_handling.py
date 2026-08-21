import os
import sys
import unittest
from pathlib import Path

from fastapi import BackgroundTasks, HTTPException

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from api.router import (  # noqa: E402
    get_saved_medications,
    get_today_medication_schedule,
    identify_loose_pill,
    update_medication_status,
    upload_and_parse_prescription,
)
from boundaries.pill_identification_boundary import (  # noqa: E402
    MAX_PILL_IMAGE_BYTES,
    PillImageQualityError,
    PillVisionResponseError,
    PillVisionUnavailableError,
)
from boundaries.prescription_ocr_boundary import (  # noqa: E402
    PrescriptionPreprocessingCapacityError,
)
from controls.input_prescription_control import (  # noqa: E402
    MAX_PRESCRIPTION_IMAGE_BYTES,
    PrescriptionAnalysisTimeoutError,
)
from controls.authorization_control import AuthorizationControl  # noqa: E402
from entities.authenticated_principal_entity import (  # noqa: E402
    AuthenticatedPrincipal,
)
from schemas.medication import MedicationStatusUpdate  # noqa: E402


_DEVELOPMENT_PRINCIPAL = AuthenticatedPrincipal.development_principal()
_DEVELOPMENT_AUTHORIZATION = AuthorizationControl(db=None)  # type: ignore[arg-type]


class _MissingSavedMedicationControl:
    def requestSavedMedicationInfo(
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
    def requestSavedMedicationInfo(
        self,
        patient_hash: str | None,
    ) -> dict[str, object]:
        raise RuntimeError("sensitive database details")


class _RecordingStatusControl:
    def updateMedicationStatus(
        self,
        medication_id: int,
        medication_status: bool,
        patient_hash: str,
        slot_key: str | None,
    ) -> dict[str, object]:
        return {
            "success": True,
            "data": {"medication_id": medication_id},
        }

    def consumeCompletionEvents(self) -> list[dict[str, str]]:
        return [
            {
                "patient_hash": "local_patient",
                "slot_key": "morning",
            }
        ]


class _RecordingUploadFile:
    filename = "prescription.jpg"
    content_type = "image/jpeg"

    def __init__(self) -> None:
        self.requested_size: int | None = None

    async def read(self, size: int = -1) -> bytes:
        self.requested_size = size
        return b"image"


class _NonImageUploadFile(_RecordingUploadFile):
    filename = "prescription.pdf"
    content_type = "application/pdf"


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


class _CapacityLimitedInputPrescription:
    async def requestPrescriptionImage(
        self,
        image_bytes: bytes,
    ) -> dict[str, object]:
        raise PrescriptionPreprocessingCapacityError(
            "Prescription image preprocessing is temporarily busy."
        )


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
    def test_saved_medication_lookup_preserves_control_http_error(self) -> None:
        with self.assertRaises(HTTPException) as context:
            get_saved_medications(
                patient_hash="patient-missing",
                principal=_DEVELOPMENT_PRINCIPAL,
                authorization=_DEVELOPMENT_AUTHORIZATION,
                check_saved_medication=_MissingSavedMedicationControl(),
            )

        self.assertEqual(context.exception.status_code, 404)

    def test_today_schedule_lookup_preserves_control_http_error(self) -> None:
        with self.assertRaises(HTTPException) as context:
            get_today_medication_schedule(
                patient_hash="patient-missing",
                principal=_DEVELOPMENT_PRINCIPAL,
                authorization=_DEVELOPMENT_AUTHORIZATION,
                check_schedule=_MissingScheduleControl(),
            )

        self.assertEqual(context.exception.status_code, 404)

    def test_saved_medication_lookup_hides_internal_exception_details(
        self,
    ) -> None:
        with self.assertRaises(HTTPException) as context:
            get_saved_medications(
                principal=_DEVELOPMENT_PRINCIPAL,
                authorization=_DEVELOPMENT_AUTHORIZATION,
                check_saved_medication=_FailingSavedMedicationControl(),
            )

        self.assertEqual(context.exception.status_code, 500)
        self.assertNotIn("sensitive", str(context.exception.detail))

    def test_medication_status_response_queues_caregiver_push_in_background(
        self,
    ) -> None:
        background_tasks = BackgroundTasks()

        response = update_medication_status(
            medication_id=7,
            request=MedicationStatusUpdate(
                medication_status=True,
                slot_key="morning",
            ),
            background_tasks=background_tasks,
            principal=_DEVELOPMENT_PRINCIPAL,
            authorization=_DEVELOPMENT_AUTHORIZATION,
            check_schedule=_RecordingStatusControl(),  # type: ignore[arg-type]
        )

        self.assertTrue(response["success"])
        self.assertEqual(len(background_tasks.tasks), 1)

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
        self.assertNotIn(upload_file.content_type, "\n".join(captured_logs.output))

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

    async def test_prescription_upload_rejects_non_image_content_type_early(
        self,
    ) -> None:
        with self.assertRaises(HTTPException) as context:
            await upload_and_parse_prescription(
                file=_NonImageUploadFile(),
                input_prescription=_RecordingInputPrescription(),
            )

        self.assertEqual(context.exception.status_code, 415)

    async def test_prescription_upload_maps_capacity_to_service_unavailable(
        self,
    ) -> None:
        with self.assertRaises(HTTPException) as context:
            await upload_and_parse_prescription(
                file=_RecordingUploadFile(),
                input_prescription=_CapacityLimitedInputPrescription(),
            )

        self.assertEqual(context.exception.status_code, 503)
        self.assertEqual(context.exception.headers, {"Retry-After": "1"})

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

    async def test_pill_upload_maps_invalid_upstream_contract_to_bad_gateway(
        self,
    ) -> None:
        with self.assertRaises(HTTPException) as context:
            await identify_loose_pill(
                front=_RecordingUploadFile(),
                back=None,
                identify_pill=_RecordingPillIdentificationControl(
                    PillVisionResponseError("private malformed payload")
                ),
            )

        self.assertEqual(context.exception.status_code, 502)
        self.assertNotIn("private", str(context.exception.detail))


if __name__ == "__main__":
    unittest.main()
