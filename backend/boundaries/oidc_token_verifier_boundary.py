"""Firebase-backed OIDC token verification boundary."""

from collections.abc import Mapping
from typing import Any

import firebase_admin
from firebase_admin import auth


class TokenVerificationError(Exception):
    """Raised when an external identity token cannot be trusted."""


class TokenVerificationUnavailableError(Exception):
    """Raised when the external identity verifier cannot complete its work."""


class OIDCTokenVerifier:
    """Verifies Firebase ID tokens without exposing Firebase to use-case controls."""

    _APP_NAME = "medbuddy-auth"

    def __init__(self, project_id: str, *, check_revoked: bool = False) -> None:
        normalized_project_id = project_id.strip()
        if not normalized_project_id:
            raise ValueError("Firebase project ID is required.")
        self._check_revoked = check_revoked
        try:
            self._app = firebase_admin.get_app(self._APP_NAME)
        except ValueError:
            self._app = firebase_admin.initialize_app(
                options={"projectId": normalized_project_id},
                name=self._APP_NAME,
            )

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
