# File Name: guardian_alert_setting_entity.py
# Role: SQLAlchemy and DTO entities for guardian alert settings.

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


class _GuardianAlertSetting(Base):
    __tablename__ = "guardian_alert_settings"
    __table_args__ = (
        UniqueConstraint(
            "guardian_hash",
            "patient_hash",
            name="uq_guardian_alert_setting_scope",
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    guardian_hash = Column(String, nullable=False, index=True)
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


# Class Name: GuardianAlertSetting
# Role: Represents guardian alert settings.
# Responsibilities:
#   - Preserve one guardian-to-patient alert preference.
#   - Expose the UML alertOption while keeping boolean toggle state for the UI.
# Attributes:
#   - setting_id: Persisted setting identifier.
#   - patient_hash: Patient monitored by the guardian.
#   - guardian_hash: Guardian receiving patient medication alerts.
#   - enabled: Whether guardian alerts are active.
#   - alert_option: UML option string, either enable or disable.
class GuardianAlertSetting(BaseModel):
    setting_id: int | None = None
    patient_hash: str = ""
    guardian_hash: str = ""
    enabled: bool = False
    alert_option: str = Field(default=_ALERT_OPTION_DISABLE)

    @property
    def patient_id(self) -> str:
        return self.patient_hash

    @property
    def guardian_id(self) -> str:
        return self.guardian_hash

    # Function Name: saveGuardianAlertSetting
    # Description:
    # - Class diagram compatible operation that returns the current DTO payload.
    # Returns:
    # - JSON-compatible guardian alert setting dictionary.
    def saveGuardianAlertSetting(self) -> dict[str, object]:
        return self.to_response_dict()

    # Function Name: enable
    # Description:
    # - Returns an enabled copy of the setting.
    # Returns:
    # - Enabled GuardianAlertSetting.
    def enable(self) -> "GuardianAlertSetting":
        return self.model_copy(
            update={"enabled": True, "alert_option": _ALERT_OPTION_ENABLE}
        )

    # Function Name: disable
    # Description:
    # - Returns a disabled copy of the setting.
    # Returns:
    # - Disabled GuardianAlertSetting.
    def disable(self) -> "GuardianAlertSetting":
        return self.model_copy(
            update={"enabled": False, "alert_option": _ALERT_OPTION_DISABLE}
        )

    # Function Name: to_response_dict
    # Description:
    # - Converts the setting to API field names used by the Flutter layer.
    # Returns:
    # - JSON-compatible guardian alert setting dictionary.
    def to_response_dict(self) -> dict[str, object]:
        return {
            "setting_id": self.setting_id,
            "patient_hash": self.patient_hash,
            "patient_id": self.patient_hash,
            "guardian_hash": self.guardian_hash,
            "guardian_id": self.guardian_hash,
            "is_enabled": self.enabled,
            "enabled": self.enabled,
            "alert_option": self.alert_option,
        }


def alert_option_from_enabled(enabled: bool) -> str:
    return _ALERT_OPTION_ENABLE if enabled else _ALERT_OPTION_DISABLE


def enabled_from_alert_option(alert_option: str) -> bool:
    normalized_option = (alert_option or "").strip().lower()
    if normalized_option in {"enable", "enabled", "on", "true", "1"}:
        return True
    if normalized_option in {"disable", "disabled", "off", "false", "0"}:
        return False
    raise ValueError("Guardian alert option is not supported.")


# Function Name: ensure_guardian_alert_setting_schema
# Description:
# - Creates or upgrades guardian alert setting storage for existing SQLite DBs.
# Parameters:
# - db_engine: SQLAlchemy engine bound to the application database.
# Returns:
# - None.
def ensure_guardian_alert_setting_schema(db_engine: Engine) -> None:
    inspector = inspect(db_engine)
    if not inspector.has_table(_GuardianAlertSetting.__tablename__):
        Base.metadata.create_all(
            bind=db_engine,
            tables=[_GuardianAlertSetting.__table__],
        )

    inspector = inspect(db_engine)
    existing_columns = {
        column["name"]
        for column in inspector.get_columns(_GuardianAlertSetting.__tablename__)
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
                        f"ALTER TABLE {_GuardianAlertSetting.__tablename__} "
                        f"ADD COLUMN {column_name} {column_type}"
                    )
                )

        connection.execute(
            text(
                f"UPDATE {_GuardianAlertSetting.__tablename__} "
                "SET guardian_hash = '' WHERE guardian_hash IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_GuardianAlertSetting.__tablename__} "
                "SET patient_hash = '' WHERE patient_hash IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_GuardianAlertSetting.__tablename__} "
                "SET enabled = CASE "
                "WHEN LOWER(alert_option) IN ('enable', 'enabled', 'on', 'true', '1') "
                "THEN 1 ELSE 0 END "
                "WHERE enabled IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_GuardianAlertSetting.__tablename__} "
                "SET enabled = 0 WHERE enabled IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_GuardianAlertSetting.__tablename__} "
                "SET alert_option = CASE "
                "WHEN enabled = 1 THEN 'enable' "
                "ELSE 'disable' END "
                "WHERE alert_option IS NULL "
                "OR LOWER(alert_option) NOT IN ('enable', 'disable')"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_GuardianAlertSetting.__tablename__} "
                "SET created_at = CURRENT_TIMESTAMP WHERE created_at IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_GuardianAlertSetting.__tablename__} "
                "SET updated_at = CURRENT_TIMESTAMP WHERE updated_at IS NULL"
            )
        )
        connection.execute(
            text(
                f"DELETE FROM {_GuardianAlertSetting.__tablename__} "
                "WHERE id NOT IN ("
                f"SELECT MAX(id) FROM {_GuardianAlertSetting.__tablename__} "
                "GROUP BY guardian_hash, patient_hash"
                ")"
            )
        )
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS "
                f"ix_{_GuardianAlertSetting.__tablename__}_scope "
                f"ON {_GuardianAlertSetting.__tablename__} "
                "(guardian_hash, patient_hash)"
            )
        )
        connection.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS "
                f"uq_{_GuardianAlertSetting.__tablename__}_scope "
                f"ON {_GuardianAlertSetting.__tablename__} "
                "(guardian_hash, patient_hash)"
            )
        )
