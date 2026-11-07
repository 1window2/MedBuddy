# 파일명: dose_sync_operation_entity.py
# 역할: 응답 유실 후 재전송이 이후의 복용 취소를 되돌리지 않도록 처리 영수증을 보관한다.

from sqlalchemy import Column, DateTime, ForeignKey, JSON, String

from core.database import Base
from entities.medication_completion_entity import utc_now


# 클래스명: _DoseSyncOperation
# 역할: 환자별 오프라인 복용 동기화 요청의 처리 영수증을 보관한다.
# 주요 책임: 환자와 작업 ID의 복합 키로 재전송을 식별하고 저장된 요청 본문과 비교할 수 있게 한다.
# 속성: patient_hash와 operation_id는 식별 키, payload는 적용된 JSON 요청 본문, created_at은 생성 UTC 시각이다.
class _DoseSyncOperation(Base):
    __tablename__ = "dose_sync_operations"

    patient_hash = Column(String, ForeignKey("user_accounts.user_hash", ondelete="CASCADE"), primary_key=True)
    operation_id = Column(String(64), primary_key=True)
    payload = Column(JSON, nullable=False)
    created_at = Column(DateTime, nullable=False, default=utc_now)
