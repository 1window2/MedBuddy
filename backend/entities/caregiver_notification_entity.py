# File Name: caregiver_notification_entity.py
# Role: Defines caregiver notification persistence, per-slot domain settings and legacy option normalization.

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


# Function Name: utc_now
# Description:
# - Returns naive UTC for database timestamps.
# Parameters:
# - None.
# Returns:
# - Current UTC datetime without timezone metadata.
def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# 클래스명: _CaregiverNotification
# 역할:
# - 보호자·환자 쌍의 시간대별 알림 JSON과 기존 단일 설정 호환 열을 저장한다.
# 주요 책임:
# - 보호자·환자 쌍의 유일성을 유지하고 시간대 설정과 기존 guardian 필드의 호환 상태를 보관한다.
# 속성:
# - caregiver_hash (String): 환자와 연동된 보호자 계정 식별자.
# - patient_hash (String): 작업 대상 환자의 데이터 소유 범위 식별자.
# - enabled (Boolean): 요청한 알림 활성 상태.
# - alert_option (String): 기존 활성 플래그보다 우선하는 선택적 알림 모드.
# - deadline_hour (Integer): 선택적인 미복용 마감 시.
# - deadline_minute (Integer): 선택적인 미복용 마감 분.
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
# 역할:
# - 보호자-환자-복약 시간대별 알림 설정을 표현한다.
# 주요 책임:
# - 알림 모드와 미복용 확인 시각을 검증한다.
# - Flutter 화면과 호환되는 응답 필드로 변환한다.
# 속성:
# - patient_hash (str): 작업 대상 환자의 데이터 소유 범위 식별자.
# - caregiver_hash (str): 환자와 연동된 보호자 계정 식별자.
# - slot_key (str): morning, lunch, evening, bedtime 중 복용 시간대 키.
# - notification_enabled (bool): 해당 알림 설정의 활성 여부.
# - notification_type (str): 기존 enable/disable 별칭을 포함하는 지원 알림 모드.
# - deadline_hour (int | None): 선택적인 미복용 마감 시.
class CaregiverNotification(BaseModel):
    notification_id: int | None = None
    patient_hash: str = ""
    caregiver_hash: str = ""
    slot_key: str = "morning"
    notification_enabled: bool = False
    notification_type: str = Field(default=CAREGIVER_NOTIFICATION_MODE_DISABLED)
    deadline_hour: int | None = Field(default=None, ge=0, le=23)
    deadline_minute: int | None = Field(default=None, ge=0, le=59)

    # 함수이름: updateNotificationSetting
    # 함수역할:
    # - 알림 모드를 정규화하고 미복용 마감 모드에는 시각을 요구하며 나머지 모드의 마감 시각은 제거한다.
    # 매개변수:
    # - notification_option (str | bool): 현재·기존 알림 모드 또는 활성 플래그.
    # - deadline_hour (int | None): 선택적인 미복용 마감 시.
    # - deadline_minute (int | None): 선택적인 미복용 마감 분.
    # 반환값:
    # - 갱신된 CaregiverNotification 복사본; 원본은 변경하지 않는다.
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

    # 함수이름: to_response_dict
    # 함수역할:
    # - 보호자·환자 알림 상태를 기존 필드 별칭과 함께 응답 사전으로 직렬화한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 활성 여부, 모드, 시간대와 마감 시각을 담은 사전.
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


# 함수이름: alert_option_from_enabled
# 함수역할:
# - 기존 활성 플래그를 복용 완료 알림 또는 비활성 모드로 변환한다.
# 매개변수:
# - enabled (bool): 요청한 알림 활성 상태.
# 반환값:
# - True는 dose_completed, False는 disabled.
def alert_option_from_enabled(enabled: bool) -> str:
    return (
        CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED
        if enabled
        else CAREGIVER_NOTIFICATION_MODE_DISABLED
    )


# 함수이름: enabled_from_alert_option
# 함수역할:
# - 문자열 알림 옵션을 정규화해 비활성 모드인지 확인한다.
# 매개변수:
# - alert_option (str): 기존 활성 플래그보다 우선하는 선택적 알림 모드.
# 반환값:
# - 정규화한 모드가 disabled가 아니면 True.
def enabled_from_alert_option(alert_option: str) -> bool:
    return (
        normalize_notification_mode(alert_option)
        != CAREGIVER_NOTIFICATION_MODE_DISABLED
    )


# 함수이름: normalize_notification_mode
# 함수역할:
# - 기존 불리언·문자열 별칭을 완료·미복용 마감·비활성 알림 모드로 통일한다.
# 매개변수:
# - notification_option (str | bool): 현재·기존 알림 모드 또는 활성 플래그.
# 반환값:
# - 지원 모드 문자열; 알 수 없는 값은 ValueError.
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


# 함수이름: normalize_notification_slot
# 함수역할:
# - 알림 시간대의 공백과 대소문자를 정리하고 지원 목록에 포함되는지 확인한다.
# 매개변수:
# - slot_key (str): morning, lunch, evening, bedtime 중 복용 시간대 키.
# 반환값:
# - 지원 시간대 키; 잘못된 값은 ValueError.
def normalize_notification_slot(slot_key: str) -> str:
    normalized_slot_key = (slot_key or "").strip().lower()
    if normalized_slot_key not in CAREGIVER_NOTIFICATION_SLOT_KEYS:
        raise ValueError("Caregiver notification slot is not supported.")
    return normalized_slot_key


# 함수이름: decode_slot_settings
# 함수역할:
# - DB에 저장된 시간대별 보호자 알림 JSON을 안전한 dict로 변환한다.
# 매개변수:
# - raw_settings (str | None): 없거나 잘못되었을 수 있는 저장 시간대별 알림 JSON.
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


# 함수이름: encode_slot_settings
# 함수역할:
# - 시간대별 알림 설정을 비ASCII 문자를 보존한 JSON으로 저장한다.
# 매개변수:
# - settings (dict[str, dict[str, object]]): 복용 시간대 키별 알림 설정.
# 반환값:
# - 저장용 JSON 문자열.
def encode_slot_settings(settings: dict[str, dict[str, object]]) -> str:
    return json.dumps(settings, ensure_ascii=False, separators=(",", ":"))


# 함수이름: ensure_caregiver_notification_schema
# 함수역할:
# - 기존 SQLite DB를 보존하면서 보호자 알림 설정 스키마를 확장한다.
# 매개변수:
# - db_engine (Engine): 애플리케이션 DB에 연결된 SQLAlchemy 엔진
# 반환값:
# - 없음.
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
