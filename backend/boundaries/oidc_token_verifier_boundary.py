"""Firebase-backed OIDC token verification boundary."""

from collections.abc import Mapping
from typing import Any

from firebase_admin import auth

from boundaries.firebase_admin_boundary import get_firebase_admin_app


class TokenVerificationError(Exception):
    """Raised when an external identity token cannot be trusted."""


class TokenVerificationUnavailableError(Exception):
    """Raised when the external identity verifier cannot complete its work."""


class OIDCTokenVerifier:
    """Verifies Firebase ID tokens without exposing Firebase to use-case controls."""

    def __init__(self, project_id: str, *, check_revoked: bool = False) -> None:
        self._check_revoked = check_revoked
        self._app = get_firebase_admin_app(project_id)

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
