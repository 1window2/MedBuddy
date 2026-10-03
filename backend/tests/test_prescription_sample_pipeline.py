# File Name: test_prescription_sample_pipeline.py
# Role: Regression coverage for a synthetic prescription flowing through name correction,
#   saving, schedules, progress, and alarms.
import asyncio
import json
import os
import sys
import unittest
from datetime import date
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from controls.check_saved_medication_control import CheckSavedMedication  # noqa: E402
from controls.check_schedule_control import CheckSchedule  # noqa: E402
from controls.check_today_medication_info_control import (  # noqa: E402
    CheckTodayMedicationInfo,
)
from controls.input_prescription_control import InputPrescription  # noqa: E402
from controls.set_notification_control import SetNotification  # noqa: E402
from core.database import Base  # noqa: E402
from entities.medication_alarm_entity import ensure_medication_alarm_schema  # noqa: E402
from entities.medication_completion_entity import (  # noqa: E402
    ensure_medication_completion_schema,
)
from entities.medication_detail_entity import _DrugBasicInfo  # noqa: E402
from entities.saved_medication_entity import ensure_saved_medication_schema  # noqa: E402
from schemas.medication import SavedMedicationCreate  # noqa: E402


ANIPEN = "\uc560\ub2c8\ud39c\uc815400\ubc00\ub9ac\uadf8\ub7a8(\ub371\uc2dc\ubd80\ud504\ub85c\ud39c)"
ANIPEN_OCR_VARIANT = "\uc5d0\ub2c8\ud39c\uc815400mg"
PAMOTER = "\ud30c\ubaa8\ud2f0\uc81520\ubc00\ub9ac\uadf8\ub7a8(\ud30c\ubaa8\ud2f0\ub518)"
PAMOTER_OCR_VARIANT = "\ud30c\ubaa8\ud2f0\uc81520mg"
PROCOUGH = "\ud504\ub85c\ucf54\ud478\uc815(\ub808\ubcf4\ub4dc\ub85c\ud504\ub85c\ud53c\uc9c4)"
PROCOUGH_OCR_NAME = "\ud504\ub85c\ucf54\ud478\uc815"
CELLEON = "\uc140\ub9ac\uc628\uc81510\ubc00\ub9ac\uadf8\ub7a8(\ubca0\ud3ec\ud0c0\uc2a4\ud2f4\ubca0\uc2e4\uc0b0\uc5fc)"
CELLEON_OCR_NAME = "\uc140\ub9ac\uc628\uc81510mg"
SUDAFED = "\uc288\ub2e4\ud398\ub4dc\uc815(\uc288\ub3c4\uc5d0\ud398\ub4dc\ub9b0\uc5fc\uc0b0\uc5fc)"
SUDAFED_OCR_NAME = "\uc288\ub2e4\ud398\ub4dc\uc815"
SMILE_PHARMACY = "\uc2a4\ub9c8\uc77c\uc57d\uad6d"


# Class Name: _FakeGeminiResponse
# Role: Gemini response double exposing configured text for the synthetic prescription pipeline.
# Responsibilities:
# - Gemini response double exposing configured text for the synthetic prescription pipeline.
# Attributes:
# - text (str): Text payload exposed by the Gemini-compatible response.
class _FakeGeminiResponse:
    # Function Name: __init__
    # Description:
    # - Stores the response text supplied to the synthetic analysis client.
    # Parameters:
    # - text (str): Text captured by the response or prescription-analysis double.
    # Returns:
    # - None.
    def __init__(self, text: str) -> None:
        self.text = text


# Class Name: _FakeGeminiModels
# Role: Gemini models double counting fallback requests and returning a deterministic text
#   response.
# Responsibilities:
# - Counts Gemini fallback calls and returns the configured response object.
# Attributes:
# - response_text (str): Deterministic AI text response returned by the double.
# - call_count (int): Number of external-analysis calls observed.
class _FakeGeminiModels:
    # Function Name: __init__
    # Description:
    # - Stores the fallback response and initializes its request count.
    # Parameters:
    # - response_text (str): Deterministic text/JSON output returned by the AI double.
    # Returns:
    # - None.
    def __init__(self, response_text: str) -> None:
        self.response_text = response_text
        self.call_count = 0

    # Function Name: generate_content
    # Description:
    # - Counts Gemini fallback calls and returns the configured response object.
    # Parameters:
    # - **_kwargs (object): Keyword arguments accepted by the substituted service interface.
    # Returns:
    # - _FakeGeminiResponse: Gemini-compatible response carrying the configured analysis
    #   JSON.
    async def generate_content(self, **_kwargs: object) -> _FakeGeminiResponse:
        self.call_count += 1
        return _FakeGeminiResponse(self.response_text)


