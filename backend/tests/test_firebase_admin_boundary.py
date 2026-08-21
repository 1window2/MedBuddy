"""Focused tests for the shared Firebase Admin application boundary."""

from concurrent.futures import ThreadPoolExecutor
from unittest.mock import Mock, patch

import pytest

from boundaries.firebase_admin_boundary import (
    get_firebase_admin_app,
    verify_firebase_admin_credentials,
)


def test_firebase_admin_app_reuses_the_same_project() -> None:
    existing_app = Mock(options={"projectId": "medbuddy-test"})

    with patch(
        "boundaries.firebase_admin_boundary.firebase_admin.get_app",
        return_value=existing_app,
    ):
        assert get_firebase_admin_app(" medbuddy-test ") is existing_app


@pytest.mark.parametrize("configured_project_id", ["", "other-project"])
def test_firebase_admin_app_rejects_project_mismatch(
    configured_project_id: str,
) -> None:
    existing_app = Mock(options={"projectId": configured_project_id})

    with patch(
        "boundaries.firebase_admin_boundary.firebase_admin.get_app",
        return_value=existing_app,
    ):
        with pytest.raises(ValueError, match="does not match"):
            get_firebase_admin_app("medbuddy-test")


def test_firebase_admin_app_initializes_once_under_concurrency() -> None:
    initialized_app = Mock(options={"projectId": "medbuddy-test"})
    initialized = False

    def get_app(_name: str) -> object:
        if not initialized:
            raise ValueError("missing")
        return initialized_app

    def initialize_app(*, options: dict[str, str], name: str) -> object:
        nonlocal initialized
        assert options == {"projectId": "medbuddy-test"}
        assert name == "medbuddy-backend"
        initialized = True
        return initialized_app

    with (
        patch(
            "boundaries.firebase_admin_boundary.firebase_admin.get_app",
            side_effect=get_app,
        ),
        patch(
            "boundaries.firebase_admin_boundary.firebase_admin.initialize_app",
            side_effect=initialize_app,
        ) as initialize,
        ThreadPoolExecutor(max_workers=4) as executor,
    ):
        apps = list(
            executor.map(
                get_firebase_admin_app,
                ["medbuddy-test"] * 4,
            )
        )

    assert apps == [initialized_app] * 4
    initialize.assert_called_once()


def test_firebase_admin_readiness_forces_lazy_credential_loading() -> None:
    credential = Mock()
    app = Mock(credential=credential)

    with patch(
        "boundaries.firebase_admin_boundary.get_firebase_admin_app",
        return_value=app,
    ) as get_app:
        verify_firebase_admin_credentials("medbuddy-test")

    get_app.assert_called_once_with("medbuddy-test")
    credential.get_credential.assert_called_once_with()
