# File Name: test_runtime_readiness.py
# Role: Regression coverage for liveness, cached readiness checks, and production dependency
#   requirements.
"""Tests for process liveness and production dependency readiness."""

from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient
from redis.exceptions import ConnectionError as RedisConnectionError
from sqlalchemy.exc import OperationalError

from main import app


# Function Name: test_liveness_does_not_depend_on_external_services
# Description:
# - Returns a successful liveness and API-contract response without depending on external
#   services.
# Parameters:
# - None.
# Returns:
# - None.
def test_liveness_does_not_depend_on_external_services() -> None:
    with TestClient(app) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "api_contract": "medbuddy-api-v1",
    }


# Function Name: test_readiness_checks_database_connectivity
# Description:
# - Checks database connectivity and returns the expected development runtime and authentication
#   readiness metadata.
# Parameters:
# - None.
# Returns:
# - None.
def test_readiness_checks_database_connectivity() -> None:
    with TestClient(app) as client:
        response = client.get("/ready")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ready",
        "api_contract": "medbuddy-api-v1",
        "app_env": "development",
        "runtime_role": "api",
        "auth_mode": "disabled",
        "firebase_project_id": "",
        "app_check_required": False,
    }


# Function Name: test_readiness_coalesces_repeated_public_dependency_checks
# Description:
# - Coalesces repeated readiness calls into one database dependency check while returning
#   success to both callers.
# Parameters:
# - None.
# Returns:
# - None.
def test_readiness_coalesces_repeated_public_dependency_checks() -> None:
    with (
        patch("main._verify_database_dependencies") as verify_database,
        TestClient(app) as client,
    ):
        first_response = client.get("/ready")
        second_response = client.get("/ready")

    assert first_response.status_code == 200
    assert second_response.status_code == 200
    verify_database.assert_called_once_with()


# Function Name: test_readiness_fails_when_database_is_unavailable
# Description:
# - Returns HTTP 503 with a generic dependency-not-ready message when the database is
#   unavailable.
# Parameters:
# - None.
# Returns:
# - None.
def test_readiness_fails_when_database_is_unavailable() -> None:
    database_error = OperationalError(
        "SELECT 1",
        {},
        RuntimeError("database unavailable"),
    )

    with (
        patch("main.engine.connect", side_effect=database_error),
        TestClient(app) as client,
    ):
        response = client.get("/ready")

    assert response.status_code == 503
    assert response.json() == {
        "detail": "MedBuddy dependencies are not ready."
    }


# Function Name: test_production_readiness_checks_schema_firebase_and_redis
# Description:
# - Checks production schema, Firebase credentials/verifiers, and Redis independently of catalogs while
#   returning the configured production readiness metadata.
# Parameters:
# - None.
# Returns:
# - None.
def test_production_readiness_checks_schema_firebase_and_redis() -> None:
    with (
        patch("main.settings.APP_ENV", "production"),
        patch("main.settings.AUTH_MODE", "firebase"),
        patch("main.settings.FIREBASE_PROJECT_ID", "medbuddy-test"),
        patch("main.settings.FIREBASE_APP_CHECK_REQUIRED", True),
        patch("main.settings.RATE_LIMIT_REQUIRE_REDIS", True),
        patch("main._verify_database_revision") as verify_revision,
        patch("main._verify_catalog_seed") as verify_catalog_seed,
        patch(
            "main.verify_firebase_admin_credentials"
        ) as verify_firebase_credentials,
        patch("main.get_oidc_token_verifier") as get_oidc,
        patch("main.get_app_check_token_verifier") as get_app_check,
        patch("main._ping_required_redis", new_callable=AsyncMock) as ping_redis,
        TestClient(app) as client,
    ):
        response = client.get("/ready")

    assert response.status_code == 200
    assert response.json()["app_env"] == "production"
    assert response.json()["runtime_role"] == "api"
    assert response.json()["auth_mode"] == "firebase"
    assert response.json()["firebase_project_id"] == "medbuddy-test"
    assert response.json()["app_check_required"] is True
    verify_revision.assert_called_once()
    verify_catalog_seed.assert_not_called()
    verify_firebase_credentials.assert_called_once_with("medbuddy-test")
    get_oidc.assert_called_once_with()
    get_app_check.assert_called_once_with()
    ping_redis.assert_awaited_once_with()


# Function Name: test_catalog_failure_does_not_poison_core_readiness
# Description:
# - Keeps core readiness available and separately caches a failed catalog probe.
# Parameters:
# - None.
# Returns:
# - None.
def test_catalog_failure_does_not_poison_core_readiness() -> None:
    with (
        patch("main._verify_catalog_seed", side_effect=RuntimeError("empty catalog")) as seed,
        TestClient(app) as client,
    ):
        assert client.get("/ready/catalogs").status_code == 503
        assert client.get("/ready").status_code == 200
        assert client.get("/ready/catalogs").json() == {
            "detail": "MedBuddy catalogs are not ready."
        }
        seed.assert_called_once()


# Function Name: test_catalog_readiness_recovers_after_cache_expiration
# Description:
# - Rechecks catalog readiness after expiration without resetting the core probe.
# Parameters:
# - None.
# Returns:
# - None.
def test_catalog_readiness_recovers_after_cache_expiration() -> None:
    with (
        patch("main._verify_catalog_seed", side_effect=[RuntimeError("empty"), None]) as seed,
        TestClient(app) as client,
    ):
        assert client.get("/ready/catalogs").status_code == 503
        app.state.catalog_readiness_probe_cache.reset()
        response = client.get("/ready/catalogs")
        assert response.status_code == 200
        assert response.json() == {"status": "ready", "api_contract": "medbuddy-api-v1"}
        assert seed.call_count == 2


# Function Name: test_readiness_fails_when_schema_revision_is_stale
# Description:
# - Returns HTTP 503 when the database schema revision is stale.
# Parameters:
# - None.
# Returns:
# - None.
def test_readiness_fails_when_schema_revision_is_stale() -> None:
    with (
        patch("main.settings.APP_ENV", "production"),
        patch(
            "main._verify_database_revision",
            side_effect=RuntimeError("stale schema"),
        ),
        TestClient(app) as client,
    ):
        response = client.get("/ready")

    assert response.status_code == 503


# Function Name: test_readiness_fails_when_required_redis_is_unavailable
# Description:
# - Returns HTTP 503 when mandatory Redis storage is unavailable.
# Parameters:
# - None.
# Returns:
# - None.
def test_readiness_fails_when_required_redis_is_unavailable() -> None:
    with (
        patch("main.settings.RATE_LIMIT_REQUIRE_REDIS", True),
        patch(
            "main._ping_required_redis",
            new=AsyncMock(side_effect=RedisConnectionError("redis unavailable")),
        ),
        TestClient(app) as client,
    ):
        response = client.get("/ready")

    assert response.status_code == 503
