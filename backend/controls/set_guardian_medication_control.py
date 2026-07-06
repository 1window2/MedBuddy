# File Name: set_guardian_medication_control.py
# Role: Control class mapped from the SetGuardianMedication box in ClassDiagram2.

from sqlalchemy.orm import Session

from controls.check_saved_medication_control import CheckSavedMedication
from controls.check_today_medication_info_control import CheckTodayMedicationInfo
from controls.patient_guardian_link_control import PatientGuardianLinkControl
from entities.patient_hash_entity import normalize_patient_hash


# Class Name: SetGuardianMedication
# Role: Coordinates guardian medication visibility for one linked patient.
# Responsibilities:
#   - Validate the guardian-patient link before exposing medication data.
#   - Return saved medication details and today's schedule summary from existing controls.
#   - Keep guardian medication reads separate from guardian alert setting persistence.
# Attributes:
#   - db: SQLAlchemy session shared by delegated controls.
class SetGuardianMedication:
    def __init__(
        self,
        db: Session,
        check_saved_medication: CheckSavedMedication | None = None,
        check_today_medication_info: CheckTodayMedicationInfo | None = None,
        link_control: PatientGuardianLinkControl | None = None,
    ) -> None:
        self.db = db
        self.check_saved_medication = check_saved_medication or CheckSavedMedication(db)
        self.check_today_medication_info = (
            check_today_medication_info or CheckTodayMedicationInfo(db)
        )
        self.link_control = link_control or PatientGuardianLinkControl(db)

    # Function Name: requestGuardianMedication
    # Description:
    # - Class diagram compatible wrapper for guardian medication lookup.
    # Parameters:
    # - guardian_hash: Guardian ownership key.
    # - patient_hash: Selected linked patient ownership key.
    # Returns:
    # - API-compatible guardian medication response dictionary.
    def requestGuardianMedication(
        self,
        guardian_hash: str,
        patient_hash: str,
    ) -> dict[str, object]:
        return self.request_guardian_medication(guardian_hash, patient_hash)

    # Function Name: request_guardian_medication
    # Description:
    # - Reads medication data that a linked guardian is allowed to inspect.
    # Parameters:
    # - guardian_hash: Guardian ownership key.
    # - patient_hash: Selected linked patient ownership key.
    # Returns:
    # - API-compatible guardian medication response dictionary.
    def request_guardian_medication(
        self,
        guardian_hash: str,
        patient_hash: str,
    ) -> dict[str, object]:
        normalized_guardian_hash = normalize_patient_hash(guardian_hash)
        normalized_patient_hash = self.link_control.get_linked_patient_hash(
            normalized_guardian_hash,
            patient_hash,
        )
        saved_medication_response = (
            self.check_saved_medication.request_saved_medication_info(
                normalized_patient_hash,
                None,
                "patient",
            )
        )
        today_info_response = self.check_today_medication_info.request_today_medication_info(
            normalized_patient_hash,
            None,
            "patient",
        )

        return {
            "success": True,
            "message": "Guardian medication lookup succeeded.",
            "data": {
                "guardian_hash": normalized_guardian_hash,
                "patient_hash": normalized_patient_hash,
                "saved_medications": saved_medication_response.get("data", []),
                "today_medication_info": today_info_response.get("data", {}),
            },
        }
