"""Exact-code consumption, revocation, and authenticated owner-only polling."""

import os
import sys
from datetime import timedelta
from pathlib import Path

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from api.dependencies import (
    get_authenticated_principal,
    get_authorization_control,
    get_link_patient_caregiver_control,
    get_registered_principal,
)
from api.router import router
from controls.authorization_control import AuthorizationControl
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from core.config import settings
from core.database import Base
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.patient_caregiver_link_entity import _PatientLinkCode
from entities.user_account_entity import utc_now


@pytest.fixture
def control():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(engine)
    with sessionmaker(bind=engine, autoflush=False)() as db:
        yield LinkPatientCaregiver(db)
    engine.dispose()


def issue(control, patient="patient-a"):
    return control.generatePatientHash(patient)["data"]["patient_code"]


def status(control, code, patient="patient-a"):
    return control.requestPatientCodeStatus(patient, code)["data"]


def test_status_requires_exact_code_consumption_even_for_existing_pair(control):
    old_code = issue(control)
    link = control.requestPatientCaregiverLink("caregiver-a", old_code)["data"]
    fresh_code = issue(control)
    assert status(control, fresh_code)["status"] == "pending"
    assert status(control, fresh_code)["link"] is None
    control.requestPatientCaregiverLink("caregiver-a", fresh_code)
    result = status(control, fresh_code.lower())
    assert result["status"] == "linked"
    assert result["link"]["id"] == link["id"]
    assert result["patient_code"] == fresh_code


def test_status_pending_expired_and_revoked_never_return_a_link(control):
    code = issue(control)
    assert status(control, code)["status"] == "pending"
    row = control.db.query(_PatientLinkCode).filter_by(patient_code=code).one()
    row.expires_at = utc_now() - timedelta(seconds=1)
    control.db.commit()
    assert status(control, code)["status"] == "expired"
    row.used = True
    control.db.commit()
    assert status(control, code)["status"] == "revoked"
    assert status(control, code)["link"] is None


def test_unlink_revokes_unused_and_consumed_codes_permanently(control):
    code = issue(control)
    link = control.requestPatientCaregiverLink("caregiver-a", code)["data"]
    pending = issue(control)
    control.requestUnlink(link["id"], "patient-a")
    for revoked in (code, pending):
        assert status(control, revoked)["status"] == "revoked"
        assert status(control, revoked)["link"] is None
    fresh = issue(control)
    control.requestPatientCaregiverLink("caregiver-a", fresh)
    assert status(control, fresh)["status"] == "linked"
    for revoked in (code, pending):
        assert status(control, revoked)["status"] == "revoked"


def test_unlink_preserves_other_active_consumers(control):
    code_a, code_b = issue(control), issue(control)
    link = control.requestPatientCaregiverLink("caregiver-a", code_a)["data"]
    control.requestPatientCaregiverLink("caregiver-b", code_b)
    control.requestUnlink(link["id"], "caregiver-a")
    assert status(control, code_a)["status"] == "revoked"
    assert status(control, code_b)["status"] == "linked"


def test_deleted_consumer_or_inactive_pair_is_not_success(control):
    code = issue(control)
    control.requestPatientCaregiverLink("caregiver-a", code)
    row = control.db.query(_PatientLinkCode).filter_by(patient_code=code).one()
    row.caregiver_hash = None  # Same persisted state as ON DELETE SET NULL.
    control.db.commit()
    assert status(control, code)["status"] == "revoked"


def test_status_preserves_alias_privacy_and_does_not_mutate_code(control):
    code = issue(control)
    link = control.requestPatientCaregiverLink("caregiver-a", code)["data"]
    control.updatePatientAlias(link["id"], "caregiver-a", "private patient alias")
    control.update_caregiver_alias(link["id"], "patient-a", "my caregiver")
    for _ in range(2):
        result = status(control, code)
        assert result["link"]["patient_alias"] is None
        assert result["link"]["caregiver_alias"] == "my caregiver"
    assert not control.db.dirty


@pytest.mark.parametrize("owner", ["other-patient", "caregiver-a"])
def test_status_hides_codes_from_every_non_owner(control, owner):
    code = issue(control)
    control.requestPatientCaregiverLink("caregiver-a", code)
    with pytest.raises(HTTPException) as error:
        status(control, code, owner)
    assert error.value.status_code == 404


def test_failed_registration_does_not_report_consumption(control):
    code = issue(control)
    with pytest.raises(HTTPException):
        control.requestPatientCaregiverLink("patient-a", code)
    assert status(control, code)["status"] == "pending"


def test_rolled_back_reservation_is_still_pending(control, monkeypatch):
    code = issue(control)
    monkeypatch.setattr(settings, "PATIENT_CAREGIVER_LINK_MAX_PER_ACCOUNT", 0)
    with pytest.raises(HTTPException) as error:
        control.requestPatientCaregiverLink("caregiver-a", code)
    assert error.value.status_code == 409
    assert status(control, code)["status"] == "pending"
    assert status(control, code)["link"] is None


def test_missing_code_is_opaque(control):
    with pytest.raises(HTTPException) as error:
        status(control, "NOTFOUND")
    assert error.value.status_code == 404
    assert error.value.detail == "Patient code was not found."


@pytest.fixture
def api(control):
    app = FastAPI()
    app.include_router(router, prefix="/api/v1/medication")
    app.dependency_overrides[get_registered_principal] = lambda: None
    app.dependency_overrides[get_authorization_control] = lambda: AuthorizationControl(None)
    app.dependency_overrides[get_link_patient_caregiver_control] = lambda: control
    with TestClient(app) as client:
        yield app, client


@pytest.mark.parametrize("caller", ["patient-a", "caregiver-a", "stranger"])
def test_status_endpoint_uses_authenticated_owner_not_user_hash(control, api, caller):
    app, client = api
    code = issue(control)
    control.requestPatientCaregiverLink("caregiver-a", code)
    app.dependency_overrides[get_authenticated_principal] = lambda: AuthenticatedPrincipal(
        subject=caller, issuer="test", user_hash=caller
    )
    response = client.get(
        "/api/v1/medication/link/code/status",
        params={"patient_code": code, "user_hash": "patient-a"},
    )
    assert response.status_code == (200 if caller == "patient-a" else 404)
    if caller == "patient-a":
        assert response.headers["cache-control"] == "no-store"
        assert response.json()["data"]["status"] == "linked"
    else:
        assert response.json() == {"detail": "Patient code was not found."}


def test_status_endpoint_requires_authentication(control, api, monkeypatch):
    _, client = api
    code = issue(control)
    monkeypatch.setattr(settings, "AUTH_MODE", "firebase")
    response = client.get(
        "/api/v1/medication/link/code/status",
        params={"patient_code": code, "user_hash": "patient-a"},
    )
    assert response.status_code == 401
