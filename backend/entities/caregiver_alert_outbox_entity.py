# 파일명: caregiver_alert_outbox_entity.py
# 역할: 보호자 푸시 알림 전송 요청을 트랜잭션 아웃박스로 영속화한다.

from datetime import UTC, datetime

from sqlalchemy import (
    Column,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    inspect,
    text,
)

from sqlalchemy.engine import Engine

from core.database import Base
from entities.user_account_entity import _UserAccount  # noqa: F401


CAREGIVER_ALERT_STATUS_PENDING = "pending"
CAREGIVER_ALERT_STATUS_PROCESSING = "processing"
CAREGIVER_ALERT_STATUS_SENT = "sent"
CAREGIVER_ALERT_STATUS_FAILED = "failed"
CAREGIVER_ALERT_STATUS_DEAD_LETTER = "dead_letter"
CAREGIVER_ALERT_EVENT_DOSE_COMPLETED = "dose_completed"
CAREGIVER_ALERT_EVENT_MISSED_DEADLINE = "missed_deadline"


# 함수이름: utc_now
# 함수역할:
# - DB에 저장할 시간대 정보 없는 UTC 현재 시각을 반환한다.
# 매개변수:
# - 없음.
# 반환값:
# - 시간대 정보가 없는 현재 UTC datetime.
def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# 클래스명: _CaregiverAlertOutbox
# 역할:
# - 복약 완료와 같은 트랜잭션에서 생성되는 보호자 알림 전송 요청이다.
# 주요 책임:
# - 서버 재시작이나 일시적인 푸시 장애에도 전송 요청을 보존한다.
# - 같은 환자·날짜·시간대 이벤트가 중복 전송되지 않게 식별한다.
# - 재시도 횟수와 다음 시도 시각, 종료 상태를 기록한다.
# 속성:
# - event_key (String(64)): 환자·날짜·시간대 완료 이벤트의 중복 방지 키.
# - patient_hash (String): 작업 대상 환자의 데이터 소유 범위 식별자.
# - slot_key (String(32)): morning, lunch, evening, bedtime 중 복용 시간대 키.
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
    caregiver_hash = Column(String, nullable=True, index=True)
    slot_key = Column(String(32), nullable=False)
    event_type = Column(
        String(32),
        nullable=False,
        default=CAREGIVER_ALERT_EVENT_DOSE_COMPLETED,
        server_default=CAREGIVER_ALERT_EVENT_DOSE_COMPLETED,
    )
    schedule_date = Column(Date, nullable=True, index=True)
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


# 함수이름: ensure_caregiver_alert_outbox_schema
# 함수역할: 기존 SQLite 아웃박스에 일반 보호자 이벤트 열과 인덱스를 보완한다.
# 매개변수:
# - db_engine (Engine): 검사하고 필요한 경우 보완할 SQLite 엔진.
# 반환값:
# - 없음.
def ensure_caregiver_alert_outbox_schema(db_engine: Engine) -> None:
    inspector = inspect(db_engine)
    if not inspector.has_table(_CaregiverAlertOutbox.__tablename__):
        Base.metadata.create_all(
            bind=db_engine,
            tables=[_CaregiverAlertOutbox.__table__],
        )
        return

    existing_columns = {
        column["name"]
        for column in inspector.get_columns(_CaregiverAlertOutbox.__tablename__)
    }
    optional_columns = {
        "caregiver_hash": "VARCHAR",
        "event_type": (
            "VARCHAR(32) DEFAULT "
            f"'{CAREGIVER_ALERT_EVENT_DOSE_COMPLETED}'"
        ),
        "schedule_date": "DATE",
    }
    with db_engine.begin() as connection:
        for column_name, column_type in optional_columns.items():
            if column_name not in existing_columns:
                connection.execute(
                    text(
                        f"ALTER TABLE {_CaregiverAlertOutbox.__tablename__} "
                        f"ADD COLUMN {column_name} {column_type}"
                    )
                )
        connection.execute(
            text(
                f"UPDATE {_CaregiverAlertOutbox.__tablename__} "
                f"SET event_type = '{CAREGIVER_ALERT_EVENT_DOSE_COMPLETED}' "
                "WHERE event_type IS NULL OR TRIM(event_type) = ''"
            )
        )
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS "
                "ix_caregiver_alert_outbox_caregiver_hash "
                f"ON {_CaregiverAlertOutbox.__tablename__} (caregiver_hash)"
            )
        )
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS "
                "ix_caregiver_alert_outbox_schedule_date "
                f"ON {_CaregiverAlertOutbox.__tablename__} (schedule_date)"
            )
        )
