# File Name: check_caregiver_medication_control.py
# Role: Combines a linked patient's saved medications and daily summary for read-only caregiver access.

from sqlalchemy.orm import Session

from controls.check_saved_medication_control import CheckSavedMedication
from controls.check_today_medication_info_control import CheckTodayMedicationInfo
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from entities.patient_hash_entity import normalize_patient_hash


# Class Name: CheckCaregiverMedication
# Role:
# - Provides read-only medication information for one linked patient.
# Responsibilities:
# - Validate the selected caregiver-patient relationship.
# - Compose saved medication and today's schedule information.
# - Keep caregiver reads separate from patient mutation controls.
# Attributes:
# - check_saved_medication (CheckSavedMedication): Control for patient-owned pillbox snapshots.
# - check_today_medication_info (CheckTodayMedicationInfo): Control for daily dose counts and progress.
# - link_patient_caregiver (LinkPatientCaregiver): Control for temporary codes and active patient-caregiver links.
class CheckCaregiverMedication:
    # Function Name: __init__
    # Description:
    # - Binds saved-medication, daily-summary and link controls to the supplied session.
    # Parameters:
    # - db (Session): SQLAlchemy session for this unit of work.
    # - check_saved_medication (CheckSavedMedication | None): Control for patient-owned pillbox snapshots.
    # - check_today_medication_info (CheckTodayMedicationInfo | None): Control for daily dose counts and progress.
    # - link_patient_caregiver (LinkPatientCaregiver | None): Control for temporary codes and active patient-caregiver links.
    # Returns:
    # - None.
    def __init__(
        self,
        db: Session,
        check_saved_medication: CheckSavedMedication | None = None,
        check_today_medication_info: CheckTodayMedicationInfo | None = None,
        link_patient_caregiver: LinkPatientCaregiver | None = None,
    ) -> None:
        self.check_saved_medication = (
            check_saved_medication or CheckSavedMedication(db)
        )
        self.check_today_medication_info = (
            check_today_medication_info or CheckTodayMedicationInfo(db)
        )
        self.link_patient_caregiver = (
            link_patient_caregiver or LinkPatientCaregiver(db)
        )

    # Function Name: requestPatientMedicationInfo
    # Description:
    # - Verifies the selected patient link and combines saved medications with today's read-only dose summary.
    # Parameters:
    # - caregiver_hash (str): Caregiver account participating in the patient link.
    # - patient_hash (str): Patient ownership scope for the operation.
    # Returns:
    # - Success envelope containing caregiver/patient scopes, saved medications and today's summary.
    def requestPatientMedicationInfo(
        self,
        caregiver_hash: str,
        patient_hash: str,
    ) -> dict[str, object]:
        normalized_caregiver_hash = normalize_patient_hash(caregiver_hash)
        normalized_patient_hash = self.link_patient_caregiver.getLinkedPatientHash(
            normalized_caregiver_hash,
            patient_hash,
        )
        saved_medication_response = (
            self.check_saved_medication.requestSavedMedicationInfo(
                normalized_patient_hash
            )
        )
        today_info_response = (
            self.check_today_medication_info.requestTodayMedicationInfo(
                normalized_patient_hash,
            )
        )

        return {
            "success": True,
            "message": "Caregiver medication lookup succeeded.",
            "data": {
                "caregiver_hash": normalized_caregiver_hash,
                "guardian_hash": normalized_caregiver_hash,
                "patient_hash": normalized_patient_hash,
                "saved_medications": saved_medication_response.get("data", []),
                "today_medication_info": today_info_response.get("data", {}),
            },
        }
