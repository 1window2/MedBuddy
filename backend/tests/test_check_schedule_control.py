# 파일명: test_check_schedule_control.py
# 역할: 오늘의 복약 일정 조회와 복약 완료 상태 변경 control을 검증한다.

import sys
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import create_engine, event, inspect, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.check_schedule_control import CheckSchedule  # noqa: E402
from controls.patient_guardian_link_control import PatientGuardianLinkControl  # noqa: E402
from core.database import Base  # noqa: E402
from entities.medication_completion_entity import (  # noqa: E402
    MedicationCompletion,
    _MedicationCompletion,
    ensure_medication_completion_schema,
)
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH  # noqa: E402
from entities.saved_medication_entity import (  # noqa: E402
    _SavedMedication,
    ensure_saved_medication_schema,
)


class CheckScheduleTest(unittest.TestCase):
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
        self.control = CheckSchedule(self.db)
        self.link_control = PatientGuardianLinkControl(self.db)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def _saved_medication(
        self,
        *,
        patient_hash: str = "patient-a",
        item_name: str = "test-tablet",
        created_date: date | None = None,
        prescription_date: date | None = None,
        total_days: str | None = "7 days",
        medication_status: bool = False,
        medication_status_date: date | None = None,
    ) -> _SavedMedication:
        medication = _SavedMedication(
            patient_hash=patient_hash,
            created_date=created_date or date.today(),
            prescription_date=prescription_date,
            item_name=item_name,
            efficacy="effect",
            use_method="usage",
            warning_message="warning",
            dosage_per_time="1 tablet",
            daily_frequency="3 times",
            total_days=total_days,
            medication_status=medication_status,
            medication_status_date=medication_status_date,
            ai_guide="guide",
            image_url="https://example.com/medicine.jpg",
        )
        self.db.add(medication)
        self.db.commit()
        self.db.refresh(medication)
        return medication

    def test_today_schedule_is_scoped_and_filters_expired_medications(self) -> None:
        today = date.today()
        old_saved_date = today - timedelta(days=20)
        active_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="active-tablet",
            created_date=old_saved_date,
            prescription_date=today,
        )
        self._saved_medication(
            patient_hash="patient-a",
            item_name="expired-tablet",
            created_date=today,
            prescription_date=today - timedelta(days=8),
            total_days="7 days",
        )
        self._saved_medication(
            patient_hash="patient-b",
            item_name="other-patient-tablet",
            created_date=today,
        )

        response = self.control.request_today_medication_schedule("patient-a")

        self.assertTrue(response["success"])
        self.assertEqual(len(response["data"]), 1)
        schedule = response["data"][0]
        self.assertEqual(schedule["medication_id"], str(active_medication.id))
        self.assertEqual(schedule["drug_name"], "active-tablet")
        self.assertEqual(schedule["patient_hash"], "patient-a")
        self.assertFalse(schedule["medication_status"])
        self.assertEqual(schedule["image_url"], "https://example.com/medicine.jpg")
        self.assertEqual(schedule["created_date"], old_saved_date.isoformat())
        self.assertEqual(schedule["prescription_date"], today.isoformat())

    def test_status_update_is_scoped_by_patient_hash(self) -> None:
        medication = self._saved_medication(patient_hash="patient-b")

        with self.assertRaises(HTTPException) as context:
            self.control.update_medication_status(
                medication.id,
                True,
                "patient-a",
            )
        self.assertEqual(context.exception.status_code, 404)

        response = self.control.update_medication_status(
            medication.id,
            True,
            "patient-b",
        )

        self.assertTrue(response["success"])
        self.assertTrue(response["data"]["medication_status"])
        self.db.refresh(medication)
        self.assertTrue(medication.medication_status)
        self.assertEqual(medication.medication_status_date, date.today())

    def test_slot_status_update_only_marks_requested_dose(self) -> None:
        medication = self._saved_medication(patient_hash="patient-a")

        response = self.control.update_medication_status(
            medication.id,
            True,
            "patient-a",
            slot_key="morning",
        )

        self.assertTrue(response["success"])
        self.assertFalse(response["data"]["medication_status"])
        self.assertEqual(
            response["data"]["slot_statuses"],
            {"morning": True, "lunch": False, "evening": False},
        )
        self.assertEqual(response["data"]["completed_slot_keys"], ["morning"])
        self.db.refresh(medication)
        self.assertFalse(medication.medication_status)

        completions = (
            self.db.query(_MedicationCompletion)
            .filter(_MedicationCompletion.saved_medication_id == medication.id)
            .all()
        )
        self.assertEqual(len(completions), 1)
        self.assertEqual(completions[0].slot_key, "morning")
        self.assertTrue(completions[0].completed)

    def test_medication_completion_preserves_uml_entity_names(self) -> None:
        schedule_date = date.today()
        completed_at = datetime(2026, 1, 1, 8, 0)
        completion = MedicationCompletion(
            patient_hash="patient-a",
            medicine_name="test-tablet",
            time_slot="morning",
            completed_at=completed_at,
            completed=True,
        )

        row = completion.insertMedicationCompletion(
            saved_medication_id=7,
            schedule_date=schedule_date,
        )

        self.assertEqual(completion.patientHash, "patient-a")
        self.assertEqual(completion.medicineName, "test-tablet")
        self.assertEqual(completion.timeSlot, "morning")
        self.assertEqual(completion.completedAt, completed_at)
        self.assertEqual(row.saved_medication_id, 7)
        self.assertEqual(row.patient_hash, "patient-a")
        self.assertEqual(row.schedule_date, schedule_date)
        self.assertEqual(row.slot_key, "morning")
        self.assertTrue(row.completed)

    def test_all_slots_complete_sets_legacy_row_status(self) -> None:
        medication = self._saved_medication(patient_hash="patient-a")

        for slot_key in ["morning", "lunch", "evening"]:
            response = self.control.update_medication_status(
                medication.id,
                True,
                "patient-a",
                slot_key=slot_key,
            )

        self.assertTrue(response["data"]["medication_status"])
        self.assertEqual(
            response["data"]["slot_statuses"],
            {"morning": True, "lunch": True, "evening": True},
        )
        self.db.refresh(medication)
        self.assertTrue(medication.medication_status)

    def test_unchecking_one_slot_clears_legacy_row_status(self) -> None:
        medication = self._saved_medication(patient_hash="patient-a")
        self.control.update_medication_status(medication.id, True, "patient-a")

        response = self.control.update_medication_status(
            medication.id,
            False,
            "patient-a",
            slot_key="lunch",
        )

        self.assertFalse(response["data"]["medication_status"])
        self.assertEqual(
            response["data"]["slot_statuses"],
            {"morning": True, "lunch": False, "evening": True},
        )
        self.db.refresh(medication)
        self.assertFalse(medication.medication_status)

    def test_slot_update_preserves_other_legacy_completed_slots(self) -> None:
        medication = self._saved_medication(
            patient_hash="patient-a",
            medication_status=True,
            medication_status_date=date.today(),
        )

        response = self.control.update_medication_status(
            medication.id,
            False,
            "patient-a",
            slot_key="lunch",
        )

        self.assertFalse(response["data"]["medication_status"])
        self.assertEqual(
            response["data"]["slot_statuses"],
            {"morning": True, "lunch": False, "evening": True},
        )
        self.db.refresh(medication)
        self.assertFalse(medication.medication_status)

    def test_invalid_slot_key_is_rejected(self) -> None:
        medication = self._saved_medication(patient_hash="patient-a")

        with self.assertRaises(HTTPException) as context:
            self.control.update_medication_status(
                medication.id,
                True,
                "patient-a",
                slot_key="bedtime",
            )

        self.assertEqual(context.exception.status_code, 400)

    def test_previous_day_completion_does_not_mark_today_complete(self) -> None:
        medication = self._saved_medication(
            patient_hash="patient-a",
            medication_status=True,
            medication_status_date=date.today() - timedelta(days=1),
        )

        response = self.control.request_today_medication_schedule("patient-a")

        self.assertTrue(response["success"])
        self.assertEqual(response["data"][0]["medication_id"], str(medication.id))
        self.assertFalse(response["data"][0]["medication_status"])

    def test_today_schedule_batches_completion_lookup(self) -> None:
        first_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="first-tablet",
        )
        second_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="second-tablet",
        )
        self.db.add_all(
            [
                _MedicationCompletion(
                    saved_medication_id=first_medication.id,
                    patient_hash="patient-a",
                    schedule_date=date.today(),
                    slot_key="morning",
                    completed=True,
                ),
                _MedicationCompletion(
                    saved_medication_id=second_medication.id,
                    patient_hash="patient-a",
                    schedule_date=date.today(),
                    slot_key="lunch",
                    completed=True,
                ),
            ]
        )
        self.db.commit()
        completion_select_count = 0

        def count_completion_select(
            _connection: object,
            _cursor: object,
            statement: str,
            _parameters: object,
            _context: object,
            _executemany: bool,
        ) -> None:
            nonlocal completion_select_count
            normalized_statement = " ".join(statement.lower().split())
            if (
                normalized_statement.startswith("select")
                and "from medication_completions" in normalized_statement
            ):
                completion_select_count += 1

        event.listen(
            self.engine,
            "before_cursor_execute",
            count_completion_select,
        )
        try:
            response = self.control.request_today_medication_schedule("patient-a")
        finally:
            event.remove(
                self.engine,
                "before_cursor_execute",
                count_completion_select,
            )

        self.assertTrue(response["success"])
        self.assertEqual(len(response["data"]), 2)
        self.assertEqual(completion_select_count, 1)

    def test_empty_patient_hash_falls_back_to_default_hash(self) -> None:
        medication = self._saved_medication(patient_hash=DEFAULT_PATIENT_HASH)

        response = self.control.request_today_medication_schedule(" ")

        self.assertTrue(response["success"])
        self.assertEqual(response["data"][0]["medication_id"], str(medication.id))

    def test_completion_schema_upgrade_hardens_legacy_table(self) -> None:
        legacy_engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        try:
            with legacy_engine.begin() as connection:
                connection.execute(
                    text(
                        "CREATE TABLE medication_completions ("
                        "id INTEGER PRIMARY KEY, "
                        "saved_medication_id INTEGER"
                        ")"
                    )
                )
                connection.execute(
                    text(
                        "INSERT INTO medication_completions "
                        "(id, saved_medication_id) "
                        "VALUES (1, 10), (2, 10)"
                    )
                )

            ensure_medication_completion_schema(legacy_engine)

            existing_columns = {
                column["name"]
                for column in inspect(legacy_engine).get_columns(
                    "medication_completions"
                )
            }
            self.assertIn("patient_hash", existing_columns)
            self.assertIn("schedule_date", existing_columns)
            self.assertIn("slot_key", existing_columns)
            self.assertIn("completed", existing_columns)
            self.assertIn("completed_at", existing_columns)

            with legacy_engine.connect() as connection:
                rows = connection.execute(
                    text(
                        "SELECT saved_medication_id, patient_hash, schedule_date, "
                        "slot_key, completed, completed_at "
                        "FROM medication_completions"
                    )
                ).all()
                self.assertEqual(len(rows), 1)
                self.assertEqual(rows[0][0], 10)
                self.assertEqual(rows[0][1], DEFAULT_PATIENT_HASH)
                self.assertIsNotNone(rows[0][2])
                self.assertEqual(rows[0][3], "morning")
                self.assertEqual(rows[0][4], 1)
                self.assertIsNotNone(rows[0][5])
                with self.assertRaises(IntegrityError):
                    connection.execute(
                        text(
                            "INSERT INTO medication_completions "
                            "(saved_medication_id, patient_hash, schedule_date, "
                            "slot_key, completed) "
                            "VALUES (10, :patient_hash, :schedule_date, 'morning', 1)"
                        ),
                        {
                            "patient_hash": DEFAULT_PATIENT_HASH,
                            "schedule_date": rows[0][2],
                        },
                    )
        finally:
            legacy_engine.dispose()

    def test_guardian_today_schedule_resolves_linked_patient_hash(self) -> None:
        medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="guardian-visible-tablet",
        )
        self._saved_medication(
            patient_hash="patient-b",
            item_name="other-tablet",
        )
        code_response = self.link_control.request_patient_code("patient-a")
        self.link_control.register_patient_code(
            "guardian-a",
            code_response["data"]["patient_code"],
        )

        response = self.control.request_today_medication_schedule(
            user_hash="guardian-a",
            role="guardian",
        )

        self.assertTrue(response["success"])
        self.assertEqual(len(response["data"]), 1)
        self.assertEqual(response["data"][0]["medication_id"], str(medication.id))
        self.assertEqual(response["data"][0]["patient_hash"], "patient-a")

    def test_guardian_status_update_resolves_linked_patient_hash(self) -> None:
        medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="guardian-updated-tablet",
        )
        self._saved_medication(
            patient_hash="patient-b",
            item_name="other-tablet",
        )
        code_response = self.link_control.request_patient_code("patient-a")
        self.link_control.register_patient_code(
            "guardian-a",
            code_response["data"]["patient_code"],
        )

        response = self.control.update_medication_status(
            medication.id,
            True,
            "patient-a",
            "guardian-a",
            "guardian",
        )

        self.assertTrue(response["success"])
        self.assertEqual(response["data"]["patient_hash"], "patient-a")
        self.assertTrue(response["data"]["medication_status"])

    def test_guardian_today_schedule_without_link_stops_with_not_found(self) -> None:
        with self.assertRaises(HTTPException) as context:
            self.control.request_today_medication_schedule(
                user_hash="guardian-missing",
                role="guardian",
            )

        self.assertEqual(context.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
