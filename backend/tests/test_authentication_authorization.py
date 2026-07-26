from unittest.mock import patch

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from api.dependencies import get_authenticated_principal
from api.router import check_prescription_change, router
from controls.authorization_control import AuthorizationControl
from core.config import Settings
from core.database import Base
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from schemas.prescription_change import (
    PrescriptionChangeRequest,
    PrescriptionChangeResponse,
    PrescriptionChangeSummary,
)


@pytest.fixture
def db_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(bind=engine)
    session = sessionmaker(bind=engine)()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _principal(subject: str = "firebase-user") -> AuthenticatedPrincipal:
    return AuthenticatedPrincipal.from_verified_claims(
        {
            "uid": subject,
            "iss": "https://securetoken.google.com/medbuddy-test",
            "email": "patient@example.com",
            "email_verified": True,
        }
    )


def test_verified_claims_map_to_stable_internal_user_hash() -> None:
    first = _principal()
    second = _principal()

    assert first.user_hash == second.user_hash
    assert first.user_hash.startswith("usr_")
    assert first.user_hash != first.subject
    assert first.email_verified is True


def test_production_configuration_fails_closed_without_firebase() -> None:
    with pytest.raises(ValueError, match="AUTH_MODE=firebase"):
        Settings(
            _env_file=None,
            GEMINI_API_KEY="test",
            PUBLIC_DATA_API_KEY="test",
            APP_ENV="production",
            AUTH_MODE="disabled",
            DATABASE_URL="postgresql+psycopg://example/test",
            AUTO_CREATE_SCHEMA=False,
        )


def test_production_configuration_requires_external_migrations() -> None:
    with pytest.raises(ValueError, match="AUTO_CREATE_SCHEMA=false"):
        Settings(
            _env_file=None,
            GEMINI_API_KEY="test",
            PUBLIC_DATA_API_KEY="test",
            APP_ENV="production",
            AUTH_MODE="firebase",
            FIREBASE_PROJECT_ID="medbuddy-test",
            DATABASE_URL="postgresql+psycopg://example/test",
            AUTO_CREATE_SCHEMA=True,
        )


@pytest.mark.parametrize(
    "database_url",
    [
        "sqlite:///production.db",
        "mysql+pymysql://example/test",
        "not-a-database-url",
    ],
)
def test_production_configuration_requires_valid_postgresql_url(
    database_url: str,
) -> None:
    with pytest.raises(ValueError, match="PostgreSQL|invalid"):
        Settings(
            _env_file=None,
            GEMINI_API_KEY="test",
            PUBLIC_DATA_API_KEY="test",
            APP_ENV="production",
            AUTH_MODE="firebase",
            FIREBASE_PROJECT_ID="medbuddy-test",
            DATABASE_URL=database_url,
            AUTO_CREATE_SCHEMA=False,
        )


def test_owner_scope_ignores_untrusted_client_hash(db_session) -> None:
    principal = _principal()
    authorization = AuthorizationControl(db_session)

    assert (
        authorization.resolvePatientScope(principal, "another-patient")
        == principal.user_hash
    )
    assert (
        authorization.resolveOwnUserHash(principal, "another-user")
        == principal.user_hash
    )


def test_prescription_change_uses_server_authorized_patient_scope(db_session) -> None:
    principal = _principal()
    authorization = AuthorizationControl(db_session)

    class RecordingPrescriptionChangeControl:
        received_patient_hash: str | None = None

        def request_prescription_change(
            self,
            request: PrescriptionChangeRequest,
        ) -> PrescriptionChangeResponse:
            self.received_patient_hash = request.patient_hash
            return PrescriptionChangeResponse(
                has_previous_prescription=False,
                summary=PrescriptionChangeSummary(),
            )

    control = RecordingPrescriptionChangeControl()
    request = PrescriptionChangeRequest(
        patient_hash="untrusted-client-scope",
        medications=[{"item_name": "test medication"}],
    )

    check_prescription_change(
        request=request,
        principal=principal,
        authorization=authorization,
        check_prescription_change_control=control,  # type: ignore[arg-type]
    )

    assert control.received_patient_hash == principal.user_hash


def test_caregiver_scope_requires_active_link(db_session) -> None:
    principal = _principal("caregiver")
    authorization = AuthorizationControl(db_session)
    patient_hash = "usr_linked_patient"

    with pytest.raises(HTTPException) as denied:
        authorization.resolvePatientScope(
            principal,
            patient_hash,
            allow_caregiver=True,
        )
    assert denied.value.status_code == 403

    link = _PatientCaregiverLink(
        patient_hash=patient_hash,
        caregiver_hash=principal.user_hash,
        linked=True,
    )
    db_session.add(link)
    db_session.commit()

    assert (
        authorization.resolvePatientScope(
            principal,
            patient_hash,
            allow_caregiver=True,
        )
        == patient_hash
    )

    link.linked = False
    db_session.commit()
    with pytest.raises(HTTPException) as revoked:
        authorization.resolvePatientScope(
            principal,
            patient_hash,
            allow_caregiver=True,
        )
    assert revoked.value.status_code == 403


