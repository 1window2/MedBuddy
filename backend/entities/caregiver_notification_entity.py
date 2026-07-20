# File Name: caregiver_notification_entity.py
# Role: SQLAlchemy and DTO entities for caregiver notification settings.

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

_ALERT_OPTION_ENABLE = "enable"
_ALERT_OPTION_DISABLE = "disable"


def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


class _CaregiverNotification(Base):
    __tablename__ = "guardian_alert_settings"
    __table_args__ = (
        UniqueConstraint(
            "guardian_hash",
            "patient_hash",
            name="uq_guardian_alert_setting_scope",
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    caregiver_hash = Column("guardian_hash", String, nullable=False, index=True)
    patient_hash = Column(String, nullable=False, index=True)
    enabled = Column(Boolean, nullable=False, default=False, server_default="0")
    alert_option = Column(
        String,
        nullable=False,
        default=_ALERT_OPTION_DISABLE,
        server_default=_ALERT_OPTION_DISABLE,
    )
    created_at = Column(DateTime, nullable=False, default=utc_now)
    updated_at = Column(DateTime, nullable=False, default=utc_now, onupdate=utc_now)


# Class Name: CaregiverNotification
# Role: Represents caregiver notification settings.
# Responsibilities:
#   - Preserve one caregiver-to-patient notification preference.
#   - Expose the UML alertOption while keeping boolean toggle state for the UI.
# Attributes:
#   - notification_id: Persisted setting identifier.
#   - patient_hash: Patient monitored by the caregiver.
#   - caregiver_hash: Caregiver receiving patient medication notifications.
#   - notification_enabled: Whether caregiver notifications are active.
#   - notification_type: UML option string, either enable or disable.
class CaregiverNotification(BaseModel):
    notification_id: int | None = None
    patient_hash: str = ""
    caregiver_hash: str = ""
    notification_enabled: bool = False
    notification_type: str = Field(default=_ALERT_OPTION_DISABLE)

    # Function Name: updateNotificationSetting
    # Description:
    # - Returns a copy with the requested notification option applied.
    # Returns:
    # - Updated CaregiverNotification.
    def updateNotificationSetting(
        self,
        notification_option: str | bool,
    ) -> "CaregiverNotification":
        enabled = (
            notification_option
            if isinstance(notification_option, bool)
            else enabled_from_alert_option(notification_option)
        )
        return self.model_copy(
            update={
                "notification_enabled": enabled,
                "notification_type": alert_option_from_enabled(enabled),
            }
        )

    # Function Name: to_response_dict
    # Description:
    # - Converts the setting to API field names used by the Flutter layer.
    # Returns:
    # - JSON-compatible caregiver setting with legacy guardian aliases.
    def to_response_dict(self) -> dict[str, object]:
        return {
            "notification_id": self.notification_id,
            "setting_id": self.notification_id,
            "patient_hash": self.patient_hash,
            "caregiver_hash": self.caregiver_hash,
            "guardian_hash": self.caregiver_hash,
            "notification_enabled": self.notification_enabled,
            "is_enabled": self.notification_enabled,
            "enabled": self.notification_enabled,
            "notification_type": self.notification_type,
            "alert_option": self.notification_type,
        }


def alert_option_from_enabled(enabled: bool) -> str:
    return _ALERT_OPTION_ENABLE if enabled else _ALERT_OPTION_DISABLE


def enabled_from_alert_option(alert_option: str) -> bool:
    normalized_option = (alert_option or "").strip().lower()
    if normalized_option in {"enable", "enabled", "on", "true", "1"}:
        return True
    if normalized_option in {"disable", "disabled", "off", "false", "0"}:
        return False
    raise ValueError("Caregiver notification option is not supported.")


# Function Name: ensure_caregiver_notification_schema
# Description:
# - Creates or upgrades guardian alert setting storage for existing SQLite DBs.
# Parameters:
# - db_engine: SQLAlchemy engine bound to the application database.
# Returns:
# - None.
def ensure_caregiver_notification_schema(db_engine: Engine) -> None:
    inspector = inspect(db_engine)
    if not inspector.has_table(_CaregiverNotification.__tablename__):
        Base.metadata.create_all(
            bind=db_engine,
            tables=[_CaregiverNotification.__table__],
        )

    inspector = inspect(db_engine)
    existing_columns = {
        column["name"]
        for column in inspector.get_columns(_CaregiverNotification.__tablename__)
    }
    optional_columns = {
        "guardian_hash": "VARCHAR DEFAULT ''",
        "patient_hash": "VARCHAR DEFAULT ''",
        "enabled": "BOOLEAN DEFAULT 0",
        "alert_option": f"VARCHAR DEFAULT '{_ALERT_OPTION_DISABLE}'",
        "created_at": "DATETIME",
        "updated_at": "DATETIME",
    }

    with db_engine.begin() as connection:
        for column_name, column_type in optional_columns.items():
            if column_name not in existing_columns:
                connection.execute(
                    text(
                        f"ALTER TABLE {_CaregiverNotification.__tablename__} "
                        f"ADD COLUMN {column_name} {column_type}"
                    )
                )

        connection.execute(
            text(
                f"UPDATE {_CaregiverNotification.__tablename__} "
                "SET guardian_hash = '' WHERE guardian_hash IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_CaregiverNotification.__tablename__} "
                "SET patient_hash = '' WHERE patient_hash IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_CaregiverNotification.__tablename__} "
                "SET enabled = CASE "
                "WHEN LOWER(alert_option) IN ('enable', 'enabled', 'on', 'true', '1') "
                "THEN 1 ELSE 0 END "
                "WHERE enabled IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_CaregiverNotification.__tablename__} "
                "SET enabled = 0 WHERE enabled IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_CaregiverNotification.__tablename__} "
                "SET alert_option = CASE "
                "WHEN enabled = 1 THEN 'enable' "
                "ELSE 'disable' END "
                "WHERE alert_option IS NULL "
                "OR LOWER(alert_option) NOT IN ('enable', 'disable')"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_CaregiverNotification.__tablename__} "
                "SET created_at = CURRENT_TIMESTAMP WHERE created_at IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_CaregiverNotification.__tablename__} "
                "SET updated_at = CURRENT_TIMESTAMP WHERE updated_at IS NULL"
            )
        )
        connection.execute(
            text(
                f"DELETE FROM {_CaregiverNotification.__tablename__} "
                "WHERE id NOT IN ("
                f"SELECT MAX(id) FROM {_CaregiverNotification.__tablename__} "
                "GROUP BY guardian_hash, patient_hash"
                ")"
            )
        )
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS "
                f"ix_{_CaregiverNotification.__tablename__}_scope "
                f"ON {_CaregiverNotification.__tablename__} "
                "(guardian_hash, patient_hash)"
            )
        )
        connection.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS "
                f"uq_{_CaregiverNotification.__tablename__}_scope "
                f"ON {_CaregiverNotification.__tablename__} "
                "(guardian_hash, patient_hash)"
            )
        )
