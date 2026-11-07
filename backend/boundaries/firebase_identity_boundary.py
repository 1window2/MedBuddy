# File Name: firebase_identity_boundary.py
# Role: Isolates Firebase identity deletion and session-revocation lookups from MedBuddy controls.

from datetime import UTC, datetime
from typing import Protocol

from firebase_admin import auth

from boundaries.firebase_admin_boundary import get_firebase_admin_app


# Class Name: IdentityDeletionUnavailableError
# Role:
# - Signals a retryable failure to delete an external Firebase identity.
# Responsibilities:
# - Allow account controls to distinguish provider outages from idempotent success.
# Attributes: Inherited exception arguments only; no additional instance state.
class IdentityDeletionUnavailableError(RuntimeError):
    """Raised when Firebase cannot complete a retryable identity deletion."""


# Class Name: IdentityDeletionBoundary
# Role:
# - Defines the external identity deletion contract used by ManageAccount.
# Responsibilities:
# - Require deletion by verified UID and allow an already absent identity to count as success.
# Attributes: None required by this protocol; implementations own storage and connection state.
class IdentityDeletionBoundary(Protocol):
    # Function Name: deleteIdentity
    # Description:
    # - Permanently deletes one already authenticated external identity.
    # - Treats a previously deleted identity as an idempotent success.
    # Parameters:
    # - subject (str): Trusted Firebase UID extracted from a verified ID token.
    # Returns:
    # - None after the identity no longer exists.
    def deleteIdentity(self, subject: str) -> None: ...


# Class Name: FirebaseIdentityDeletionBoundary
# Role:
# - Deletes Firebase Authentication users through the Admin SDK.
# Responsibilities:
# - Reuse the process-wide project-scoped Firebase Admin app.
# - Classify user-not-found as success and other provider failures as retryable.
# Attributes:
# - _app (App): Shared Firebase Admin application used for identity deletion.
class FirebaseIdentityDeletionBoundary:
    # Function Name: __init__
    # Description:
    # - Reuse the configured project's Admin app for subsequent identity deletion requests.
    # Parameters:
    # - project_id (str): Firebase project ID used by the shared Admin app.
    # Returns:
    # - None; the shared Admin app is retained.
    def __init__(self, project_id: str) -> None:
        self._app = get_firebase_admin_app(project_id)

    # Function Name: deleteIdentity
    # Description:
    # - Deletes the trusted Firebase UID without accepting a client user hash.
    # Parameters:
    # - subject (str): Verified Firebase UID.
    # Returns:
    # - None after deletion or when the identity was already absent.
    def deleteIdentity(self, subject: str) -> None:
        normalized_subject = subject.strip()
        if not normalized_subject:
            raise ValueError("Firebase subject is required for account deletion.")
        try:
            auth.delete_user(normalized_subject, app=self._app)
        except auth.UserNotFoundError:
            return
        except Exception as exc:
            raise IdentityDeletionUnavailableError(
                "Firebase identity deletion is temporarily unavailable."
            ) from exc


# Class Name: FirebaseSessionRevocationBoundary
# Role:
# - Reads when a Firebase user's sessions were last revoked (password change, revokeRefreshTokens).
# Responsibilities:
# - Report the revocation time so device registrations from older sessions can be retired.
# - Never fail a caller: an unavailable lookup reports no revocation.
# Attributes:
# - _app (App): Shared Firebase Admin application.
class FirebaseSessionRevocationBoundary:
    # Function Name: __init__
    # Description: Reuses the configured project's shared Firebase Admin app for identity operations.
    # Parameters: project_id (str) is the Firebase project ID.
    # Returns: None; Admin initialization/configuration errors propagate.
    def __init__(self, project_id: str) -> None:
        self._app = get_firebase_admin_app(project_id)

    # Function Name: sessionsValidAfter
    # Description:
    # - Returns the time before which the user's sessions are revoked, as naive UTC like the
    #   database columns, or None when unknown.
    # Parameters:
    # - subject (str): Verified Firebase UID.
    # Returns:
    # - Naive UTC datetime or None.
    def sessionsValidAfter(self, subject: str) -> datetime | None:
        try:
            milliseconds = auth.get_user(subject.strip(), app=self._app).tokens_valid_after_timestamp
        except Exception:
            return None
        if not milliseconds:
            return None
        return datetime.fromtimestamp(milliseconds / 1000, tz=UTC).replace(tzinfo=None)
