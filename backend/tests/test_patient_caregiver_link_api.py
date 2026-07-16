import asyncio
import os
import sys
from collections.abc import Generator
from pathlib import Path

import httpx
from fastapi import FastAPI
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from api.dependencies import get_link_patient_caregiver_control  # noqa: E402
from api.router import router  # noqa: E402
from controls.link_patient_caregiver_control import (  # noqa: E402
    LinkPatientCaregiver,
)
from core.database import Base  # noqa: E402


def test_patient_and_caregiver_clients_complete_link_lifecycle() -> None:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    session_factory = sessionmaker(
        autocommit=False,
        autoflush=False,
        bind=engine,
    )

    def override_link_control() -> Generator[LinkPatientCaregiver, None, None]:
        db: Session = session_factory()
        try:
            yield LinkPatientCaregiver(db=db)
        finally:
            db.close()

    app = FastAPI()
    app.include_router(router, prefix="/api/v1/medication")
    app.dependency_overrides[get_link_patient_caregiver_control] = (
        override_link_control
    )

    async def run_link_lifecycle() -> None:
        async with (
            httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app),
                base_url="http://patient-device.test",
            ) as patient_device,
            httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app),
                base_url="http://caregiver-device.test",
            ) as caregiver_device,
        ):
            code_response = await patient_device.post(
                "/api/v1/medication/link/code",
                json={"patient_hash": "patient-device"},
            )
            assert code_response.status_code == 200
            patient_code = code_response.json()["data"]["patient_code"]

            register_response = await caregiver_device.post(
                "/api/v1/medication/link/register",
                json={
                    "caregiver_hash": "caregiver-device",
                    "patient_code": patient_code,
                },
            )
            assert register_response.status_code == 200
            link = register_response.json()["data"]
            assert link["patient_hash"] == "patient-device"
            assert link["caregiver_hash"] == "caregiver-device"
            assert link["linked"] is True

            patient_links = await patient_device.get(
                "/api/v1/medication/link/list",
                params={"user_hash": "patient-device"},
            )
            caregiver_links = await caregiver_device.get(
                "/api/v1/medication/link/list",
                params={"user_hash": "caregiver-device"},
            )
            assert patient_links.status_code == 200
            assert caregiver_links.status_code == 200
            assert patient_links.json()["data"] == [link]
            assert caregiver_links.json()["data"] == [link]

            unlink_response = await caregiver_device.delete(
                f"/api/v1/medication/link/{link['id']}",
                params={"user_hash": "caregiver-device"},
            )
            assert unlink_response.status_code == 200
            assert unlink_response.json()["data"]["linked"] is False

            patient_links_after_unlink = await patient_device.get(
                "/api/v1/medication/link/list",
                params={"user_hash": "patient-device"},
            )
            caregiver_links_after_unlink = await caregiver_device.get(
                "/api/v1/medication/link/list",
                params={"user_hash": "caregiver-device"},
            )
            assert patient_links_after_unlink.status_code == 200
            assert caregiver_links_after_unlink.status_code == 200
            assert patient_links_after_unlink.json()["data"] == []
            assert caregiver_links_after_unlink.json()["data"] == []

    try:
        asyncio.run(run_link_lifecycle())
    finally:
        app.dependency_overrides.clear()
        Base.metadata.drop_all(bind=engine)
        engine.dispose()
