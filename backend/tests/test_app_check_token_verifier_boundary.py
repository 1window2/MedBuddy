"""Focused tests for Firebase App Check verification classification."""

from unittest.mock import patch

import pytest
from jwt import PyJWKClientConnectionError, PyJWKClientError

from boundaries.app_check_token_verifier_boundary import (
    AppCheckTokenVerificationError,
    AppCheckTokenVerificationUnavailableError,
    AppCheckTokenVerifier,
)


def _verifier_without_firebase_initialization() -> AppCheckTokenVerifier:
    verifier = object.__new__(AppCheckTokenVerifier)
    verifier._app = object()
    return verifier


def test_invalid_app_check_token_is_classified_as_untrusted() -> None:
    verifier = _verifier_without_firebase_initialization()

    with patch(
        "boundaries.app_check_token_verifier_boundary.app_check.verify_token",
        side_effect=ValueError("invalid"),
    ):
        with pytest.raises(AppCheckTokenVerificationError):
            verifier.verifyToken("token")


def test_app_check_key_fetch_failure_is_classified_as_unavailable() -> None:
    verifier = _verifier_without_firebase_initialization()

    with patch(
        "boundaries.app_check_token_verifier_boundary.app_check.verify_token",
        side_effect=PyJWKClientConnectionError("network failure"),
    ):
        with pytest.raises(AppCheckTokenVerificationUnavailableError):
            verifier.verifyToken("token")


def test_app_check_unknown_signing_key_is_classified_as_untrusted() -> None:
    verifier = _verifier_without_firebase_initialization()

    with patch(
        "boundaries.app_check_token_verifier_boundary.app_check.verify_token",
        side_effect=PyJWKClientError("signing key not found"),
    ):
        with pytest.raises(AppCheckTokenVerificationError):
            verifier.verifyToken("token")
