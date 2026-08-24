# File Name: user_setting_entity.py
# Role: Entity/DTO definitions for user display and reading settings.

from datetime import UTC, datetime

from pydantic import BaseModel
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    inspect,
    text,
)
from sqlalchemy.engine import Engine

from core.database import Base
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH
from entities.user_account_entity import _UserAccount  # noqa: F401


def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


class _UserSetting(Base):
    __tablename__ = "user_settings"

    id = Column(Integer, primary_key=True, index=True)
    user_hash = Column(
        String,
        ForeignKey("user_accounts.user_hash", ondelete="CASCADE"),
        unique=True,
        index=True,
        nullable=False,
        default=DEFAULT_PATIENT_HASH,
        server_default=DEFAULT_PATIENT_HASH,
    )
    font_size = Column(Integer, nullable=False, default=16, server_default="16")
    reading_speed = Column(Float, nullable=False, default=1.0, server_default="1.0")
    language = Column(String, nullable=False, default="ko", server_default="ko")
    language_mode = Column(String, nullable=False, default="ko", server_default="ko")
    time_format = Column(String, nullable=False, default="24h", server_default="24h")
    medication_notifications_enabled = Column(
        Boolean,
        nullable=False,
        default=True,
        server_default="1",
    )
    caregiver_notifications_enabled = Column(
        Boolean,
        nullable=False,
        default=True,
        server_default="1",
    )
    chat_notifications_enabled = Column(
        Boolean,
        nullable=False,
        default=True,
        server_default="1",
    )
    notification_detail_mode = Column(
        String,
        nullable=False,
        default="full",
        server_default="full",
    )
    default_morning_time = Column(
        String,
        nullable=False,
        default="08:00",
        server_default="08:00",
    )
    default_lunch_time = Column(
        String,
        nullable=False,
        default="12:00",
        server_default="12:00",
    )
    default_evening_time = Column(
        String,
        nullable=False,
        default="18:00",
        server_default="18:00",
    )
    default_bedtime = Column(
        String,
        nullable=False,
        default="22:00",
        server_default="22:00",
    )
    updated_at = Column(DateTime, nullable=False, default=utc_now, onupdate=utc_now)


# Class Name: UserSetting
# Role: Represents local user display and reading settings.
class UserSetting(BaseModel):
    user_hash: str = DEFAULT_PATIENT_HASH
    font_size: int = 16
    reading_speed: float = 1.0
    language: str = "ko"
    language_mode: str = "ko"
    time_format: str = "24h"
    medication_notifications_enabled: bool = True
    caregiver_notifications_enabled: bool = True
    chat_notifications_enabled: bool = True
    notification_detail_mode: str = "full"
    default_morning_time: str = "08:00"
    default_lunch_time: str = "12:00"
    default_evening_time: str = "18:00"
    default_bedtime: str = "22:00"

    def updateUserSetting(
        self,
        font_size: int,
        reading_speed: float,
        language: str,
        language_mode: str,
        time_format: str,
        medication_notifications_enabled: bool,
        caregiver_notifications_enabled: bool,
        chat_notifications_enabled: bool,
        notification_detail_mode: str,
        default_morning_time: str,
        default_lunch_time: str,
        default_evening_time: str,
        default_bedtime: str,
    ) -> "UserSetting":
        return self.model_copy(
            update={
                "font_size": font_size,
                "reading_speed": reading_speed,
                "language": language,
                "language_mode": language_mode,
                "time_format": time_format,
                "medication_notifications_enabled": medication_notifications_enabled,
                "caregiver_notifications_enabled": caregiver_notifications_enabled,
                "chat_notifications_enabled": chat_notifications_enabled,
                "notification_detail_mode": notification_detail_mode,
                "default_morning_time": default_morning_time,
                "default_lunch_time": default_lunch_time,
                "default_evening_time": default_evening_time,
                "default_bedtime": default_bedtime,
            }
        )

    def getUserSetting(self) -> dict[str, object]:
        return {
            "user_hash": self.user_hash,
            "font_size": self.font_size,
            "reading_speed": self.reading_speed,
            "language": self.language,
            "language_mode": self.language_mode,
            "time_format": self.time_format,
            "medication_notifications_enabled": self.medication_notifications_enabled,
            "caregiver_notifications_enabled": self.caregiver_notifications_enabled,
            "chat_notifications_enabled": self.chat_notifications_enabled,
            "notification_detail_mode": self.notification_detail_mode,
            "default_morning_time": self.default_morning_time,
            "default_lunch_time": self.default_lunch_time,
            "default_evening_time": self.default_evening_time,
            "default_bedtime": self.default_bedtime,
        }


