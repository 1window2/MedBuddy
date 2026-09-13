# File Name: patient_caregiver_link_entity.py
# Role: Defines persisted relationships and one-use codes with domain link state and UTC expiration serialization.

from datetime import UTC, datetime

from pydantic import BaseModel
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)

from core.database import Base
from entities.user_account_entity import _UserAccount  # noqa: F401


# Function Name: utc_now
# Description:
# - Returns naive UTC for database timestamps.
# Parameters:
# - None.
# Returns:
# - Current UTC datetime without timezone metadata.
def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# Function Name: _as_naive_utc
# Description:
# - Converts aware timestamps to UTC and removes timezone metadata; naive timestamps are already treated as UTC.
# Parameters:
# - value (datetime): Timestamp to normalize; naive inputs are already treated as UTC.
# Returns:
# - Naive UTC datetime.
def _as_naive_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone(UTC).replace(tzinfo=None)


# 클래스명: _PatientCaregiverLink
# 역할:
# - 환자·보호자 쌍별 연동 상태와 환자 별칭을 저장하고 계정 삭제에 연동한다.
# 주요 책임:
# - 연동 쌍의 유일성, 활성 상태와 보호자가 지정한 환자 별칭을 유지한다.
# 속성:
# - patient_hash (String): 작업 대상 환자의 데이터 소유 범위 식별자.
# - caregiver_hash (String): 환자와 연동된 보호자 계정 식별자.
# - patient_alias (String(20)): 보호자가 지정한 환자 표시 이름; 빈 값은 별칭 해제.
class _PatientCaregiverLink(Base):
    __tablename__ = "patient_caregiver_links"
    __table_args__ = (
        UniqueConstraint(
            "patient_hash",
            "caregiver_hash",
            name="uq_patient_caregiver_link_pair",
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    patient_hash = Column(
        String,
        ForeignKey("user_accounts.user_hash", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    caregiver_hash = Column(
        String,
        ForeignKey("user_accounts.user_hash", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    patient_alias = Column(String(20), nullable=True)
    linked = Column(Boolean, nullable=False, default=True, server_default="1")
    created_at = Column(DateTime, nullable=False, default=utc_now)


# 클래스명: _PatientLinkCode
# 역할:
# - 일회용 환자 연동 코드의 만료·사용 상태와 사용한 보호자를 저장한다.
# 주요 책임:
# - 코드의 유일성·만료·일회 사용을 추적하고 보호자 삭제 시 사용 기록의 식별자를 해제한다.
# 속성:
# - patient_hash (String): 작업 대상 환자의 데이터 소유 범위 식별자.
# - patient_code (String): 보호자 연동 등록을 위해 입력한 임시 환자 코드.
# - caregiver_hash (String): 코드를 사용한 보호자 식별자; 미사용 또는 보호자 삭제 시 None.
class _PatientLinkCode(Base):
    __tablename__ = "patient_link_codes"

    id = Column(Integer, primary_key=True, index=True)
    patient_hash = Column(
        String,
        ForeignKey("user_accounts.user_hash", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    patient_code = Column(String, nullable=False, unique=True, index=True)
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, nullable=False, default=utc_now)
    used = Column(Boolean, nullable=False, default=False, server_default="0")
    caregiver_hash = Column(
        String,
        ForeignKey("user_accounts.user_hash", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )


# Class Name: PatientLinkCode
# Role:
# - Represents one expiring code shared by a patient with a caregiver.
# Responsibilities:
# - Compare expiration consistently in UTC and expose a timezone-explicit code response.
# Attributes:
# - code (str): Temporary code shared with a caregiver for link registration.
# - patient_hash (str): Patient ownership scope for the operation.
# - expires_at (datetime): Expiration timestamp compared and serialized in UTC.
class PatientLinkCode(BaseModel):
    code: str
    patient_hash: str
    expires_at: datetime

    # Function Name: isExpired
    # Description:
    # - Compares the code expiration with a supplied or current timestamp after UTC normalization.
    # Parameters:
    # - now (datetime | None): Reference datetime for time-sensitive status or expiration checks.
    # Returns:
    # - True when the expiration is at or before the comparison time.
    def isExpired(self, now: datetime | None = None) -> bool:
        comparison_time = _as_naive_utc(now) if now is not None else utc_now()
        return _as_naive_utc(self.expires_at) <= comparison_time

    # Function Name: to_response_dict
    # Description:
    # - Serializes the temporary patient code with an explicitly UTC expiration timestamp.
    # Parameters:
    # - None.
    # Returns:
    # - Patient scope, code and ISO-formatted expiration.
    def to_response_dict(self) -> dict[str, str]:
        expires_at_utc = _as_naive_utc(self.expires_at).replace(tzinfo=UTC)
        return {
            "patient_hash": self.patient_hash,
            "patient_code": self.code,
            "expires_at": expires_at_utc.isoformat(),
        }


# 클래스명: PatientCaregiverLink
# 역할:
# - 환자·보호자 식별값과 별칭·연동 상태를 전달하며 자기 자신과의 연동을 검증한다.
# 주요 책임:
# - 서로 다른 참여자 식별자인지 확인하고 메모리상 연동 활성·해제 상태를 관리한다.
# 속성:
# - link_id (int | None): 저장된 환자·보호자 연동 식별자.
# - patient_id (str): 연동 대상 환자의 도메인 식별자.
# - patient_hash (str): 작업 대상 환자의 데이터 소유 범위 식별자.
# - caregiver_hash (str): 환자와 연동된 보호자 계정 식별자.
# - patient_alias (str | None): 보호자가 지정한 환자 표시 이름; 빈 값은 별칭 해제.
class PatientCaregiverLink(BaseModel):
    link_id: int | None = None
    patient_id: str = ""
    caregiver_id: str = ""
    patient_hash: str = ""
    caregiver_hash: str = ""
    patient_alias: str | None = None
    link_status: bool = False
    linked_at: datetime | None = None

    # Function Name: validateCaregiverHash
    # Description:
    # - Requires a nonblank caregiver identifier distinct from the patient's identifier.
    # Parameters:
    # - None.
    # Returns:
    # - True when the participant hashes can represent a valid pair.
    def validateCaregiverHash(self) -> bool:
        patient_hash = self.patient_hash.strip()
        caregiver_hash = self.caregiver_hash.strip()
        return bool(caregiver_hash) and caregiver_hash != patient_hash

    # Function Name: savePatientCaregiverLink
    # Description:
    # - Validates the participant hashes and marks this in-memory link active; persistence belongs to the control layer.
    # Parameters:
    # - None.
    # Returns:
    # - This active link entity, or ValueError for a missing or identical caregiver hash.
    def savePatientCaregiverLink(self) -> "PatientCaregiverLink":
        if not self.validateCaregiverHash():
            raise ValueError("Caregiver hash must differ from the patient hash.")
        self.link_status = True
        return self

    # Function Name: removePatientCaregiverLink
    # Description:
    # - Marks this in-memory relationship inactive without performing database persistence.
    # Parameters:
    # - None.
    # Returns:
    # - This link entity with link_status set to False.
    def removePatientCaregiverLink(self) -> "PatientCaregiverLink":
        self.link_status = False
        return self
