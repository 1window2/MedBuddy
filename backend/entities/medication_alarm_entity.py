# File Name: medication_alarm_entity.py
# Role: SQLAlchemy and DTO entities for medication alarms.

from datetime import UTC, datetime

from pydantic import BaseModel, Field
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Integer,
    String,
    UniqueConstraint,
    inspect,
    text,
)
from sqlalchemy.engine import Engine

from core.database import Base
from entities.medication_schedule_entity import (
    DEFAULT_MEDICATION_SCHEDULE_SLOT_KEY,
    MEDICATION_SCHEDULE_SLOT_KEYS,
)
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH


# Function Name: utc_now
# Description:
# - Returns a naive UTC timestamp for SQLite DateTime compatibility.
# Returns:
# - Current UTC datetime without tzinfo.
def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# Class Name: _MedicationAlarm
# Role: Internal SQLAlchemy row for one medication alarm setting.
# Responsibilities:
#   - Store a patient-scoped medication alarm by time slot.
#   - Preserve whether the alarm is enabled and what local time it should use.
# Attributes:
#   - patient_hash: Patient ownership key.
#   - slot_key: Medication schedule time slot such as morning or evening.
#   - hour: 24-hour local notification hour.
#   - minute: Local notification minute.
#   - enabled: Whether the alarm is active.
#   - updated_at: Last update timestamp.
class _MedicationAlarm(Base):
    # Keep the existing physical table name so v0.0.4 SQLite databases preserve
    # saved alarm settings while this slot-level extension evolves independently.
    __tablename__ = "notification_settings"
    __table_args__ = (
        UniqueConstraint(
            "patient_hash",
            "slot_key",
            name="uq_notification_setting_slot",
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    patient_hash = Column(
        String,
        index=True,
        nullable=False,
        default=DEFAULT_PATIENT_HASH,
        server_default=DEFAULT_PATIENT_HASH,
    )
    slot_key = Column(String, index=True, nullable=False)
    hour = Column(Integer, nullable=False, default=8, server_default="8")
    minute = Column(Integer, nullable=False, default=0, server_default="0")
    enabled = Column(Boolean, nullable=False, default=False, server_default="0")
    updated_at = Column(DateTime, nullable=False, default=utc_now, onupdate=utc_now)


# Class Name: MedicationAlarm
# Role: Represents patient medication alarms.
# Responsibilities:
#   - Extend the v5 NotificationSetting concept with schedule-slot granularity.
#   - Convert database rows into API-safe dictionaries.
# Attributes:
#   - patient_hash: Patient ownership key.
#   - slot_key: Medication schedule time slot.
#   - hour: 24-hour local notification hour.
#   - minute: Local notification minute.
#   - enabled: Whether the alarm is active.
class MedicationAlarm(BaseModel):
    patient_hash: str = DEFAULT_PATIENT_HASH
    slot_key: str = Field(default=DEFAULT_MEDICATION_SCHEDULE_SLOT_KEY)
    hour: int = 8
    minute: int = 0
    enabled: bool = False

    # Function Name: enable
    # Description:
    # - Returns an enabled copy of the setting.
    # Returns:
    # - Enabled MedicationAlarm.
    def enable(self) -> "MedicationAlarm":
        return self.model_copy(update={"enabled": True})

    # Function Name: disable
    # Description:
    # - Returns a disabled copy of the setting.
    # Returns:
    # - Disabled MedicationAlarm.
    def disable(self) -> "MedicationAlarm":
        return self.model_copy(update={"enabled": False})

    # Function Name: to_response_dict
    # Description:
    # - Converts the setting to the API field names used by Flutter.
    # Returns:
    # - JSON-compatible medication alarm dictionary.
    def to_response_dict(self) -> dict[str, object]:
        return {
            "patient_hash": self.patient_hash,
            "slot_key": self.slot_key,
            "hour": self.hour,
            "minute": self.minute,
            "is_enabled": self.enabled,
        }


# Function Name: default_alarm_hour
# Description:
# - Provides the default reminder hour for a medication schedule slot.
# Parameters:
# - slot_key: Schedule time slot key.
# Returns:
# - Default 24-hour alarm hour.
def default_alarm_hour(slot_key: str) -> int:
    return {
        "morning": 8,
        "lunch": 12,
        "evening": 18,
        "bedtime": 22,
    }.get(slot_key, 8)


# Function Name: valid_alarm_slot_keys
# Description:
# - Returns all supported medication reminder slot keys.
# Returns:
# - Tuple of valid slot keys.
def valid_alarm_slot_keys() -> tuple[str, ...]:
    return MEDICATION_SCHEDULE_SLOT_KEYS


# Function Name: ensure_medication_alarm_schema
# Description:
# - Creates or upgrades the medication alarm storage table for existing SQLite DBs.
# - SQLAlchemy create_all creates missing tables but does not alter existing tables.
# Parameters:
# - db_engine: SQLAlchemy engine bound to the application database.
# Returns:
# - None.
def ensure_medication_alarm_schema(db_engine: Engine) -> None:
    inspector = inspect(db_engine)
    if not inspector.has_table(_MedicationAlarm.__tablename__):
        Base.metadata.create_all(
            bind=db_engine,
            tables=[_MedicationAlarm.__table__],
        )

    inspector = inspect(db_engine)
    existing_columns = {
        column["name"]
        for column in inspector.get_columns(_MedicationAlarm.__tablename__)
    }
    optional_columns = {
        "patient_hash": f"VARCHAR DEFAULT '{DEFAULT_PATIENT_HASH}'",
        "slot_key": f"VARCHAR DEFAULT '{DEFAULT_MEDICATION_SCHEDULE_SLOT_KEY}'",
        "hour": "INTEGER DEFAULT 8",
        "minute": "INTEGER DEFAULT 0",
        "enabled": "BOOLEAN DEFAULT 0",
        "updated_at": "DATETIME",
    }

    with db_engine.begin() as connection:
        for column_name, column_type in optional_columns.items():
            if column_name not in existing_columns:
                connection.execute(
                    text(
                        f"ALTER TABLE {_MedicationAlarm.__tablename__} "
                        f"ADD COLUMN {column_name} {column_type}"
                    )
                )

        connection.execute(
            text(
                f"UPDATE {_MedicationAlarm.__tablename__} "
                "SET patient_hash = :default_patient_hash "
                "WHERE patient_hash IS NULL OR patient_hash = ''"
            ),
            {"default_patient_hash": DEFAULT_PATIENT_HASH},
        )
        connection.execute(
            text(
                f"UPDATE {_MedicationAlarm.__tablename__} "
                "SET slot_key = :default_slot_key "
                "WHERE slot_key IS NULL OR slot_key = ''"
            ),
            {"default_slot_key": DEFAULT_MEDICATION_SCHEDULE_SLOT_KEY},
        )
        connection.execute(
            text(
                f"UPDATE {_MedicationAlarm.__tablename__} "
                "SET hour = 8 WHERE hour IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_MedicationAlarm.__tablename__} "
                "SET minute = 0 WHERE minute IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_MedicationAlarm.__tablename__} "
                "SET enabled = 0 WHERE enabled IS NULL"
            )
        )
        connection.execute(
            text(
                f"DELETE FROM {_MedicationAlarm.__tablename__} "
                "WHERE id NOT IN ("
                f"SELECT MAX(id) FROM {_MedicationAlarm.__tablename__} "
                "GROUP BY patient_hash, slot_key"
                ")"
            )
        )
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS "
                f"ix_{_MedicationAlarm.__tablename__}_scope "
                f"ON {_MedicationAlarm.__tablename__} "
                "(patient_hash, slot_key)"
            )
        )
        connection.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS "
                f"uq_{_MedicationAlarm.__tablename__}_scope_slot "
                f"ON {_MedicationAlarm.__tablename__} "
                "(patient_hash, slot_key)"
            )
        )
