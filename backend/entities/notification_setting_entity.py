# File Name: notification_setting_entity.py
# Role: SQLAlchemy and DTO entities for medication notification settings.

from datetime import UTC, datetime

from pydantic import BaseModel, Field
from sqlalchemy import Boolean, Column, DateTime, Integer, String, UniqueConstraint, inspect, text
from sqlalchemy.engine import Engine

from core.database import Base
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH


_VALID_SLOT_KEYS = ("morning", "lunch", "evening", "bedtime")


# Function Name: utc_now
# Description:
# - Returns a naive UTC timestamp for SQLite DateTime compatibility.
# Returns:
# - Current UTC datetime without tzinfo.
def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# Class Name: _NotificationSetting
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
class _NotificationSetting(Base):
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


# Class Name: NotificationSetting
# Role: Represents patient medication notification settings.
# Responsibilities:
#   - Expose a UML-compatible notification setting entity.
#   - Convert database rows into API-safe dictionaries.
# Attributes:
#   - patient_hash: Patient ownership key.
#   - slot_key: Medication schedule time slot.
#   - hour: 24-hour local notification hour.
#   - minute: Local notification minute.
#   - enabled: Whether the alarm is active.
class NotificationSetting(BaseModel):
    patient_hash: str = DEFAULT_PATIENT_HASH
    slot_key: str = Field(default="morning")
    hour: int = 8
    minute: int = 0
    enabled: bool = False

    # Function Name: saveNotificationSetting
    # Description:
    # - Class diagram compatible operation that returns the current DTO payload.
    # Returns:
    # - JSON-compatible notification setting dictionary.
    def saveNotificationSetting(self) -> dict[str, object]:
        return self.to_response_dict()

    # Function Name: enable
    # Description:
    # - Returns an enabled copy of the setting.
    # Returns:
    # - Enabled NotificationSetting.
    def enable(self) -> "NotificationSetting":
        return self.model_copy(update={"enabled": True})

    # Function Name: disable
    # Description:
    # - Returns a disabled copy of the setting.
    # Returns:
    # - Disabled NotificationSetting.
    def disable(self) -> "NotificationSetting":
        return self.model_copy(update={"enabled": False})

    # Function Name: to_response_dict
    # Description:
    # - Converts the setting to the API field names used by Flutter.
    # Returns:
    # - JSON-compatible notification setting dictionary.
    def to_response_dict(self) -> dict[str, object]:
        return {
            "patient_hash": self.patient_hash,
            "slot_key": self.slot_key,
            "hour": self.hour,
            "minute": self.minute,
            "is_enabled": self.enabled,
        }


# Function Name: default_notification_hour
# Description:
# - Provides the default reminder hour for a medication schedule slot.
# Parameters:
# - slot_key: Schedule time slot key.
# Returns:
# - Default 24-hour alarm hour.
def default_notification_hour(slot_key: str) -> int:
    return {
        "morning": 8,
        "lunch": 12,
        "evening": 18,
        "bedtime": 22,
    }.get(slot_key, 8)


# Function Name: valid_notification_slot_keys
# Description:
# - Returns all supported medication reminder slot keys.
# Returns:
# - Tuple of valid slot keys.
def valid_notification_slot_keys() -> tuple[str, ...]:
    return _VALID_SLOT_KEYS


# Function Name: ensure_notification_setting_schema
# Description:
# - Creates the notification setting table and indexes for existing SQLite DBs.
# Parameters:
# - db_engine: SQLAlchemy engine bound to the application database.
# Returns:
# - None.
def ensure_notification_setting_schema(db_engine: Engine) -> None:
    inspector = inspect(db_engine)
    if not inspector.has_table(_NotificationSetting.__tablename__):
        Base.metadata.create_all(
            bind=db_engine,
            tables=[_NotificationSetting.__table__],
        )

    with db_engine.begin() as connection:
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS "
                f"ix_{_NotificationSetting.__tablename__}_scope "
                f"ON {_NotificationSetting.__tablename__} "
                "(patient_hash, slot_key)"
            )
        )
