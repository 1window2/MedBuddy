# 파일명: user_setting_entity.py
# 역할: 사용자 접근성·언어·알림·기본 복약 시각의 저장 구조와 로컬 스키마 호환 갱신을 정의한다.

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


# Function Name: utc_now
# Description:
# - Returns naive UTC for database timestamps.
# Parameters:
# - None.
# Returns:
# - Current UTC datetime without timezone metadata.
def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# 클래스명: _UserSetting
# 역할:
# - 계정별 접근성·언어·알림·기본 복약 시각을 한 행에 저장하고 계정 삭제에 연동한다.
# 주요 책임:
# - 계정별 유일 설정과 기본값을 보관하고 계정이 삭제되면 설정도 제거한다.
# 속성:
# - user_hash (String): 작업 대상 계정의 데이터 소유 범위 식별자.
# - font_size (Integer): 지원하는 접근성 범위의 표시 글자 크기.
# - reading_speed (Float): 음성 읽기 속도 배율.
# - language (String): 요청한 한국어 또는 영어 콘텐츠 언어.
# - language_mode (String): 명시적 언어 또는 시스템 언어 사용 설정.
# - time_format (String): 사용자가 선택한 12시간제·24시간제 표시.
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


# 클래스명: UserSetting
# 역할:
# - 접근성·언어·알림 표시와 기본 시간대 설정을 전달하고 원본을 보존한 갱신을 지원한다.
# 주요 책임:
# - 사용자 식별자는 보존하고 설정 변경을 새 복사본으로 반환하며 전체 설정을 직렬화한다.
# 속성:
# - user_hash (str): 작업 대상 계정의 데이터 소유 범위 식별자.
# - font_size (int): 지원하는 접근성 범위의 표시 글자 크기.
# - reading_speed (float): 음성 읽기 속도 배율.
# - language (str): 요청한 한국어 또는 영어 콘텐츠 언어.
# - language_mode (str): 명시적 언어 또는 시스템 언어 사용 설정.
# - time_format (str): 사용자가 선택한 12시간제·24시간제 표시.
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

    # 함수이름: updateUserSetting
    # 함수역할:
    # - 사용자 식별자는 유지하면서 접근성·언어·알림·기본 시각을 바꾼 복사본을 만든다.
    # 매개변수:
    # - font_size (int): 지원하는 접근성 범위의 표시 글자 크기.
    # - reading_speed (float): 음성 읽기 속도 배율.
    # - language (str): 요청한 한국어 또는 영어 콘텐츠 언어.
    # - language_mode (str): 명시적 언어 또는 시스템 언어 사용 설정.
    # - time_format (str): 사용자가 선택한 12시간제·24시간제 표시.
    # - medication_notifications_enabled (bool): 복약 알림 전체 활성 여부.
    # - caregiver_notifications_enabled (bool): 보호자 알림 전체 활성 여부.
    # - chat_notifications_enabled (bool): 새 채팅 메시지 알림 전체 활성 여부.
    # - notification_detail_mode (str): 알림 미리보기의 전체 내용·종류만 표시 모드.
    # - default_morning_time (str): HH:MM 형식의 기본 아침 알림 시각.
    # - default_lunch_time (str): HH:MM 형식의 기본 점심 알림 시각.
    # - default_evening_time (str): HH:MM 형식의 기본 저녁 알림 시각.
    # - default_bedtime (str): HH:MM 형식의 기본 취침 전 알림 시각.
    # 반환값:
    # - 요청 값이 반영된 새 UserSetting; 원본은 변경하지 않는다.
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

    # 함수이름: getUserSetting
    # 함수역할:
    # - 저장 또는 응답에 필요한 전체 사용자 설정을 명시적 필드 사전으로 내보낸다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 사용자 식별자와 접근성·언어·알림·기본 시각 설정.
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


# 함수이름: ensure_user_setting_schema
# 함수역할:
# - 로컬 호환 테이블·누락 열을 만들고 기본값을 보완한 뒤 사용자별 최신 행만 남겨 유일 인덱스를 만든다.
# 매개변수:
# - db_engine (Engine): 스키마 확인과 호환성 갱신에 사용할 DB 엔진.
# 반환값:
# - 없음.
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
