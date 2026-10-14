# File Name: test_oidc_token_verifier_boundary.py
# Role: Regression coverage for invalid Firebase ID tokens versus unavailable certificate
#   verification.
"""Focused tests for Firebase token-verification failure classification."""

from unittest.mock import patch

import pytest
from firebase_admin import auth

from boundaries.oidc_token_verifier_boundary import (
    OIDCTokenVerifier,
    TokenVerificationError,
    TokenVerificationUnavailableError,
)


# Function Name: _verifier_without_firebase_initialization
# Description:
# - Creates an ID-token verifier with revocation checking enabled and a placeholder app,
#   avoiding Firebase initialization.
# Parameters:
# - None.
# Returns:
# - OIDCTokenVerifier: Verifier with a placeholder Firebase app and no initialization side
#   effects.
def _verifier_without_firebase_initialization() -> OIDCTokenVerifier:
    verifier = object.__new__(OIDCTokenVerifier)
    verifier._app = object()
    verifier._check_revoked = True
    return verifier


# Function Name: test_invalid_or_revoked_token_is_classified_as_untrusted
# Description:
# - Classifies invalid or revoked tokens as untrusted token-verification errors.
# Parameters:
# - verification_error (Exception): Injected trust or availability exception from token
#   verification.
# Returns:
# - None.
@pytest.mark.parametrize(
    "verification_error",
    [
        auth.InvalidIdTokenError("invalid"),
        auth.ExpiredIdTokenError("expired", RuntimeError("expired")),
        auth.RevokedIdTokenError("revoked"),
        auth.UserDisabledError("disabled"),
        auth.UserNotFoundError("deleted"),
    ],
)
def test_invalid_or_revoked_token_is_classified_as_untrusted(
    verification_error: Exception,
) -> None:
    verifier = _verifier_without_firebase_initialization()

    with patch(
        "boundaries.oidc_token_verifier_boundary.auth.verify_id_token",
        side_effect=verification_error,
    ):
        with pytest.raises(TokenVerificationError):
            verifier.verifyIdToken("token")


# Function Name: test_certificate_fetch_failure_is_classified_as_unavailable
# Description:
# - Classifies certificate retrieval failure as retryable verification unavailability.
# Parameters:
# - None.
# Returns:
# - None.
def test_certificate_fetch_failure_is_classified_as_unavailable() -> None:
    verifier = _verifier_without_firebase_initialization()

    with patch(
        "boundaries.oidc_token_verifier_boundary.auth.verify_id_token",
        side_effect=auth.CertificateFetchError(
            "certificate service unavailable",
            RuntimeError("network failure"),
        ),
    ):
        with pytest.raises(TokenVerificationUnavailableError):
            verifier.verifyIdToken("token")


# Function Name: test_deleted_account_token_keeps_its_verified_claims
# Description:
# - A correctly signed token whose Firebase account no longer exists is still rejected, as a
#   DeletedIdentityTokenError that carries the claims read without the revocation lookup, so that
#   only a retried account deletion can finish with it.
# Parameters:
# - None.
# Returns:
# - None.
def test_deleted_account_token_keeps_its_verified_claims() -> None:
    from boundaries.oidc_token_verifier_boundary import DeletedIdentityTokenError

    verifier = _verifier_without_firebase_initialization()
    claims = {"uid": "gone-user", "iss": "https://securetoken.google.com/medbuddy-test"}

    def verify(token: str, *, app: object, check_revoked: bool) -> dict[str, object]:
        if check_revoked:
            raise auth.UserNotFoundError("deleted")
        return claims

    with patch(
        "boundaries.oidc_token_verifier_boundary.auth.verify_id_token",
        side_effect=verify,
    ):
        with pytest.raises(DeletedIdentityTokenError) as rejected:
            verifier.verifyIdToken("token")

    assert isinstance(rejected.value, TokenVerificationError)
    assert rejected.value.claims == claims
