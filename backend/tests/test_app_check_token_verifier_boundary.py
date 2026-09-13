# File Name: test_app_check_token_verifier_boundary.py
# Role: Regression coverage for App Check trust failures versus verification-service outages.
"""Focused tests for Firebase App Check verification classification."""

from unittest.mock import patch

import pytest
from jwt import PyJWKClientConnectionError, PyJWKClientError

from boundaries.app_check_token_verifier_boundary import (
    AppCheckTokenVerificationError,
    AppCheckTokenVerificationUnavailableError,
    AppCheckTokenVerifier,
)


# Function Name: _verifier_without_firebase_initialization
# Description:
# - Allocates an App Check verifier with a placeholder app to avoid Firebase initialization in
#   exception tests.
# Parameters:
# - None.
# Returns:
# - AppCheckTokenVerifier: Verifier with a placeholder Firebase app and no initialization side
#   effects.
def _verifier_without_firebase_initialization() -> AppCheckTokenVerifier:
    verifier = object.__new__(AppCheckTokenVerifier)
    verifier._app = object()
    return verifier


# Function Name: test_invalid_app_check_token_is_classified_as_untrusted
# Description:
# - Requires an invalid App Check token to be classified as untrusted, not a verifier outage.
# Parameters:
# - None.
# Returns:
# - None.
def test_invalid_app_check_token_is_classified_as_untrusted() -> None:
    verifier = _verifier_without_firebase_initialization()

    with patch(
        "boundaries.app_check_token_verifier_boundary.app_check.verify_token",
        side_effect=ValueError("invalid"),
    ):
        with pytest.raises(AppCheckTokenVerificationError):
            verifier.verifyToken("token")


# Function Name: test_app_check_key_fetch_failure_is_classified_as_unavailable
# Description:
# - Requires signing-key retrieval failure to produce the retryable verification-unavailable
#   error.
# Parameters:
# - None.
# Returns:
# - None.
def test_app_check_key_fetch_failure_is_classified_as_unavailable() -> None:
    verifier = _verifier_without_firebase_initialization()

    with patch(
        "boundaries.app_check_token_verifier_boundary.app_check.verify_token",
        side_effect=PyJWKClientConnectionError("network failure"),
    ):
        with pytest.raises(AppCheckTokenVerificationUnavailableError):
            verifier.verifyToken("token")


# Function Name: test_app_check_unknown_signing_key_is_classified_as_untrusted
# Description:
# - Requires an unknown signing key to classify the token as untrusted.
# Parameters:
# - None.
# Returns:
# - None.
def test_app_check_unknown_signing_key_is_classified_as_untrusted() -> None:
    verifier = _verifier_without_firebase_initialization()

    with patch(
        "boundaries.app_check_token_verifier_boundary.app_check.verify_token",
        side_effect=PyJWKClientError("signing key not found"),
    ):
        with pytest.raises(AppCheckTokenVerificationError):
            verifier.verifyToken("token")
