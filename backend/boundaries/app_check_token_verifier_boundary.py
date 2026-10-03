# File Name: app_check_token_verifier_boundary.py
# Role: Verifies Firebase App Check attestations and classifies invalid tokens versus verifier outages.
"""Firebase App Check verification boundary for first-party app requests."""

from collections.abc import Mapping
from typing import Any

from firebase_admin import app_check
import logging

from jwt import PyJWKClientConnectionError, PyJWKClientError

from boundaries.firebase_admin_boundary import get_firebase_admin_app

logger = logging.getLogger(__name__)


# Class Name: AppCheckTokenVerificationError
# Role:
# - Signals an untrusted device-attestation token.
# Responsibilities:
# - Separate invalid or empty tokens from retryable verifier outages.
class AppCheckTokenVerificationError(Exception):
    """Raised when a device-attestation token cannot be trusted."""


# Class Name: AppCheckTokenVerificationUnavailableError
# Role:
# - Signals a temporary inability to verify device attestations.
# Responsibilities:
# - Expose signing-key connection failures and unexpected provider errors to callers.
class AppCheckTokenVerificationUnavailableError(Exception):
    """Raised when the external verifier cannot complete verification."""


# Class Name: AppCheckTokenVerifier
# Role:
# - Adapts Firebase App Check verification to control-layer claims.
# Responsibilities:
# - Normalize tokens and distinguish authentication failures from verifier unavailability.
# Attributes:
# - _app (App): Shared Firebase Admin application for the configured project.
class AppCheckTokenVerifier:
    """Verifies App Check tokens without exposing Firebase to API controls."""

    # Function Name: __init__
    # Description:
    # - Bind the verifier to the process-wide Firebase Admin application.
    # Parameters:
    # - project_id (str): Firebase project ID used by the shared Admin app.
    # Returns:
    # - None; the project-scoped app is retained.
    def __init__(self, project_id: str) -> None:
        self._app = get_firebase_admin_app(project_id)

    # Function Name: verifyToken
    # Description:
    # - Verify a nonblank App Check token and translate SDK/key-fetch failures into boundary exceptions.
    # Parameters:
    # - token (str): Unverified token supplied by the requesting client.
    # Returns:
    # - Verified claims as a dictionary; raises a token or availability error on failure.
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
