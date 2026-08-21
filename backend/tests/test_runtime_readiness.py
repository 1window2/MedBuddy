"""Tests for process liveness and production dependency readiness."""

from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient
from redis.exceptions import ConnectionError as RedisConnectionError
from sqlalchemy.exc import OperationalError

from main import app


def test_liveness_does_not_depend_on_external_services() -> None:
    with TestClient(app) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "api_contract": "medbuddy-api-v1",
    }


def test_readiness_checks_database_connectivity() -> None:
    with TestClient(app) as client:
        response = client.get("/ready")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ready",
        "api_contract": "medbuddy-api-v1",
    }


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
    verify_revision.assert_called_once()
    verify_catalog_seed.assert_called_once()
    verify_firebase_credentials.assert_called_once_with("medbuddy-test")
    get_oidc.assert_called_once_with()
    get_app_check.assert_called_once_with()
    ping_redis.assert_awaited_once_with()


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
