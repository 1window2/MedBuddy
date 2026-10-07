# File Name: medication_completion_entity.py
# Role: Defines per-dose completion persistence and UML-compatible completion data accessors.

from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Column,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)
from pydantic import BaseModel

from core.application_clock import application_today
from core.database import Base
from entities.medication_schedule_entity import DEFAULT_MEDICATION_SCHEDULE_SLOT_KEY
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH
from entities.user_account_entity import _UserAccount, utc_now  # noqa: F401


# 클래스명: _MedicationCompletion
# 역할:
# - 저장 약·환자·날짜·시간대별 완료 기록을 유일하게 저장하고 약 또는 계정 삭제 시 함께 제거한다.
# 주요 책임:
# - 날짜와 시간대 단위의 복용 이력을 유지하고 약·계정 외래키로 고아 기록을 방지한다.
# 속성:
# - saved_medication_id (Integer): 해당 복용 기록이 참조하는 저장 약 행 식별자.
# - patient_hash (String): 작업 대상 환자의 데이터 소유 범위 식별자.
# - schedule_date (Date): 복용 완료 상태가 적용되는 일정 날짜.
# - slot_key (String): morning, lunch, evening, bedtime 중 복용 시간대 키.
# - completed (Boolean): 해당 복용 시간대의 복용 완료 여부.
# - completed_at (DateTime): 기록된 경우 복용 완료 시각.
class _MedicationCompletion(Base):
    __tablename__ = "medication_completions"
    __table_args__ = (
        UniqueConstraint(
            "saved_medication_id",
            "patient_hash",
            "schedule_date",
            "slot_key",
            name="uq_medication_completion_slot",
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    saved_medication_id = Column(
        Integer,
        ForeignKey("saved_medications.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    patient_hash = Column(
        String,
        ForeignKey("user_accounts.user_hash", ondelete="CASCADE"),
        index=True,
        nullable=False,
        default=DEFAULT_PATIENT_HASH,
        server_default=DEFAULT_PATIENT_HASH,
    )
    schedule_date = Column(Date, index=True, nullable=False, default=application_today)
    slot_key = Column(String, index=True, nullable=False)
    completed = Column(Boolean, nullable=False, default=True, server_default="1")
    completed_at = Column(DateTime, nullable=True, default=utc_now)


# Class Name: MedicationCompletion
# Role:
# - Public slot-completion extension to the v5 MedicationSchedule model.
# Responsibilities:
# - Preserve the patient, medicine, time slot, and completion timestamp names used by the schedule and completion flows.
# - Build the internal persistence row without exposing SQLAlchemy details to control code.
# Attributes:
# - completion_id (int | None): Persisted completion identifier.
# - patient_hash (str): Patient ownership key.
# - medicine_name (str): Human-readable medication name from the schedule item.
# - time_slot (str): Schedule time slot such as morning or evening.
# - completed_at (datetime | None): Timestamp when the slot was marked complete.
# - completed (bool): Whether this slot is currently marked complete.
class MedicationCompletion(BaseModel):
    completion_id: int | None = None
    patient_hash: str = DEFAULT_PATIENT_HASH
    medicine_name: str = ""
    time_slot: str = DEFAULT_MEDICATION_SCHEDULE_SLOT_KEY
    completed_at: datetime | None = None
    completed: bool = True

    # Function Name: completionId
    # Description:
    # - Reads the stored persisted dose-completion record identifier, if assigned.
    # Parameters:
    # - None.
    # Returns:
    # - Persisted dose-completion record identifier, if assigned.
    @property
    def completionId(self) -> int | None:
        return self.completion_id

    # Function Name: patientHash
    # Description:
    # - Reads the stored patient ownership scope for the operation.
    # Parameters:
    # - None.
    # Returns:
    # - Patient ownership scope for the operation.
    @property
    def patientHash(self) -> str:
        return self.patient_hash

    # Function Name: medicineName
    # Description:
    # - Reads the stored medication display name attached to the completion.
    # Parameters:
    # - None.
    # Returns:
    # - Medication display name attached to the completion.
    @property
    def medicineName(self) -> str:
        return self.medicine_name

    # Function Name: timeSlot
    # Description:
    # - Reads the stored medication time slot associated with this dose.
    # Parameters:
    # - None.
    # Returns:
    # - Medication time slot associated with this dose.
    @property
    def timeSlot(self) -> str:
        return self.time_slot

    # Function Name: completedAt
    # Description:
    # - Reads the stored time the dose was marked complete, if available.
    # Parameters:
    # - None.
    # Returns:
    # - Time the dose was marked complete, if available.
    @property
    def completedAt(self) -> datetime | None:
        return self.completed_at

    # Function Name: insertMedicationCompletion
    # Description:
    # - Creates the internal persistence row for this slot completion entity.
    # Parameters:
    # - saved_medication_id (int): Saved medication row id connected to this schedule slot.
    # - schedule_date (date): Date represented by this schedule slot.
    # Returns:
    # - SQLAlchemy _MedicationCompletion row ready to be added by a control.
    def insertMedicationCompletion(
        self,
        saved_medication_id: int,
        schedule_date: date,
    ) -> _MedicationCompletion:
        return _MedicationCompletion(
            saved_medication_id=saved_medication_id,
            patient_hash=self.patient_hash,
            schedule_date=schedule_date,
            slot_key=self.time_slot,
            completed=self.completed,
            completed_at=self.completed_at,
        )

