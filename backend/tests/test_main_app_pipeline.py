# File Name: test_main_app_pipeline.py
# Role: Exercises the request-pipeline policies through the application main.create_app()
#   builds: the mounted route table, App Check and bearer checks, per-user and per-IP quotas,
#   detached lookup registration, body limits, the API contract header, account tombstones,
#   pool-timeout mapping and the shared Gemini clients.
#
# Routers, dependencies, middleware and controls are the production objects. Only the outer
# boundaries are replaced by the `pipeline` fixture:
# - the Firebase ID-token and App Check verifiers, the identity-deletion and push boundaries;
# - the Gemini SDK client class (so nothing reaches the network and constructions are counted);
# - the Redis client of the quota store (support.fakes.FakeRedis, a real counter);
# - get_db, bound to a foreign-key-enforcing SQLite file under tmp_path.
#
# The literal tables below are the reviewed policy. A route, a rate-limit rule or a detached
# lookup entry that is added, removed, renamed or mounted under another prefix fails here.

import asyncio
import re
import time
from collections.abc import AsyncIterator, Iterator
from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path
from types import SimpleNamespace

import httpx
import pytest
from fastapi import FastAPI
from fastapi.routing import APIRoute, iter_route_contexts
from google import genai
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

import main
from api import dependencies
from core import request_rate_limits
from boundaries.app_check_token_verifier_boundary import AppCheckTokenVerificationError
from boundaries.pill_identification_boundary import MAX_PILL_IMAGE_BYTES
from core.account_database_lock import ACCOUNT_BUSY_DETAIL
from core.account_operation_locks import AccountOperationLocks
from core.application_clock import application_today
from core.config import settings
from core.database import get_db
from core.request_rate_limits import (
    DAILY_QUOTA_EXCEEDED_DETAIL,
    DEFAULT_AUTHENTICATED_API_RULES,
    DEFAULT_RATE_LIMIT_RULES,
    RateLimitRule,
    RequestRateLimitStore,
    mounted_route_template,
    resolve_daily_quota,
)
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.user_account_entity import _UserAccount, utc_now
from support.db import make_engine, make_session_factory, seed_account, seed_medication
from support.fakes import FakeGeminiClient, FakeRedis, RecordingPushBoundary

_APP_CHECK_TOKEN = "valid-app-check"
_APP_CHECK_HEADERS = {"X-Firebase-AppCheck": _APP_CHECK_TOKEN}
_MULTIPART_OVERHEAD_BYTES = 512 * 1024
_JSON_BODY_LIMIT_BYTES = 1024 * 1024
# Wall-clock instant the quota store sees: 30 seconds into its 60, 300 and 3600 second windows,
# so a test never straddles a window boundary and Retry-After values are exact.
_QUOTA_CLOCK_SECONDS = 1_800_000_030.0

# Every authenticated HTTP route of the application, as (method, full route template).
EXPECTED_API_ROUTES = frozenset({
    ("DELETE", "/api/v1/auth/account-data"),
    ("GET", "/api/v1/auth/account-data"),
    ("DELETE", "/api/v1/auth/push-token"),
    ("POST", "/api/v1/auth/push-token"),
    ("GET", "/api/v1/auth/session"),
    ("POST", "/api/v1/chat/links/{link_id}/medication-taken"),
    ("GET", "/api/v1/chat/links/{link_id}/medications"),
    ("GET", "/api/v1/chat/links/{link_id}/medications/{medication_id}"),
    ("GET", "/api/v1/chat/links/{link_id}/messages"),
    ("POST", "/api/v1/chat/links/{link_id}/messages"),
    ("POST", "/api/v1/chat/links/{link_id}/messages/delete"),
    ("POST", "/api/v1/chat/links/{link_id}/read"),
    ("GET", "/api/v1/chat/links/{link_id}/schedule-contexts"),
    ("GET", "/api/v1/chat/links/{link_id}/unread-count"),
    ("GET", "/api/v1/hospitals/nearby"),
    ("POST", "/api/v1/medication/analyze-prescription-text"),
    ("GET", "/api/v1/medication/caregiver-alerts/local-deliveries"),
    ("POST", "/api/v1/medication/caregiver-alerts/{alert_id}/snooze"),
    ("GET", "/api/v1/medication/caregiver-notification/settings/{patient_hash}"),
    ("PUT", "/api/v1/medication/caregiver-notification/settings/{patient_hash}"),
    ("GET", "/api/v1/medication/caregiver-notification/settings/{patient_hash}/slots"),
    ("GET", "/api/v1/medication/caregiver/medications/{patient_hash}"),
    ("GET", "/api/v1/medication/caregiver/monitoring"),
    ("GET", "/api/v1/medication/caregiver/schedules"),
    ("DELETE", "/api/v1/medication/delete/{drug_id}"),
    ("GET", "/api/v1/medication/guardian-alert/settings/{patient_hash}"),
    ("PUT", "/api/v1/medication/guardian-alert/settings/{patient_hash}"),
    ("GET", "/api/v1/medication/guardian/medications/{patient_hash}"),
    ("GET", "/api/v1/medication/guardian/monitoring"),
    ("GET", "/api/v1/medication/health/recommendation"),
    ("POST", "/api/v1/medication/identify"),
    ("POST", "/api/v1/medication/link/code"),
    ("GET", "/api/v1/medication/link/list"),
    ("POST", "/api/v1/medication/link/register"),
    ("DELETE", "/api/v1/medication/link/{link_id}"),
    ("PATCH", "/api/v1/medication/link/{link_id}/caregiver-alias"),
    ("PATCH", "/api/v1/medication/link/{link_id}/patient-alias"),
    ("GET", "/api/v1/medication/list"),
    ("GET", "/api/v1/medication/notification/settings"),
    ("GET", "/api/v1/medication/notification/settings/{slot_key}"),
    ("PUT", "/api/v1/medication/notification/settings/{slot_key}"),
    ("PATCH", "/api/v1/medication/notification/settings/{slot_key}/disable"),
    ("POST", "/api/v1/medication/pill-identification/candidates"),
    ("POST", "/api/v1/medication/pill-identification/multiple-candidates"),
    ("POST", "/api/v1/medication/prescription/change-radar"),
    ("POST", "/api/v1/medication/save"),
    ("POST", "/api/v1/medication/schedule/completion-operations"),
    ("PATCH", "/api/v1/medication/schedule/slot/{slot_key}/status"),
    ("GET", "/api/v1/medication/schedule/today"),
    ("GET", "/api/v1/medication/schedule/today/info"),
    ("GET", "/api/v1/medication/schedule/window"),
    ("PATCH", "/api/v1/medication/schedule/{medication_id}/status"),
    ("GET", "/api/v1/medication/settings/user"),
    ("PUT", "/api/v1/medication/settings/user"),
    ("POST", "/api/v1/medication/voice-guide"),
    ("GET", "/api/v1/pharmacy/nearby"),
})

# Unauthenticated probes registered on the application itself.
EXPECTED_PROBE_ROUTES = frozenset({
    ("GET", "/health"),
    ("GET", "/ready"),
    ("GET", "/ready/catalogs"),
})

