# 파일명: dose_sync_operation_entity.py
# 역할: 응답 유실 후 재전송이 이후의 복용 취소를 되돌리지 않도록 처리 영수증을 보관한다.

from sqlalchemy import Column, DateTime, ForeignKey, JSON, String

from core.database import Base
from entities.medication_completion_entity import utc_now


# 클래스명: _DoseSyncOperation
# 역할: 환자와 요청 ID의 복합 키로 같은 요청의 중복 반영을 막는다.
# 속성: patient_hash - 소유 환자, operation_id - 요청 ID,
#       payload - 원본 요청, created_at - 서버 저장 시각.
class _DoseSyncOperation(Base):
    __tablename__ = "dose_sync_operations"

    patient_hash = Column(String, ForeignKey("user_accounts.user_hash", ondelete="CASCADE"), primary_key=True)
    operation_id = Column(String(64), primary_key=True)
    payload = Column(JSON, nullable=False)
    created_at = Column(DateTime, nullable=False, default=utc_now)
