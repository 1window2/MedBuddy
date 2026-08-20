from unittest.mock import patch

import pytest
from fastapi import FastAPI, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from api.dependencies import (
    get_authenticated_principal,
    get_registered_principal,
    verify_app_check_token,
)
from api.router import check_prescription_change, router
from boundaries.oidc_token_verifier_boundary import (
    TokenVerificationUnavailableError,
)
from boundaries.app_check_token_verifier_boundary import (
    AppCheckTokenVerificationError,
    AppCheckTokenVerificationUnavailableError,
)
from controls.authorization_control import AuthorizationControl
from core.config import Settings
from core.database import Base
from core.request_rate_limits import RateLimitRule, RequestRateLimitStore
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.user_account_entity import _UserAccount, utc_now
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


def _production_api_settings(**overrides: object) -> Settings:
    values: dict[str, object] = {
        "_env_file": None,
        "GEMINI_API_KEY": "test",
        "PUBLIC_DATA_API_KEY": "test",
        "APP_ENV": "production",
        "RUNTIME_ROLE": "api",
        "AUTH_MODE": "firebase",
        "FIREBASE_PROJECT_ID": "medbuddy-test",
        "FIREBASE_APP_CHECK_REQUIRED": True,
        "RATE_LIMIT_ENABLED": True,
        "RATE_LIMIT_REQUIRE_REDIS": True,
        "PILL_IDENTIFICATION_CATALOG_ALLOW_INLINE_REFRESH": False,
        "DATABASE_URL": "postgresql+psycopg://example/test",
        "AUTO_CREATE_SCHEMA": False,
    }
    values.update(overrides)
    return Settings(**values)


class _RecordingRateLimitStore(RequestRateLimitStore):
    def __init__(self) -> None:
        super().__init__(redis_url="redis://unused")
        self.calls: list[tuple[str, str, RateLimitRule]] = []

    async def consume(
        self,
        *,
        identity: str,
        request_scope: str,
        rule: RateLimitRule,
    ) -> tuple[bool, int]:
        self.calls.append((identity, request_scope, rule))
        return True, 0


def _request(app: FastAPI, method: str, path: str) -> Request:
    return Request(
        {
            "type": "http",
            "http_version": "1.1",
            "method": method,
            "scheme": "https",
            "path": path,
            "raw_path": path.encode("ascii"),
            "query_string": b"",
            "headers": [],
            "client": ("203.0.113.10", 12345),
            "server": ("api.medbuddy.example", 443),
            "app": app,
        }
    )


@pytest.mark.anyio
async def test_deleted_account_only_allows_authenticated_deletion_retry(
    db_session,
) -> None:
    principal = _principal("deleted-firebase-user")
    db_session.add(
        _UserAccount(
            user_hash=principal.user_hash,
            deletion_requested_at=utc_now(),
        )
    )
    db_session.commit()
    app = FastAPI()

    with patch("api.dependencies.settings.RATE_LIMIT_ENABLED", False):
        deletion_principal = await get_registered_principal(
            request=_request(app, "DELETE", "/api/v1/auth/account-data"),
            principal=principal,
            db=db_session,
        )
        with pytest.raises(HTTPException) as denied:
            await get_registered_principal(
                request=_request(app, "GET", "/api/v1/auth/session"),
                principal=principal,
                db=db_session,
            )

    assert deletion_principal == principal
    assert denied.value.status_code == 410

def test_verified_claims_map_to_stable_internal_user_hash() -> None:
    first = _principal()
    second = _principal()

    assert first.user_hash == second.user_hash
    assert first.user_hash.startswith("usr_")
    assert first.user_hash != first.subject
    assert first.email_verified is True


@pytest.mark.anyio
async def test_registered_principal_quota_uses_stable_identity_and_route_scope(
    db_session,
) -> None:
    class RotatingTokenVerifier:
        def __init__(self) -> None:
            self.tokens: list[str] = []

        def verifyIdToken(self, token: str) -> dict[str, object]:
            self.tokens.append(token)
            return {
                "uid": "stable-firebase-user",
                "iss": "https://securetoken.google.com/medbuddy-test",
                "email": "patient@example.com",
                "email_verified": True,
            }

    verifier = RotatingTokenVerifier()
    credentials = [
        HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="rotated-token-one",
        ),
        HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="rotated-token-two",
        ),
    ]
    rate_limit_store = _RecordingRateLimitStore()
    app = FastAPI()
    app.state.request_rate_limit_store = rate_limit_store

    with (
        patch("api.dependencies.settings.AUTH_MODE", "firebase"),
        patch("api.dependencies.settings.RATE_LIMIT_ENABLED", True),
        patch("api.dependencies.get_oidc_token_verifier", return_value=verifier),
    ):
        principals = [
            get_authenticated_principal(token_credentials)
            for token_credentials in credentials
        ]
        await get_registered_principal(
            request=_request(
                app,
                "POST",
                "/api/v1/medication/identify",
            ),
            principal=principals[0],
            db=db_session,
        )
        await get_registered_principal(
            request=_request(
                app,
                "GET",
                "/api/v1/medication/health/recommendation",
            ),
            principal=principals[1],
            db=db_session,
        )

    assert verifier.tokens == ["rotated-token-one", "rotated-token-two"]
    assert principals[0].user_hash == principals[1].user_hash
    stable_identity = f"user:{principals[0].user_hash}"
    assert [call[0] for call in rate_limit_store.calls] == [
        stable_identity,
        stable_identity,
    ]
    assert all(
        credentials.credentials not in stable_identity
        for credentials in credentials
    )
    assert [call[1] for call in rate_limit_store.calls] == [
        "POST:/api/v1/medication/identify",
        "GET:/api/v1/medication/health/recommendation",
    ]


