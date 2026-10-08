# File Name: test_router_error_handling.py
# Role: Regression coverage for router error preservation, sanitized internal failures, upload
#   bounds, and deferred caregiver alerts.
import os
import sys
import unittest
from datetime import date, timedelta
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
    identify_multiple_loose_pills,
    update_medication_status,
)
from boundaries.pill_identification_boundary import (  # noqa: E402
    MAX_PILL_IMAGE_BYTES,
    PillCatalogUnavailableError,
    PillImageQualityError,
    PillVisionResponseError,
    PillVisionUnavailableError,
)
from controls.authorization_control import AuthorizationControl  # noqa: E402
from controls.check_schedule_control import CheckSchedule  # noqa: E402
from core.application_clock import application_today  # noqa: E402
from entities.authenticated_principal_entity import (  # noqa: E402
    AuthenticatedPrincipal,
)
from schemas.medication import MedicationStatusUpdate  # noqa: E402
from support.db import make_engine, make_session, seed_medication  # noqa: E402


_DEVELOPMENT_PRINCIPAL = AuthenticatedPrincipal.development_principal()
_DEVELOPMENT_AUTHORIZATION = AuthorizationControl(db=None)  # type: ignore[arg-type]


# Class Name: _MissingSavedMedicationControl
# Role: Saved-medication control double that raises an expected not-found HTTP error.
# Responsibilities:
# - Raises HTTP 404 for missing patient medications to test router status preservation.
class _MissingSavedMedicationControl:
    # Function Name: requestSavedMedicationInfo
    # Description:
    # - Raises HTTP 404 for missing patient medications to test router status preservation.
    # Parameters:
    # - patient_hash (str | None): Patient owner identifying the medication or linked-data
    #   scope.
    # Returns:
    # - No normal result; raises the configured failure described above.
    def requestSavedMedicationInfo(
        self,
        patient_hash: str | None,
    ) -> dict[str, object]:
        raise HTTPException(status_code=404, detail="Patient medication was not found.")


# Class Name: _MissingScheduleControl
# Role: Schedule control double that raises an expected not-found HTTP error.
# Responsibilities:
# - Raises HTTP 404 for a missing patient schedule to test router status preservation.
class _MissingScheduleControl:
    # Function Name: requestTodayMedicationSchedule
    # Description:
    # - Raises HTTP 404 for a missing patient schedule to test router status preservation.
    # Parameters:
    # - patient_hash (str | None): Patient owner identifying the medication or linked-data
    #   scope.
    # Returns:
    # - No normal result; raises the configured failure described above.
    def requestTodayMedicationSchedule(
        self,
        patient_hash: str | None,
    ) -> dict[str, object]:
        raise HTTPException(status_code=404, detail="Patient schedule was not found.")


# Class Name: _FailingSavedMedicationControl
# Role: Saved-medication control double exposing a private internal failure for sanitization
#   tests.
# Responsibilities:
# - Raises a runtime error with sensitive database text that the router must not expose.
class _FailingSavedMedicationControl:
    # Function Name: requestSavedMedicationInfo
    # Description:
    # - Raises a runtime error with sensitive database text that the router must not expose.
    # Parameters:
    # - patient_hash (str | None): Patient owner identifying the medication or linked-data
    #   scope.
    # Returns:
    # - No normal result; raises the configured failure described above.
    def requestSavedMedicationInfo(
        self,
        patient_hash: str | None,
    ) -> dict[str, object]:
        raise RuntimeError("sensitive database details")


# 클래스명: _RecordingRequestSession
# 역할: 라우터가 요청 세션의 트랜잭션을 끝냈는지 기록하는 세션 대역이다.
# 속성:
# - rollback_count (int): rollback() 호출 횟수.
class _RecordingRequestSession:
    # 함수이름: __init__
    # 함수역할:
    # - 호출 횟수를 0으로 준비한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def __init__(self) -> None:
        self.rollback_count = 0

    # 함수이름: rollback
    # 함수역할:
    # - 트랜잭션 종료 요청을 한 건 기록한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def rollback(self) -> None:
        self.rollback_count += 1


