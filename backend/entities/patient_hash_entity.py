# File Name: patient_hash_entity.py
# Role: Provides secure patient link-code generation and allowed-format validation alongside patient scope data.

import secrets
import string

from pydantic import BaseModel

DEFAULT_PATIENT_HASH = "local_patient"
MAX_PATIENT_HASH_LENGTH = 128
PATIENT_LINK_CODE_LENGTH = 8
_PATIENT_LINK_CODE_ALPHABET = string.ascii_uppercase + string.digits


# Function Name: normalize_patient_hash
# Description:
# - Normalizes empty patient hashes to the local default until UC-6/7 provides real links.
# Parameters:
# - patient_hash (str | None): Raw patient hash from an API request or internal call.
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
# Parameters:
# - None.
# Returns:
# - Random uppercase alphanumeric patient link code.
def generate_patient_link_code() -> str:
    return "".join(
        secrets.choice(_PATIENT_LINK_CODE_ALPHABET)
        for _ in range(PATIENT_LINK_CODE_LENGTH)
    )


# Class Name: PatientHash
# Role:
# - Represents a shareable patient hash or link code.
# Responsibilities:
# - Generate secure fixed-length link codes and validate their allowed alphabet without claiming account ownership.
# Attributes:
# - patient_hash (str): Patient ownership scope for the operation.
class PatientHash(BaseModel):
    patient_hash: str = DEFAULT_PATIENT_HASH

    # Function Name: createPatientHash
    # Description:
    # - Generates a secure temporary caregiver-link code using the shared code policy.
    # Parameters:
    # - None.
    # Returns:
    # - Newly generated patient link code, not a persisted account hash.
    def createPatientHash(self) -> str:
        return generate_patient_link_code()

    # Function Name: validatePatientHash
    # Description:
    # - Normalizes a candidate and checks the fixed length and uppercase alphanumeric code alphabet.
    # Parameters:
    # - candidate (str): User-supplied temporary patient link code.
    # Returns:
    # - True when the candidate has a supported link-code shape.
    def validatePatientHash(self, candidate: str) -> bool:
        normalized_candidate = (candidate or "").strip().upper()
        return (
            len(normalized_candidate) == PATIENT_LINK_CODE_LENGTH
            and all(
                character in _PATIENT_LINK_CODE_ALPHABET
                for character in normalized_candidate
            )
        )
