# File Name: database.py
# Role: Configures environment-specific database connections and request-scoped SQLAlchemy sessions.
from collections.abc import Generator
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, declarative_base, sessionmaker

from core.config import settings


SQLALCHEMY_DATABASE_URL = settings.DATABASE_URL

# 변수이름: engine
# 변수역할:
# - 로컬 SQLite와 운영 PostgreSQL에서 공통으로 사용할 연결 엔진
_engine_options: dict[str, object] = {"pool_pre_ping": True}
if SQLALCHEMY_DATABASE_URL.startswith("sqlite"):
    _engine_options["connect_args"] = {
        "check_same_thread": False,
        "timeout": 15,
    }
else:
    _engine_options.update(
        pool_size=settings.DATABASE_POOL_SIZE,
        max_overflow=settings.DATABASE_MAX_OVERFLOW,
        pool_timeout=settings.DATABASE_POOL_TIMEOUT_SECONDS,
        pool_recycle=settings.DATABASE_POOL_RECYCLE_SECONDS,
    )

engine = create_engine(SQLALCHEMY_DATABASE_URL, **_engine_options)


# 함수이름: _configure_sqlite_connection
# 함수역할:
# - 로컬 SQLite 연결에서도 운영 PostgreSQL과 동일하게 FK와 cascade를 적용한다.
# - 앱 시작 시 겹치는 읽기 요청이 잠깐의 쓰기 작업 때문에 실패하지 않도록 한다.
# 매개변수:
# - dbapi_connection (object): 연결 이벤트에서 전달받은 원시 DB-API 연결.
# - _record (object): SQLAlchemy 연결 풀 레코드; 이 설정에서는 사용하지 않는다.
# 반환값:
# - 없음; SQLite가 아니면 설정 없이 종료한다.
@event.listens_for(engine, "connect")
def _configure_sqlite_connection(dbapi_connection: object, _record: object) -> None:
    if not SQLALCHEMY_DATABASE_URL.startswith("sqlite"):
        return
    cursor = dbapi_connection.cursor()
    try:
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA busy_timeout=15000")
    finally:
        cursor.close()

# 변수이름: SessionLocal
# 변수역할:
# - 요청 단위 SQLAlchemy 세션을 생성하는 factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# 변수이름: Base
# 변수역할:
# - SQLAlchemy ORM 엔티티들이 상속하는 declarative base
Base = declarative_base()

# Function Name: get_db
# Description:
# - Yields a SQLAlchemy session and closes it after request handling.
# Parameters:
# - None.
# Returns:
# - Generator yielding one Session.
def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
