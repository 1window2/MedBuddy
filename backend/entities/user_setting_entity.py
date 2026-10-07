# 파일명: user_setting_entity.py
# 역할: 사용자 접근성·언어·알림·기본 복약 시각의 저장 구조와 로컬 스키마 호환 갱신을 정의한다.

from pydantic import BaseModel
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
)
from core.database import Base
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH
from entities.user_account_entity import _UserAccount, utc_now  # noqa: F401


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
    home_schedule_source = Column(
        String, nullable=False, default="self", server_default="self"
    )
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
    home_schedule_source: str = "self"
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
        home_schedule_source: str | None = None,
    ) -> "UserSetting":
        return self.model_copy(
            update={
                "font_size": font_size,
                "reading_speed": reading_speed,
                "language": language,
                "language_mode": language_mode,
                "time_format": time_format,
                # 구형 앱이 새 필드를 보내지 않아도 기존 선택을 유지한다.
                "home_schedule_source": home_schedule_source or self.home_schedule_source,
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
            "home_schedule_source": self.home_schedule_source,
            "medication_notifications_enabled": self.medication_notifications_enabled,
            "caregiver_notifications_enabled": self.caregiver_notifications_enabled,
            "chat_notifications_enabled": self.chat_notifications_enabled,
            "notification_detail_mode": self.notification_detail_mode,
            "default_morning_time": self.default_morning_time,
            "default_lunch_time": self.default_lunch_time,
            "default_evening_time": self.default_evening_time,
            "default_bedtime": self.default_bedtime,
        }