# Lookups that return their database connection before waiting for an external provider.
EXPECTED_DETACHED_LOOKUP_ROUTES = frozenset({
    ("POST", "/api/v1/medication/identify"),
    ("POST", "/api/v1/medication/analyze-prescription-text"),
    ("POST", "/api/v1/medication/pill-identification/candidates"),
    ("POST", "/api/v1/medication/pill-identification/multiple-candidates"),
    ("POST", "/api/v1/medication/voice-guide"),
    ("GET", "/api/v1/pharmacy/nearby"),
    ("GET", "/api/v1/hospitals/nearby"),
    ("GET", "/api/v1/medication/health/recommendation"),
})

# Explicit quotas: per user as written, per IP at twenty times the value.
EXPECTED_EXPLICIT_RATE_LIMIT_RULES = {
    ("GET", "/ready"): RateLimitRule(6, 60),
    ("GET", "/ready/catalogs"): RateLimitRule(6, 60),
    ("POST", "/api/v1/medication/analyze-prescription-text"): RateLimitRule(12, 60),
    ("POST", "/api/v1/medication/pill-identification/candidates"): RateLimitRule(12, 60),
    ("POST", "/api/v1/medication/pill-identification/multiple-candidates"): RateLimitRule(8, 60),
    ("POST", "/api/v1/medication/identify"): RateLimitRule(30, 60),
    ("GET", "/api/v1/medication/health/recommendation"): RateLimitRule(12, 60),
    ("GET", "/api/v1/pharmacy/nearby"): RateLimitRule(30, 60),
    ("GET", "/api/v1/hospitals/nearby"): RateLimitRule(30, 60),
    ("POST", "/api/v1/medication/link/code"): RateLimitRule(10, 3_600),
    ("POST", "/api/v1/medication/link/register"): RateLimitRule(5, 300),
    ("DELETE", "/api/v1/medication/delete/{drug_id}"): RateLimitRule(120, 60),
    ("GET", "/api/v1/chat/links/{link_id}/messages"): RateLimitRule(60, 60),
    ("GET", "/api/v1/chat/links/{link_id}/medications"): RateLimitRule(60, 60),
    ("GET", "/api/v1/chat/links/{link_id}/schedule-contexts"): RateLimitRule(60, 60),
    ("GET", "/api/v1/chat/links/{link_id}/medications/{medication_id}"): RateLimitRule(60, 60),
    ("POST", "/api/v1/chat/links/{link_id}/messages"): RateLimitRule(20, 60),
    ("POST", "/api/v1/chat/links/{link_id}/read"): RateLimitRule(60, 60),
    ("POST", "/api/v1/chat/links/{link_id}/messages/delete"): RateLimitRule(10, 60),
    ("GET", "/api/v1/chat/links/{link_id}/unread-count"): RateLimitRule(60, 60),
}

# Per-user quota of every authenticated route without an explicit rule, by method.
EXPECTED_DEFAULT_RATE_LIMIT_RULES = {
    "GET": RateLimitRule(180, 60),
    "POST": RateLimitRule(60, 60),
    "PUT": RateLimitRule(60, 60),
    "PATCH": RateLimitRule(60, 60),
    "DELETE": RateLimitRule(30, 60),
}

EXPECTED_BODY_LIMITS = {
    "/api/v1/medication/pill-identification/candidates": (
        2 * MAX_PILL_IMAGE_BYTES + _MULTIPART_OVERHEAD_BYTES
    ),
    "/api/v1/medication/pill-identification/multiple-candidates": (
        MAX_PILL_IMAGE_BYTES + _MULTIPART_OVERHEAD_BYTES
    ),
}


# Class Name: _FakeFirebaseVerifier
# Role: Stands in for both Firebase verifiers; the bearer token is the Firebase uid.
# Responsibilities:
# - Return verified-email password claims for any ID token, authenticated just now, or one day
#   ago when the token starts with "stale-".
# - Accept exactly one App Check token and reject every other value.
class _FakeFirebaseVerifier:
    # Function Name: verifyIdToken
    # Description:
    # - Builds verified claims whose uid is the token itself.
    # Parameters:
    # - token (str): Bearer token of the request, used as the Firebase uid.
    # Returns:
    # - Claims accepted by AuthenticatedPrincipal.from_verified_claims.
    def verifyIdToken(self, token: str) -> dict[str, object]:
        age_seconds = 86_400 if token.startswith("stale-") else 0
        return {
            "uid": token,
            "iss": "https://securetoken.google.com/medbuddy-test",
            "email": f"{token}@example.com",
            "email_verified": True,
            "auth_time": int(time.time()) - age_seconds,
            "firebase": {"sign_in_provider": "password"},
        }

    # Function Name: verifyToken
    # Description:
    # - Accepts the single valid App Check token of this file.
    # Parameters:
    # - token (str): App Check header value.
    # Returns:
    # - App Check claims; raises AppCheckTokenVerificationError for any other token.
    def verifyToken(self, token: str) -> dict[str, object]:
        if token != _APP_CHECK_TOKEN:
            raise AppCheckTokenVerificationError("invalid")
        return {"app_id": "medbuddy-android"}


# Class Name: _RecordingIdentityDeletion
# Role: Replaces the Firebase identity-deletion boundary so account deletion stays local.
# Attributes:
# - deleted_subjects (list[str]): Firebase subjects whose identity deletion was requested.
class _RecordingIdentityDeletion:
    # Function Name: __init__
    # Description:
    # - Starts with no deleted identity.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.deleted_subjects: list[str] = []

    # Function Name: deleteIdentity
    # Description:
    # - Records the subject instead of calling Firebase.
    # Parameters:
    # - subject (str): Firebase uid of the account being deleted.
    # Returns:
    # - None.
    def deleteIdentity(self, subject: str) -> None:
        self.deleted_subjects.append(subject)


# Class Name: _RecordingRateLimitStore
# Role: The production quota store on a fake Redis, with a ledger of every consume call.
# Responsibilities:
# - Record identity, scope and rule of each quota check, then count it in the real store.
# - Simulate a storage outage for one kind of identity when a test asks for it.
# Attributes:
# - redis (FakeRedis): Counter backend; its keys are the production counter keys.
# - calls (list[tuple[str, str, RateLimitRule]]): Every consume call, in order.
# - unavailable_for (str | None): Identity prefix ("user:" or "ip:") whose checks fail the way
#   the store fails when required Redis storage is down.
class _RecordingRateLimitStore(RequestRateLimitStore):
    # Function Name: __init__
    # Description:
    # - Builds the store on a new fake Redis with an empty ledger.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.redis = FakeRedis()
        super().__init__(redis_url="redis://unused", redis_client=self.redis)
        self.calls: list[tuple[str, str, RateLimitRule]] = []
        self.unavailable_for: str | None = None

    # Function Name: consume
    # Description:
    # - Records the check, then delegates to the production counter.
    # Parameters:
    # - identity (str): "user:<hash>" or "ip:<address>".
    # - request_scope (str): "<METHOD>:<route template>".
    # - rule (RateLimitRule): Limit applied to this check.
    # Returns:
    # - Allowed flag and retry-after seconds from the production store.
    async def consume(
        self,
        *,
        identity: str,
        request_scope: str,
        rule: RateLimitRule,
    ) -> tuple[bool, int]:
        self.calls.append((identity, request_scope, rule))
        if self.unavailable_for is not None and identity.startswith(self.unavailable_for):
            raise RuntimeError("Distributed request-rate storage is unavailable.")
        return await super().consume(
            identity=identity,
            request_scope=request_scope,
            rule=rule,
        )

    # Function Name: user_calls
    # Description:
    # - Selects the per-user checks of one account.
    # Parameters:
    # - user (str): Bearer token / Firebase uid of the account.
    # Returns:
    # - (scope, rule) of each per-user check for that account, in order.
    def user_calls(self, user: str) -> list[tuple[str, RateLimitRule]]:
        identity = f"user:{_user_hash(user)}"
        return [(scope, rule) for called, scope, rule in self.calls if called == identity]

    # Function Name: ip_calls
    # Description:
    # - Selects the per-IP checks made by the middleware.
    # Parameters:
    # - None.
    # Returns:
    # - (scope, rule) of each per-IP check, in order.
    def ip_calls(self) -> list[tuple[str, RateLimitRule]]:
        return [(scope, rule) for called, scope, rule in self.calls if called.startswith("ip:")]


