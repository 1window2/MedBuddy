# File Name: oidc_token_verifier_boundary.py
# Role: Verifies Firebase OIDC ID tokens and exposes provider-independent authentication failures.
"""Firebase-backed OIDC token verification boundary."""

from collections.abc import Mapping
from typing import Any

from firebase_admin import auth

from boundaries.firebase_admin_boundary import get_firebase_admin_app


# Class Name: TokenVerificationError
# Role:
# - Signals an invalid, expired or otherwise untrusted identity token.
# Responsibilities:
# - Classify rejected credentials separately from temporary verification outages.
class TokenVerificationError(Exception):
    """Raised when an external identity token cannot be trusted."""


# Class Name: TokenVerificationUnavailableError
# Role:
# - Signals that the identity provider could not complete verification.
# Responsibilities:
# - Preserve retryable provider failures without exposing SDK exceptions to controls.
class TokenVerificationUnavailableError(Exception):
    """Raised when the external identity verifier cannot complete its work."""


# Class Name: OIDCTokenVerifier
# Role:
# - Converts Firebase ID-token verification into trusted claim dictionaries.
# Responsibilities:
# - Reject blank tokens, apply optional revocation checks and classify provider exceptions.
# Attributes:
# - _app (App): Shared project-scoped Admin application.
# - _check_revoked (bool): Whether Firebase revocation checks are requested.
class OIDCTokenVerifier:
    """Verifies Firebase ID tokens without exposing Firebase to use-case controls."""

    # Function Name: __init__
    # Description:
    # - Bind the shared project app and retain the requested token-revocation policy.
    # Parameters:
    # - project_id (str): Firebase project ID used by the shared Admin app.
    # - check_revoked (bool): Whether to ask Firebase to reject revoked tokens.
    # Returns:
    # - None; verification occurs only when verifyIdToken is called.
    def __init__(self, project_id: str, *, check_revoked: bool = False) -> None:
        self._check_revoked = check_revoked
        self._app = get_firebase_admin_app(project_id)

    # Function Name: verifyIdToken
    # Description:
    # - Verify the normalized Firebase token, rejecting expired, invalid, revoked or disabled-user credentials.
    # Parameters:
    # - token (str): Unverified token supplied by the requesting client.
    # Returns:
    # - Verified claim dictionary; raises an authentication or availability boundary error on failure.
    def verifyIdToken(self, token: str) -> dict[str, object]:
        normalized_token = token.strip()
        if not normalized_token:
            raise TokenVerificationError("Bearer token is empty.")
        try:
            claims: Mapping[str, Any] = auth.verify_id_token(
                normalized_token,
                app=self._app,
                check_revoked=self._check_revoked,
            )
        except (
            auth.ExpiredIdTokenError,
            auth.InvalidIdTokenError,
            auth.RevokedIdTokenError,
            auth.UserDisabledError,
            ValueError,
        ) as exc:
            raise TokenVerificationError("Bearer token is invalid.") from exc
        except Exception as exc:
            raise TokenVerificationUnavailableError(
                "Firebase token verification is unavailable."
            ) from exc
        return dict(claims)
