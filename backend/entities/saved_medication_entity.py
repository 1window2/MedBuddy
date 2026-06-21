# 파일명: saved_medication_entity.py
# 역할: 저장된 복약 정보 snapshot을 저장하는 SQLAlchemy 엔티티이다.

from datetime import date

from sqlalchemy import Boolean, Column, Date, Integer, String, inspect, text
from sqlalchemy.engine import Engine

from core.database import Base
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH


# 클래스명: _SavedMedication
# 역할: 저장된 약 상세 정보 snapshot을 보관하는 내부 SQLAlchemy row이다.
# 주요 책임:
#   - Map saved medication fields to the saved_medications table.
#   - Keep saved medication snapshots scoped to a patient hash.
#   - Preserve prescription-derived dosage schedule fields for later schedule features.
#   - Persist the current medication schedule status for CheckSchedule use cases.
class _SavedMedication(Base):
    __tablename__ = "saved_medications"

    id = Column(Integer, primary_key=True, index=True)
    patient_hash = Column(
        String,
        index=True,
        nullable=False,
        default=DEFAULT_PATIENT_HASH,
        server_default=DEFAULT_PATIENT_HASH,
    )
    created_date = Column(Date, nullable=True, default=date.today)
    prescription_date = Column(Date, nullable=True)
    item_name = Column(String, index=True)
    efficacy = Column(String)
    use_method = Column(String)
    warning_message = Column(String)
    dosage_per_time = Column(String, nullable=True)
    daily_frequency = Column(String, nullable=True)
    total_days = Column(String, nullable=True)
    image_url = Column(String, nullable=True)
    medication_status = Column(
        Boolean,
        nullable=False,
        default=False,
        server_default="0",
    )
    ai_guide = Column(String, nullable=True)


# 함수명: ensure_saved_medication_schema
# 함수역할:
# - Adds newly introduced saved medication columns to an existing SQLite table.
# - SQLAlchemy create_all은 누락된 테이블만 생성하고 기존 테이블 구조는 변경하지 않는다.
# 매개변수:
# - db_engine: 애플리케이션 데이터베이스에 연결된 SQLAlchemy engine
# 반환값:
# - None.
def ensure_saved_medication_schema(db_engine: Engine) -> None:
    inspector = inspect(db_engine)
    if not inspector.has_table(_SavedMedication.__tablename__):
        return

    existing_columns = {
        column["name"] for column in inspector.get_columns(_SavedMedication.__tablename__)
    }
    optional_columns = {
        "patient_hash": f"VARCHAR DEFAULT '{DEFAULT_PATIENT_HASH}'",
        "created_date": "DATE",
        "prescription_date": "DATE",
        "dosage_per_time": "VARCHAR",
        "daily_frequency": "VARCHAR",
        "total_days": "VARCHAR",
        "image_url": "VARCHAR",
        "medication_status": "BOOLEAN DEFAULT 0",
    }
    today = date.today().isoformat()

    with db_engine.begin() as connection:
        for column_name, column_type in optional_columns.items():
            if column_name not in existing_columns:
                connection.execute(
                    text(
                        f"ALTER TABLE {_SavedMedication.__tablename__} "
                        f"ADD COLUMN {column_name} {column_type}"
                    )
                )

        connection.execute(
            text(
                f"UPDATE {_SavedMedication.__tablename__} "
                "SET created_date = :today "
                "WHERE created_date IS NULL OR created_date = ''"
            ),
            {"today": today},
        )
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS "
                f"ix_{_SavedMedication.__tablename__}_patient_hash "
                f"ON {_SavedMedication.__tablename__} (patient_hash)"
            )
        )
