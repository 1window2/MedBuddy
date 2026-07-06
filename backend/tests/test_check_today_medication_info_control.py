# File Name: test_check_today_medication_info_control.py
# Role: Verifies today's medication summary control.

import sys
import unittest
from datetime import date
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.check_schedule_control import CheckSchedule  # noqa: E402
from controls.check_today_medication_info_control import (  # noqa: E402
    CheckTodayMedicationInfo,
)
from controls.patient_guardian_link_control import PatientGuardianLinkControl  # noqa: E402
from core.database import Base  # noqa: E402
from entities.medication_completion_entity import (  # noqa: E402
    _MedicationCompletion,
    ensure_medication_completion_schema,
)
from entities.saved_medication_entity import (  # noqa: E402
    _SavedMedication,
    ensure_saved_medication_schema,
)


class CheckTodayMedicationInfoTest(unittest.TestCase):
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
        self.schedule_control = CheckSchedule(self.db)
        self.link_control = PatientGuardianLinkControl(self.db)
        self.control = CheckTodayMedicationInfo(
            self.db,
            check_schedule=self.schedule_control,
        )

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def _saved_medication(
        self,
        *,
        patient_hash: str = "patient-a",
        item_name: str = "test-tablet",
        daily_frequency: str = "3 times",
    ) -> _SavedMedication:
        medication = _SavedMedication(
            patient_hash=patient_hash,
            created_date=date.today(),
            prescription_date=date.today(),
            item_name=item_name,
            dosage_per_time="1 tablet",
            daily_frequency=daily_frequency,
            total_days="7 days",
            medication_status=False,
        )
        self.db.add(medication)
        self.db.commit()
        self.db.refresh(medication)
        return medication

    def test_today_medication_info_counts_slot_level_progress(self) -> None:
        medication = self._saved_medication()
        self.db.add(
            _MedicationCompletion(
                saved_medication_id=medication.id,
                patient_hash="patient-a",
                schedule_date=date.today(),
                slot_key="morning",
                completed=True,
            )
        )
        self.db.commit()

        response = self.control.request_today_medication_info("patient-a")

        self.assertTrue(response["success"])
        data = response["data"]
        self.assertEqual(data["patient_hash"], "patient-a")
        self.assertEqual(data["medication_count"], 1)
        self.assertEqual(data["total_dose_count"], 3)
        self.assertEqual(data["completed_dose_count"], 1)
        self.assertEqual(data["remaining_dose_count"], 2)
        self.assertAlmostEqual(data["progress_ratio"], 1 / 3)
        self.assertEqual(len(data["schedules"]), 1)

    def test_guardian_scope_is_resolved_before_summary_lookup(self) -> None:
        self._saved_medication(
            patient_hash="patient-a",
            item_name="guardian-visible-tablet",
            daily_frequency="1 time",
        )
        self._saved_medication(
            patient_hash="patient-b",
            item_name="other-tablet",
            daily_frequency="1 time",
        )
        code_response = self.link_control.request_patient_code("patient-a")
        self.link_control.register_patient_code(
            "guardian-a",
            code_response["data"]["patient_code"],
        )

        response = self.control.request_today_medication_info(
            "patient-a",
            "guardian-a",
            "guardian",
        )

        data = response["data"]
        self.assertEqual(data["patient_hash"], "patient-a")
        self.assertEqual(data["medication_count"], 1)
        self.assertEqual(
            data["schedules"][0]["drug_name"],
            "guardian-visible-tablet",
        )


if __name__ == "__main__":
    unittest.main()
