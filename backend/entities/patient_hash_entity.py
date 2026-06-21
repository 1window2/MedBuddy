# 파일명: patient_hash_entity.py
# 역할: ClassDiagram2의 PatientHash 박스에 대응하는 엔티티이다.

import secrets
import string

from pydantic import BaseModel

DEFAULT_PATIENT_HASH = "local_patient"
PATIENT_LINK_CODE_LENGTH = 8
_PATIENT_LINK_CODE_ALPHABET = string.ascii_uppercase + string.digits


# 함수명: normalize_patient_hash
# 함수역할:
# - Normalizes empty patient hashes to the local default until UC-6/7 provides real links.
# 매개변수:
# - patient_hash: API 요청 또는 내부 호출에서 전달된 원본 환자 해시
# 반환값:
# - Non-empty patient hash string.
def normalize_patient_hash(patient_hash: str | None) -> str:
    normalized_patient_hash = (patient_hash or "").strip()
    if normalized_patient_hash:
        return normalized_patient_hash
    return DEFAULT_PATIENT_HASH


# 함수명: generate_patient_link_code
# 함수역할:
# - Generates a short share code for UC-6 patient-caregiver linking.
# 반환값:
# - Random uppercase alphanumeric patient link code.
def generate_patient_link_code() -> str:
    return "".join(
        secrets.choice(_PATIENT_LINK_CODE_ALPHABET)
        for _ in range(PATIENT_LINK_CODE_LENGTH)
    )


# 클래스명: PatientHash
# 역할: a shareable patient hash or link code을 표현한다.
class PatientHash(BaseModel):
    patient_hash: str = DEFAULT_PATIENT_HASH

    def generatePatientHash(self) -> str:
        return generate_patient_link_code()
