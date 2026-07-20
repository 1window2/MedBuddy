import asyncio
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

from controls.check_caregiver_medication_control import (  # noqa: E402
    CheckCaregiverMedication,
)
from controls.check_saved_medication_control import CheckSavedMedication  # noqa: E402
from controls.link_patient_caregiver_control import LinkPatientCaregiver  # noqa: E402
from core.database import Base  # noqa: E402
from schemas.medication import SavedMedicationCreate  # noqa: E402


class CheckCaregiverMedicationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.saved_control = CheckSavedMedication(self.db)
        self.link_control = LinkPatientCaregiver(self.db)
        self.control = CheckCaregiverMedication(self.db)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def _save_medication(self, patient_hash: str, item_name: str) -> None:
        self.saved_control.saveMedicationDetail(
            SavedMedicationCreate(
                patient_hash=patient_hash,
                prescription_date=date.today(),
                item_name=item_name,
                efficacy="effect",
                use_method="usage",
                warning_message="warning",
                dosage_per_time="1 tablet",
                daily_frequency="1 time",
                total_days="3 days",
                image_url="https://example.com/tablet.jpg",
            )
        )

    def _link(self, caregiver_hash: str, patient_hash: str) -> None:
        code = self.link_control.generatePatientHash(patient_hash)
        self.link_control.requestPatientCaregiverLink(
            caregiver_hash,
            code["data"]["patient_code"],
        )

    def test_request_honors_explicit_patient_when_caregiver_has_multiple_links(
        self,
    ) -> None:
        self._save_medication("patient-a", "A tablet")
        self._save_medication("patient-b", "B tablet")
        self._link("caregiver-a", "patient-a")
        self._link("caregiver-a", "patient-b")

        response = asyncio.run(
            self.control.requestPatientMedicationInfo(
                "caregiver-a",
                "patient-b",
            )
        )

        self.assertTrue(response["success"])
        self.assertEqual(response["data"]["caregiver_hash"], "caregiver-a")
        self.assertEqual(response["data"]["patient_hash"], "patient-b")
        self.assertEqual(
            [item["item_name"] for item in response["data"]["saved_medications"]],
            ["B tablet"],
        )
        self.assertEqual(
            [
                item["drug_name"]
                for item in response["data"]["today_medication_info"]["schedules"]
            ],
            ["B tablet"],
        )

    def test_request_rejects_unlinked_patient(self) -> None:
        self._link("caregiver-a", "patient-a")

        with self.assertRaises(HTTPException) as context:
            asyncio.run(
                self.control.requestPatientMedicationInfo(
                    "caregiver-a",
                    "patient-b",
                )
            )

        self.assertEqual(context.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