# Class Name: _FakeGeminiAio
# Role: Asynchronous Gemini namespace double sharing the recording models object.
# Responsibilities:
# - Asynchronous Gemini namespace double sharing the recording models object.
# Attributes:
# - models (_FakeGeminiModels): Recording Gemini-compatible model interface.
class _FakeGeminiAio:
    # Function Name: __init__
    # Description:
    # - Exposes the supplied models object through the asynchronous client namespace.
    # Parameters:
    # - models (_FakeGeminiModels): Injected Gemini-compatible model implementation.
    # Returns:
    # - None.
    def __init__(self, models: _FakeGeminiModels) -> None:
        self.models = models


# Class Name: _FakeGeminiClient
# Role: Gemini client double supporting both sync and async model access in the sample pipeline.
# Responsibilities:
# - Gemini client double supporting both sync and async model access in the sample pipeline.
# Attributes:
# - models (_FakeGeminiModels): Recording Gemini-compatible model interface.
# - aio (_FakeGeminiAio): Gemini-compatible asynchronous namespace or owned async client.
class _FakeGeminiClient:
    # Function Name: __init__
    # Description:
    # - Creates response-backed models and attaches their asynchronous namespace.
    # Parameters:
    # - response_text (str): Deterministic text/JSON output returned by the AI double.
    # Returns:
    # - None.
    def __init__(self, response_text: str) -> None:
        self.models = _FakeGeminiModels(response_text)
        self.aio = _FakeGeminiAio(self.models)


# Class Name: _FakePrescriptionTextBoundary
# Role: Prescription text boundary double recording masked input and supplying sample analysis
#   JSON.
# Responsibilities:
# - Records the masked sample prescription text and returns its configured analysis response.
# Attributes:
# - response_text (str): Deterministic AI text response returned by the double.
# - received_text (str): Prescription text captured by the analysis double.
class _FakePrescriptionTextBoundary:
    # Function Name: __init__
    # Description:
    # - Stores the sample response and initializes empty captured text.
    # Parameters:
    # - response_text (str): Deterministic text/JSON output returned by the AI double.
    # Returns:
    # - None.
    def __init__(self, response_text: str) -> None:
        self.response_text = response_text
        self.received_text = ""

    # Function Name: extractPrescriptionTextData
    # Description:
    # - Records the masked sample prescription text and returns its configured analysis
    #   response.
    # Parameters:
    # - masked_text (str): De-identified prescription text allowed across the AI boundary.
    # Returns:
    # - str: Configured prescription analysis JSON text.
    async def extractPrescriptionTextData(self, masked_text: str) -> str:
        self.received_text = masked_text
        return self.response_text


