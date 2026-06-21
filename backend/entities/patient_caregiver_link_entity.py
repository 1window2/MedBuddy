# 파일명: patient_caregiver_link_entity.py
# 역할: ClassDiagram2의 PatientCaregiverLink에 대응하는 엔티티와 저장 모델을 정의한다.

from datetime import datetime

from pydantic import BaseModel
from sqlalchemy import Boolean, Column, DateTime, Integer, String, UniqueConstraint

from core.database import Base


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
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class _PatientLinkCode(Base):
    __tablename__ = "patient_link_codes"

    id = Column(Integer, primary_key=True, index=True)
    patient_hash = Column(String, nullable=False, index=True)
    patient_code = Column(String, nullable=False, unique=True, index=True)
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    used = Column(Boolean, nullable=False, default=False, server_default="0")
    caregiver_hash = Column(String, nullable=True, index=True)


# 클래스명: PatientCaregiverLink
# 역할: a patient-caregiver relationship을 표현한다.
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