# Class Name: _Pipeline
# Role: What the `pipeline` fixture hands to a test.
# Attributes:
# - app (FastAPI): Application built by main.create_app() for this test.
# - engine (Engine): Foreign-key-enforcing SQLite file engine behind get_db.
# - factory (sessionmaker[Session]): Session factory on that engine, for seeding and reading.
# - store (_RecordingRateLimitStore): Quota store of the application.
# - identity_deletion (_RecordingIdentityDeletion): Replacement identity-deletion boundary.
# - gemini_clients (list[FakeGeminiClient]): Every Gemini client constructed during the test.
@dataclass
class _Pipeline:
    app: FastAPI
    engine: Engine
    factory: sessionmaker[Session]
    store: _RecordingRateLimitStore
    identity_deletion: _RecordingIdentityDeletion
    gemini_clients: list[FakeGeminiClient]


# Function Name: quota_clock
# Description:
# - Fixes the wall clock the quota store derives its counting window from; the monotonic clock
#   of its outage backoff and every other module keep the real time.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Restores the module's clock after the test.
# Returns:
# - The fixed instant in seconds since the epoch.
@pytest.fixture
def quota_clock(monkeypatch: pytest.MonkeyPatch) -> float:
    monkeypatch.setattr(
        request_rate_limits,
        "time",
        SimpleNamespace(time=lambda: _QUOTA_CLOCK_SECONDS, monotonic=time.monotonic),
    )
    return _QUOTA_CLOCK_SECONDS


# Function Name: pipeline
# Description:
# - Builds the application with firebase authentication, required App Check and quotas enabled,
#   on the replaced outer boundaries listed in the file header.
# - Resets the process-wide clients of api.dependencies for the test; monkeypatch restores them.
# Parameters:
# - tmp_path (Path): Directory of the SQLite file.
# - monkeypatch (pytest.MonkeyPatch): Restores settings and module state after the test.
# - quota_clock (float): Fixed quota-window clock.
# Returns:
# - Iterator yielding the _Pipeline; the engine is disposed afterwards.
@pytest.fixture
def pipeline(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    quota_clock: float,
) -> Iterator[_Pipeline]:
    monkeypatch.setattr(settings, "AUTH_MODE", "firebase")
    monkeypatch.setattr(settings, "FIREBASE_PROJECT_ID", "medbuddy-test")
    monkeypatch.setattr(settings, "FIREBASE_APP_CHECK_REQUIRED", True)
    monkeypatch.setattr(settings, "FIREBASE_REQUIRE_VERIFIED_EMAIL", True)
    monkeypatch.setattr(settings, "RATE_LIMIT_ENABLED", True)

    verifier = _FakeFirebaseVerifier()
    identity_deletion = _RecordingIdentityDeletion()
    monkeypatch.setattr(dependencies, "get_oidc_token_verifier", lambda: verifier)
    monkeypatch.setattr(dependencies, "get_app_check_token_verifier", lambda: verifier)
    monkeypatch.setattr(
        dependencies,
        "FirebaseIdentityDeletionBoundary",
        lambda project_id: identity_deletion,
    )
    monkeypatch.setattr(dependencies, "_push_notification_boundary", RecordingPushBoundary())
    monkeypatch.setattr(dependencies, "_sqlite_account_lock_registry", AccountOperationLocks())
    for shared_client in (
        "_gemini_text_client",
        "_gemini_ocr_client",
        "_medication_summary_generator",
        "_health_recommendation_llm_service",
        "_pill_vision_boundary",
        "_pill_catalog_boundary",
        "_medication_detail_cache",
    ):
        monkeypatch.setattr(dependencies, shared_client, None)

    gemini_clients: list[FakeGeminiClient] = []

    # Class Name: _CountingGeminiClient
    # Role: FakeGeminiClient that registers each construction with the fixture.
    class _CountingGeminiClient(FakeGeminiClient):
        # Function Name: __init__
        # Description:
        # - Records the SDK constructor keywords and adds the client to the fixture's list.
        # Parameters:
        # - **client_options (object): Keywords production passes to genai.Client.
        # Returns:
        # - None.
        def __init__(self, **client_options: object) -> None:
            super().__init__(**client_options)
            gemini_clients.append(self)

    monkeypatch.setattr(genai, "Client", _CountingGeminiClient)

    store = _RecordingRateLimitStore()
    monkeypatch.setattr(main, "RequestRateLimitStore", lambda **_options: store)
    app = main.create_app()

    engine = make_engine(tmp_path)
    factory = make_session_factory(engine)

    # Function Name: override_db
    # Description:
    # - Provides the request session on the test engine, as core.database.get_db does.
    # Parameters:
    # - None.
    # Returns:
    # - Iterator yielding one Session, closed after the request.
    def override_db() -> Iterator[Session]:
        db = factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_db
    try:
        yield _Pipeline(
            app=app,
            engine=engine,
            factory=factory,
            store=store,
            identity_deletion=identity_deletion,
            gemini_clients=gemini_clients,
        )
    finally:
        engine.dispose()


# Function Name: _client
# Description:
# - Opens an HTTP client that calls the application in-process, without running its lifespan.
# Parameters:
# - app (FastAPI): Application under test.
# Returns:
# - httpx.AsyncClient; application errors that no handler maps are raised into the test.
def _client(app: FastAPI) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://testserver",
    )


# Function Name: _headers
# Description:
# - Builds the headers of an attested, signed-in request.
# Parameters:
# - user (str): Bearer token, which the fake verifier uses as the Firebase uid.
# Returns:
# - App Check and Authorization headers.
def _headers(user: str = "user-a") -> dict[str, str]:
    return {**_APP_CHECK_HEADERS, "Authorization": f"Bearer {user}"}


# Function Name: _user_hash
# Description:
# - Derives the account hash the server assigns to a bearer token of this file.
# Parameters:
# - user (str): Bearer token / Firebase uid.
# Returns:
# - Server-side user hash.
def _user_hash(user: str) -> str:
    claims = _FakeFirebaseVerifier().verifyIdToken(user)
    return AuthenticatedPrincipal.from_verified_claims(claims).user_hash


# Function Name: _concrete
# Description:
# - Turns a route template into a request path by filling every parameter with "1".
# Parameters:
# - template (str): Full route template.
# Returns:
# - Request path matching the template.
def _concrete(template: str) -> str:
    return re.sub(r"\{[^}]+\}", "1", template)


# Function Name: _json_body
# Description:
# - Gives body-bearing methods an empty JSON object so the request reaches the dependencies.
# Parameters:
# - method (str): HTTP method.
# Returns:
# - Keyword arguments for httpx.AsyncClient.request.
def _json_body(method: str) -> dict[str, object]:
    return {"json": {}} if method in {"POST", "PUT", "PATCH"} else {}


