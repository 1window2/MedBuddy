# File Name: test_patient_caregiver_link_api.py
# Role: Regression coverage for the patient-caregiver link lifecycle across separate HTTP
#   clients.
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

from api.dependencies import (  # noqa: E402
    get_authorization_control,
    get_link_patient_caregiver_control,
    get_registered_principal,
)
from api.router import router  # noqa: E402
from controls.authorization_control import AuthorizationControl  # noqa: E402
from controls.link_patient_caregiver_control import (  # noqa: E402
    LinkPatientCaregiver,
)
from core.database import Base  # noqa: E402
from core.request_rate_limits import RequestRateLimitStore  # noqa: E402
from entities.authenticated_principal_entity import (  # noqa: E402
    AuthenticatedPrincipal,
)


# Class Name: _UnavailableRedis
# Role: Redis double that forces the local fallback path without making a network connection.
# Responsibilities:
# - Raises an intentional Redis connection error for every atomic quota request.
# - Accepts client cleanup without side effects because the Redis double owns no connection.
class _UnavailableRedis:
    # Function Name: eval
    # Description:
    # - Raises an intentional Redis connection error for every atomic quota request.
    # Parameters:
    # - script (str): Lua script combining quota increment and expiry.
    # - number_of_keys (int): Number of Redis keys preceding the Lua arguments.
    # - *keys_and_args (object): Redis keys and Lua arguments captured in call order.
    # Returns:
    # - No normal result; raises the configured failure described above.
    async def eval(
        self,
        script: str,
        number_of_keys: int,
        *keys_and_args: object,
    ) -> object:
        del script, number_of_keys, keys_and_args
        raise ConnectionError("Redis is intentionally unavailable in this test.")

    # Function Name: aclose
    # Description:
    # - Accepts client cleanup without side effects because the Redis double owns no
    #   connection.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def aclose(self) -> None:
        return None


# Function Name: test_patient_and_caregiver_clients_complete_link_lifecycle
# Description:
# - Runs separate patient and caregiver clients through code creation, link registration, shared
#   listing, and unlink removal.
# Parameters:
# - None.
# Returns:
# - None.
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

    # Function Name: override_link_control
    # Description:
    # - Yields a linking control with a fresh test session and closes the session after
    #   dependency cleanup.
    # Parameters:
    # - None.
    # Returns:
    # - Yields a linking control; closes its request session afterward.
    def override_link_control() -> Generator[LinkPatientCaregiver, None, None]:
        db: Session = session_factory()
        try:
            yield LinkPatientCaregiver(db=db)
        finally:
            db.close()

    # Function Name: override_authorization_control
    # Description:
    # - Yields an authorization control with an isolated request session and closes it after
    #   use.
    # Parameters:
    # - None.
    # Returns:
    # - Yields an authorization control; closes its request session afterward.
    def override_authorization_control() -> Generator[AuthorizationControl, None, None]:
        db: Session = session_factory()
        try:
            yield AuthorizationControl(db=db)
        finally:
            db.close()

    app = FastAPI()
    request_rate_limit_store = RequestRateLimitStore(
        redis_url="redis://localhost:6379",
        redis_client=_UnavailableRedis(),
    )
    app.state.request_rate_limit_store = request_rate_limit_store
    app.include_router(router, prefix="/api/v1/medication")
    app.dependency_overrides[get_authorization_control] = (
        override_authorization_control
    )
    app.dependency_overrides[get_link_patient_caregiver_control] = (
        override_link_control
    )
    app.dependency_overrides[get_registered_principal] = (
        AuthenticatedPrincipal.development_principal
    )

    # Function Name: run_link_lifecycle
    # Description:
    # - Requires both device clients to see the same active link, then empty lists after a
    #   successful caregiver unlink.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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
