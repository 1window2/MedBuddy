"""Firebase App Check verification boundary for first-party app requests."""

from collections.abc import Mapping
from typing import Any

from firebase_admin import app_check
import logging

from jwt import PyJWKClientConnectionError, PyJWKClientError

from boundaries.firebase_admin_boundary import get_firebase_admin_app

logger = logging.getLogger(__name__)


class AppCheckTokenVerificationError(Exception):
    """Raised when a device-attestation token cannot be trusted."""


class AppCheckTokenVerificationUnavailableError(Exception):
    """Raised when the external verifier cannot complete verification."""


class AppCheckTokenVerifier:
    """Verifies App Check tokens without exposing Firebase to API controls."""

    def __init__(self, project_id: str) -> None:
        self._app = get_firebase_admin_app(project_id)

    def verifyToken(self, token: str) -> dict[str, object]:
        normalized_token = token.strip()
        if not normalized_token:
            raise AppCheckTokenVerificationError("App Check token is empty.")
        try:
            claims: Mapping[str, Any] = app_check.verify_token(
                normalized_token,
                app=self._app,
            )
        except ValueError as exc:
            raise AppCheckTokenVerificationError(
                "App Check token is invalid."
            ) from exc
        except PyJWKClientConnectionError as exc:
            raise AppCheckTokenVerificationUnavailableError(
                "App Check signing keys are unavailable."
            ) from exc
        except PyJWKClientError as exc:
            raise AppCheckTokenVerificationError(
                "App Check token is invalid."
            ) from exc
        except Exception as exc:
            logger.warning(
                "Unexpected App Check verification failure: %s",
                type(exc).__name__,
            )
            raise AppCheckTokenVerificationUnavailableError(
                "App Check verification is unavailable."
            ) from exc
        return dict(claims)