# Function Name: _mounted_http_routes
# Description:
# - Lists the API routes of an application with their full templates. FastAPI keeps included
#   routers lazy, so app.routes itself holds no APIRoute of a prefixed router; the route
#   contexts are walked instead.
# Parameters:
# - app (FastAPI): Application to inspect.
# Returns:
# - Set of (method, full route template).
def _mounted_http_routes(app: FastAPI) -> set[tuple[str, str]]:
    return {
        (method, context.path)
        for context in iter_route_contexts(app.routes)
        if isinstance(context.original_route, APIRoute)
        for method in (context.methods or ())
    }


# Function Name: _expected_user_rule
# Description:
# - Looks up the reviewed per-user quota of one route.
# Parameters:
# - method (str): HTTP method.
# - template (str): Full route template.
# Returns:
# - The explicit rule of the route, or the default rule of its method.
def _expected_user_rule(method: str, template: str) -> RateLimitRule:
    return EXPECTED_EXPLICIT_RATE_LIMIT_RULES.get(
        (method, template),
        EXPECTED_DEFAULT_RATE_LIMIT_RULES[method],
    )


# Function Name: _chunked
# Description:
# - Streams a body in pieces so httpx sends it chunked, without a Content-Length header.
# Parameters:
# - body (bytes): Complete request body.
# - chunk_size (int): Size of each piece.
# Returns:
# - Async iterator over the pieces.
async def _chunked(body: bytes, chunk_size: int = 64 * 1024) -> AsyncIterator[bytes]:
    for start in range(0, len(body), chunk_size):
        yield body[start:start + chunk_size]


# Function Name: test_mounted_route_template_restores_the_mount_prefix
# Description:
# - Requires the full template for a prefixed route, the unchanged template when the route
#   already carries its prefix, and the concrete path when no usable template exists.
# Parameters:
# - route_template (str | None): Template of the matched route.
# - concrete_path (str): Request path.
# - expected (str): Path the policy tables are looked up with.
# Returns:
# - None.
@pytest.mark.parametrize("route_template,concrete_path,expected", [
    (None, "/api/v1/pharmacy/nearby", "/api/v1/pharmacy/nearby"),
    ("", "/api/v1/pharmacy/nearby", "/api/v1/pharmacy/nearby"),
    ("/api/v1/auth/session", "/api/v1/auth/session", "/api/v1/auth/session"),
    ("/nearby", "/api/v1/pharmacy/nearby", "/api/v1/pharmacy/nearby"),
    (
        "/links/{link_id}/unread-count",
        "/api/v1/chat/links/7/unread-count",
        "/api/v1/chat/links/{link_id}/unread-count",
    ),
    (
        "/caregiver/medications/{patient_hash}",
        "/api/v1/medication/caregiver/medications/caller-chosen-value",
        "/api/v1/medication/caregiver/medications/{patient_hash}",
    ),
    ("/a/{b}/c", "/c", "/c"),
    ("/", "/", "/"),
    ("/", "/api/v1/items/", "/api/v1/items/"),
    ("/items/", "/api/v1/items/", "/api/v1/items/"),
    ("/items/{item_id}/", "/api/v1/items/7/", "/api/v1/items/{item_id}/"),
])
def test_mounted_route_template_restores_the_mount_prefix(
    route_template: str | None,
    concrete_path: str,
    expected: str,
) -> None:
    assert mounted_route_template(route_template, concrete_path) == expected


# Function Name: test_mounted_routes_match_the_reviewed_list
# Description:
# - Compares the routes of the served application (main.app) with the reviewed list, so an
#   added, removed or re-prefixed route is noticed together with its policies.
# Parameters:
# - None.
# Returns:
# - None.
def test_mounted_routes_match_the_reviewed_list() -> None:
    assert _mounted_http_routes(main.app) == EXPECTED_API_ROUTES | EXPECTED_PROBE_ROUTES


# Function Name: test_policy_tables_match_the_reviewed_values
# Description:
# - Pins the explicit and default quotas, the detached lookup routes and the body limits to the
#   reviewed literals of this file.
# Parameters:
# - None.
# Returns:
# - None.
def test_policy_tables_match_the_reviewed_values() -> None:
    body_limits = next(
        middleware.kwargs["limits"]
        for middleware in main.app.user_middleware
        if middleware.cls.__name__ == "RequestBodyLimitMiddleware"
    )

    assert DEFAULT_RATE_LIMIT_RULES == EXPECTED_EXPLICIT_RATE_LIMIT_RULES
    assert DEFAULT_AUTHENTICATED_API_RULES == EXPECTED_DEFAULT_RATE_LIMIT_RULES
    assert dependencies._DETACHED_LOOKUP_ROUTES == EXPECTED_DETACHED_LOOKUP_ROUTES
    assert body_limits == EXPECTED_BODY_LIMITS


# Function Name: test_every_explicit_rate_limit_rule_names_a_mounted_route
# Description:
# - Requires each key of the production rule table to be the method and full template of a
#   route the application serves; a misspelt or router-relative key never applies.
# Parameters:
# - method (str): HTTP method of the rule.
# - template (str): Route template of the rule.
# Returns:
# - None.
@pytest.mark.parametrize("method,template", sorted(DEFAULT_RATE_LIMIT_RULES))
def test_every_explicit_rate_limit_rule_names_a_mounted_route(
    method: str,
    template: str,
) -> None:
    assert (method, template) in _mounted_http_routes(main.app)


# Function Name: test_every_detached_lookup_entry_names_a_mounted_route
# Description:
# - Requires each entry of the production detached-lookup table to be a served route.
# Parameters:
# - method (str): HTTP method of the entry.
# - path (str): Full route path of the entry.
# Returns:
# - None.
@pytest.mark.parametrize("method,path", sorted(dependencies._DETACHED_LOOKUP_ROUTES))
def test_every_detached_lookup_entry_names_a_mounted_route(method: str, path: str) -> None:
    assert (method, path) in _mounted_http_routes(main.app)


# Function Name: test_every_body_limit_names_a_mounted_post_route
# Description:
# - Requires each path-specific body limit to belong to a served POST route.
# Parameters:
# - path (str): Request path of the limit.
# Returns:
# - None.
@pytest.mark.parametrize("path", sorted(EXPECTED_BODY_LIMITS))
def test_every_body_limit_names_a_mounted_post_route(path: str) -> None:
    assert ("POST", path) in _mounted_http_routes(main.app)


# Function Name: test_route_checks_app_check_then_bearer_then_charges_the_user_once
# Description:
# - Walks every authenticated route: without headers 403, with App Check only 401, and with
#   both exactly one per-user quota check under the full route template and the reviewed rule,
#   next to one per-IP check. Routes with a daily cost quota add one daily check to each.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# - method (str): HTTP method of the route.
# - template (str): Full route template.
# Returns:
# - None.
@pytest.mark.anyio
@pytest.mark.parametrize("method,template", sorted(EXPECTED_API_ROUTES))
async def test_route_checks_app_check_then_bearer_then_charges_the_user_once(
    pipeline: _Pipeline,
    method: str,
    template: str,
) -> None:
    path = _concrete(template)
    async with _client(pipeline.app) as client:
        anonymous = await client.request(method, path, **_json_body(method))
        attested = await client.request(
            method, path, headers=_APP_CHECK_HEADERS, **_json_body(method),
        )
        rejected_identities = [identity for identity, _, _ in pipeline.store.calls]
        pipeline.store.calls.clear()
        signed_in = await client.request(method, path, headers=_headers(), **_json_body(method))

    assert anonymous.status_code == 403
    assert attested.status_code == 401
    assert all(identity.startswith("ip:") for identity in rejected_identities)
    assert signed_in.status_code not in {401, 429}, signed_in.text
    assert signed_in.status_code < 500, signed_in.text
    daily_quota = resolve_daily_quota(method, template)
    daily_checks = [] if daily_quota is None else [(daily_quota[1], daily_quota[0])]
    assert pipeline.store.user_calls("user-a") == [
        (f"{method}:{template}", _expected_user_rule(method, template)),
        *daily_checks,
    ]
    assert len(pipeline.store.ip_calls()) == 1 + len(daily_checks)


