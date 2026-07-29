# File Name: main.py
# Role: Creates and configures the MedBuddy FastAPI application.

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from api.router import auth_router, router as medication_router
from api.dependencies import (
    close_medication_detail_cache,
    close_pill_identification_boundaries,
    get_oidc_token_verifier,
)
from boundaries.pill_identification_boundary import MAX_PILL_IMAGE_BYTES
from controls.input_prescription_control import MAX_PRESCRIPTION_IMAGE_BYTES
from core.config import settings
from core.database import Base, engine
from core.request_limits import RequestBodyLimitMiddleware
from entities import health_recommendation_cache_entity  # noqa: F401
from entities import medication_detail_entity  # noqa: F401
from entities import medication_completion_entity  # noqa: F401
from entities import medication_alarm_entity  # noqa: F401
from entities import caregiver_notification_entity  # noqa: F401
from entities import device_push_token_entity  # noqa: F401
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
    configure_logging()
    if settings.AUTO_CREATE_SCHEMA:
        Base.metadata.create_all(bind=engine)
        if engine.dialect.name == "sqlite":
            ensure_saved_medication_schema(engine)
            ensure_medication_completion_schema(engine)
            ensure_medication_alarm_schema(engine)
            ensure_caregiver_notification_schema(engine)
            ensure_user_setting_schema(engine)
    app = FastAPI(
        title="MedBuddy API",
        version="0.0.9-alpha",
        lifespan=application_lifespan,
        docs_url=None if settings.APP_ENV == "production" else "/docs",
        redoc_url=None if settings.APP_ENV == "production" else "/redoc",
        openapi_url=None if settings.APP_ENV == "production" else "/openapi.json",
    )
    multipart_overhead_bytes = 512 * 1024
    app.add_middleware(
        RequestBodyLimitMiddleware,
        limits={
            "/api/v1/medication/upload-prescription": (
                MAX_PRESCRIPTION_IMAGE_BYTES + multipart_overhead_bytes
            ),
            "/api/v1/medication/pill-identification/candidates": (
                2 * MAX_PILL_IMAGE_BYTES + multipart_overhead_bytes
            ),
        },
    )
    app.include_router(
        medication_router,
        prefix="/api/v1/medication",
        tags=["Medication"],
    )
    app.include_router(auth_router)

    @app.get("/health", include_in_schema=False)
    def health_check() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/ready", include_in_schema=False)
    def readiness_check() -> dict[str, str]:
        try:
            with engine.connect() as connection:
                connection.execute(text("SELECT 1"))
            if settings.AUTH_MODE == "firebase":
                get_oidc_token_verifier()
        except (SQLAlchemyError, RuntimeError, ValueError) as exc:
            raise HTTPException(
                status_code=503,
                detail="MedBuddy dependencies are not ready.",
            ) from exc
        return {"status": "ready"}

    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
