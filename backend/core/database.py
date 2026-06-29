from collections.abc import Generator
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, declarative_base, sessionmaker

DATABASE_PATH = Path(__file__).resolve().parents[1] / "medbuddy.db"
SQLALCHEMY_DATABASE_URL = f"sqlite:///{DATABASE_PATH.as_posix()}"

# Create the SQLite connection engine.
engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)

# Create request-scoped SQLAlchemy sessions.
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Base class inherited by SQLAlchemy ORM entities.
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
