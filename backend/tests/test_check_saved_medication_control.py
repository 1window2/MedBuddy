# 파일명: test_check_saved_medication_control.py
# 역할: 저장 복약 control의 저장, 조회, 삭제, 보호자 권한 범위 처리를 검증한다.

import unittest
import sys
from datetime import date, timedelta
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.check_saved_medication_control import CheckSavedMedication  # noqa: E402
from controls.patient_guardian_link_control import PatientGuardianLinkControl  # noqa: E402
from core.database import Base  # noqa: E402
from entities.medication_completion_entity import (  # noqa: E402
    _MedicationCompletion,
    ensure_medication_completion_schema,
)
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
        ensure_medication_completion_schema(self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.control = CheckSavedMedication(self.db)
        self.link_control = PatientGuardianLinkControl(self.db)
        self.active_prescription_date = date.today()

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
            prescription_date=self.active_prescription_date,
            item_name=item_name,
            efficacy="effect",
            use_method="usage",
            warning_message="warning",
            dosage_per_time="1 tablet",
            daily_frequency="3 times",
            total_days="7 days",
            image_url="https://example.com/medicine.jpg",
            ai_guide="guide",
        )

    def test_save_preserves_patient_hash_and_schedule_fields(self) -> None:
        response = self.control.save_medication_detail(self._saved_medication())

        self.assertTrue(response["success"])
        self.assertFalse(response["duplicate"])
        saved_row = self.db.get(_SavedMedication, response["id"])
        self.assertIsNotNone(saved_row)
        self.assertEqual(saved_row.patient_hash, "patient-a")
        self.assertEqual(saved_row.dosage_per_time, "1 tablet")
        self.assertEqual(saved_row.daily_frequency, "3 times")
        self.assertEqual(saved_row.total_days, "7 days")
        self.assertEqual(saved_row.prescription_date, self.active_prescription_date)
        self.assertEqual(saved_row.image_url, "https://example.com/medicine.jpg")

    def test_schema_upgrade_adds_ai_guide_to_legacy_saved_medications(self) -> None:
        engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        with engine.begin() as connection:
            connection.execute(
                text(
                    """
                    CREATE TABLE saved_medications (
                        id INTEGER PRIMARY KEY,
                        patient_hash VARCHAR DEFAULT 'local_patient',
                        created_date DATE,
                        prescription_date DATE,
                        item_name VARCHAR,
                        efficacy VARCHAR,
                        use_method VARCHAR,
                        warning_message VARCHAR,
                        dosage_per_time VARCHAR,
                        daily_frequency VARCHAR,
                        total_days VARCHAR,
                        image_url VARCHAR,
                        medication_status BOOLEAN DEFAULT 0,
                        medication_status_date DATE
                    )
                    """
                )
            )

        ensure_saved_medication_schema(engine)

        existing_columns = {
            column["name"] for column in inspect(engine).get_columns("saved_medications")
        }
        self.assertIn("ai_guide", existing_columns)

        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=engine,
        )
        db = session_factory()
        try:
            response = CheckSavedMedication(db).save_medication_detail(
                self._saved_medication(patient_hash="patient-a", item_name="legacy")
            )
            saved_row = db.get(_SavedMedication, response["id"])
            self.assertIsNotNone(saved_row)
            self.assertEqual(saved_row.ai_guide, "guide")
        finally:
            db.close()
            engine.dispose()

    def test_save_rejects_same_day_duplicate_medication(self) -> None:
        first_response = self.control.save_medication_detail(
            self._saved_medication(patient_hash="patient-a", item_name="A tablet")
        )
        duplicate_response = self.control.save_medication_detail(
            self._saved_medication(patient_hash="patient-a", item_name="  A   tablet  ")
        )

        self.assertTrue(first_response["success"])
        self.assertFalse(duplicate_response["success"])
        self.assertTrue(duplicate_response["duplicate"])
        saved_rows = self.db.query(_SavedMedication).all()
        self.assertEqual(len(saved_rows), 1)

    def test_save_allows_same_medication_with_different_period(self) -> None:
        first_response = self.control.save_medication_detail(
            self._saved_medication(patient_hash="patient-a", item_name="A tablet")
        )
        second_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="A tablet",
        )
        second_medication.prescription_date = self.active_prescription_date + timedelta(days=10)
        second_response = self.control.save_medication_detail(second_medication)

        self.assertTrue(first_response["success"])
        self.assertTrue(second_response["success"])
        self.assertFalse(second_response["duplicate"])
        saved_rows = self.db.query(_SavedMedication).all()
        self.assertEqual(len(saved_rows), 2)

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
        self.assertEqual(
            response["data"][0]["prescription_date"],
            self.active_prescription_date.isoformat(),
        )
        self.assertEqual(
            response["data"][0]["image_url"],
            "https://example.com/medicine.jpg",
        )

    def test_list_removes_medications_ended_more_than_retention_period(self) -> None:
        expired_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="expired-tablet",
        )
        expired_medication.prescription_date = date.today() - timedelta(days=40)
        expired_medication.total_days = "7 days"
        active_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="active-tablet",
        )
        active_medication.prescription_date = date.today() - timedelta(days=10)
        active_medication.total_days = "7 days"
        expired_response = self.control.save_medication_detail(expired_medication)
        active_response = self.control.save_medication_detail(active_medication)
        self.db.add_all(
            [
                _MedicationCompletion(
                    saved_medication_id=expired_response["id"],
                    patient_hash="patient-a",
                    schedule_date=date.today() - timedelta(days=33),
                    slot_key="morning",
                    completed=True,
                ),
                _MedicationCompletion(
                    saved_medication_id=active_response["id"],
                    patient_hash="patient-a",
                    schedule_date=date.today(),
                    slot_key="morning",
                    completed=True,
                ),
            ]
        )
        self.db.commit()

        response = self.control.request_saved_medication_info("patient-a")

        self.assertEqual(len(response["data"]), 1)
        self.assertEqual(response["data"][0]["item_name"], "active-tablet")
        saved_names = [
            medication.item_name
            for medication in self.db.query(_SavedMedication).all()
        ]
        self.assertEqual(saved_names, ["active-tablet"])
        remaining_completion_medication_ids = sorted(
            completion.saved_medication_id
            for completion in self.db.query(_MedicationCompletion).all()
        )
        self.assertEqual(remaining_completion_medication_ids, [active_response["id"]])

    def test_list_keeps_medications_without_total_days(self) -> None:
        unknown_period_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="unknown-period-tablet",
        )
        unknown_period_medication.prescription_date = date.today() - timedelta(days=90)
        unknown_period_medication.total_days = ""
        self.control.save_medication_detail(unknown_period_medication)

        response = self.control.request_saved_medication_info("patient-a")

        self.assertEqual(len(response["data"]), 1)
        self.assertEqual(response["data"][0]["item_name"], "unknown-period-tablet")

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

    def test_delete_removes_owned_completion_rows(self) -> None:
        response = self.control.save_medication_detail(
            self._saved_medication(patient_hash="patient-a", item_name="A tablet")
        )
        self.db.add(
            _MedicationCompletion(
                saved_medication_id=response["id"],
                patient_hash="patient-a",
                schedule_date=date.today(),
                slot_key="morning",
                completed=True,
            )
        )
        self.db.commit()

        delete_response = self.control.request_delete(response["id"], "patient-a")

        self.assertTrue(delete_response["success"])
        self.assertIsNone(self.db.get(_SavedMedication, response["id"]))
        self.assertEqual(self.db.query(_MedicationCompletion).count(), 0)

    def test_empty_patient_hash_falls_back_to_default_hash(self) -> None:
        response = self.control.save_medication_detail(
            self._saved_medication(patient_hash=" ")
        )

        saved_row = self.db.get(_SavedMedication, response["id"])
        self.assertIsNotNone(saved_row)
        self.assertEqual(saved_row.patient_hash, DEFAULT_PATIENT_HASH)

    def test_guardian_list_resolves_linked_patient_hash(self) -> None:
        self.control.save_medication_detail(
            self._saved_medication(patient_hash="patient-a", item_name="A tablet")
        )
        self.control.save_medication_detail(
            self._saved_medication(patient_hash="patient-b", item_name="B tablet")
        )
        code_response = self.link_control.request_patient_code("patient-a")
        self.link_control.register_patient_code(
            "guardian-a",
            code_response["data"]["patient_code"],
        )

        response = self.control.request_saved_medication_info(
            user_hash="guardian-a",
            role="guardian",
        )

        self.assertTrue(response["success"])
        self.assertEqual(len(response["data"]), 1)
        self.assertEqual(response["data"][0]["patient_hash"], "patient-a")
        self.assertEqual(response["data"][0]["item_name"], "A tablet")

    def test_guardian_list_honors_requested_linked_patient_hash(self) -> None:
        self.control.save_medication_detail(
            self._saved_medication(patient_hash="patient-a", item_name="A tablet")
        )
        self.control.save_medication_detail(
            self._saved_medication(patient_hash="patient-b", item_name="B tablet")
        )
        patient_a_code = self.link_control.request_patient_code("patient-a")
        patient_b_code = self.link_control.request_patient_code("patient-b")
        self.link_control.register_patient_code(
            "guardian-a",
            patient_a_code["data"]["patient_code"],
        )
        self.link_control.register_patient_code(
            "guardian-a",
            patient_b_code["data"]["patient_code"],
        )

        response = self.control.request_saved_medication_info(
            patient_hash="patient-b",
            user_hash="guardian-a",
            role="guardian",
        )

        self.assertTrue(response["success"])
        self.assertEqual(len(response["data"]), 1)
        self.assertEqual(response["data"][0]["patient_hash"], "patient-b")
        self.assertEqual(response["data"][0]["item_name"], "B tablet")

    def test_guardian_list_without_link_stops_with_not_found(self) -> None:
        with self.assertRaises(HTTPException) as context:
            self.control.request_saved_medication_info(
                user_hash="guardian-missing",
                role="guardian",
            )

        self.assertEqual(context.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
