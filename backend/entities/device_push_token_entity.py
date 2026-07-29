# 파일명: device_push_token_entity.py
# 역할: Firebase Cloud Messaging 기기 토큰의 사용자 소유권과 활성 상태를 저장한다.

from datetime import UTC, datetime

from sqlalchemy import Boolean, Column, DateTime, Integer, String, UniqueConstraint

from core.database import Base


# 함수명: utc_now
# 역할:
# - DB에 저장할 시간대 정보 없는 UTC 현재 시각을 반환한다.
def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# 클래스명: _DevicePushToken
# 역할: 한 사용자에게 등록된 FCM 기기 토큰을 표현하는 내부 DB 모델이다.
# 주요 책임:
#   - FCM 토큰을 인증된 사용자 hash와 연결한다.
#   - 토큰 갱신과 로그아웃 시 활성 상태를 변경할 수 있게 한다.
class _DevicePushToken(Base):
    __tablename__ = "device_push_tokens"
    __table_args__ = (
        UniqueConstraint("token", name="uq_device_push_token_value"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_hash = Column(String, nullable=False, index=True)
    token = Column(String, nullable=False)
    platform = Column(String, nullable=False, default="android", server_default="android")
    enabled = Column(Boolean, nullable=False, default=True, server_default="1")
    created_at = Column(DateTime, nullable=False, default=utc_now)
    updated_at = Column(DateTime, nullable=False, default=utc_now, onupdate=utc_now)
