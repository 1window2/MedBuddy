# File Name: saved_medication_entity.py
# Role: SQLAlchemy entity for saved medication snapshots.

from sqlalchemy import Column, Integer, String, inspect, text
from sqlalchemy.engine import Engine

from core.database import Base
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH


# Class Name: _SavedMedication
# Role: Internal SQLAlchemy row for saved medication detail snapshots.
# Responsibilities:
#   - Map saved medication fields to the saved_medications table.
#   - Keep saved medication snapshots scoped to a patient hash.
#   - Preserve prescription-derived dosage schedule fields for later schedule features.
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
    item_name = Column(String, index=True)
    efficacy = Column(String)
    use_method = Column(String)
    warning_message = Column(String)
    dosage_per_time = Column(String, nullable=True)
    daily_frequency = Column(String, nullable=True)
    total_days = Column(String, nullable=True)
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
        "dosage_per_time": "VARCHAR",
        "daily_frequency": "VARCHAR",
        "total_days": "VARCHAR",
    }

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
                "CREATE INDEX IF NOT EXISTS "
                f"ix_{_SavedMedication.__tablename__}_patient_hash "
                f"ON {_SavedMedication.__tablename__} (patient_hash)"
            )
        )
