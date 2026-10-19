# 파일명: medication_care_entity.py
# 역할: 약 변경·복용 기록의 재전송 영수증과 수정 이력을 환자 범위로 보관한다.

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint

from core.database import Base
from entities.user_account_entity import utc_now


# 클래스명: _MedicationCareOperation
# 역할: 같은 작업 식별자의 재전송을 중복 저장 없이 처리한다.
# 주요 책임: 요청 서명과 성공 응답을 같은 변경 트랜잭션에 보관한다.
# 속성: patient_hash: 소유자, operation_id: 클라이언트 UUID, request_hash: 요청 서명, response_json: 응답.
class _MedicationCareOperation(Base):
    __tablename__ = "medication_care_operations"
    __table_args__ = (UniqueConstraint("patient_hash", "operation_id", name="uq_care_operation_owner"),)
    id = Column(Integer, primary_key=True)
    patient_hash = Column(String, ForeignKey("user_accounts.user_hash", ondelete="CASCADE"), nullable=False, index=True)
    operation_id = Column(String(36), nullable=False)
    request_hash = Column(String(64), nullable=False)
    response_json = Column(Text, nullable=False)
    created_at = Column(DateTime, nullable=False, default=utc_now)


# 클래스명: _MedicationCareAudit
# 역할: 복용 기록과 약 변경의 이전 값·새 값을 보존한다.
# 주요 책임: 사용자 정정과 기존 완료 API의 변경을 같은 이력으로 남긴다.
# 속성: medication_id: 약, kind: 변경 종류, before_json/after_json: 변경 내용, recorded_at: 서버 기록 시각.
class _MedicationCareAudit(Base):
    __tablename__ = "medication_care_audits"
    id = Column(Integer, primary_key=True)
    patient_hash = Column(String, ForeignKey("user_accounts.user_hash", ondelete="CASCADE"), nullable=False, index=True)
    medication_id = Column(Integer, ForeignKey("saved_medications.id", ondelete="CASCADE"), nullable=False, index=True)
    kind = Column(String(32), nullable=False)
    before_json = Column(Text, nullable=False)
    after_json = Column(Text, nullable=False)
    recorded_at = Column(DateTime, nullable=False, default=utc_now)