# 클래스명: _RecordingStatusControl
# 역할: 복약 상태 갱신 성공과 전달할 완료 이벤트를 제공하는 라우터 테스트용 control이다.
# 주요 책임:
# - 지정 약 ID를 담은 성공 응답을 제공하여 백그라운드 알림 예약을 검증하게 한다.
# - 로컬 환자의 아침 완료와 outbox ID가 포함된 단일 이벤트를 제공한다.
# 속성:
# - db (_RecordingRequestSession): 라우터가 트랜잭션을 끝내는 요청 세션 대역.
# - expected_schedule_dates (list[date | None]): 라우터가 전달한 기대 복약 날짜 목록.
class _RecordingStatusControl:
    # 함수이름: __init__
    # 함수역할:
    # - 요청 세션 대역과 빈 날짜 기록을 준비한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def __init__(self) -> None:
        self.db = _RecordingRequestSession()
        self.expected_schedule_dates: list[date | None] = []

    # 함수이름: updateMedicationStatus
    # 함수역할:
    # - 지정 약 ID를 담은 성공 응답을 제공하여 백그라운드 알림 예약을 검증하게 한다.
    # 매개변수:
    # - medication_id (int): 완료 또는 미완료로 변경할 저장 약 ID.
    # - medication_status (bool): 요청한 복약 완료 여부.
    # - patient_hash (str): 약 또는 연동 데이터 범위를 식별할 환자 소유자 해시.
    # - slot_key (str | None): 복약 시간대 키 또는 약 전체 상태 변경을 뜻하는 None.
    # - expected_schedule_date (date | None): 요청이 가리키는 복약 날짜.
    # 반환값:
    # - dict[str, object]: 요청한 약 ID를 포함한 성공 응답.
    def updateMedicationStatus(
        self,
        medication_id: int,
        medication_status: bool,
        patient_hash: str,
        slot_key: str | None,
        *,
        expected_schedule_date: date | None = None,
    ) -> dict[str, object]:
        self.expected_schedule_dates.append(expected_schedule_date)
        return {
            "success": True,
            "data": {"medication_id": medication_id},
        }

    # 함수이름: consumeCompletionEvents
    # 함수역할:
    # - 로컬 환자의 아침 완료와 outbox ID가 포함된 단일 이벤트를 제공한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - list[dict[str, str | int]]: outbox_id=1인 로컬 환자의 아침 완료 이벤트 한 건.
    def consumeCompletionEvents(self) -> list[dict[str, str | int]]:
        return [
            {
                "patient_hash": "local_patient",
                "slot_key": "morning",
                "outbox_id": 1,
            }
        ]


# Class Name: _RecordingUploadFile
# Role: Upload-file double recording the requested read bound while returning fixed image bytes.
# Responsibilities:
# - Records the read limit and returns fixed image bytes without accessing a real upload.
# Attributes:
# - filename (str): Synthetic upload filename exposed to the router.
# - content_type (str): Upload MIME type exposed to the router.
# - requested_size (int | None): Last byte limit requested from the upload reader.
class _RecordingUploadFile:
    filename = "prescription.jpg"
    content_type = "image/jpeg"

    # Function Name: __init__
    # Description:
    # - Marks the requested upload-read size absent until the router reads the file.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.requested_size: int | None = None

    # Function Name: read
    # Description:
    # - Records the read limit and returns fixed image bytes without accessing a real
    #   upload.
    # Parameters:
    # - size (int): Maximum upload bytes requested by the router.
    # Returns:
    # - bytes: b'image', independent of the requested read limit.
    async def read(self, size: int = -1) -> bytes:
        self.requested_size = size
        return b"image"


