# File Name: patient_caregiver_link_entity.py
# Role: Entity and persistence models mapped from PatientCaregiverLink in ClassDiagram2.

from datetime import UTC, datetime

from pydantic import BaseModel
from sqlalchemy import Boolean, Column, DateTime, Integer, String, UniqueConstraint

from core.database import Base


def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


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


# Class Name: PatientCaregiverLink
# Role: Represents a patient-caregiver relationship.
class PatientCaregiverLink(BaseModel):
    link_id: int | None = None
    patient_id: str = ""
    caregiver_id: str = ""
    linked: bool = False

    def createPatientCaregiverLink(self) -> "PatientCaregiverLink":
        self.linked = True
        return self

    def deletePatientCaregiverLink(self) -> "PatientCaregiverLink":
        self.linked = False
        return self
