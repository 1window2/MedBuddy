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


# Function Name: as_naive_utc
# Description: Convert an aware timestamp to UTC and remove timezone metadata; already-naive values are treated as UTC and left unchanged.
# Parameters: value (datetime) is the timestamp to normalize for database storage.
# Returns: datetime without tzinfo.
def as_naive_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone(UTC).replace(tzinfo=None)


# Function Name: utc_isoformat
# Description: Serialize aware timestamps in UTC and interpret naive timestamps as UTC.
# Parameters: value (datetime | None) is the optional database timestamp.
# Returns: str ISO timestamp with UTC offset, or None for an absent value.
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
