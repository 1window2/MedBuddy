# 파일명: device_push_token_entity.py
# 역할: Firebase Cloud Messaging 기기 토큰의 사용자 소유권과 활성 상태를 저장한다.

from datetime import UTC, datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)

from core.database import Base
from entities.user_account_entity import _UserAccount  # noqa: F401


# 함수이름: utc_now
# 함수역할:
# - DB에 저장할 시간대 정보 없는 UTC 현재 시각을 반환한다.
# 매개변수:
# - 없음.
# 반환값:
# - 시간대 정보가 없는 현재 UTC datetime.
def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# 클래스명: _DevicePushToken
# 역할:
# - 한 사용자에게 등록된 FCM 기기 토큰을 표현하는 내부 DB 모델이다.
# 주요 책임:
# - FCM 토큰을 인증된 사용자 hash와 연결한다.
# - 토큰 갱신과 로그아웃 시 활성 상태를 변경할 수 있게 한다.
# 속성:
# - user_hash (String): 작업 대상 계정의 데이터 소유 범위 식별자.
# - enabled (Boolean): 해당 기기 토큰의 푸시 수신 활성 상태.
# - updated_at (DateTime): 기기 토큰 등록 상태를 마지막으로 갱신한 시각.
class _DevicePushToken(Base):
    __tablename__ = "device_push_tokens"
    __table_args__ = (
        UniqueConstraint("token", name="uq_device_push_token_value"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_hash = Column(
        String,
        ForeignKey("user_accounts.user_hash", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    token = Column(String, nullable=False)
    platform = Column(String, nullable=False, default="android", server_default="android")
    enabled = Column(Boolean, nullable=False, default=True, server_default="1")
    created_at = Column(DateTime, nullable=False, default=utc_now)
    updated_at = Column(DateTime, nullable=False, default=utc_now, onupdate=utc_now)
