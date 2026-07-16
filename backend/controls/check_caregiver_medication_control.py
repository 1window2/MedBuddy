# File Name: check_caregiver_medication_control.py
# Role: Control mapped from CheckCaregiverMedication in integrated class diagram v5.

from sqlalchemy.orm import Session

from controls.check_saved_medication_control import CheckSavedMedication
from controls.check_today_medication_info_control import CheckTodayMedicationInfo
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from entities.patient_hash_entity import normalize_patient_hash


# Class Name: CheckCaregiverMedication
# Role: Provides read-only medication information for one linked patient.
# Responsibilities:
#   - Validate the selected caregiver-patient relationship.
#   - Compose saved medication and today's schedule information.
#   - Keep caregiver reads separate from patient mutation controls.
class CheckCaregiverMedication:
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
    # - Returns medication information for an explicitly selected linked patient.
    async def requestPatientMedicationInfo(
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
            await self.check_saved_medication.requestSavedMedicationInfoWithImages(
                normalized_patient_hash,
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