def test_missing_firebase_bearer_token_is_rejected() -> None:
    with patch("api.dependencies.settings.AUTH_MODE", "firebase"):
        with pytest.raises(HTTPException) as denied:
            get_authenticated_principal(None)
    assert denied.value.status_code == 401
    assert denied.value.headers == {"WWW-Authenticate": "Bearer"}


def test_medication_router_rejects_anonymous_requests_in_firebase_mode() -> None:
    app = FastAPI()
    app.include_router(router, prefix="/api/v1/medication")

    with (
        patch("api.dependencies.settings.AUTH_MODE", "firebase"),
        TestClient(app) as client,
    ):
        response = client.post(
            "/api/v1/medication/identify",
            json={"extracted_text": "test"},
        )

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_unverified_firebase_email_is_rejected() -> None:
    verifier = type(
        "Verifier",
        (),
        {
            "verifyIdToken": lambda self, token: {
                "uid": "unverified-user",
                "iss": "https://securetoken.google.com/medbuddy-test",
                "email": "unverified@example.com",
                "email_verified": False,
            }
        },
    )()
    credentials = HTTPAuthorizationCredentials(
        scheme="Bearer",
        credentials="valid-token",
    )

    with (
        patch("api.dependencies.settings.AUTH_MODE", "firebase"),
        patch("api.dependencies.get_oidc_token_verifier", return_value=verifier),
    ):
        with pytest.raises(HTTPException) as denied:
            get_authenticated_principal(credentials)

    assert denied.value.status_code == 403


def test_verified_firebase_token_creates_principal() -> None:
    verifier = type(
        "Verifier",
        (),
        {
            "verifyIdToken": lambda self, token: {
                "uid": "verified-user",
                "iss": "https://securetoken.google.com/medbuddy-test",
                "email": "verified@example.com",
                "email_verified": True,
            }
        },
    )()
    credentials = HTTPAuthorizationCredentials(
        scheme="Bearer",
        credentials="valid-token",
    )

    with (
        patch("api.dependencies.settings.AUTH_MODE", "firebase"),
        patch("api.dependencies.get_oidc_token_verifier", return_value=verifier),
    ):
        principal = get_authenticated_principal(credentials)

    assert principal.subject == "verified-user"
    assert principal.authentication_disabled is False


@pytest.mark.parametrize(
    ("provider", "allow_setting"),
    [
        ("phone", "FIREBASE_ALLOW_PHONE_AUTH"),
        ("anonymous", "FIREBASE_ALLOW_ANONYMOUS_AUTH"),
    ],
)
def test_non_email_firebase_provider_requires_explicit_opt_in(
    provider: str,
    allow_setting: str,
) -> None:
    verifier = type(
        "Verifier",
        (),
        {
            "verifyIdToken": lambda self, token: {
                "uid": f"{provider}-user",
                "iss": "https://securetoken.google.com/medbuddy-test",
                "phone_number": "+821012345678" if provider == "phone" else None,
                "firebase": {"sign_in_provider": provider},
            }
        },
    )()
    credentials = HTTPAuthorizationCredentials(
        scheme="Bearer",
        credentials="valid-token",
    )

    with (
        patch("api.dependencies.settings.AUTH_MODE", "firebase"),
        patch("api.dependencies.get_oidc_token_verifier", return_value=verifier),
        patch(f"api.dependencies.settings.{allow_setting}", False),
    ):
        with pytest.raises(HTTPException) as denied:
            get_authenticated_principal(credentials)
    assert denied.value.status_code == 403

    with (
        patch("api.dependencies.settings.AUTH_MODE", "firebase"),
        patch("api.dependencies.get_oidc_token_verifier", return_value=verifier),
        patch(f"api.dependencies.settings.{allow_setting}", True),
    ):
        principal = get_authenticated_principal(credentials)

    assert principal.sign_in_provider == provider
    assert principal.anonymous is (provider == "anonymous")


def test_password_provider_still_requires_verified_email() -> None:
    verifier = type(
        "Verifier",
        (),
        {
            "verifyIdToken": lambda self, token: {
                "uid": "password-user",
                "iss": "https://securetoken.google.com/medbuddy-test",
                "email": "unverified@example.com",
                "email_verified": False,
                "firebase": {"sign_in_provider": "password"},
            }
        },
    )()
    credentials = HTTPAuthorizationCredentials(
        scheme="Bearer",
        credentials="valid-token",
    )

    with (
        patch("api.dependencies.settings.AUTH_MODE", "firebase"),
        patch("api.dependencies.get_oidc_token_verifier", return_value=verifier),
    ):
        with pytest.raises(HTTPException) as denied:
            get_authenticated_principal(credentials)

    assert denied.value.status_code == 403
