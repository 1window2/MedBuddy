# File Name: test_set_guardian_medication_control.py
# Role: Verifies guardian medication lookup orchestration.

import sys
import unittest
from datetime import date
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.patient_guardian_link_control import PatientGuardianLinkControl  # noqa: E402
from controls.set_guardian_medication_control import SetGuardianMedication  # noqa: E402
from core.database import Base  # noqa: E402
from entities.medication_completion_entity import (  # noqa: E402
    ensure_medication_completion_schema,
)
from entities.saved_medication_entity import (  # noqa: E402
    _SavedMedication,
    ensure_saved_medication_schema,
)


class SetGuardianMedicationTest(unittest.TestCase):
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
        self.link_control = PatientGuardianLinkControl(self.db)
        self.control = SetGuardianMedication(self.db)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def _link_guardian(self) -> None:
        code_response = self.link_control.request_patient_code("patient-a")
        self.link_control.register_patient_code(
            "guardian-a",
            code_response["data"]["patient_code"],
        )

    def _saved_medication(self) -> _SavedMedication:
        medication = _SavedMedication(
            patient_hash="patient-a",
            created_date=date.today(),
            prescription_date=date.today(),
            item_name="guardian-visible-tablet",
            dosage_per_time="1 tablet",
            daily_frequency="2 times",
            total_days="5 days",
            medication_status=False,
        )
        self.db.add(medication)
        self.db.commit()
        self.db.refresh(medication)
        return medication

    def test_guardian_medication_returns_saved_list_and_today_info(self) -> None:
        self._link_guardian()
        self._saved_medication()

        response = self.control.request_guardian_medication(
            "guardian-a",
            "patient-a",
        )

        self.assertTrue(response["success"])
        data = response["data"]
        self.assertEqual(data["guardian_hash"], "guardian-a")
        self.assertEqual(data["patient_hash"], "patient-a")
        self.assertEqual(len(data["saved_medications"]), 1)
        self.assertEqual(
            data["saved_medications"][0]["item_name"],
            "guardian-visible-tablet",
        )
        self.assertEqual(data["today_medication_info"]["total_dose_count"], 2)

    def test_unlinked_guardian_cannot_read_medication(self) -> None:
        with self.assertRaises(HTTPException) as context:
            self.control.request_guardian_medication("guardian-a", "patient-a")

        self.assertEqual(context.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
