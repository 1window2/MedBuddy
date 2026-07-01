# File Name: medication_completion_entity.py
# Role: SQLAlchemy entity for per-slot medication completion records.

from datetime import UTC, date, datetime

from sqlalchemy import (
    Boolean,
    Column,
    Date,
    DateTime,
    Integer,
    String,
    UniqueConstraint,
    inspect,
    text,
)
from sqlalchemy.engine import Engine

from core.database import Base
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH


# Function Name: utc_now
# Description:
# - Returns a timezone-aware UTC timestamp converted to a naive DB value.
# Returns:
# - Current UTC datetime without tzinfo for SQLite DateTime compatibility.
def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# Class Name: _MedicationCompletion
# Role: Internal SQLAlchemy row for a medication schedule slot completion.
# Responsibilities:
#   - Store completion state by saved medication, patient, date, and time slot.
#   - Keep MedicationSchedule row-level status as a derived compatibility value.
# Attributes:
#   - saved_medication_id: Saved medication row identifier.
#   - patient_hash: Patient ownership key for scoped lookups.
#   - schedule_date: Date of the schedule slot.
#   - slot_key: Time-slot key such as morning, lunch, evening, or bedtime.
#   - completed: Whether this slot was marked as taken.
#   - completed_at: Timestamp when the slot was marked complete.
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
    saved_medication_id = Column(Integer, index=True, nullable=False)
    patient_hash = Column(
        String,
        index=True,
        nullable=False,
        default=DEFAULT_PATIENT_HASH,
        server_default=DEFAULT_PATIENT_HASH,
    )
    schedule_date = Column(Date, index=True, nullable=False, default=date.today)
    slot_key = Column(String, index=True, nullable=False)
    completed = Column(Boolean, nullable=False, default=True, server_default="1")
    completed_at = Column(DateTime, nullable=True, default=utc_now)


# Function Name: ensure_medication_completion_schema
# Description:
# - Creates the per-slot completion table and supporting index for existing SQLite DBs.
# Parameters:
# - db_engine: SQLAlchemy engine bound to the application database.
# Returns:
# - None.
def ensure_medication_completion_schema(db_engine: Engine) -> None:
    inspector = inspect(db_engine)
    if not inspector.has_table(_MedicationCompletion.__tablename__):
        Base.metadata.create_all(
            bind=db_engine,
            tables=[_MedicationCompletion.__table__],
        )

    inspector = inspect(db_engine)
    existing_columns = {
        column["name"]
        for column in inspector.get_columns(_MedicationCompletion.__tablename__)
    }
    optional_columns = {
        "saved_medication_id": "INTEGER DEFAULT 0",
        "patient_hash": f"VARCHAR DEFAULT '{DEFAULT_PATIENT_HASH}'",
        "schedule_date": "DATE",
        "slot_key": "VARCHAR DEFAULT 'morning'",
        "completed": "BOOLEAN DEFAULT 1",
        "completed_at": "DATETIME",
    }

    with db_engine.begin() as connection:
        for column_name, column_type in optional_columns.items():
            if column_name not in existing_columns:
                connection.execute(
                    text(
                        f"ALTER TABLE {_MedicationCompletion.__tablename__} "
                        f"ADD COLUMN {column_name} {column_type}"
                    )
                )

        connection.execute(
            text(
                f"UPDATE {_MedicationCompletion.__tablename__} "
                "SET saved_medication_id = 0 WHERE saved_medication_id IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_MedicationCompletion.__tablename__} "
                "SET patient_hash = :default_patient_hash "
                "WHERE patient_hash IS NULL OR patient_hash = ''"
            ),
            {"default_patient_hash": DEFAULT_PATIENT_HASH},
        )
        connection.execute(
            text(
                f"UPDATE {_MedicationCompletion.__tablename__} "
                "SET schedule_date = CURRENT_DATE WHERE schedule_date IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_MedicationCompletion.__tablename__} "
                "SET slot_key = 'morning' WHERE slot_key IS NULL OR slot_key = ''"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_MedicationCompletion.__tablename__} "
                "SET completed = 1 WHERE completed IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_MedicationCompletion.__tablename__} "
                "SET completed_at = CURRENT_TIMESTAMP WHERE completed_at IS NULL"
            )
        )
        connection.execute(
            text(
                f"DELETE FROM {_MedicationCompletion.__tablename__} "
                "WHERE id NOT IN ("
                f"SELECT MAX(id) FROM {_MedicationCompletion.__tablename__} "
                "GROUP BY saved_medication_id, patient_hash, schedule_date, slot_key"
                ")"
            )
        )
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS "
                f"ix_{_MedicationCompletion.__tablename__}_scope "
                f"ON {_MedicationCompletion.__tablename__} "
                "(patient_hash, schedule_date, saved_medication_id)"
            )
        )
        connection.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS "
                f"uq_{_MedicationCompletion.__tablename__}_scope_slot "
                f"ON {_MedicationCompletion.__tablename__} "
                "(saved_medication_id, patient_hash, schedule_date, slot_key)"
            )
        )
