# File Name: user_setting_entity.py
# Role: Entity/DTO definitions for user display and reading settings.

from datetime import UTC, datetime

from pydantic import BaseModel
from sqlalchemy import Column, DateTime, Float, Integer, String, inspect, text
from sqlalchemy.engine import Engine

from core.database import Base
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH


def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


class _UserSetting(Base):
    __tablename__ = "user_settings"

    id = Column(Integer, primary_key=True, index=True)
    user_hash = Column(
        String,
        unique=True,
        index=True,
        nullable=False,
        default=DEFAULT_PATIENT_HASH,
        server_default=DEFAULT_PATIENT_HASH,
    )
    font_size = Column(Integer, nullable=False, default=16, server_default="16")
    reading_speed = Column(Float, nullable=False, default=1.0, server_default="1.0")
    language = Column(String, nullable=False, default="ko", server_default="ko")
    updated_at = Column(DateTime, nullable=False, default=utc_now, onupdate=utc_now)


# Class Name: UserSetting
# Role: Represents local user display and reading settings.
class UserSetting(BaseModel):
    user_hash: str = DEFAULT_PATIENT_HASH
    font_size: int = 16
    reading_speed: float = 1.0
    language: str = "ko"

    def updateUserSetting(
        self,
        font_size: int,
        reading_speed: float,
        language: str,
    ) -> "UserSetting":
        return self.model_copy(
            update={
                "font_size": font_size,
                "reading_speed": reading_speed,
                "language": language,
            }
        )

    def getUserSetting(self) -> dict[str, object]:
        return {
            "user_hash": self.user_hash,
            "font_size": self.font_size,
            "reading_speed": self.reading_speed,
            "language": self.language,
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
