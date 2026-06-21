# 파일명: test_check_schedule_control.py
# 역할: 오늘의 복약 일정 조회와 복약 완료 상태 변경 control을 검증한다.

import sys
import unittest
from datetime import date, timedelta
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.check_schedule_control import CheckSchedule  # noqa: E402
from controls.link_patient_caregiver_control import LinkPatientCaregiver  # noqa: E402
from core.database import Base  # noqa: E402
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
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.control = CheckSchedule(self.db)
        self.link_control = LinkPatientCaregiver(self.db)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def _saved_medication(
        self,
        *,
        patient_hash: str = "patient-a",
        item_name: str = "test-tablet",
        created_date: date | None = None,
        total_days: str | None = "7 days",
        medication_status: bool = False,
    ) -> _SavedMedication:
        medication = _SavedMedication(
            patient_hash=patient_hash,
            created_date=created_date or date.today(),
            item_name=item_name,
            efficacy="effect",
            use_method="usage",
            warning_message="warning",
            dosage_per_time="1 tablet",
            daily_frequency="3 times",
            total_days=total_days,
            medication_status=medication_status,
            ai_guide="guide",
        )
        self.db.add(medication)
        self.db.commit()
        self.db.refresh(medication)
        return medication

    def test_today_schedule_is_scoped_and_filters_expired_medications(self) -> None:
        today = date.today()
        active_medication = self._saved_medication(
            patient_hash="patient-a",
            item_name="active-tablet",
            created_date=today,
        )
        self._saved_medication(
            patient_hash="patient-a",
            item_name="expired-tablet",
            created_date=today - timedelta(days=8),
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
        self.assertEqual(schedule["created_date"], today.isoformat())

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

    def test_empty_patient_hash_falls_back_to_default_hash(self) -> None:
        medication = self._saved_medication(patient_hash=DEFAULT_PATIENT_HASH)

        response = self.control.request_today_medication_schedule(" ")

        self.assertTrue(response["success"])
        self.assertEqual(response["data"][0]["medication_id"], str(medication.id))

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

    def test_guardian_today_schedule_without_link_stops_with_not_found(self) -> None:
        with self.assertRaises(HTTPException) as context:
            self.control.request_today_medication_schedule(
                user_hash="guardian-missing",
                role="guardian",
            )

        self.assertEqual(context.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
