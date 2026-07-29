# 파일명: user_account_entity.py
# 역할: MedBuddy 내부 사용자 범위와 외부 인증 주체의 연결 기준을 정의한다.

from datetime import UTC, datetime

from sqlalchemy import Column, DateTime, String

from core.database import Base


def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# 클래스명: _UserAccount
# 역할: 환자·보호자 데이터가 참조할 내부 사용자 식별자를 보관한다.
# 주요 책임:
# - Firebase 또는 로컬 데모 사용자를 동일한 user_hash 기준으로 표현한다.
# - 사용자 데이터 삭제 시 종속 데이터의 cascade 기준점으로 사용한다.
class _UserAccount(Base):
    __tablename__ = "user_accounts"

    user_hash = Column(String, primary_key=True)
    created_at = Column(DateTime, nullable=False, default=utc_now)
    updated_at = Column(DateTime, nullable=False, default=utc_now, onupdate=utc_now)
