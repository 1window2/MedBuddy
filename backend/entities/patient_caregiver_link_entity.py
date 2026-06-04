# File Name: patient_caregiver_link_entity.py
# Role: Skeleton entity mapped from the PatientCaregiverLink box in ClassDiagram2.

from pydantic import BaseModel


# Class Name: PatientCaregiverLink
# Role: Represents a patient-caregiver relationship.
class PatientCaregiverLink(BaseModel):
    patient_id: str = ""
    caregiver_id: str = ""
    linked: bool = False

    def createPatientCaregiverLink(self) -> None:
        raise NotImplementedError("Patient-caregiver linking is not implemented yet.")

    def deletePatientCaregiverLink(self) -> None:
        raise NotImplementedError("Patient-caregiver unlinking is not implemented yet.")