# Function Name: test_default_rule_counts_caller_chosen_path_values_in_one_bucket
# Description:
# - Requires two different caller-chosen path values on a route without an explicit rule to
#   share one per-user counter key, named after the route template.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# Returns:
# - None.
@pytest.mark.anyio
async def test_default_rule_counts_caller_chosen_path_values_in_one_bucket(
    pipeline: _Pipeline,
) -> None:
    template = "/api/v1/medication/caregiver/medications/{patient_hash}"
    async with _client(pipeline.app) as client:
        for chosen in ("first-caller-chosen-value", "second-caller-chosen-value"):
            await client.get(template.replace("{patient_hash}", chosen), headers=_headers())

    user_keys = {
        key: count for key, count in pipeline.store.redis.values.items() if ":user:" in key
    }
    assert [scope for scope, _ in pipeline.store.user_calls("user-a")] == [f"GET:{template}"] * 2
    assert list(user_keys.values()) == ["2"]
    assert all("caller-chosen" not in key for key in pipeline.store.redis.values)


# Function Name: test_per_user_limit_returns_429_on_a_prefixed_router
# Description:
# - Sends one account past the link-registration quota (5 per 300 seconds) on a router mounted
#   with a prefix: the sixth request is 429 with Retry-After, long before the per-IP quota of
#   100, and another account is still served.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# Returns:
# - None.
@pytest.mark.anyio
async def test_per_user_limit_returns_429_on_a_prefixed_router(pipeline: _Pipeline) -> None:
    path = "/api/v1/medication/link/register"
    async with _client(pipeline.app) as client:
        responses = [
            await client.post(path, headers=_headers("user-a"), json={}) for _ in range(6)
        ]
        other_account = await client.post(path, headers=_headers("user-b"), json={})

    assert [response.status_code for response in responses] == [422] * 5 + [429]
    assert responses[5].headers["retry-after"] == "270"
    assert other_account.status_code == 422
    assert len(pipeline.store.ip_calls()) == 7
    with pipeline.factory() as db:
        assert db.get(_UserAccount, _user_hash("user-a")) is not None


# Function Name: test_ip_limit_is_installed_on_the_application
# Description:
# - Requires the IP middleware in front of the routes: the 101st unauthenticated request from
#   one address to a 5-per-window route is 429 instead of the App Check rejection.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# Returns:
# - None.
@pytest.mark.anyio
async def test_ip_limit_is_installed_on_the_application(pipeline: _Pipeline) -> None:
    async with _client(pipeline.app) as client:
        statuses = [
            (await client.post("/api/v1/medication/link/register", json={})).status_code
            for _ in range(101)
        ]

    assert statuses[:100] == [403] * 100
    assert statuses[100] == 429
    assert pipeline.store.user_calls("user-a") == []


# Function Name: test_quota_store_rejects_only_after_the_limit_is_exceeded
# Description:
# - Drives the production store on a counting Redis: the first two checks of a 2-per-window
#   rule pass, the third is refused, and another identity has its own counter.
# Parameters:
# - quota_clock (float): Fixed quota-window clock.
# Returns:
# - None.
@pytest.mark.anyio
async def test_quota_store_rejects_only_after_the_limit_is_exceeded(quota_clock: float) -> None:
    redis = FakeRedis()
    store = RequestRateLimitStore(redis_url="redis://unused", redis_client=redis)
    rule = RateLimitRule(2, 60)

    results = [
        await store.consume(identity="user:a", request_scope="GET:/x", rule=rule)
        for _ in range(3)
    ]
    other_identity = await store.consume(identity="user:b", request_scope="GET:/x", rule=rule)

    assert [allowed for allowed, _ in results] == [True, True, False]
    assert [retry_after for _, retry_after in results] == [30, 30, 30]
    assert other_identity[0] is True
    assert redis.calls["eval"] == 4


# Function Name: test_quota_storage_outage_returns_503_before_any_route_work
# Description:
# - With Redis required and down, the IP middleware answers 503 with Retry-After.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# Returns:
# - None.
@pytest.mark.anyio
async def test_quota_storage_outage_returns_503_before_any_route_work(
    pipeline: _Pipeline,
) -> None:
    pipeline.store.require_redis = True
    pipeline.store.redis.fail_with = ConnectionError("redis down")
    async with _client(pipeline.app) as client:
        response = await client.get("/api/v1/auth/session", headers=_headers())

    assert response.status_code == 503
    assert response.headers["retry-after"] == "5"
    assert response.json() == {"detail": "Request quota storage is temporarily unavailable."}


# Function Name: test_per_user_quota_outage_returns_503_without_registering_the_account
# Description:
# - When only the per-user check cannot reach its storage, the dependency answers 503 with
#   Retry-After and does not create the account row.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# Returns:
# - None.
@pytest.mark.anyio
async def test_per_user_quota_outage_returns_503_without_registering_the_account(
    pipeline: _Pipeline,
) -> None:
    pipeline.store.unavailable_for = "user:"
    async with _client(pipeline.app) as client:
        response = await client.get("/api/v1/medication/list", headers=_headers())

    assert response.status_code == 503
    assert response.headers["retry-after"] == "5"
    assert response.json() == {"detail": "Request quota storage is temporarily unavailable."}
    with pipeline.factory() as db:
        assert db.get(_UserAccount, _user_hash("user-a")) is None


# Function Name: test_detached_registration_is_selected_by_the_mounted_route
# Description:
# - Requires the eight external-lookup routes to register through the detached path, which
#   commits and returns the connection, and account-data routes to keep the request-lifetime
#   registration.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# - monkeypatch (pytest.MonkeyPatch): Installs the recording wrappers.
# - method (str): HTTP method of the request.
# - path (str): Request path.
# - detached (bool): Whether the detached registration is expected.
# Returns:
# - None.
@pytest.mark.anyio
@pytest.mark.parametrize(
    "method,path,detached",
    [(method, path, True) for method, path in sorted(EXPECTED_DETACHED_LOOKUP_ROUTES)]
    + [
        ("POST", "/api/v1/medication/save", False),
        ("POST", "/api/v1/chat/links/1/messages", False),
        ("GET", "/api/v1/auth/session", False),
    ],
)
async def test_detached_registration_is_selected_by_the_mounted_route(
    pipeline: _Pipeline,
    monkeypatch: pytest.MonkeyPatch,
    method: str,
    path: str,
    detached: bool,
) -> None:
    used: list[str] = []
    real_detached = dependencies._register_detached_lookup_scope
    real_account_scope = dependencies._register_account_scope

    # Function Name: recording_detached
    # Description:
    # - Notes that the detached registration ran, then runs it.
    # Parameters:
    # - db (Session): Request session.
    # - user_hash (str): Account being registered.
    # Returns:
    # - None.
    def recording_detached(db: Session, user_hash: str) -> None:
        used.append("detached")
        real_detached(db, user_hash)

    # Function Name: recording_account_scope
    # Description:
    # - Notes that the account registration ran, then runs it.
    # Parameters:
    # - db (Session): Request session.
    # - user_hash (str): Account being registered.
    # Returns:
    # - None.
    def recording_account_scope(db: Session, user_hash: str) -> None:
        used.append("account")
        real_account_scope(db, user_hash)

    monkeypatch.setattr(dependencies, "_register_detached_lookup_scope", recording_detached)
    monkeypatch.setattr(dependencies, "_register_account_scope", recording_account_scope)
    async with _client(pipeline.app) as client:
        await client.request(method, path, headers=_headers(), **_json_body(method))

    assert used == (["detached", "account"] if detached else ["account"])
    with pipeline.factory() as db:
        assert db.get(_UserAccount, _user_hash("user-a")) is not None


