# File Name: patient_caregiver_link_entity.py
# Role: Entity and persistence models mapped from PatientCaregiverLink in integrated v5.

from datetime import UTC, datetime

from pydantic import BaseModel
from sqlalchemy import Boolean, Column, DateTime, Integer, String, UniqueConstraint

from core.database import Base


def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


def _as_naive_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone(UTC).replace(tzinfo=None)


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
    patient_hash = Column(String, nullable=False, index=True)
    caregiver_hash = Column(String, nullable=False, index=True)
    linked = Column(Boolean, nullable=False, default=True, server_default="1")
    created_at = Column(DateTime, nullable=False, default=utc_now)


class _PatientLinkCode(Base):
    __tablename__ = "patient_link_codes"

    id = Column(Integer, primary_key=True, index=True)
    patient_hash = Column(String, nullable=False, index=True)
    patient_code = Column(String, nullable=False, unique=True, index=True)
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, nullable=False, default=utc_now)
    used = Column(Boolean, nullable=False, default=False, server_default="0")
    caregiver_hash = Column(String, nullable=True, index=True)


# Class Name: PatientLinkCode
# Role: Represents one expiring code shared by a patient with a caregiver.
class PatientLinkCode(BaseModel):
    code: str
    patient_hash: str
    expires_at: datetime

    def isExpired(self, now: datetime | None = None) -> bool:
        comparison_time = _as_naive_utc(now) if now is not None else utc_now()
        return _as_naive_utc(self.expires_at) <= comparison_time

    def to_response_dict(self) -> dict[str, str]:
        expires_at_utc = _as_naive_utc(self.expires_at).replace(tzinfo=UTC)
        return {
            "patient_hash": self.patient_hash,
            "patient_code": self.code,
            "expires_at": expires_at_utc.isoformat(),
        }


# Class Name: PatientCaregiverLink
# Role: Represents a patient-caregiver relationship.
class PatientCaregiverLink(BaseModel):
    link_id: int | None = None
    patient_id: str = ""
    caregiver_id: str = ""
    patient_hash: str = ""
    caregiver_hash: str = ""
    link_status: bool = False
    linked_at: datetime | None = None

    def validateCaregiverHash(self) -> bool:
        patient_hash = self.patient_hash.strip()
        caregiver_hash = self.caregiver_hash.strip()
        return bool(caregiver_hash) and caregiver_hash != patient_hash

    def savePatientCaregiverLink(self) -> "PatientCaregiverLink":
        if not self.validateCaregiverHash():
            raise ValueError("Caregiver hash must differ from the patient hash.")
        self.link_status = True
        return self

    def removePatientCaregiverLink(self) -> "PatientCaregiverLink":
        self.link_status = False
        return self