# Class Name: PrescriptionSamplePipelineTest
# Role: End-to-end synthetic prescription tests connecting local name verification to schedules
#   and notification settings.
# Responsibilities:
# - Corrects five sample names locally without Gemini, preserves thirteen dose slots, updates
#   completion progress, and saves a custom morning alarm.
# - Builds today's five-medication OCR JSON with vowel, strength-unit, and prefix variants for
#   deterministic correction tests.
# - Returns an initially incomplete morning/lunch/evening status map for a three-dose
#   medication.
# Attributes:
# - engine (Engine): Isolated in-memory SQLite engine.
# - db (Session): SQLAlchemy session holding only this test's database state.
# - patient_hash (str): Owner of the synthetic sample prescription.
class PrescriptionSamplePipelineTest(unittest.TestCase):
    # Function Name: setUp
    # Description:
    # - Creates current medication, completion, and alarm schemas and seeds five
    #   authoritative sample product names.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=self.engine)
        ensure_saved_medication_schema(self.engine)
        ensure_medication_completion_schema(self.engine)
        ensure_medication_alarm_schema(self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.patient_hash = "sample-patient"
        self._seed_catalog_names(ANIPEN, PAMOTER, PROCOUGH, CELLEON, SUDAFED)

    # Function Name: tearDown
    # Description:
    # - Closes the sample-pipeline database session and disposes its engine.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # Function Name: test_sample_prescription_flows_into_today_schedule_and_notifications
    # Description:
    # - Corrects five sample names locally without Gemini, preserves thirteen dose slots,
    #   updates completion progress, and saves a custom morning alarm.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_sample_prescription_flows_into_today_schedule_and_notifications(
        self,
    ) -> None:
        text_boundary = _FakePrescriptionTextBoundary(self._sample_ocr_response())
        ai_client = _FakeGeminiClient(json.dumps({"corrections": []}))
        prescription_control = InputPrescription(
            client=ai_client,
            db=self.db,
            ocr_service_boundary=text_boundary,
        )

        analysis_payload = asyncio.run(
            prescription_control.requestPrescriptionText(
                "masked sample prescription text"
            )
        )

        self.assertEqual(
            text_boundary.received_text,
            "masked sample prescription text",
        )
        self.assertEqual(analysis_payload["prescription_date"], date.today().isoformat())
        self.assertEqual(analysis_payload["raw_medication_count"], 5)
        self.assertEqual(analysis_payload["parsed_medication_count"], 5)
        self.assertEqual(analysis_payload["skipped_medication_count"], 0)
        medications = analysis_payload["medications"]
        self.assertEqual(
            [medication["drug_name"] for medication in medications],
            [ANIPEN, PAMOTER, PROCOUGH, CELLEON, SUDAFED],
        )
        self.assertEqual(medications[0]["raw_drug_name"], ANIPEN_OCR_VARIANT)
        self.assertEqual(
            medications[0]["name_correction_source"],
            "local_catalog_ocr_vowel_variant",
        )
        self.assertEqual(medications[1]["raw_drug_name"], PAMOTER_OCR_VARIANT)
        self.assertEqual(
            medications[1]["name_correction_source"],
            "local_catalog_strength_unit_variant",
        )
        self.assertEqual(medications[2]["raw_drug_name"], PROCOUGH_OCR_NAME)
        self.assertEqual(
            medications[2]["name_correction_source"],
            "local_catalog_prefix",
        )
        self.assertEqual(medications[3]["raw_drug_name"], CELLEON_OCR_NAME)
        self.assertEqual(
            medications[3]["name_correction_source"],
            "local_catalog_strength_unit_variant",
        )
        self.assertEqual(medications[4]["raw_drug_name"], SUDAFED_OCR_NAME)
        self.assertEqual(
            medications[4]["name_correction_source"],
            "local_catalog_prefix",
        )
        self.assertEqual(ai_client.models.call_count, 0)

        save_control = CheckSavedMedication(self.db)
        saved_ids = [
            save_control.saveMedicationDetail(
                SavedMedicationCreate(
                    patient_hash=self.patient_hash,
                    prescription_date=date.fromisoformat(
                        str(analysis_payload["prescription_date"])
                    ),
                    item_name=str(medication["drug_name"]),
                    efficacy="sample efficacy",
                    use_method="sample use",
                    warning_message="sample warning",
                    dosage_per_time=str(medication["dosage_per_time"]),
                    daily_frequency=str(medication["daily_frequency"]),
                    total_days=str(medication["total_days"]),
                )
            )["id"]
            for medication in medications
        ]

        schedule_control = CheckSchedule(self.db)
        schedule_response = schedule_control.requestTodayMedicationSchedule(
            self.patient_hash
        )
        schedules = schedule_response["data"]

        self.assertEqual(len(schedules), 5)
        self.assertEqual(
            [schedule["drug_name"] for schedule in schedules],
            [ANIPEN, PAMOTER, PROCOUGH, CELLEON, SUDAFED],
        )
        self.assertEqual(schedules[0]["slot_statuses"], self._three_times_slots())
        self.assertEqual(
            schedules[1]["slot_statuses"],
            {"morning": False, "evening": False},
        )
        self.assertEqual(schedules[4]["dosage_per_time"], "0.5")

        today_info_control = CheckTodayMedicationInfo(
            self.db,
            check_schedule=schedule_control,
        )
        today_info = today_info_control.requestTodayMedicationInfo(
            self.patient_hash
        )["data"]
        self.assertEqual(today_info["medication_count"], 5)
        self.assertEqual(today_info["total_dose_count"], 13)
        self.assertEqual(today_info["completed_dose_count"], 0)

        schedule_control.updateMedicationStatus(
            int(saved_ids[0]),
            True,
            self.patient_hash,
            slot_key="morning",
        )
        updated_today_info = today_info_control.requestTodayMedicationInfo(
            self.patient_hash
        )["data"]
        self.assertEqual(updated_today_info["completed_dose_count"], 1)
        self.assertEqual(updated_today_info["remaining_dose_count"], 12)

        notification_control = SetNotification(self.db)
        default_alarms = notification_control.requestMedicationAlarm(
            self.patient_hash
        )["data"]
        self.assertEqual(
            [alarm["slot_key"] for alarm in default_alarms],
            ["morning", "lunch", "evening", "bedtime"],
        )
        saved_alarm = notification_control.saveNotificationSetting(
            self.patient_hash,
            "morning",
            8,
            32,
        )["data"]
        self.assertTrue(saved_alarm["is_enabled"])
        self.assertEqual(saved_alarm["slot_key"], "morning")
        self.assertEqual(saved_alarm["hour"], 8)
        self.assertEqual(saved_alarm["minute"], 32)

    # Function Name: _seed_catalog_names
    # Description:
    # - Seeds each supplied sample drug name with a stable product code and normalized local
    #   lookup key.
    # Parameters:
    # - *names (str): Medication names to seed as separate authoritative catalog entries.
    # Returns:
    # - None.
    def _seed_catalog_names(self, *names: str) -> None:
        for index, name in enumerate(names, start=1):
            self.db.add(
                _DrugBasicInfo(
                    item_seq=f"SAMPLE-{index}",
                    item_name=name,
                    normalized_item_name=name.strip().lower().replace(" ", ""),
                    raw_json="{}",
                )
            )
        self.db.commit()

    # Function Name: _sample_ocr_response
    # Description:
    # - Builds today's five-medication OCR JSON with vowel, strength-unit, and prefix
    #   variants for deterministic correction tests.
    # Parameters:
    # - None.
    # Returns:
    # - str: Today's five-medication sample prescription encoded as JSON.
    def _sample_ocr_response(self) -> str:
        return json.dumps(
            {
                "hospital_name": SMILE_PHARMACY,
                "prescription_date": date.today().isoformat(),
                "medications": [
                    self._medication(ANIPEN_OCR_VARIANT, "1", "3", "3"),
                    self._medication(PAMOTER_OCR_VARIANT, "1", "2", "3"),
                    self._medication(PROCOUGH_OCR_NAME, "1", "3", "3"),
                    self._medication(CELLEON_OCR_NAME, "1", "2", "3"),
                    self._medication(SUDAFED_OCR_NAME, "0.5", "3", "3"),
                ],
            },
            ensure_ascii=False,
        )

    # Function Name: _medication
    # Description:
    # - Builds one OCR medication object with the specified drug name, dose, frequency, and
    #   treatment duration.
    # Parameters:
    # - drug_name (str): OCR or canonical medication name used in the payload.
    # - dosage_per_time (str): Amount taken in one medication dose.
    # - daily_frequency (str): Prescription dose-frequency label.
    # - total_days (str): Prescribed course-duration label, possibly unknown.
    # Returns:
    # - dict[str, str]: Medication payload preserving the supplied four prescription fields.
    def _medication(
        self,
        drug_name: str,
        dosage_per_time: str,
        daily_frequency: str,
        total_days: str,
    ) -> dict[str, str]:
        return {
            "drug_name": drug_name,
            "dosage_per_time": dosage_per_time,
            "daily_frequency": daily_frequency,
            "total_days": total_days,
        }

    # Function Name: _three_times_slots
    # Description:
    # - Returns an initially incomplete morning/lunch/evening status map for a three-dose
    #   medication.
    # Parameters:
    # - None.
    # Returns:
    # - dict[str, bool]: Morning, lunch, and evening mapped to incomplete states.
    def _three_times_slots(self) -> dict[str, bool]:
        return {"morning": False, "lunch": False, "evening": False}


if __name__ == "__main__":
    unittest.main()
