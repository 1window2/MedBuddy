# 파일명: test_check_saved_medication_control.py
# 역할: 저장 복약 control의 저장, 조회, 삭제, 보호자 권한 범위 처리를 검증한다.

import hashlib
import sys
import unittest
from datetime import date, timedelta
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.check_saved_medication_control import CheckSavedMedication  # noqa: E402
from core.database import Base  # noqa: E402
from entities.medication_completion_entity import (  # noqa: E402
    _MedicationCompletion,
    ensure_medication_completion_schema,
)
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH  # noqa: E402
from entities.saved_medication_entity import (  # noqa: E402
    _SavedMedication,
    build_saved_medication_deduplication_key,
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
        self.active_prescription_date = date.today()

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def _saved_medication(
        self,
        *,
        patient_hash: str = "patient-a",
        item_name: str = "test-tablet",
        schedule_slot_keys: list[str] | None = None,
        prescription_batch_id: str | None = "batch_1234567890abcdef",
    ) -> SavedMedicationCreate:
        return SavedMedicationCreate(
            patient_hash=patient_hash,
            prescription_date=self.active_prescription_date,
            prescription_batch_id=prescription_batch_id,
            item_seq="200000001",
            item_name=item_name,
            efficacy="effect",
            use_method="usage",
            warning_message="warning",
            interaction="avoid anticoagulants",
            side_effect="drowsiness",
            storage_method="store below 25 C",
            dosage_per_time="1 tablet",
            daily_frequency="3 times",
            total_days="7 days",
            schedule_slot_keys=schedule_slot_keys or [],
            image_url="https://nedrug.mfds.go.kr/medicine.jpg",
            ai_guide="guide",
        )

    def test_save_preserves_patient_hash_and_schedule_fields(self) -> None:
        response = self.control.saveMedicationDetail(self._saved_medication())

        self.assertTrue(response["success"])
        self.assertFalse(response["duplicate"])
        saved_row = self.db.get(_SavedMedication, response["id"])
        self.assertIsNotNone(saved_row)
        self.assertEqual(saved_row.patient_hash, "patient-a")
        self.assertEqual(saved_row.item_seq, "200000001")
        self.assertEqual(saved_row.dosage_per_time, "1 tablet")
        self.assertEqual(saved_row.daily_frequency, "3 times")
        self.assertEqual(saved_row.total_days, "7 days")
        self.assertEqual(saved_row.interaction, "avoid anticoagulants")
        self.assertEqual(saved_row.side_effect, "drowsiness")
        self.assertEqual(saved_row.storage_method, "store below 25 C")
        self.assertEqual(saved_row.prescription_date, self.active_prescription_date)
        self.assertEqual(
            saved_row.prescription_batch_id,
            "batch_1234567890abcdef",
        )
        self.assertEqual(
            saved_row.image_url,
            "https://nedrug.mfds.go.kr/medicine.jpg",
        )
        list_item = self.control.requestSavedMedicationInfo("patient-a")["data"][
            0
        ]
        self.assertEqual(list_item["interaction"], "avoid anticoagulants")
        self.assertEqual(list_item["side_effect"], "drowsiness")
        self.assertEqual(list_item["storage_method"], "store below 25 C")

    def test_save_preserves_user_confirmed_schedule_slots(self) -> None:
        response = self.control.saveMedicationDetail(
            self._saved_medication(
                schedule_slot_keys=["morning", "bedtime"],
            )
        )

        saved_row = self.db.get(_SavedMedication, response["id"])
        self.assertIsNotNone(saved_row)
        self.assertEqual(saved_row.schedule_slot_keys, '["morning","bedtime"]')

        list_response = self.control.requestSavedMedicationInfo("patient-a")
        self.assertEqual(
            list_response["data"][0]["schedule_slot_keys"],
            ["morning", "bedtime"],
        )

    def test_schema_upgrade_adds_saved_metadata_to_legacy_table(self) -> None:
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
        self.assertIn("item_seq", existing_columns)
        self.assertIn("schedule_slot_keys", existing_columns)
        self.assertIn("prescription_batch_id", existing_columns)
        self.assertIn("interaction", existing_columns)
        self.assertIn("side_effect", existing_columns)
        self.assertIn("storage_method", existing_columns)

        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=engine,
        )
        db = session_factory()
        try:
            response = CheckSavedMedication(db).saveMedicationDetail(
                self._saved_medication(patient_hash="patient-a", item_name="legacy")
            )
            saved_row = db.get(_SavedMedication, response["id"])
            self.assertIsNotNone(saved_row)
            self.assertEqual(saved_row.ai_guide, "guide")
            self.assertEqual(saved_row.item_seq, "200000001")
            self.assertEqual(saved_row.interaction, "avoid anticoagulants")
            self.assertEqual(saved_row.side_effect, "drowsiness")
            self.assertEqual(saved_row.storage_method, "store below 25 C")
        finally:
            db.close()
            engine.dispose()

    def test_save_rejects_same_day_duplicate_medication(self) -> None:
        first_response = self.control.saveMedicationDetail(
            self._saved_medication(patient_hash="patient-a", item_name="A tablet")
        )
        duplicate_response = self.control.saveMedicationDetail(
            self._saved_medication(patient_hash="patient-a", item_name="  A   tablet  ")
        )

        self.assertTrue(first_response["success"])
        self.assertFalse(duplicate_response["success"])
        self.assertTrue(duplicate_response["duplicate"])
        saved_rows = self.db.query(_SavedMedication).all()
        self.assertEqual(len(saved_rows), 1)

    def test_legacy_deduplication_key_is_stable_without_batch_id(self) -> None:
        legacy_signature = "\0".join(
            (
                "a tablet",
                self.active_prescription_date.isoformat(),
                "1 tablet",
                "3 times",
                "7 days",
                '["morning","lunch","evening"]',
            )
        )

        actual_key = build_saved_medication_deduplication_key(
            item_name="A tablet",
            prescription_date=self.active_prescription_date,
            prescription_batch_id=None,
            dosage_per_time="1 tablet",
            daily_frequency="3 times",
            total_days="7 days",
            schedule_slot_keys=["morning", "lunch", "evening"],
        )

        self.assertEqual(
            actual_key,
            hashlib.sha256(legacy_signature.encode("utf-8")).hexdigest(),
        )

    def test_save_allows_same_medication_with_different_period(self) -> None:
        first_response = self.control.saveMedicationDetail(
            self._saved_medication(patient_hash="patient-a", item_name="A tablet")
        )
        second_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="A tablet",
        )
        second_medication.prescription_date = self.active_prescription_date + timedelta(days=10)
        second_response = self.control.saveMedicationDetail(second_medication)

        self.assertTrue(first_response["success"])
        self.assertTrue(second_response["success"])
        self.assertFalse(second_response["duplicate"])
        saved_rows = self.db.query(_SavedMedication).all()
        self.assertEqual(len(saved_rows), 2)

    def test_save_allows_same_medication_from_distinct_analysis_batches(self) -> None:
        first_response = self.control.saveMedicationDetail(
            self._saved_medication(
                item_name="A tablet",
                prescription_batch_id="batch_1111111111111111",
            )
        )
        second_response = self.control.saveMedicationDetail(
            self._saved_medication(
                item_name="A tablet",
                prescription_batch_id="batch_2222222222222222",
            )
        )

        self.assertTrue(first_response["success"])
        self.assertTrue(second_response["success"])
        self.assertEqual(self.db.query(_SavedMedication).count(), 2)

    def test_list_is_scoped_by_patient_hash(self) -> None:
        self.control.saveMedicationDetail(
            self._saved_medication(patient_hash="patient-a", item_name="A tablet")
        )
        self.control.saveMedicationDetail(
            self._saved_medication(patient_hash="patient-b", item_name="B tablet")
        )

        response = self.control.requestSavedMedicationInfo("patient-a")

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
            "https://nedrug.mfds.go.kr/medicine.jpg",
        )

    def test_list_does_not_enrich_or_mutate_legacy_missing_image(self) -> None:
        medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="catalog-tablet",
        )
        medication.item_seq = None
        medication.image_url = None
        save_response = self.control.saveMedicationDetail(medication)
        response = self.control.requestSavedMedicationInfo("patient-a")

        self.assertFalse(response["data"][0]["item_seq"])
        self.assertFalse(response["data"][0]["image_url"])
        saved_row = self.db.get(_SavedMedication, save_response["id"])
        self.assertIsNone(saved_row.item_seq)
        self.assertIsNone(saved_row.image_url)

    def test_list_suppresses_legacy_untrusted_image_url(self) -> None:
        medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="legacy-image-tablet",
        )
        save_response = self.control.saveMedicationDetail(medication)
        saved_row = self.db.get(_SavedMedication, save_response["id"])
        saved_row.image_url = "https://tracker.example/patient-a.png"
        self.db.commit()

        response = self.control.requestSavedMedicationInfo("patient-a")

        self.assertEqual(response["data"][0]["image_url"], "")
        self.assertEqual(
            self.db.get(_SavedMedication, save_response["id"]).image_url,
            "https://tracker.example/patient-a.png",
        )

    def test_list_preserves_expired_medications_without_mutating_storage(self) -> None:
        expired_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="expired-tablet",
        )
        expired_medication.total_days = "7 days"
        active_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="active-tablet",
        )
        active_medication.prescription_date = date.today() - timedelta(days=10)
        active_medication.total_days = "7 days"
        expired_response = self.control.saveMedicationDetail(expired_medication)
        active_response = self.control.saveMedicationDetail(active_medication)
        expired_row = self.db.get(_SavedMedication, expired_response["id"])
        expired_row.prescription_date = date.today() - timedelta(days=40)
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

        response = self.control.requestSavedMedicationInfo("patient-a")

        self.assertEqual(len(response["data"]), 2)
        self.assertCountEqual(
            [medication["item_name"] for medication in response["data"]],
            ["expired-tablet", "active-tablet"],
        )
        saved_names = [
            medication.item_name
            for medication in self.db.query(_SavedMedication).all()
        ]
        self.assertCountEqual(saved_names, ["expired-tablet", "active-tablet"])
        remaining_completion_medication_ids = sorted(
            completion.saved_medication_id
            for completion in self.db.query(_MedicationCompletion).all()
        )
        self.assertEqual(
            remaining_completion_medication_ids,
            [expired_response["id"], active_response["id"]],
        )

        self.control.saveMedicationDetail(
            self._saved_medication(
                patient_hash="patient-a",
                item_name="new-tablet",
            )
        )
        self.assertIsNotNone(self.db.get(_SavedMedication, expired_response["id"]))

    def test_list_keeps_medications_without_total_days(self) -> None:
        unknown_period_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="unknown-period-tablet",
        )
        unknown_period_medication.prescription_date = date.today() - timedelta(days=90)
        unknown_period_medication.total_days = ""
        self.control.saveMedicationDetail(unknown_period_medication)

        response = self.control.requestSavedMedicationInfo("patient-a")

        self.assertEqual(len(response["data"]), 1)
        self.assertEqual(response["data"][0]["item_name"], "unknown-period-tablet")

    def test_delete_is_scoped_by_patient_hash(self) -> None:
        patient_a_response = self.control.saveMedicationDetail(
            self._saved_medication(patient_hash="patient-a", item_name="A tablet")
        )
        patient_b_response = self.control.saveMedicationDetail(
            self._saved_medication(patient_hash="patient-b", item_name="B tablet")
        )

        with self.assertRaises(HTTPException) as context:
            self.control.requestDelete(patient_b_response["id"], "patient-a")
        self.assertEqual(context.exception.status_code, 404)

        delete_response = self.control.requestDelete(
            patient_b_response["id"],
            "patient-b",
        )
        self.assertTrue(delete_response["success"])

        patient_a_list = self.control.requestSavedMedicationInfo("patient-a")
        self.assertEqual(len(patient_a_list["data"]), 1)
        self.assertEqual(patient_a_list["data"][0]["id"], patient_a_response["id"])

    def test_delete_removes_owned_completion_rows(self) -> None:
        response = self.control.saveMedicationDetail(
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

        delete_response = self.control.requestDelete(response["id"], "patient-a")

        self.assertTrue(delete_response["success"])
        self.assertIsNone(self.db.get(_SavedMedication, response["id"]))
        self.assertEqual(self.db.query(_MedicationCompletion).count(), 0)

    def test_empty_patient_hash_falls_back_to_default_hash(self) -> None:
        response = self.control.saveMedicationDetail(
            self._saved_medication(patient_hash=" ")
        )

        saved_row = self.db.get(_SavedMedication, response["id"])
        self.assertIsNotNone(saved_row)
        self.assertEqual(saved_row.patient_hash, DEFAULT_PATIENT_HASH)

if __name__ == "__main__":
    unittest.main()
