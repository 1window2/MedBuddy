# File Name: patient_hash_entity.py
# Role: Skeleton entity mapped from the PatientHash box in ClassDiagram2.

from pydantic import BaseModel

DEFAULT_PATIENT_HASH = "local_patient"


# Function Name: normalize_patient_hash
# Description:
# - Normalizes empty patient hashes to the local default until UC-6/7 provides real links.
# Parameters:
# - patient_hash: Raw patient hash from an API request or internal call.
# Returns:
# - Non-empty patient hash string.
def normalize_patient_hash(patient_hash: str | None) -> str:
    normalized_patient_hash = (patient_hash or "").strip()
    if normalized_patient_hash:
        return normalized_patient_hash
    return DEFAULT_PATIENT_HASH


# Class Name: PatientHash
# Role: Represents a shareable patient hash or link code.
class PatientHash(BaseModel):
    patient_hash: str = DEFAULT_PATIENT_HASH

    def generatePatientHash(self) -> str:
        raise NotImplementedError("Patient hash generation is not implemented yet.")
