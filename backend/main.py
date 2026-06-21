# 파일명: main.py
# 역할: MedBuddy FastAPI 애플리케이션을 생성하고 설정한다.

import logging

from fastapi import FastAPI
from dotenv import load_dotenv

from api.router import router as medication_router
from core.database import Base, engine
from entities import medication_detail_entity  # noqa: F401
from entities import patient_caregiver_link_entity  # noqa: F401
from entities import saved_medication_entity  # noqa: F401
from entities.saved_medication_entity import ensure_saved_medication_schema


# 함수명: configure_logging
# 함수역할:
# - Configures application logging in the bootstrap layer.
# 반환값:
# - None.
def configure_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )


# 함수명: create_app
# 함수역할:
# - 환경변수를 로드한다.
# - 현재 구현된 모델의 데이터베이스 테이블을 생성한다.
# - Registers medication API routes.
# 반환값:
# - Configured FastAPI application.
def create_app() -> FastAPI:
    load_dotenv()
    configure_logging()
    Base.metadata.create_all(bind=engine)
    ensure_saved_medication_schema(engine)

    app = FastAPI(title="MedBuddy API", version="1.0.0")
    app.include_router(
        medication_router,
        prefix="/api/v1/medication",
        tags=["Medication"],
    )
    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
