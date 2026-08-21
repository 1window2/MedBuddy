# File Name: firebase_identity_boundary.py
# Role: Isolates Firebase identity deletion from MedBuddy account controls.

from typing import Protocol

from firebase_admin import auth

from boundaries.firebase_admin_boundary import get_firebase_admin_app


class IdentityDeletionUnavailableError(RuntimeError):
    """Raised when Firebase cannot complete a retryable identity deletion."""


# Class Name: IdentityDeletionBoundary
# Role: Defines the external identity deletion contract used by ManageAccount.
class IdentityDeletionBoundary(Protocol):
    # Function Name: deleteIdentity
    # Description:
    # - Permanently deletes one already authenticated external identity.
    # - Treats a previously deleted identity as an idempotent success.
    # Parameters:
    # - subject: Trusted Firebase UID extracted from a verified ID token.
    # Returns:
    # - None after the identity no longer exists.
    def deleteIdentity(self, subject: str) -> None: ...


# Class Name: FirebaseIdentityDeletionBoundary
# Role: Deletes Firebase Authentication users through the Admin SDK.
# Responsibilities:
# - Reuse the process-wide project-scoped Firebase Admin app.
# - Classify user-not-found as success and other provider failures as retryable.
class FirebaseIdentityDeletionBoundary:
    def __init__(self, project_id: str) -> None:
        self._app = get_firebase_admin_app(project_id)

    # Function Name: deleteIdentity
    # Description:
    # - Deletes the trusted Firebase UID without accepting a client user hash.
    # Parameters:
    # - subject: Verified Firebase UID.
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