# File Name: main.py
# Role: Creates and configures the MedBuddy FastAPI application.

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from dotenv import load_dotenv

from api.router import router as medication_router
from api.dependencies import (
    close_medication_detail_cache,
    close_pill_identification_boundaries,
)
from core.database import Base, engine
from entities import health_recommendation_cache_entity  # noqa: F401
from entities import medication_detail_entity  # noqa: F401
from entities import medication_completion_entity  # noqa: F401
from entities import medication_alarm_entity  # noqa: F401
from entities import caregiver_notification_entity  # noqa: F401
from entities import patient_caregiver_link_entity  # noqa: F401
from entities import saved_medication_entity  # noqa: F401
from entities import user_setting_entity  # noqa: F401
from entities.caregiver_notification_entity import ensure_caregiver_notification_schema
from entities.medication_completion_entity import ensure_medication_completion_schema
from entities.medication_alarm_entity import ensure_medication_alarm_schema
from entities.saved_medication_entity import ensure_saved_medication_schema
from entities.user_setting_entity import ensure_user_setting_schema


# Function Name: configure_logging
# Description:
# - Configures application logging in the bootstrap layer.
# Returns:
# - None.
def configure_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)


@asynccontextmanager
async def application_lifespan(_app: FastAPI) -> AsyncIterator[None]:
    try:
        yield
    finally:
        await close_pill_identification_boundaries()
        await close_medication_detail_cache()


# Function Name: create_app
# Description:
# - Loads environment variables.
# - Creates database tables for currently implemented models.
# - Registers medication API routes.
# Returns:
# - Configured FastAPI application.
def create_app() -> FastAPI:
    load_dotenv()
    configure_logging()
    Base.metadata.create_all(bind=engine)
    ensure_saved_medication_schema(engine)
    ensure_medication_completion_schema(engine)
    ensure_medication_alarm_schema(engine)
    ensure_caregiver_notification_schema(engine)
    ensure_user_setting_schema(engine)
    app = FastAPI(
        title="MedBuddy API",
        version="1.0.0",
        lifespan=application_lifespan,
    )
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