# Function Name: test_pending_external_lookup_does_not_block_the_same_account
# Description:
# - While a pharmacy lookup of an account waits for its provider, the request holds no pooled
#   connection and another request of the same account is answered at once.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# Returns:
# - None.
@pytest.mark.anyio
async def test_pending_external_lookup_does_not_block_the_same_account(
    pipeline: _Pipeline,
) -> None:
    entered = asyncio.Event()
    release = asyncio.Event()

    # Class Name: _ParkedPharmacySearch
    # Role: Pharmacy control whose provider call does not answer until the test releases it.
    class _ParkedPharmacySearch:
        # Function Name: requestNearbyPharmacySearch
        # Description:
        # - Signals that the lookup started, waits for the release and then fails validation.
        # Parameters:
        # - **_search (object): Search arguments of the route; unused.
        # Returns:
        # - Never returns; raises ValueError, which the route maps to 422.
        async def requestNearbyPharmacySearch(self, **_search: object) -> object:
            entered.set()
            await release.wait()
            raise ValueError("released")

    pipeline.app.dependency_overrides[dependencies.get_check_nearby_pharmacy] = (
        lambda: _ParkedPharmacySearch()
    )
    async with _client(pipeline.app) as client:
        lookup = asyncio.create_task(client.get(
            "/api/v1/pharmacy/nearby",
            headers=_headers(),
            params={"latitude": 37.5, "longitude": 127.0},
        ))
        try:
            await asyncio.wait_for(entered.wait(), 3)
            assert pipeline.engine.pool.checkedout() == 0
            session = await asyncio.wait_for(
                client.get("/api/v1/auth/session", headers=_headers()), 2,
            )
        finally:
            release.set()
        lookup_response = await lookup

    assert session.status_code == 200
    assert lookup_response.status_code == 422


# Function Name: test_body_limits_apply_to_the_mounted_upload_and_json_routes
# Description:
# - Requires the upload routes to accept a body above the 1 MiB JSON default (their own limits
#   are keyed by the full path) and to answer 413 one byte above their limit, and a JSON route
#   to answer 413 above the default, declared or streamed without Content-Length.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# Returns:
# - None.
@pytest.mark.anyio
async def test_body_limits_apply_to_the_mounted_upload_and_json_routes(
    pipeline: _Pipeline,
) -> None:
    # Class Name: _RejectingIdentifyPill
    # Role: Pill control that proves the upload reached the route and then refuses it.
    class _RejectingIdentifyPill:
        # Function Name: requestPillIdentification
        # Description:
        # - Refuses the single-pill request after the upload was accepted.
        # Parameters:
        # - *_images (object): Uploaded image bytes; unused.
        # - **_options (object): Remaining arguments; unused.
        # Returns:
        # - Never returns; raises ValueError.
        async def requestPillIdentification(self, *_images: object, **_options: object) -> object:
            raise ValueError("reached the control")

        # Function Name: requestMultiplePillIdentification
        # Description:
        # - Refuses the multiple-pill request after the upload was accepted.
        # Parameters:
        # - *_images (object): Uploaded image bytes; unused.
        # - **_options (object): Remaining arguments; unused.
        # Returns:
        # - Never returns; raises ValueError.
        async def requestMultiplePillIdentification(
            self, *_images: object, **_options: object,
        ) -> object:
            raise ValueError("reached the control")

    pipeline.app.dependency_overrides[dependencies.get_identify_pill] = (
        lambda: _RejectingIdentifyPill()
    )
    single = "/api/v1/medication/pill-identification/candidates"
    multiple = "/api/v1/medication/pill-identification/multiple-candidates"
    image = b"\xff" * (_JSON_BODY_LIMIT_BYTES + 4096)
    oversized_json = b'{"padding": "' + b"a" * _JSON_BODY_LIMIT_BYTES + b'"}'
    multipart = {"content-type": "multipart/form-data; boundary=b"}

    async with _client(pipeline.app) as client:
        single_upload = await client.post(
            single, headers=_headers(), files={"front": ("f.jpg", image, "image/jpeg")},
        )
        multiple_upload = await client.post(
            multiple, headers=_headers(), files={"image": ("m.jpg", image, "image/jpeg")},
        )
        single_too_large = await client.post(
            single,
            headers={
                **_headers(), **multipart,
                "content-length": str(EXPECTED_BODY_LIMITS[single] + 1),
            },
            content=b"--b--\r\n",
        )
        multiple_too_large = await client.post(
            multiple,
            headers={
                **_headers(), **multipart,
                "content-length": str(EXPECTED_BODY_LIMITS[multiple] + 1),
            },
            content=b"--b--\r\n",
        )
        declared_json = await client.post(
            "/api/v1/medication/save",
            headers={**_headers(), "content-type": "application/json"},
            content=oversized_json,
        )
        streamed_json = await client.post(
            "/api/v1/medication/save",
            headers={**_headers(), "content-type": "application/json"},
            content=_chunked(oversized_json),
        )

    assert single_upload.status_code != 413, single_upload.text
    assert multiple_upload.status_code != 413, multiple_upload.text
    assert single_too_large.status_code == 413
    assert multiple_too_large.status_code == 413
    assert declared_json.status_code == 413
    assert "content-length" not in streamed_json.request.headers
    assert streamed_json.status_code == 413
    assert streamed_json.json() == {"detail": "The uploaded request is too large."}


# Function Name: test_contract_header_is_enforced_by_the_application
# Description:
# - Requires every response to carry the server contract version and a client that announces
#   another version to get 426 with the expected one.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# Returns:
# - None.
@pytest.mark.anyio
async def test_contract_header_is_enforced_by_the_application(pipeline: _Pipeline) -> None:
    expected = (
        Path(main.__file__).parent / "API_CONTRACT_VERSION"
    ).read_text(encoding="utf-8").strip()
    async with _client(pipeline.app) as client:
        health = await client.get("/health")
        stale = await client.get(
            "/api/v1/auth/session",
            headers={**_headers(), "X-MedBuddy-Api-Contract": "stale"},
        )

    assert health.status_code == 200
    assert health.headers["x-medbuddy-api-contract"] == expected
    assert stale.status_code == 426
    assert stale.json()["expected_contract"] == expected