# Class Name: _RecordingPillIdentificationControl
# Role: Identification control double injecting a selected domain error for HTTP error mapping.
# Responsibilities:
# - Raises the configured identification failure and fails the test if incorrectly used for a
#   success path.
# Attributes:
# - error (Exception | None): Domain exception injected into the next control call.
class _RecordingPillIdentificationControl:
    # Function Name: __init__
    # Description:
    # - Stores the domain error that the router-facing identification call must raise.
    # Parameters:
    # - error (Exception | None): Domain exception to inject into the router call.
    # Returns:
    # - None.
    def __init__(self, error: Exception | None = None) -> None:
        self.error = error

    # Function Name: requestPillIdentification
    # Description:
    # - Raises the configured identification failure and fails the test if incorrectly used
    #   for a success path.
    # Parameters:
    # - _front_image (bytes): Front-side pill photograph bytes. Unused by this double.
    # - _back_image (bytes | None): Optional back-side pill photograph bytes. Unused by this
    #   double.
    # Returns:
    # - No normal result; raises the configured failure described above.
    async def requestPillIdentification(
        self,
        _front_image: bytes,
        _back_image: bytes | None = None,
    ) -> object:
        if self.error is not None:
            raise self.error
        raise AssertionError("This fake is only used for error mapping.")

    # Function Name: requestMultiplePillIdentification
    # Description:
    # - Raises the configured identification failure for the multiple-pill route and fails
    #   the test if incorrectly used for a success path.
    # Parameters:
    # - _image (bytes): Multi-pill photograph bytes. Unused by this double.
    # Returns:
    # - No normal result; raises the configured failure described above.
    async def requestMultiplePillIdentification(self, _image: bytes) -> object:
        if self.error is not None:
            raise self.error
        raise AssertionError("This fake is only used for error mapping.")


