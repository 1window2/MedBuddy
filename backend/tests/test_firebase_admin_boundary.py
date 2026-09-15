# File Name: test_firebase_admin_boundary.py
# Role: Regression coverage for Firebase Admin app reuse, project isolation, concurrency, and
#   credential readiness.
"""Focused tests for the shared Firebase Admin application boundary."""

from concurrent.futures import ThreadPoolExecutor
from unittest.mock import Mock, patch

import pytest

from boundaries.firebase_admin_boundary import (
    get_firebase_admin_app,
    verify_firebase_admin_credentials,
)


# Function Name: test_firebase_admin_app_reuses_the_same_project
# Description:
# - Reuses the existing Firebase app after trimming the configured project ID.
# Parameters:
# - None.
# Returns:
# - None.
def test_firebase_admin_app_reuses_the_same_project() -> None:
    existing_app = Mock(options={"projectId": "medbuddy-test"})

    with patch(
        "boundaries.firebase_admin_boundary.firebase_admin.get_app",
        return_value=existing_app,
    ):
        assert get_firebase_admin_app(" medbuddy-test ") is existing_app


# Function Name: test_firebase_admin_app_rejects_project_mismatch
# Description:
# - Rejects an existing Firebase app whose project does not match the configured project.
# Parameters:
# - configured_project_id (str): Project ID compared with the existing Firebase app.
# Returns:
# - None.
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


# Function Name: test_firebase_admin_app_initializes_once_under_concurrency
# Description:
# - Requires four concurrent initialization requests to receive the same app from one
#   initialization call.
# Parameters:
# - None.
# Returns:
# - None.
def test_firebase_admin_app_initializes_once_under_concurrency() -> None:
    initialized_app = Mock(options={"projectId": "medbuddy-test"})
    initialized = False

    # Function Name: get_app
    # Description:
    # - Simulates Firebase app lookup by failing until the test initializer has registered
    #   its app.
    # Parameters:
    # - _name (str): Named Firebase application to initialize. Unused by this double.
    # Returns:
    # - object: Shared initialized Firebase app object.
    def get_app(_name: str) -> object:
        if not initialized:
            raise ValueError("missing")
        return initialized_app

    # Function Name: initialize_app
    # Description:
    # - Checks the project and named-app options, marks initialization complete, and returns
    #   the shared app object.
    # Parameters:
    # - options (dict[str, str]): Firebase initialization options containing the expected
    #   project ID.
    # - name (str): Named Firebase application to initialize.
    # Returns:
    # - object: Shared Firebase app object registered by the initializer double.
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


# Function Name: test_firebase_admin_readiness_forces_lazy_credential_loading
# Description:
# - Forces lazy Firebase credentials to load during readiness checks instead of accepting an
#   unvalidated app handle.
# Parameters:
# - None.
# Returns:
# - None.
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