# Function Name: test_production_application_rejects_untrusted_hosts
# Description:
# - An application built for production answers only its configured hosts; the development
#   build of the fixture does not check the Host header.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# - monkeypatch (pytest.MonkeyPatch): Selects the production environment for a second build.
# Returns:
# - None.
@pytest.mark.anyio
async def test_production_application_rejects_untrusted_hosts(
    pipeline: _Pipeline,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "APP_ENV", "production")
    monkeypatch.setattr(settings, "TRUSTED_HOSTS", "api.medbuddy.example")
    production_app = main.create_app()

    # Function Name: health_status
    # Description:
    # - Requests the liveness probe of an application under a given Host header.
    # Parameters:
    # - app (FastAPI): Application to call.
    # - host (str): Host the client addresses.
    # Returns:
    # - HTTP status code.
    async def health_status(app: FastAPI, host: str) -> int:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url=f"http://{host}",
        ) as client:
            return (await client.get("/health")).status_code

    assert await health_status(production_app, "api.medbuddy.example") == 200
    assert await health_status(production_app, "untrusted.example") == 400
    assert await health_status(pipeline.app, "untrusted.example") == 200


# Function Name: test_deleted_account_gets_410_everywhere_except_the_deletion_retry
# Description:
# - A tombstoned account is refused with 410 on the medication, chat and pharmacy routers and
#   on a DELETE that is not the account deletion; only the deletion retry is let through.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# Returns:
# - None.
@pytest.mark.anyio
async def test_deleted_account_gets_410_everywhere_except_the_deletion_retry(
    pipeline: _Pipeline,
) -> None:
    with pipeline.factory() as db:
        db.add(_UserAccount(user_hash=_user_hash("gone"), deletion_requested_at=utc_now()))
        db.commit()

    async with _client(pipeline.app) as client:
        refused = [
            await client.get("/api/v1/medication/list", headers=_headers("gone")),
            await client.get("/api/v1/chat/links/1/unread-count", headers=_headers("gone")),
            await client.get(
                "/api/v1/pharmacy/nearby",
                headers=_headers("gone"),
                params={"latitude": 37.5, "longitude": 127.0},
            ),
            await client.delete("/api/v1/medication/delete/1", headers=_headers("gone")),
        ]
        retry = await client.delete("/api/v1/auth/account-data", headers=_headers("gone"))

    assert [response.status_code for response in refused] == [410] * 4
    assert retry.status_code == 200, retry.text
    assert pipeline.identity_deletion.deleted_subjects == ["gone"]


# Function Name: test_account_deletion_requires_recent_authentication
# Description:
# - A sign-in older than the step-up window cannot delete the account (401 with a bearer
#   challenge, nothing deleted); a fresh sign-in of the same kind can.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# Returns:
# - None.
@pytest.mark.anyio
async def test_account_deletion_requires_recent_authentication(pipeline: _Pipeline) -> None:
    async with _client(pipeline.app) as client:
        stale = await client.delete("/api/v1/auth/account-data", headers=_headers("stale-user"))
        with pipeline.factory() as db:
            stale_account = db.get(_UserAccount, _user_hash("stale-user"))
            stale_account_kept = (
                stale_account is not None and stale_account.deletion_requested_at is None
            )
        fresh = await client.delete("/api/v1/auth/account-data", headers=_headers("fresh-user"))

    assert stale.status_code == 401
    assert stale.headers["www-authenticate"] == "Bearer"
    assert "Recent authentication is required" in stale.json()["detail"]
    assert stale_account_kept
    assert fresh.status_code == 200, fresh.text
    assert pipeline.identity_deletion.deleted_subjects == ["fresh-user"]


# Function Name: test_chat_daily_quota_is_enforced_over_http
# Description:
# - With the daily chat quota lowered to two, the third message of an account on a real link is
#   429 with Retry-After, counted in the account-wide daily scope.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# - monkeypatch (pytest.MonkeyPatch): Lowers the daily quota for this test.
# Returns:
# - None.
@pytest.mark.anyio
async def test_chat_daily_quota_is_enforced_over_http(
    pipeline: _Pipeline,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "CHAT_MESSAGE_DAILY_LIMIT", 2)
    with pipeline.factory() as db:
        seed_account(db, _user_hash("user-a"), _user_hash("user-b"))
        link = _PatientCaregiverLink(
            patient_hash=_user_hash("user-a"),
            caregiver_hash=_user_hash("user-b"),
            linked=True,
        )
        db.add(link)
        db.commit()
        link_id = link.id

    async with _client(pipeline.app) as client:
        responses = [
            await client.post(
                f"/api/v1/chat/links/{link_id}/messages",
                headers=_headers("user-a"),
                json={"client_message_id": f"message-{number}", "body": "hello"},
            )
            for number in range(3)
        ]

    assert [response.status_code for response in responses] == [200, 200, 429], [
        response.text for response in responses
    ]
    assert responses[2].headers["retry-after"] == str(86_400 - int(_QUOTA_CLOCK_SECONDS) % 86_400)
    assert [scope for scope, _ in pipeline.store.user_calls("user-a")] == [
        "POST:/api/v1/chat/links/{link_id}/messages",
        "POST:/api/v1/chat/messages:daily",
    ] * 3


# Function Name: test_dose_day_filtering_applies_only_to_clients_that_declare_it
# Description:
# - A weekly medication that is not due today is left out of today's schedule and its summary
#   for a client that sends the dose-days feature, and still listed for a client that does not
#   (released apps, which would switch the slot's reminder off on an empty list). The schedule
#   window lists it for both, with the dose cycle.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# Returns:
# - None.
@pytest.mark.anyio
async def test_dose_day_filtering_applies_only_to_clients_that_declare_it(
    pipeline: _Pipeline,
) -> None:
    today = application_today()
    with pipeline.factory() as db:
        seed_medication(
            db, patient_hash=_user_hash("user-a"), item_name="weekly",
            prescription_date=today - timedelta(days=3), total_days="8주",
            daily_frequency="주 1회", schedule_slot_keys='["bedtime"]',
        )
    aware = {**_headers("user-a"), "X-MedBuddy-Client-Features": "dose-days"}

    async with _client(pipeline.app) as client:
        legacy_today = await client.get(
            "/api/v1/medication/schedule/today", headers=_headers("user-a"),
        )
        aware_today = await client.get("/api/v1/medication/schedule/today", headers=aware)
        legacy_info = await client.get(
            "/api/v1/medication/schedule/today/info", headers=_headers("user-a"),
        )
        aware_info = await client.get("/api/v1/medication/schedule/today/info", headers=aware)
        window = await client.get("/api/v1/medication/schedule/window", headers=aware)
        # The feature of one request must not carry over to the next request.
        legacy_again = await client.get(
            "/api/v1/medication/schedule/today", headers=_headers("user-a"),
        )

    assert [item["drug_name"] for item in legacy_today.json()["data"]] == ["weekly"]
    assert aware_today.json()["data"] == []
    assert [item["drug_name"] for item in legacy_again.json()["data"]] == ["weekly"]
    assert legacy_info.json()["data"]["medication_count"] == 1, legacy_info.text
    assert aware_info.json()["data"]["medication_count"] == 0, aware_info.text
    assert [
        (item["drug_name"], item["dose_cycle_days"], item["dose_cycle_anchor"])
        for item in window.json()["data"]
    ] == [("weekly", 7, (today - timedelta(days=3)).isoformat())]


