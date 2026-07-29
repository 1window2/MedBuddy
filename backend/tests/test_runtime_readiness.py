"""Tests for process liveness and production dependency readiness."""

from unittest.mock import patch

from fastapi.testclient import TestClient
from sqlalchemy.exc import OperationalError

from main import app


def test_liveness_does_not_depend_on_external_services() -> None:
    with TestClient(app) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_readiness_checks_database_connectivity() -> None:
    with TestClient(app) as client:
        response = client.get("/ready")

    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


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
