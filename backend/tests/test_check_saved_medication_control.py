import sys
import unittest
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.check_saved_medication_control import CheckSavedMedication  # noqa: E402
from core.database import Base  # noqa: E402
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH  # noqa: E402
from entities.saved_medication_entity import (  # noqa: E402
    _SavedMedication,
    ensure_saved_medication_schema,
)
from schemas.medication import SavedMedicationCreate  # noqa: E402


class CheckSavedMedicationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=self.engine)
        ensure_saved_medication_schema(self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.control = CheckSavedMedication(self.db)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def _saved_medication(
        self,
        *,
        patient_hash: str = "patient-a",
        item_name: str = "test-tablet",
    ) -> SavedMedicationCreate:
        return SavedMedicationCreate(
            patient_hash=patient_hash,
            item_name=item_name,
            efficacy="effect",
            use_method="usage",
            warning_message="warning",
            dosage_per_time="1 tablet",
            daily_frequency="3 times",
            total_days="7 days",
            ai_guide="guide",
        )

    def test_save_preserves_patient_hash_and_schedule_fields(self) -> None:
        response = self.control.save_medication_detail(self._saved_medication())

        self.assertTrue(response["success"])
        saved_row = self.db.get(_SavedMedication, response["id"])
        self.assertIsNotNone(saved_row)
        self.assertEqual(saved_row.patient_hash, "patient-a")
        self.assertEqual(saved_row.dosage_per_time, "1 tablet")
        self.assertEqual(saved_row.daily_frequency, "3 times")
        self.assertEqual(saved_row.total_days, "7 days")

    def test_list_is_scoped_by_patient_hash(self) -> None:
        self.control.save_medication_detail(
            self._saved_medication(patient_hash="patient-a", item_name="A tablet")
        )
        self.control.save_medication_detail(
            self._saved_medication(patient_hash="patient-b", item_name="B tablet")
        )

        response = self.control.request_saved_medication_info("patient-a")

        self.assertTrue(response["success"])
        self.assertEqual(len(response["data"]), 1)
        self.assertEqual(response["data"][0]["patient_hash"], "patient-a")
        self.assertEqual(response["data"][0]["item_name"], "A tablet")

    def test_delete_is_scoped_by_patient_hash(self) -> None:
        patient_a_response = self.control.save_medication_detail(
            self._saved_medication(patient_hash="patient-a", item_name="A tablet")
        )
        patient_b_response = self.control.save_medication_detail(
            self._saved_medication(patient_hash="patient-b", item_name="B tablet")
        )

        with self.assertRaises(HTTPException) as context:
            self.control.request_delete(patient_b_response["id"], "patient-a")
        self.assertEqual(context.exception.status_code, 404)

        delete_response = self.control.request_delete(
            patient_b_response["id"],
            "patient-b",
        )
        self.assertTrue(delete_response["success"])

        patient_a_list = self.control.request_saved_medication_info("patient-a")
        self.assertEqual(len(patient_a_list["data"]), 1)
        self.assertEqual(patient_a_list["data"][0]["id"], patient_a_response["id"])

    def test_empty_patient_hash_falls_back_to_default_hash(self) -> None:
        response = self.control.save_medication_detail(
            self._saved_medication(patient_hash=" ")
        )

        saved_row = self.db.get(_SavedMedication, response["id"])
        self.assertIsNotNone(saved_row)
        self.assertEqual(saved_row.patient_hash, DEFAULT_PATIENT_HASH)


if __name__ == "__main__":
    unittest.main()