# Function Name: test_disabling_an_alarm_accepts_an_optional_new_time
# Description:
# - The disable route works without a body, as released clients call it, and stores a time sent
#   with it; an invalid time is rejected by request validation.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# Returns:
# - None.
@pytest.mark.anyio
async def test_disabling_an_alarm_accepts_an_optional_new_time(pipeline: _Pipeline) -> None:
    disable_url = "/api/v1/medication/notification/settings/morning/disable"
    async with _client(pipeline.app) as client:
        saved = await client.put(
            "/api/v1/medication/notification/settings/morning",
            headers=_headers("user-a"), json={"hour": 9, "minute": 30},
        )
        without_body = await client.patch(disable_url, headers=_headers("user-a"))
        with_time = await client.patch(
            disable_url, headers=_headers("user-a"), json={"hour": 7, "minute": 15},
        )
        invalid = await client.patch(disable_url, headers=_headers("user-a"), json={"hour": 24})

    assert saved.status_code == 200, saved.text
    assert without_body.status_code == 200, without_body.text
    assert [without_body.json()["data"][key] for key in ("hour", "minute", "is_enabled")] == [
        9, 30, False,
    ]
    assert with_time.status_code == 200, with_time.text
    assert [with_time.json()["data"][key] for key in ("hour", "minute", "is_enabled")] == [
        7, 15, False,
    ]
    assert invalid.status_code == 422


# Function Name: test_costly_routes_have_a_daily_quota_per_account_and_per_address
# Description:
# - With the daily hospital-search quota lowered to two, the third search of an account is 429
#   with a Retry-After to the end of the day, while another account on the same address still
#   passes: the address is allowed twenty times the account quota in the same daily scope.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# - monkeypatch (pytest.MonkeyPatch): Lowers the daily quota for this test.
# Returns:
# - None.
@pytest.mark.anyio
async def test_costly_routes_have_a_daily_quota_per_account_and_per_address(
    pipeline: _Pipeline,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "HOSPITAL_SEARCH_DAILY_LIMIT", 2)
    search = {"latitude": 37.5, "longitude": 127.0}

    async with _client(pipeline.app) as client:
        responses = [
            await client.get(
                "/api/v1/hospitals/nearby", headers=_headers("user-a"), params=search,
            )
            for _ in range(3)
        ]
        other_account = await client.get(
            "/api/v1/hospitals/nearby", headers=_headers("user-b"), params=search,
        )

    assert [response.status_code == 429 for response in responses] == [False, False, True], [
        response.text for response in responses
    ]
    assert responses[2].json()["detail"] == DAILY_QUOTA_EXCEEDED_DETAIL
    assert responses[2].headers["retry-after"] == str(86_400 - int(_QUOTA_CLOCK_SECONDS) % 86_400)
    assert other_account.status_code != 429
    assert ("daily:hospital-search", RateLimitRule(40, 86_400)) in pipeline.store.ip_calls()
    assert [scope for scope, _ in pipeline.store.user_calls("user-a")] == [
        "GET:/api/v1/hospitals/nearby",
        "daily:hospital-search",
    ] * 3
    assert resolve_daily_quota("POST", "/api/v1/medication/analyze-prescription-text") == (
        RateLimitRule(settings.AI_REQUEST_DAILY_LIMIT, 86_400), "daily:ai",
    )
    assert resolve_daily_quota("GET", "/api/v1/medication/list") is None


# Function Name: test_exhausted_connection_pool_returns_503_with_retry_after
# Description:
# - When every pooled connection is in use and the wait expires, the request is answered with
#   the retryable busy response instead of an unhandled 500.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# Returns:
# - None.
@pytest.mark.anyio
async def test_exhausted_connection_pool_returns_503_with_retry_after(
    pipeline: _Pipeline,
) -> None:
    exhausted_engine = create_engine(
        pipeline.engine.url,
        connect_args={"check_same_thread": False},
        pool_size=1,
        max_overflow=0,
        pool_timeout=0.1,
    )
    exhausted_factory = make_session_factory(exhausted_engine)

    # Function Name: override_db
    # Description:
    # - Provides the request session on the one-connection engine.
    # Parameters:
    # - None.
    # Returns:
    # - Iterator yielding one Session, closed after the request.
    def override_db() -> Iterator[Session]:
        db = exhausted_factory()
        try:
            yield db
        finally:
            db.close()

    pipeline.app.dependency_overrides[get_db] = override_db
    try:
        with exhausted_engine.connect():
            async with _client(pipeline.app) as client:
                response = await client.get("/api/v1/auth/session", headers=_headers())
    finally:
        exhausted_engine.dispose()

    assert response.status_code == 503
    assert response.headers["retry-after"] == "5"
    assert response.json() == {"detail": ACCOUNT_BUSY_DETAIL}


# Function Name: test_gemini_clients_are_shared_by_requests_and_closed_at_shutdown
# Description:
# - Two rounds of requests to the recommendation, medication-detail and prescription routes
#   construct one text client and one v1alpha OCR client in total, and the application
#   shutdown closes both transports of each.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries.
# Returns:
# - None.
@pytest.mark.anyio
async def test_gemini_clients_are_shared_by_requests_and_closed_at_shutdown(
    pipeline: _Pipeline,
) -> None:
    async with pipeline.app.router.lifespan_context(pipeline.app):
        async with _client(pipeline.app) as client:
            for _ in range(2):
                await client.get(
                    "/api/v1/medication/health/recommendation", headers=_headers(),
                )
                await client.post(
                    "/api/v1/medication/identify", headers=_headers(), json={},
                )
                await client.post(
                    "/api/v1/medication/analyze-prescription-text",
                    headers=_headers(),
                    json={},
                )
        constructed = [client.client_options for client in pipeline.gemini_clients]
        closed_while_serving = [
            client.closed or client.aio.closed for client in pipeline.gemini_clients
        ]

    assert sorted(constructed, key=len) == [
        {"api_key": settings.GEMINI_API_KEY},
        {"api_key": settings.GEMINI_API_KEY, "http_options": {"api_version": "v1alpha"}},
    ]
    assert closed_while_serving == [False, False]
    assert [
        (client.aio.closed, client.closed) for client in pipeline.gemini_clients
    ] == [(True, True), (True, True)]
    assert dependencies._gemini_text_client is None
    assert dependencies._gemini_ocr_client is None
    assert dependencies._medication_summary_generator is None
    assert dependencies._health_recommendation_llm_service is None


# Function Name: test_gemini_shutdown_closes_the_remaining_transports_after_a_failure
# Description:
# - A failing asynchronous close of one client neither skips its synchronous close nor the
#   other client.
# Parameters:
# - pipeline (_Pipeline): Application on replaced outer boundaries; supplies the fake SDK.
# Returns:
# - None.
@pytest.mark.anyio
async def test_gemini_shutdown_closes_the_remaining_transports_after_a_failure(
    pipeline: _Pipeline,
) -> None:
    text_client = dependencies._get_gemini_text_client()
    ocr_client = dependencies._get_gemini_ocr_client()

    # Function Name: failing_aclose
    # Description:
    # - Fails the asynchronous close of the text client.
    # Parameters:
    # - None.
    # Returns:
    # - Never returns; raises OSError.
    async def failing_aclose() -> None:
        raise OSError("transport already gone")

    text_client.aio.aclose = failing_aclose

    await dependencies.close_gemini_clients()

    assert text_client.closed is True
    assert (ocr_client.aio.closed, ocr_client.closed) == (True, True)
    assert dependencies._get_gemini_text_client() is not text_client
