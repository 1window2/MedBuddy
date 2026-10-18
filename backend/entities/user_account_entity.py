# 파일명: user_account_entity.py
# 역할: MedBuddy 내부 사용자 범위와 외부 인증 주체의 연결 기준을 정의한다.

from datetime import UTC, datetime

from sqlalchemy import Column, DateTime, String

from core.database import Base


# 함수이름: utc_now
# 함수역할:
# - DB 시각 저장에 사용할 시간대 정보 없는 현재 UTC를 구한다.
# 매개변수:
# - 없음.
# 반환값:
# - 시간대 정보가 없는 현재 UTC datetime.
def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# 함수이름: as_naive_utc
# 함수역할:
# - 시간대가 있는 시각은 UTC로 변환한 뒤 시간대 정보를 제거하여 DB 저장값과 비교 가능하게 한다.
# 매개변수:
# - value (datetime): 정규화할 시각; 시간대 정보가 없으면 이미 UTC로 간주한다.
# 반환값:
# - 시간대 정보가 없는 UTC datetime; 원래 naive 값은 그대로 반환한다.
def as_naive_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone(UTC).replace(tzinfo=None)


# 함수이름: utc_isoformat
# 함수역할:
# - DB의 시간대 없는 UTC 시각 또는 시간대가 있는 시각을 명시적인 UTC ISO 문자열로 변환한다.
# 매개변수:
# - value (datetime | None): 변환할 시각; 시간대 정보가 없으면 UTC로 간주한다.
# 반환값:
# - UTC 오프셋을 포함한 ISO 8601 문자열, 입력이 None이면 None.
def utc_isoformat(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    else:
        value = value.astimezone(UTC)
    return value.isoformat()


# Class Name: _UserAccount
# Role:
# - Stores internal account scopes and durable local-deletion and external-identity completion markers.
# Responsibilities:
# - Anchor user-owned foreign keys and distinguish deletion requested from external identity deletion completed.
# Attributes:
# - user_hash (String): Account ownership scope for the operation.
# - updated_at (DateTime): Timestamp of the most recent account-row update.
class _UserAccount(Base):
    __tablename__ = "user_accounts"

    user_hash = Column(String, primary_key=True)
    created_at = Column(DateTime, nullable=False, default=utc_now)
    updated_at = Column(DateTime, nullable=False, default=utc_now, onupdate=utc_now)
    deletion_requested_at = Column(DateTime, nullable=True)
    identity_deleted_at = Column(DateTime, nullable=True)
