# File Name: test_check_caregiver_medication_control.py
# Role: Regression coverage for caregiver medication queries across multiple active patient
#   links.
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


# Class Name: CheckCaregiverMedicationTest
# Role: Isolated caregiver medication tests covering explicit patient selection and unlinked
#   access.
# Responsibilities:
# - Saves a three-day medication snapshot with the requested patient and product name for
#   caregiver queries.
# - Requires an explicitly selected linked patient to determine both saved medications and
#   today's schedules.
# - Requires querying an unlinked patient to raise HTTP 404.
# Attributes:
# - engine (Engine): Isolated in-memory SQLite engine.
# - db (Session): SQLAlchemy session holding only this test's database state.
# - saved_control (CheckSavedMedication): Saved-medication control used to seed patient
#   snapshots.
# - link_control (LinkPatientCaregiver): Linking control used to create the fixture's
#   patient-caregiver relationships.
# - control (CheckCaregiverMedication): Use-case control under test, isolated from production
#   state.
class CheckCaregiverMedicationTest(unittest.TestCase):
    # Function Name: setUp
    # Description:
    # - Creates an in-memory database and saved-medication, linking, and caregiver-query
    #   controls for each case.
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
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.saved_control = CheckSavedMedication(self.db)
        self.link_control = LinkPatientCaregiver(self.db)
        self.control = CheckCaregiverMedication(self.db)

    # Function Name: tearDown
    # Description:
    # - Closes the test session and disposes its in-memory database engine.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # Function Name: _save_medication
    # Description:
    # - Saves a three-day medication snapshot with the requested patient and product name
    #   for caregiver queries.
    # Parameters:
    # - patient_hash (str): Patient owner identifying the medication or linked-data scope.
    # - item_name (str): Product name in the authoritative or saved medication record.
    # Returns:
    # - None.
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
                image_url="https://nedrug.mfds.go.kr/tablet.jpg",
            )
        )

    # Function Name: _link
    # Description:
    # - Generates a patient's link code and connects the supplied caregiver through the
    #   normal linking control.
    # Parameters:
    # - caregiver_hash (str): Caregiver identity used to scope links or notification
    #   settings.
    # - patient_hash (str): Patient owner identifying the medication or linked-data scope.
    # Returns:
    # - None.
    def _link(self, caregiver_hash: str, patient_hash: str) -> None:
        code = self.link_control.generatePatientHash(patient_hash)
        self.link_control.requestPatientCaregiverLink(
            caregiver_hash,
            code["data"]["patient_code"],
        )

    # Function Name: test_request_honors_explicit_patient_when_caregiver_has_multiple_links
    # Description:
    # - Requires an explicitly selected linked patient to determine both saved medications
    #   and today's schedules.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_request_honors_explicit_patient_when_caregiver_has_multiple_links(
        self,
    ) -> None:
        self._save_medication("patient-a", "A tablet")
        self._save_medication("patient-b", "B tablet")
        self._link("caregiver-a", "patient-a")
        self._link("caregiver-a", "patient-b")

        response = self.control.requestPatientMedicationInfo(
            "caregiver-a",
            "patient-b",
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

    # Function Name: test_request_rejects_unlinked_patient
    # Description:
    # - Requires querying an unlinked patient to raise HTTP 404.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_request_rejects_unlinked_patient(self) -> None:
        self._link("caregiver-a", "patient-a")

        with self.assertRaises(HTTPException) as context:
            self.control.requestPatientMedicationInfo(
                "caregiver-a",
                "patient-b",
            )

        self.assertEqual(context.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