# Function Name: ensure_user_setting_schema
# Description:
# - Creates or upgrades user setting storage for existing SQLite databases.
# Parameters:
# - db_engine: SQLAlchemy engine bound to the application database.
# Returns:
# - None.
def ensure_user_setting_schema(db_engine: Engine) -> None:
    inspector = inspect(db_engine)
    if not inspector.has_table(_UserSetting.__tablename__):
        Base.metadata.create_all(bind=db_engine, tables=[_UserSetting.__table__])

    inspector = inspect(db_engine)
    existing_columns = {
        column["name"] for column in inspector.get_columns(_UserSetting.__tablename__)
    }
    optional_columns = {
        "user_hash": f"VARCHAR DEFAULT '{DEFAULT_PATIENT_HASH}'",
        "font_size": "INTEGER DEFAULT 16",
        "reading_speed": "FLOAT DEFAULT 1.0",
        "language": "VARCHAR DEFAULT 'ko'",
        "language_mode": "VARCHAR DEFAULT 'ko'",
        "time_format": "VARCHAR DEFAULT '24h'",
        "medication_notifications_enabled": "BOOLEAN DEFAULT 1",
        "caregiver_notifications_enabled": "BOOLEAN DEFAULT 1",
        "chat_notifications_enabled": "BOOLEAN DEFAULT 1",
        "notification_detail_mode": "VARCHAR DEFAULT 'full'",
        "default_morning_time": "VARCHAR DEFAULT '08:00'",
        "default_lunch_time": "VARCHAR DEFAULT '12:00'",
        "default_evening_time": "VARCHAR DEFAULT '18:00'",
        "default_bedtime": "VARCHAR DEFAULT '22:00'",
        "updated_at": "DATETIME",
    }

    with db_engine.begin() as connection:
        for column_name, column_type in optional_columns.items():
            if column_name not in existing_columns:
                connection.execute(
                    text(
                        f"ALTER TABLE {_UserSetting.__tablename__} "
                        f"ADD COLUMN {column_name} {column_type}"
                    )
                )

        connection.execute(
            text(
                f"UPDATE {_UserSetting.__tablename__} "
                "SET user_hash = :default_user_hash "
                "WHERE user_hash IS NULL OR user_hash = ''"
            ),
            {"default_user_hash": DEFAULT_PATIENT_HASH},
        )
        connection.execute(
            text(
                f"UPDATE {_UserSetting.__tablename__} "
                "SET font_size = 16 WHERE font_size IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_UserSetting.__tablename__} "
                "SET reading_speed = 1.0 WHERE reading_speed IS NULL"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_UserSetting.__tablename__} "
                "SET language = 'ko' WHERE language IS NULL OR language = ''"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_UserSetting.__tablename__} SET "
                "language_mode = COALESCE(NULLIF(language_mode, ''), language, 'ko'), "
                "time_format = COALESCE(NULLIF(time_format, ''), '24h'), "
                "medication_notifications_enabled = "
                "COALESCE(medication_notifications_enabled, 1), "
                "caregiver_notifications_enabled = "
                "COALESCE(caregiver_notifications_enabled, 1), "
                "chat_notifications_enabled = COALESCE(chat_notifications_enabled, 1), "
                "notification_detail_mode = "
                "COALESCE(NULLIF(notification_detail_mode, ''), 'full'), "
                "default_morning_time = "
                "COALESCE(NULLIF(default_morning_time, ''), '08:00'), "
                "default_lunch_time = "
                "COALESCE(NULLIF(default_lunch_time, ''), '12:00'), "
                "default_evening_time = "
                "COALESCE(NULLIF(default_evening_time, ''), '18:00'), "
                "default_bedtime = "
                "COALESCE(NULLIF(default_bedtime, ''), '22:00')"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_UserSetting.__tablename__} "
                "SET updated_at = CURRENT_TIMESTAMP WHERE updated_at IS NULL"
            )
        )
        connection.execute(
            text(
                f"DELETE FROM {_UserSetting.__tablename__} "
                "WHERE id NOT IN ("
                f"SELECT MAX(id) FROM {_UserSetting.__tablename__} "
                "GROUP BY user_hash"
                ")"
            )
        )
        connection.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS "
                f"uq_{_UserSetting.__tablename__}_user_hash "
                f"ON {_UserSetting.__tablename__} (user_hash)"
            )
        )
