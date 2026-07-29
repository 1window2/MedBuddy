from collections.abc import Generator
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, declarative_base, sessionmaker

from core.config import settings

# 파일명: database.py
# 역할: 환경별 데이터베이스 연결과 요청 단위 세션 생성을 담당한다.

SQLALCHEMY_DATABASE_URL = settings.DATABASE_URL

# 변수이름: engine
# 변수역할:
# - 로컬 SQLite와 운영 PostgreSQL에서 공통으로 사용할 연결 엔진
_engine_options: dict[str, object] = {"pool_pre_ping": True}
if SQLALCHEMY_DATABASE_URL.startswith("sqlite"):
    _engine_options["connect_args"] = {"check_same_thread": False}
else:
    _engine_options.update(
        pool_size=settings.DATABASE_POOL_SIZE,
        max_overflow=settings.DATABASE_MAX_OVERFLOW,
        pool_timeout=settings.DATABASE_POOL_TIMEOUT_SECONDS,
        pool_recycle=settings.DATABASE_POOL_RECYCLE_SECONDS,
    )

engine = create_engine(SQLALCHEMY_DATABASE_URL, **_engine_options)


# 함수명: _enable_sqlite_foreign_keys
# 역할:
# - 로컬 SQLite 연결에서도 운영 PostgreSQL과 동일하게 FK와 cascade를 적용한다.
# - SQLite가 기본적으로 비활성화하는 외래키 검사를 연결마다 활성화한다.
@event.listens_for(engine, "connect")
def _enable_sqlite_foreign_keys(dbapi_connection: object, _record: object) -> None:
    if not SQLALCHEMY_DATABASE_URL.startswith("sqlite"):
        return
    cursor = dbapi_connection.cursor()
    try:
        cursor.execute("PRAGMA foreign_keys=ON")
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
# Returns:
# - Generator yielding one Session.
def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
