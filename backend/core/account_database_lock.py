# 파일명: account_database_lock.py
# 역할: 계정 삭제와 짧은 DB 작업에 공통 transaction 잠금을 제공한다.

from collections.abc import Iterable

from sqlalchemy import text
from sqlalchemy.orm import Session

# 계정 잠금이나 DB 연결을 제때 얻지 못한 요청에 돌려주는 503 안내문이다. 클라이언트가
# 이 문구로 재시도 여부를 판단하므로 모든 응답 지점이 이 상수 하나를 사용한다.
ACCOUNT_BUSY_DETAIL = "This account is busy. Retry the request shortly."


# 계정 삭제와 짧은 DB 작업을 직렬화한다. 여러 계정은 항상 같은 순서로 잠근다.
# 함수이름: lock_account_operations
# 함수역할: 새 transaction에 계정 잠금을 획득하고 중첩 transaction은 거부한다.
# 매개변수: db: 작업 세션, user_hashes: 보호할 계정 식별자 목록.
# 반환값: 없음. 중첩 transaction 또는 지원하지 않는 DB는 RuntimeError.
def lock_account_operations(db: Session, user_hashes: Iterable[str]) -> None:
    if db.in_transaction():
        raise RuntimeError("Account database phase requires a fresh transaction.")
    dialect = db.get_bind().dialect.name
    if dialect == "postgresql":
        db.execute(
            text("SELECT set_config('lock_timeout', :timeout, true)"),
            {"timeout": "5s"},
        )
        for user_hash in sorted(set(user_hashes)):
            db.execute(
                text("SELECT pg_advisory_xact_lock(hashtextextended(:user_hash, 0))"),
                {"user_hash": user_hash},
            )
    elif dialect == "sqlite":
        db.connection().exec_driver_sql("BEGIN IMMEDIATE")
    else:
        raise RuntimeError(
            "Authenticated account-operation locking requires PostgreSQL or SQLite."
        )