# 클래스명: RouterErrorHandlingTest
# 역할: control 오류의 HTTP 변환, 민감정보 숨김, 업로드 제한 및 알림 예약을 검증하는 비동기 테스트 모음이다.
# 주요 책임:
# - 복약 상태 성공 응답에서 보호자 푸시를 즉시 실행하지 않고 백그라운드 작업 한 건으로 예약하는지 검증한다.
class RouterErrorHandlingTest(unittest.IsolatedAsyncioTestCase):
    # Function Name: test_saved_medication_lookup_preserves_control_http_error
    # Description:
    # - Preserves the control's HTTP 404 when saved-medication lookup fails.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_saved_medication_lookup_preserves_control_http_error(self) -> None:
        with self.assertRaises(HTTPException) as context:
            get_saved_medications(
                patient_hash="patient-missing",
                principal=_DEVELOPMENT_PRINCIPAL,
                authorization=_DEVELOPMENT_AUTHORIZATION,
                check_saved_medication=_MissingSavedMedicationControl(),
            )

        self.assertEqual(context.exception.status_code, 404)

    # Function Name: test_today_schedule_lookup_preserves_control_http_error
    # Description:
    # - Preserves the control's HTTP 404 when today's schedule is missing.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_today_schedule_lookup_preserves_control_http_error(self) -> None:
        with self.assertRaises(HTTPException) as context:
            get_today_medication_schedule(
                patient_hash="patient-missing",
                principal=_DEVELOPMENT_PRINCIPAL,
                authorization=_DEVELOPMENT_AUTHORIZATION,
                check_schedule=_MissingScheduleControl(),
            )

        self.assertEqual(context.exception.status_code, 404)

    # Function Name: test_saved_medication_lookup_hides_internal_exception_details
    # Description:
    # - Maps unexpected saved-medication failures to HTTP 500 without exposing sensitive
    #   database details.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

    # 함수이름: test_medication_status_response_queues_caregiver_push_in_background
    # 함수역할:
    # - 복약 상태 성공 응답에서 보호자 푸시를 즉시 실행하지 않고 백그라운드 작업 한 건으로 예약하는지 검증한다.
    # - 예약한 뒤 요청 세션의 트랜잭션을 끝내고, 요청의 기대 복약 날짜를 control에 전달하는지도 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_medication_status_response_queues_caregiver_push_in_background(
        self,
    ) -> None:
        background_tasks = BackgroundTasks()
        control = _RecordingStatusControl()
        expected_date = date(2026, 10, 8)

        response = update_medication_status(
            medication_id=7,
            request=MedicationStatusUpdate(
                medication_status=True,
                slot_key="morning",
                expected_schedule_date=expected_date,
            ),
            background_tasks=background_tasks,
            principal=_DEVELOPMENT_PRINCIPAL,
            authorization=_DEVELOPMENT_AUTHORIZATION,
            check_schedule=control,  # type: ignore[arg-type]
        )

        self.assertTrue(response["success"])
        self.assertEqual(len(background_tasks.tasks), 1)
        self.assertEqual(control.db.rollback_count, 1)
        self.assertEqual(control.expected_schedule_dates, [expected_date])

    # Function Name: test_medication_status_rejects_a_reminder_for_another_day
    # Description:
    # - A single-medication completion whose expected schedule date is not today is refused
    #   with HTTP 409 by the real schedule control and records nothing, while the same
    #   request dated today is applied.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_medication_status_rejects_a_reminder_for_another_day(self) -> None:
        engine = make_engine()
        self.addCleanup(engine.dispose)
        db = make_session(engine)
        self.addCleanup(db.close)
        medication = seed_medication(
            db,
            patient_hash=_DEVELOPMENT_PRINCIPAL.user_hash,
            daily_frequency="1",
            schedule_slot_keys='["morning"]',
        )
        today = application_today()

        # Function Name: complete_morning
        # Description:
        # - Sends the morning completion of the seeded medication for one expected date.
        # Parameters:
        # - expected_schedule_date (date): Day the reminder action was issued for.
        # Returns:
        # - dict[str, object]: Router response for an accepted request.
        def complete_morning(expected_schedule_date: date) -> dict[str, object]:
            return update_medication_status(
                medication_id=int(medication.id),
                request=MedicationStatusUpdate(
                    medication_status=True,
                    slot_key="morning",
                    expected_schedule_date=expected_schedule_date,
                ),
                background_tasks=BackgroundTasks(),
                principal=_DEVELOPMENT_PRINCIPAL,
                authorization=_DEVELOPMENT_AUTHORIZATION,
                check_schedule=CheckSchedule(db),
            )

        with self.assertRaises(HTTPException) as context:
            complete_morning(today - timedelta(days=1))

        self.assertEqual(context.exception.status_code, 409)
        schedule = CheckSchedule(db).requestTodayMedicationSchedule(
            _DEVELOPMENT_PRINCIPAL.user_hash
        )["data"][0]
        self.assertFalse(schedule["slot_statuses"]["morning"])

        accepted = complete_morning(today)

        self.assertTrue(accepted["data"]["slot_statuses"]["morning"])

    # Function Name: test_pill_upload_reads_only_the_validated_size_window
    # Description:
    # - Reads at most the image-size limit plus one byte and maps image-quality failure to
    #   HTTP 422 with a retake instruction.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

    # Function Name: test_pill_upload_maps_visual_outage_to_service_unavailable
    # Description:
    # - Maps vision unavailability to HTTP 503 without leaking private upstream details.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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
        self.assertEqual(context.exception.headers, {"Retry-After": "5"})

    # Function Name: test_pill_outages_tell_the_client_when_to_retry
    # Description:
    # - Catalog and vision outages on both pill-identification routes keep HTTP 503 and
    #   carry Retry-After: 5 like the other retryable 503 responses.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def test_pill_outages_tell_the_client_when_to_retry(self) -> None:
        outages = (
            PillCatalogUnavailableError("The pill catalog is temporarily unavailable."),
            PillVisionUnavailableError("The pill visual analysis is unavailable."),
        )
        for outage in outages:
            control = _RecordingPillIdentificationControl(outage)
            for route_name, call in (
                (
                    "single",
                    lambda: identify_loose_pill(
                        front=_RecordingUploadFile(),
                        back=None,
                        identify_pill=control,
                    ),
                ),
                (
                    "multiple",
                    lambda: identify_multiple_loose_pills(
                        image=_RecordingUploadFile(),
                        identify_pill=control,
                    ),
                ),
            ):
                with self.subTest(outage=type(outage).__name__, route=route_name):
                    with self.assertRaises(HTTPException) as context:
                        await call()

                    self.assertEqual(context.exception.status_code, 503)
                    self.assertEqual(context.exception.detail, str(outage))
                    self.assertEqual(
                        context.exception.headers,
                        {"Retry-After": "5"},
                    )

    # Function Name: test_pill_upload_maps_invalid_upstream_contract_to_bad_gateway
    # Description:
    # - Maps malformed upstream vision responses to HTTP 502 without leaking private
    #   contract details.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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
