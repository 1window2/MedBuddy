from collections.abc import Generator
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, declarative_base, sessionmaker

# 파일명: database.py
# 역할: SQLite 데이터베이스 연결과 요청 단위 세션 생성을 담당한다.

DATABASE_PATH = Path(__file__).resolve().parents[1] / "medbuddy.db"
SQLALCHEMY_DATABASE_URL = f"sqlite:///{DATABASE_PATH.as_posix()}"

# 변수이름: engine
# 변수역할:
# - FastAPI 요청에서 사용할 SQLite 연결 엔진
engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)

# 변수이름: SessionLocal
# 변수역할:
# - 요청 단위 SQLAlchemy 세션을 생성하는 factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# 변수이름: Base
# 변수역할:
# - SQLAlchemy ORM 엔티티들이 상속하는 declarative base
Base = declarative_base()

# 함수명: get_db
# 함수역할:
# - FastAPI 의존성 주입에서 사용할 DB 세션을 생성한다.
# - 요청 처리가 끝나면 세션을 반드시 닫는다.
# 반환값:
# - SQLAlchemy 세션을 한 번 yield하는 Generator
def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
