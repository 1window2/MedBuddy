# File Name: main.py
# Role: Creates and configures the MedBuddy FastAPI application.

import logging

from fastapi import FastAPI
from dotenv import load_dotenv

from api.router import router as medication_router
from core.database import engine
from models.db_models import Base


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
