# 파일명: caregiver_alert_outbox_entity.py
# 역할: 보호자 푸시 알림 전송 요청을 트랜잭션 아웃박스로 영속화한다.

from datetime import UTC, datetime

from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)

from core.database import Base
from entities.user_account_entity import _UserAccount  # noqa: F401


CAREGIVER_ALERT_STATUS_PENDING = "pending"
CAREGIVER_ALERT_STATUS_PROCESSING = "processing"
CAREGIVER_ALERT_STATUS_SENT = "sent"
CAREGIVER_ALERT_STATUS_FAILED = "failed"


# 함수명: utc_now
# 역할:
# - DB에 저장할 시간대 정보 없는 UTC 현재 시각을 반환한다.
def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# 클래스명: _CaregiverAlertOutbox
# 역할: 복약 완료와 같은 트랜잭션에서 생성되는 보호자 알림 전송 요청이다.
# 주요 책임:
# - 서버 재시작이나 일시적인 푸시 장애에도 전송 요청을 보존한다.
# - 같은 환자·날짜·시간대 이벤트가 중복 전송되지 않게 식별한다.
# - 재시도 횟수와 다음 시도 시각을 기록한다.
class _CaregiverAlertOutbox(Base):
    __tablename__ = "caregiver_alert_outbox"
    __table_args__ = (
        UniqueConstraint("event_key", name="uq_caregiver_alert_outbox_event_key"),
    )

    id = Column(Integer, primary_key=True, index=True)
    event_key = Column(String(64), nullable=False, index=True)
    patient_hash = Column(
        String,
        ForeignKey("user_accounts.user_hash", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    slot_key = Column(String(32), nullable=False)
    status = Column(
        String(16),
        nullable=False,
        default=CAREGIVER_ALERT_STATUS_PENDING,
        server_default=CAREGIVER_ALERT_STATUS_PENDING,
        index=True,
    )
    attempt_count = Column(Integer, nullable=False, default=0, server_default="0")
    available_at = Column(DateTime, nullable=False, default=utc_now, index=True)
    processing_started_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, default=utc_now)
    sent_at = Column(DateTime, nullable=True)
    last_error = Column(String(500), nullable=True)
