# 파일명: caregiver_notification_entity.py
# 역할: 보호자 알림 설정의 SQLAlchemy 저장 모델과 API DTO를 정의한다.

import json
from datetime import UTC, datetime

from pydantic import BaseModel, Field
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    inspect,
    text,
)
from sqlalchemy.engine import Engine

from core.database import Base
from entities.user_account_entity import _UserAccount  # noqa: F401

CAREGIVER_NOTIFICATION_MODE_DISABLED = "disabled"
CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED = "dose_completed"
CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE = "missed_deadline"
CAREGIVER_NOTIFICATION_SLOT_KEYS = (
    "morning",
    "lunch",
    "evening",
    "bedtime",
)
_SUPPORTED_NOTIFICATION_MODES = {
    CAREGIVER_NOTIFICATION_MODE_DISABLED,
    CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
}


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
    caregiver_hash = Column(
        "guardian_hash",
        String,
        ForeignKey("user_accounts.user_hash", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    patient_hash = Column(
        String,
        ForeignKey("user_accounts.user_hash", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    enabled = Column(Boolean, nullable=False, default=False, server_default="0")
    alert_option = Column(
        String,
        nullable=False,
        default=CAREGIVER_NOTIFICATION_MODE_DISABLED,
        server_default=CAREGIVER_NOTIFICATION_MODE_DISABLED,
    )
    deadline_hour = Column(Integer, nullable=True)
    deadline_minute = Column(Integer, nullable=True)
    slot_settings = Column(Text, nullable=False, default="{}", server_default="{}")
    created_at = Column(DateTime, nullable=False, default=utc_now)
    updated_at = Column(DateTime, nullable=False, default=utc_now, onupdate=utc_now)


# 클래스명: CaregiverNotification
# 역할: 보호자-환자-복약 시간대별 알림 설정을 표현한다.
# 주요 책임:
# - 알림 모드와 미복용 확인 시각을 검증한다.
# - Flutter 화면과 호환되는 응답 필드로 변환한다.
class CaregiverNotification(BaseModel):
    notification_id: int | None = None
    patient_hash: str = ""
    caregiver_hash: str = ""
    slot_key: str = "morning"
    notification_enabled: bool = False
    notification_type: str = Field(default=CAREGIVER_NOTIFICATION_MODE_DISABLED)
    deadline_hour: int | None = Field(default=None, ge=0, le=23)
    deadline_minute: int | None = Field(default=None, ge=0, le=59)

    # 함수명: updateNotificationSetting
    # 역할:
    # - 선택한 알림 모드와 마감 시각을 반영한 새 객체를 반환한다.
    def updateNotificationSetting(
        self,
        notification_option: str | bool,
        deadline_hour: int | None = None,
        deadline_minute: int | None = None,
    ) -> "CaregiverNotification":
        notification_mode = normalize_notification_mode(notification_option)
        if notification_mode == CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE:
            if deadline_hour is None or deadline_minute is None:
                raise ValueError("Missed-dose notifications require a deadline.")
        else:
            deadline_hour = None
            deadline_minute = None
        return self.model_copy(
            update={
                "notification_enabled": (
                    notification_mode != CAREGIVER_NOTIFICATION_MODE_DISABLED
                ),
                "notification_type": notification_mode,
                "deadline_hour": deadline_hour,
                "deadline_minute": deadline_minute,
            }
        )

    # 함수명: to_response_dict
    # 역할:
    # - Flutter 계층과 이전 guardian 필드가 함께 사용할 응답으로 변환한다.
    def to_response_dict(self) -> dict[str, object]:
        return {
            "notification_id": self.notification_id,
            "setting_id": self.notification_id,
            "patient_hash": self.patient_hash,
            "caregiver_hash": self.caregiver_hash,
            "guardian_hash": self.caregiver_hash,
            "slot_key": self.slot_key,
            "notification_enabled": self.notification_enabled,
            "is_enabled": self.notification_enabled,
            "enabled": self.notification_enabled,
            "notification_type": self.notification_type,
            "alert_option": self.notification_type,
            "deadline_hour": self.deadline_hour,
            "deadline_minute": self.deadline_minute,
        }


def alert_option_from_enabled(enabled: bool) -> str:
    return (
        CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED
        if enabled
        else CAREGIVER_NOTIFICATION_MODE_DISABLED
    )


def enabled_from_alert_option(alert_option: str) -> bool:
    return (
        normalize_notification_mode(alert_option)
        != CAREGIVER_NOTIFICATION_MODE_DISABLED
    )


def normalize_notification_mode(notification_option: str | bool) -> str:
    if isinstance(notification_option, bool):
        return alert_option_from_enabled(notification_option)
    normalized_option = (notification_option or "").strip().lower()
    if normalized_option in {
        "enable",
        "enabled",
        "on",
        "true",
        "1",
        CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
    }:
        return CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED
    if normalized_option in {
        "disable",
        "off",
        "false",
        "0",
        CAREGIVER_NOTIFICATION_MODE_DISABLED,
    }:
        return CAREGIVER_NOTIFICATION_MODE_DISABLED
    if normalized_option == CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE:
        return CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE
    raise ValueError("Caregiver notification option is not supported.")


def normalize_notification_slot(slot_key: str) -> str:
    normalized_slot_key = (slot_key or "").strip().lower()
    if normalized_slot_key not in CAREGIVER_NOTIFICATION_SLOT_KEYS:
        raise ValueError("Caregiver notification slot is not supported.")
    return normalized_slot_key


# 함수명: decode_slot_settings
# 역할:
# - DB에 저장된 시간대별 보호자 알림 JSON을 안전한 dict로 변환한다.
# 반환값:
# - 유효한 시간대 설정만 포함한 dict
def decode_slot_settings(raw_settings: str | None) -> dict[str, dict[str, object]]:
    try:
        decoded = json.loads(raw_settings or "{}")
    except (TypeError, ValueError):
        return {}
    if not isinstance(decoded, dict):
        return {}

    result: dict[str, dict[str, object]] = {}
    for raw_slot_key, raw_setting in decoded.items():
        try:
            slot_key = normalize_notification_slot(str(raw_slot_key))
        except ValueError:
            continue
        if not isinstance(raw_setting, dict):
            continue
        try:
            mode = normalize_notification_mode(
                str(
                    raw_setting.get(
                        "notification_type",
                        raw_setting.get("mode", CAREGIVER_NOTIFICATION_MODE_DISABLED),
                    )
                )
            )
        except ValueError:
            mode = CAREGIVER_NOTIFICATION_MODE_DISABLED
        deadline_hour = raw_setting.get("deadline_hour")
        deadline_minute = raw_setting.get("deadline_minute")
        if mode != CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE:
            deadline_hour = None
            deadline_minute = None
        result[slot_key] = {
            "notification_type": mode,
            "deadline_hour": deadline_hour,
            "deadline_minute": deadline_minute,
        }
    return result


# 함수명: encode_slot_settings
# 역할:
# - 시간대별 보호자 알림 설정을 DB 저장용 JSON 문자열로 변환한다.
def encode_slot_settings(settings: dict[str, dict[str, object]]) -> str:
    return json.dumps(settings, ensure_ascii=False, separators=(",", ":"))


# 함수명: ensure_caregiver_notification_schema
# 역할:
# - 기존 SQLite DB를 보존하면서 보호자 알림 설정 스키마를 확장한다.
# 매개변수:
# - db_engine: 애플리케이션 DB에 연결된 SQLAlchemy 엔진
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
        "alert_option": (
            f"VARCHAR DEFAULT '{CAREGIVER_NOTIFICATION_MODE_DISABLED}'"
        ),
        "deadline_hour": "INTEGER",
        "deadline_minute": "INTEGER",
        "slot_settings": "TEXT DEFAULT '{}'",
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
                "SET slot_settings = '{}' "
                "WHERE slot_settings IS NULL OR TRIM(slot_settings) = ''"
            )
        )
        connection.execute(
            text(
                f"UPDATE {_CaregiverNotification.__tablename__} "
                "SET alert_option = CASE "
                f"WHEN enabled = 1 THEN '{CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED}' "
                f"ELSE '{CAREGIVER_NOTIFICATION_MODE_DISABLED}' END "
                "WHERE alert_option IS NULL "
                "OR LOWER(alert_option) NOT IN "
                "('disabled', 'dose_completed', 'missed_deadline')"
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
