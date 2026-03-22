from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# 데이터베이스 파일 이름 설정
SQLALCHEMY_DATABASE_URL = "sqlite:///./medbuddy.db"

# SQLite 연결 엔진 생성
engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)

# 세션 생성기
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# DB 모델들이 상속받을 기본 클래스
Base = declarative_base()

# DB 세션을 가져오고 반환하는 의존성 함수
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()