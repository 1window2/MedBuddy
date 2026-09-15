# File Name: test_authentication_authorization.py
# Role: Regression coverage for Firebase identity, patient authorization, production settings,
#   and request-scoped account locks.
import asyncio
from unittest.mock import patch

import pytest
from fastapi import FastAPI, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session, sessionmaker

from api.dependencies import (
    _sqlite_account_locks,
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


# Function Name: db_session
# Description:
# - Yields an isolated in-memory account database and closes its session and engine after each
#   test.
# Parameters:
# - None.
# Returns:
# - Yields an isolated Session; closes the session and engine during fixture cleanup.
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


# Function Name: _principal
# Description:
# - Builds a verified-email Firebase principal whose subject determines the internal user hash.
# Parameters:
# - subject (str): Verified external Firebase user identifier.
# Returns:
# - AuthenticatedPrincipal: Verified Firebase principal with an internal user hash.
def _principal(subject: str = "firebase-user") -> AuthenticatedPrincipal:
    return AuthenticatedPrincipal.from_verified_claims(
        {
            "uid": subject,
            "iss": "https://securetoken.google.com/medbuddy-test",
            "email": "patient@example.com",
            "email_verified": True,
        }
    )


# Function Name: _production_api_settings
# Description:
# - Constructs valid production API settings and applies selected overrides to exercise
#   configuration guards.
# Parameters:
# - **overrides (object): Selected configuration or response fields replacing the valid
#   defaults.
# Returns:
# - Settings: Validated production API settings with the selected overrides.
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


# Class Name: _RecordingRateLimitStore
# Role: Rate-limit store double that captures identity, route scope, and rule without contacting
#   Redis.
# Responsibilities:
# - Records the quota identity and route rule while allowing the request with no retry delay.
# Attributes:
# - calls (list[tuple[str, str, RateLimitRule]]): Ordered requests captured for later
#   assertions.
class _RecordingRateLimitStore(RequestRateLimitStore):
    # Function Name: __init__
    # Description:
    # - Initializes an empty quota-call history and an unused Redis endpoint for the store
    #   double.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        super().__init__(redis_url="redis://unused")
        self.calls: list[tuple[str, str, RateLimitRule]] = []

    # Function Name: consume
    # Description:
    # - Records the quota identity and route rule while allowing the request with no retry
    #   delay.
    # Parameters:
    # - identity (str): Stable account or IP key used for request quota accounting.
    # - request_scope (str): Canonical HTTP method/route key for quota isolation.
    # - rule (RateLimitRule): Request count and time-window limits applied to the quota.
    # Returns:
    # - tuple[bool, int]: (True, 0): quota accepted with no retry delay.
    async def consume(
        self,
        *,
        identity: str,
        request_scope: str,
        rule: RateLimitRule,
    ) -> tuple[bool, int]:
        self.calls.append((identity, request_scope, rule))
        return True, 0


# Function Name: _request
# Description:
# - Builds an HTTPS request with a fixed client address and the supplied application, method,
#   and route.
# Parameters:
# - app (FastAPI): Application supplying request state and dependencies.
# - method (str): HTTP method used to derive the request's quota scope.
# - path (str): HTTP route path used by the request and rate-limit scope.
# Returns:
# - Request: Synthetic HTTPS request with the supplied app, method, and route.
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


# Function Name: _resolve_registered_principal
# Description:
# - Enters and closes the request-scoped registration dependency in unit tests.
# Parameters:
# - request: Synthetic FastAPI request under test.
# - principal: Verified identity to register.
# - db_session: SQLite session used by the dependency.
# Returns:
# - The principal yielded for endpoint handling.
async def _resolve_registered_principal(
    request: Request,
    principal: AuthenticatedPrincipal,
    db_session: Session,
) -> AuthenticatedPrincipal:
    dependency = get_registered_principal(
        request=request,
        principal=principal,
        db=db_session,
    )
    registered_principal = await anext(dependency)
    await dependency.aclose()
    return registered_principal


# Function Name: test_deleted_account_only_allows_authenticated_deletion_retry
# Description:
# - Allows authenticated deletion retries for a deleted account but returns 410 for other
#   account operations.
# Parameters:
# - db_session (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
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
        deletion_principal = await _resolve_registered_principal(
            request=_request(app, "DELETE", "/api/v1/auth/account-data"),
            principal=principal,
            db_session=db_session,
        )
        with pytest.raises(HTTPException) as denied:
            await _resolve_registered_principal(
                request=_request(app, "GET", "/api/v1/auth/session"),
                principal=principal,
                db_session=db_session,
            )

    assert deletion_principal == principal
    assert denied.value.status_code == 410

# Function Name: test_verified_claims_map_to_stable_internal_user_hash
# Description:
# - Requires equal verified subjects to produce the same opaque usr_ hash without exposing the
#   subject as the hash.
# Parameters:
# - None.
# Returns:
# - None.
def test_verified_claims_map_to_stable_internal_user_hash() -> None:
    first = _principal()
    second = _principal()

    assert first.user_hash == second.user_hash
    assert first.user_hash.startswith("usr_")
    assert first.user_hash != first.subject
    assert first.email_verified is True


# Function Name: test_registered_principal_quota_uses_stable_identity_and_route_scope
# Description:
# - Requires rotated tokens to share a stable quota identity while preserving distinct HTTP
#   method and route scopes.
# Parameters:
# - db_session (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
@pytest.mark.anyio
async def test_registered_principal_quota_uses_stable_identity_and_route_scope(
    db_session,
) -> None:
    # Class Name: RotatingTokenVerifier
    # Role: Firebase verifier double that records rotated tokens while resolving them to one
    #   verified user.
    # Responsibilities:
    # - Records the submitted token and supplies the same verified Firebase claims for every
    #   rotation.
    # Attributes:
    # - tokens (list[str]): Authentication tokens submitted to the verifier double.
    class RotatingTokenVerifier:
        # Function Name: __init__
        # Description:
        # - Starts an empty token history for the rotating-token quota test.
        # Parameters:
        # - None.
        # Returns:
        # - None.
        def __init__(self) -> None:
            self.tokens: list[str] = []

        # Function Name: verifyIdToken
        # Description:
        # - Records the submitted token and supplies the same verified Firebase claims
        #   for every rotation.
        # Parameters:
        # - token (str): Token submitted to the identity or App Check verifier double.
        # Returns:
        # - dict[str, object]: Fixed verified-email Firebase claims for the stable test
        #   user.
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
        await _resolve_registered_principal(
            request=_request(
                app,
                "POST",
                "/api/v1/medication/identify",
            ),
            principal=principals[0],
            db_session=db_session,
        )
        await _resolve_registered_principal(
            request=_request(
                app,
                "GET",
                "/api/v1/medication/health/recommendation",
            ),
            principal=principals[1],
            db_session=db_session,
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


# Function Name: test_sqlite_account_lock_is_held_until_dependency_cleanup
# Description:
# - Requires the SQLite account lock to block a competing request until dependency cleanup and
#   then remove the released lock.
# Parameters:
# - db_session (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
@pytest.mark.anyio
async def test_sqlite_account_lock_is_held_until_dependency_cleanup(
    db_session,
) -> None:
    principal = _principal("request-lifetime-lock-user")
    app = FastAPI()
    dependency = get_registered_principal(
        request=_request(app, "POST", "/save"),
        principal=principal,
        db=db_session,
    )

    with patch("api.dependencies.settings.RATE_LIMIT_ENABLED", False):
        assert await anext(dependency) == principal
        account_lock = _sqlite_account_locks[principal.user_hash]
        assert account_lock.locked()

        contender = get_registered_principal(
            request=_request(app, "GET", "/list"),
            principal=principal,
            db=db_session,
        )
        with patch(
            "api.dependencies.run_in_threadpool",
            side_effect=AssertionError("SQLite lock waits must remain asynchronous"),
        ):
            contender_task = asyncio.create_task(anext(contender))
            await asyncio.sleep(0)
            assert contender_task.done() is False
            await dependency.aclose()
            assert await contender_task == principal
            await contender.aclose()

    assert account_lock.locked() is False
    assert principal.user_hash not in _sqlite_account_locks


# Function Name: test_production_configuration_fails_closed_without_firebase
# Description:
# - Rejects production API configuration without Firebase authentication.
# Parameters:
# - None.
# Returns:
# - None.
def test_production_configuration_fails_closed_without_firebase() -> None:
    with pytest.raises(ValueError, match="AUTH_MODE=firebase"):
        _production_api_settings(AUTH_MODE="disabled")


# Function Name: test_production_configuration_allows_explicit_off_play_beta_mode
# Description:
# - Allows explicit off-Play beta mode to disable App Check while retaining Firebase
#   authentication.
# Parameters:
# - None.
# Returns:
# - None.
def test_production_configuration_allows_explicit_off_play_beta_mode() -> None:
    settings = _production_api_settings(
        FIREBASE_APP_CHECK_REQUIRED=False,
        FIREBASE_OFF_PLAY_BETA_MODE=True,
    )

    assert settings.AUTH_MODE == "firebase"
    assert settings.FIREBASE_APP_CHECK_REQUIRED is False
    assert settings.FIREBASE_OFF_PLAY_BETA_MODE is True


# Function Name: test_off_play_beta_mode_rejects_conflicting_app_check_requirement
# Description:
# - Rejects simultaneously requiring App Check and enabling its off-Play beta exception.
# Parameters:
# - None.
# Returns:
# - None.
def test_off_play_beta_mode_rejects_conflicting_app_check_requirement() -> None:
    with pytest.raises(ValueError, match="FIREBASE_OFF_PLAY_BETA_MODE"):
        _production_api_settings(FIREBASE_OFF_PLAY_BETA_MODE=True)


# Function Name: test_production_api_requires_abuse_protection
# Description:
# - Requires each missing production abuse-protection setting to raise its expected validation
#   error.
# Parameters:
# - override (dict[str, object]): Production configuration changes expected to violate a guard.
# - message (str): Expected production-setting validation message.
# Returns:
# - None.
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


# Function Name: test_production_configuration_requires_external_migrations
# Description:
# - Requires production schema changes to use migrations instead of automatic table creation.
# Parameters:
# - None.
# Returns:
# - None.
def test_production_configuration_requires_external_migrations() -> None:
    with pytest.raises(ValueError, match="AUTO_CREATE_SCHEMA=false"):
        _production_api_settings(AUTO_CREATE_SCHEMA=True)


# Function Name: test_production_jobs_do_not_require_request_authentication
# Description:
# - Allows background production roles to run without request-authentication credentials.
# Parameters:
# - runtime_role (str): Production process role whose credentials are validated.
# Returns:
# - None.
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


# Function Name: test_production_api_requires_runtime_api_credentials
# Description:
# - Rejects production API settings when Gemini or public-data credentials are missing.
# Parameters:
# - None.
# Returns:
# - None.
def test_production_api_requires_runtime_api_credentials() -> None:
    with pytest.raises(ValueError, match="GEMINI_API_KEY"):
        _production_api_settings(GEMINI_API_KEY="")
    with pytest.raises(ValueError, match="PUBLIC_DATA_API_KEY"):
        _production_api_settings(PUBLIC_DATA_API_KEY="")


# Function Name: test_production_catalog_sync_only_requires_public_data_credential
# Description:
# - Allows catalog synchronization without Gemini but still requires the public-data credential.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_production_configuration_requires_valid_postgresql_url
# Description:
# - Rejects malformed or non-PostgreSQL production database URLs.
# Parameters:
# - database_url (str): Candidate production database connection URL.
# Returns:
# - None.
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


# Function Name: test_structured_database_settings_escape_reserved_password_characters
# Description:
# - Requires structured database settings to preserve reserved password characters and all
#   connection fields after URL parsing.
# Parameters:
# - None.
# Returns:
# - None.
def test_structured_database_settings_escape_reserved_password_characters() -> None:
    raw_password = "p@ss:/word?#[]"

    settings = Settings(
        _env_file=None,
        DATABASE_URL="",
        DATABASE_HOST="postgres",
        DATABASE_PORT=5432,
        DATABASE_NAME="medbuddy",
        DATABASE_USER="medbuddy",
        DATABASE_PASSWORD=raw_password,
    )

    database_url = make_url(settings.DATABASE_URL)
    assert database_url.host == "postgres"
    assert database_url.port == 5432
    assert database_url.database == "medbuddy"
    assert database_url.username == "medbuddy"
    assert database_url.password == raw_password


# Function Name: test_owner_scope_ignores_untrusted_client_hash
# Description:
# - Requires owner-scoped requests to use the verified principal hash regardless of
#   client-supplied patient or user hashes.
# Parameters:
# - db_session (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
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


# Function Name: test_prescription_change_uses_server_authorized_patient_scope
# Description:
# - Requires prescription-change requests to receive the server-authorized patient hash.
# Parameters:
# - db_session (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
def test_prescription_change_uses_server_authorized_patient_scope(db_session) -> None:
    principal = _principal()
    authorization = AuthorizationControl(db_session)

    # Class Name: RecordingPrescriptionChangeControl
    # Role: Prescription-change double that captures the authorized patient scope and
    #   supplies an empty comparison.
    # Responsibilities:
    # - Records the request's patient hash and returns a response with no previous
    #   prescription.
    # Attributes:
    # - received_patient_hash (str | None): Authorized patient scope captured from the
    #   request.
    class RecordingPrescriptionChangeControl:
        received_patient_hash: str | None = None

        # Function Name: request_prescription_change
        # Description:
        # - Records the request's patient hash and returns a response with no previous
        #   prescription.
        # Parameters:
        # - request (PrescriptionChangeRequest): Prescription comparison request with a
        #   server-authorized patient scope.
        # Returns:
        # - PrescriptionChangeResponse: Empty comparison with no previous prescription.
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


# Function Name: test_caregiver_scope_requires_active_link
# Description:
# - Rejects caregiver access with 403 before linking and after revocation, allowing it only
#   while the patient link is active.
# Parameters:
# - db_session (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
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


# Function Name: test_missing_firebase_bearer_token_is_rejected
# Description:
# - Requires missing Firebase credentials to produce a 401 Bearer challenge.
# Parameters:
# - None.
# Returns:
# - None.
def test_missing_firebase_bearer_token_is_rejected() -> None:
    with patch("api.dependencies.settings.AUTH_MODE", "firebase"):
        with pytest.raises(HTTPException) as denied:
            get_authenticated_principal(None)
    assert denied.value.status_code == 401
    assert denied.value.headers == {"WWW-Authenticate": "Bearer"}


# Function Name: test_medication_router_rejects_anonymous_requests_in_firebase_mode
# Description:
# - Requires the medication route to return a 401 Bearer challenge for unauthenticated
#   Firebase-mode requests.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_missing_app_check_token_is_rejected_when_required
# Description:
# - Rejects missing App Check credentials with 403 when attestation is required.
# Parameters:
# - None.
# Returns:
# - None.
def test_missing_app_check_token_is_rejected_when_required() -> None:
    with patch("api.dependencies.settings.FIREBASE_APP_CHECK_REQUIRED", True):
        with pytest.raises(HTTPException) as denied:
            verify_app_check_token(None)

    assert denied.value.status_code == 403


# Function Name: test_missing_app_check_token_is_accepted_in_off_play_beta_mode
# Description:
# - Allows absent App Check credentials under the explicit off-Play beta exception without
#   raising an error.
# Parameters:
# - None.
# Returns:
# - None.
def test_missing_app_check_token_is_accepted_in_off_play_beta_mode() -> None:
    with patch("api.dependencies.settings.FIREBASE_APP_CHECK_REQUIRED", False):
        verify_app_check_token(None)


# Function Name: test_valid_app_check_token_is_accepted
# Description:
# - Allows a successfully verified App Check token without raising an authentication error.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_app_check_verification_failure_is_classified
# Description:
# - Maps App Check verification errors to the configured HTTP status and includes a five-second
#   retry hint for outages.
# Parameters:
# - verification_error (Exception): Injected trust or availability exception from token
#   verification.
# - expected_status (int): HTTP status expected for the injected verification failure.
# Returns:
# - None.
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
    # Class Name: FailingVerifier
    # Role: App Check verifier double that injects the parameterized trust or availability
    #   failure.
    # Responsibilities:
    # - Raises the selected verification error without inspecting or forwarding the token.
    class FailingVerifier:
        # Function Name: verifyToken
        # Description:
        # - Raises the selected verification error without inspecting or forwarding the
        #   token.
        # Parameters:
        # - token (str): Token submitted to the identity or App Check verifier double.
        # Returns:
        # - No normal result; raises the configured failure described above.
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


# Function Name: test_unverified_firebase_email_is_rejected
# Description:
# - Rejects password-provider Firebase claims with unverified email using HTTP 403.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_verified_firebase_token_creates_principal
# Description:
# - Requires valid Firebase claims to produce the verified subject with authentication enabled.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_firebase_verifier_outage_returns_retryable_service_error
# Description:
# - Maps a Firebase verifier outage to HTTP 503 with a five-second Retry-After header.
# Parameters:
# - None.
# Returns:
# - None.
def test_firebase_verifier_outage_returns_retryable_service_error() -> None:
    # Class Name: UnavailableVerifier
    # Role: Firebase verifier double that simulates unavailable token-verification
    #   infrastructure.
    # Responsibilities:
    # - Raises TokenVerificationUnavailableError to exercise retryable authentication
    #   failures.
    class UnavailableVerifier:
        # Function Name: verifyIdToken
        # Description:
        # - Raises TokenVerificationUnavailableError to exercise retryable
        #   authentication failures.
        # Parameters:
        # - token (str): Token submitted to the identity or App Check verifier double.
        # Returns:
        # - No normal result; raises the configured failure described above.
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


# Function Name: test_non_email_firebase_provider_requires_explicit_opt_in
# Description:
# - Rejects each non-email sign-in provider until explicitly enabled, then preserves its
#   provider and anonymous status.
# Parameters:
# - provider (str): Firebase sign-in provider claimed by the test identity.
# - allow_setting (str): Configuration flag enabling the provider under test.
# Returns:
# - None.
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


# Function Name: test_password_provider_still_requires_verified_email
# Description:
# - Keeps verified email mandatory for password sign-in even when non-email providers are
#   enabled.
# Parameters:
# - None.
# Returns:
# - None.
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
