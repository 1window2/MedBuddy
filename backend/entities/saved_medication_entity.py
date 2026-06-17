# File Name: saved_medication_entity.py
# Role: SQLAlchemy entity for saved medication snapshots.

from datetime import date

from sqlalchemy import Boolean, Column, Date, Integer, String, inspect, text
from sqlalchemy.engine import Engine

from core.database import Base
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH


# Class Name: _SavedMedication
# Role: Internal SQLAlchemy row for saved medication detail snapshots.
# Responsibilities:
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
    item_name = Column(String, index=True)
    efficacy = Column(String)
    use_method = Column(String)
    warning_message = Column(String)
    dosage_per_time = Column(String, nullable=True)
    daily_frequency = Column(String, nullable=True)
    total_days = Column(String, nullable=True)
    medication_status = Column(
        Boolean,
        nullable=False,
        default=False,
        server_default="0",
    )
    ai_guide = Column(String, nullable=True)


# Function Name: ensure_saved_medication_schema
# Description:
# - Adds newly introduced saved medication columns to an existing SQLite table.
# - SQLAlchemy create_all creates missing tables but does not alter existing tables.
# Parameters:
# - db_engine: SQLAlchemy engine bound to the application database.
# Returns:
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
        "dosage_per_time": "VARCHAR",
        "daily_frequency": "VARCHAR",
        "total_days": "VARCHAR",
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
