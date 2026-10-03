# File Name: test_firebase_identity_boundary.py
# Role: Regression coverage for verified-subject identity deletion and retryable Firebase
#   failures.
"""Focused tests for idempotent Firebase identity deletion."""

from unittest.mock import patch

import pytest
from firebase_admin import auth

from boundaries.firebase_identity_boundary import (
    FirebaseIdentityDeletionBoundary,
    IdentityDeletionUnavailableError,
)


# Function Name: test_delete_identity_uses_verified_subject
# Description:
# - Passes the verified Firebase subject and correct app to the identity-deletion API exactly
#   once.
# Parameters:
# - None.
# Returns:
# - None.
def test_delete_identity_uses_verified_subject() -> None:
    firebase_app = object()
    with (
        patch(
            "boundaries.firebase_identity_boundary.get_firebase_admin_app",
            return_value=firebase_app,
        ),
        patch(
            "boundaries.firebase_identity_boundary.auth.delete_user"
        ) as delete_user,
    ):
        boundary = FirebaseIdentityDeletionBoundary("medbuddy-test")
        boundary.deleteIdentity(" firebase-uid ")

    delete_user.assert_called_once_with("firebase-uid", app=firebase_app)


# Function Name: test_delete_identity_treats_missing_user_as_success
# Description:
# - Treats an already missing Firebase user as successful idempotent deletion without raising an
#   error.
# Parameters:
# - None.
# Returns:
# - None.
def test_delete_identity_treats_missing_user_as_success() -> None:
    with (
        patch(
            "boundaries.firebase_identity_boundary.get_firebase_admin_app",
            return_value=object(),
        ),
        patch(
            "boundaries.firebase_identity_boundary.auth.delete_user",
            side_effect=auth.UserNotFoundError("already deleted"),
        ),
    ):
        FirebaseIdentityDeletionBoundary("medbuddy-test").deleteIdentity(
            "firebase-uid"
        )


# Function Name: test_delete_identity_classifies_provider_outage_as_retryable
# Description:
# - Classifies a Firebase deletion outage as retryable IdentityDeletionUnavailableError.
# Parameters:
# - None.
# Returns:
# - None.
def test_delete_identity_classifies_provider_outage_as_retryable() -> None:
    with (
        patch(
            "boundaries.firebase_identity_boundary.get_firebase_admin_app",
            return_value=object(),
        ),
        patch(
            "boundaries.firebase_identity_boundary.auth.delete_user",
            side_effect=RuntimeError("provider unavailable"),
        ),
    ):
        with pytest.raises(IdentityDeletionUnavailableError):
            FirebaseIdentityDeletionBoundary("medbuddy-test").deleteIdentity(
                "firebase-uid"
            )