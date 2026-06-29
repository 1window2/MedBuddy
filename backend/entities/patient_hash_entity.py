# File Name: patient_hash_entity.py
# Role: Entity mapped from the PatientHash box in ClassDiagram2.

import secrets
import string

from pydantic import BaseModel

DEFAULT_PATIENT_HASH = "local_patient"
PATIENT_LINK_CODE_LENGTH = 8
_PATIENT_LINK_CODE_ALPHABET = string.ascii_uppercase + string.digits


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


# Function Name: generate_patient_link_code
# Description:
# - Generates a short share code for UC-6 patient-caregiver linking.
# Returns:
# - Random uppercase alphanumeric patient link code.
def generate_patient_link_code() -> str:
    return "".join(
        secrets.choice(_PATIENT_LINK_CODE_ALPHABET)
        for _ in range(PATIENT_LINK_CODE_LENGTH)
    )


# Class Name: PatientHash
# Role: Represents a shareable patient hash or link code.
class PatientHash(BaseModel):
    patient_hash: str = DEFAULT_PATIENT_HASH

    def generatePatientHash(self) -> str:
        return generate_patient_link_code()