def test_production_configuration_fails_closed_without_firebase() -> None:
    with pytest.raises(ValueError, match="AUTH_MODE=firebase"):
        _production_api_settings(AUTH_MODE="disabled")


@pytest.mark.parametrize(
    ("override", "message"),
    [
        ({"FIREBASE_APP_CHECK_REQUIRED": False}, "FIREBASE_APP_CHECK_REQUIRED"),
        ({"RATE_LIMIT_ENABLED": False}, "RATE_LIMIT_ENABLED"),
        ({"RATE_LIMIT_REQUIRE_REDIS": False}, "RATE_LIMIT_REQUIRE_REDIS"),
        (
            {"PILL_IDENTIFICATION_CATALOG_ALLOW_INLINE_REFRESH": True},
            "PILL_IDENTIFICATION_CATALOG_ALLOW_INLINE_REFRESH",
        ),
    ],
)
def test_production_api_requires_abuse_protection(
    override: dict[str, object],
    message: str,
) -> None:
    with pytest.raises(ValueError, match=message):
        _production_api_settings(**override)


def test_production_configuration_requires_external_migrations() -> None:
    with pytest.raises(ValueError, match="AUTO_CREATE_SCHEMA=false"):
        _production_api_settings(AUTO_CREATE_SCHEMA=True)


@pytest.mark.parametrize("runtime_role", ["migration", "maintenance", "catalog_sync"])
def test_production_jobs_do_not_require_request_authentication(
    runtime_role: str,
) -> None:
    settings = _production_api_settings(
        RUNTIME_ROLE=runtime_role,
        AUTH_MODE="disabled",
        FIREBASE_PROJECT_ID="",
        FIREBASE_APP_CHECK_REQUIRED=False,
        RATE_LIMIT_ENABLED=False,
        RATE_LIMIT_REQUIRE_REDIS=False,
    )

    assert settings.RUNTIME_ROLE == runtime_role


def test_production_api_requires_runtime_api_credentials() -> None:
    with pytest.raises(ValueError, match="GEMINI_API_KEY"):
        _production_api_settings(GEMINI_API_KEY="")
    with pytest.raises(ValueError, match="PUBLIC_DATA_API_KEY"):
        _production_api_settings(PUBLIC_DATA_API_KEY="")


def test_production_catalog_sync_only_requires_public_data_credential() -> None:
    settings = _production_api_settings(
        RUNTIME_ROLE="catalog_sync",
        AUTH_MODE="disabled",
        FIREBASE_PROJECT_ID="",
        FIREBASE_APP_CHECK_REQUIRED=False,
        RATE_LIMIT_ENABLED=False,
        RATE_LIMIT_REQUIRE_REDIS=False,
        GEMINI_API_KEY="",
    )

    assert settings.GEMINI_API_KEY == ""
    with pytest.raises(ValueError, match="catalog synchronization"):
        _production_api_settings(
            RUNTIME_ROLE="catalog_sync",
            AUTH_MODE="disabled",
            FIREBASE_PROJECT_ID="",
            FIREBASE_APP_CHECK_REQUIRED=False,
            RATE_LIMIT_ENABLED=False,
            RATE_LIMIT_REQUIRE_REDIS=False,
            PUBLIC_DATA_API_KEY="",
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
        _production_api_settings(DATABASE_URL=database_url)


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


def test_missing_app_check_token_is_rejected_when_required() -> None:
    with patch("api.dependencies.settings.FIREBASE_APP_CHECK_REQUIRED", True):
        with pytest.raises(HTTPException) as denied:
            verify_app_check_token(None)

    assert denied.value.status_code == 403


def test_valid_app_check_token_is_accepted() -> None:
    verifier = type(
        "Verifier",
        (),
        {"verifyToken": lambda self, token: {"app_id": "medbuddy-android"}},
    )()

    with (
        patch("api.dependencies.settings.FIREBASE_APP_CHECK_REQUIRED", True),
        patch("api.dependencies.get_app_check_token_verifier", return_value=verifier),
    ):
        verify_app_check_token("valid-app-check-token")


@pytest.mark.parametrize(
    ("verification_error", "expected_status"),
    [
        (AppCheckTokenVerificationError("invalid"), 403),
        (AppCheckTokenVerificationUnavailableError("unavailable"), 503),
    ],
)
def test_app_check_verification_failure_is_classified(
    verification_error: Exception,
    expected_status: int,
) -> None:
    class FailingVerifier:
        def verifyToken(self, token: str) -> dict[str, object]:
            raise verification_error

    with (
        patch("api.dependencies.settings.FIREBASE_APP_CHECK_REQUIRED", True),
        patch(
            "api.dependencies.get_app_check_token_verifier",
            return_value=FailingVerifier(),
        ),
    ):
        with pytest.raises(HTTPException) as failure:
            verify_app_check_token("app-check-token")

    assert failure.value.status_code == expected_status
    if expected_status == 503:
        assert failure.value.headers == {"Retry-After": "5"}


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


def test_firebase_verifier_outage_returns_retryable_service_error() -> None:
    class UnavailableVerifier:
        def verifyIdToken(self, token: str) -> dict[str, object]:
            raise TokenVerificationUnavailableError("unavailable")

    credentials = HTTPAuthorizationCredentials(
        scheme="Bearer",
        credentials="valid-token",
    )

    with (
        patch("api.dependencies.settings.AUTH_MODE", "firebase"),
        patch(
            "api.dependencies.get_oidc_token_verifier",
            return_value=UnavailableVerifier(),
        ),
    ):
        with pytest.raises(HTTPException) as unavailable:
            get_authenticated_principal(credentials)

    assert unavailable.value.status_code == 503
    assert unavailable.value.headers == {"Retry-After": "5"}


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
