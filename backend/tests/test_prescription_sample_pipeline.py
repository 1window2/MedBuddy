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


class _FakeGeminiResponse:
    def __init__(self, text: str) -> None:
        self.text = text


class _FakeGeminiModels:
    def __init__(self, response_text: str) -> None:
        self.response_text = response_text
        self.call_count = 0

    async def generate_content(self, **_kwargs: object) -> _FakeGeminiResponse:
        self.call_count += 1
        return _FakeGeminiResponse(self.response_text)


class _FakeGeminiAio:
    def __init__(self, models: _FakeGeminiModels) -> None:
        self.models = models


class _FakeGeminiClient:
    def __init__(self, response_text: str) -> None:
        self.models = _FakeGeminiModels(response_text)
        self.aio = _FakeGeminiAio(self.models)


class _FakeOcrBoundary:
    def __init__(self, response_text: str) -> None:
        self.response_text = response_text
        self.received_image = b""

    async def extractPrescriptionData(self, image: bytes) -> str:
        self.received_image = image
        return self.response_text


class PrescriptionSamplePipelineTest(unittest.TestCase):
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

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def test_sample_prescription_flows_into_today_schedule_and_notifications(
        self,
    ) -> None:
        ocr_boundary = _FakeOcrBoundary(self._sample_ocr_response())
        ai_client = _FakeGeminiClient(json.dumps({"corrections": []}))
        prescription_control = InputPrescription(
            client=ai_client,
            db=self.db,
            ocr_service_boundary=ocr_boundary,
        )

        analysis_payload = asyncio.run(
            prescription_control.requestPrescriptionImage(b"sample-image")
        )

        self.assertEqual(ocr_boundary.received_image, b"sample-image")
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

    def _three_times_slots(self) -> dict[str, bool]:
        return {"morning": False, "lunch": False, "evening": False}


if __name__ == "__main__":
    unittest.main()
