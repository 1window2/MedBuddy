# File Name: oidc_token_verifier_boundary.py
# Role: Verifies Firebase OIDC ID tokens and exposes provider-independent authentication failures.
"""Firebase-backed OIDC token verification boundary."""

import threading
import time
from collections.abc import Callable, Mapping
from typing import Any

from firebase_admin import auth

from boundaries.firebase_admin_boundary import get_firebase_admin_app


# Class Name: TokenVerificationError
# Role:
# - Signals an invalid, expired or otherwise untrusted identity token.
# Responsibilities:
# - Classify rejected credentials separately from temporary verification outages.
# Attributes: Inherited exception arguments only; no additional instance state.
class TokenVerificationError(Exception):
    """Raised when an external identity token cannot be trusted."""


# Class Name: DeletedIdentityTokenError
# Role:
# - Signals a correctly signed, unexpired token whose Firebase account no longer exists.
# Responsibilities:
# - Carry the verified claims so that only a retried account deletion can finish with them;
#   every other request treats the token as rejected.
# Attributes:
# - claims (dict[str, object]): Claims verified without the revocation lookup.
class DeletedIdentityTokenError(TokenVerificationError):
    """Raised when the token is valid but its Firebase account has been deleted."""

    # Function Name: __init__
    # Description: Retains verified token claims so account cleanup can identify a deleted Firebase identity without treating it as an active account.
    # Parameters: claims (dict[str, object]) were verified without the revocation lookup.
    # Returns: None; initializes the exception message and stores the supplied claims.
    def __init__(self, claims: dict[str, object]) -> None:
        super().__init__("The Firebase account of this token has been deleted.")
        self.claims = claims


# Class Name: TokenVerificationUnavailableError
# Role:
# - Signals that the identity provider could not complete verification.
# Responsibilities:
# - Preserve retryable provider failures without exposing SDK exceptions to controls.
# Attributes: Inherited exception arguments only; no additional instance state.
class TokenVerificationUnavailableError(Exception):
    """Raised when the external identity verifier cannot complete its work."""


# Class Name: _IdentityStateCache
# Role:
# - Remembers each Firebase account's disabled flag and session-revocation time for a short time.
# Responsibilities:
# - Let the revocation check skip the Firebase account lookup, a network round trip, for repeated
#   requests from one account; the single API process keeps one shared cache.
# - Forget an account at once when this server deletes its Firebase identity, and refuse to store a
#   lookup that started before that deletion.
# Attributes:
# - _entries (dict[str, tuple[float, bool, int]]): uid -> (expiry, disabled, tokens valid after in ms).
# - _forgotten (dict[str, float]): uid -> monotonic time it was last forgotten.
# - _lock (Lock): Guards the entries across request threads.
class _IdentityStateCache:
    _MAX_ENTRIES = 10_000

    # Function Name: __init__
    # Description: Starts with no remembered accounts.
    # Parameters: None.
    # Returns: None.
    def __init__(self) -> None:
        self._entries: dict[str, tuple[float, bool, int]] = {}
        self._forgotten: dict[str, float] = {}
        self._lock = threading.Lock()

    # Function Name: get
    # Description: Returns a remembered state that has not expired.
    # Parameters: uid (str): Firebase account; now (float): monotonic time.
    # Returns: (disabled, tokens valid after in ms), or None when absent or expired.
    def get(self, uid: str, now: float) -> tuple[bool, int] | None:
        with self._lock:
            entry = self._entries.get(uid)
            if entry is None or entry[0] <= now:
                return None
            return entry[1], entry[2]

    # Function Name: put
    # Description: Remembers an account state until now + ttl, unless the account was forgotten after the
    #   lookup started; drops expired entries when the cache is full.
    # Parameters: uid (str); disabled (bool); valid_after_ms (int); looked_up_at (float): monotonic
    #   time the lookup started; ttl (float): seconds.
    # Returns: None.
    def put(self, uid: str, disabled: bool, valid_after_ms: int, looked_up_at: float, ttl: float) -> None:
        with self._lock:
            if self._forgotten.get(uid, float("-inf")) >= looked_up_at:
                return
            if len(self._entries) >= self._MAX_ENTRIES:
                for key in [key for key, entry in self._entries.items() if entry[0] <= now]:
                    del self._entries[key]
                if len(self._entries) >= self._MAX_ENTRIES:
                    self._entries.clear()
            self._entries[uid] = (looked_up_at + ttl, disabled, valid_after_ms)

    # Function Name: forget
    # Description: Drops one account so its next request looks Firebase up again.
    # Parameters: uid (str): Firebase account; now (float): monotonic time of the deletion.
    # Returns: None.
    def forget(self, uid: str, now: float) -> None:
        with self._lock:
            self._entries.pop(uid, None)
            if len(self._forgotten) >= self._MAX_ENTRIES:
                self._forgotten.clear()
            self._forgotten[uid] = now


_identity_states = _IdentityStateCache()


# Function Name: forget_identity_state
# Description: Makes the next token check of a Firebase account look the account up again; called when this server deletes the identity.
# Parameters: uid (str): Firebase account.
# Returns: None.
def forget_identity_state(uid: str) -> None:
    _identity_states.forget(uid.strip(), time.monotonic())


# Class Name: OIDCTokenVerifier
# Role:
# - Converts Firebase ID-token verification into trusted claim dictionaries.
# Responsibilities:
# - Reject blank tokens, apply optional revocation checks and classify provider exceptions.
# - Check revocation as Firebase does (disabled account, token issued before the revocation time)
#   against an account state remembered for at most revocation_cache_seconds.
# Attributes:
# - _app (App): Shared project-scoped Admin application.
# - _check_revoked (bool): Whether Firebase revocation checks are requested.
# - _cache_seconds (float): How long an account's revocation state is reused; 0 looks it up every time.
# - _clock (Callable[[], float]): Monotonic clock.
class OIDCTokenVerifier:
    """Verifies Firebase ID tokens without exposing Firebase to use-case controls."""

    # Function Name: __init__
    # Description:
    # - Bind the shared project app and retain the requested token-revocation policy.
    # Parameters:
    # - project_id (str): Firebase project ID used by the shared Admin app.
    # - check_revoked (bool): Whether to reject revoked tokens and disabled accounts.
    # - revocation_cache_seconds (float): Reuse of an account's revocation state; a revocation made
    #   in Firebase applies within this time, one made by this server's deletion applies at once.
    # - clock (Callable[[], float]): Monotonic clock, replaceable in tests.
    # Returns:
    # - None; verification occurs only when verifyIdToken is called.
    def __init__(
        self,
        project_id: str,
        *,
        check_revoked: bool = False,
        revocation_cache_seconds: float = 0,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._check_revoked = check_revoked
        self._cache_seconds = max(0.0, float(revocation_cache_seconds))
        self._clock = clock
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
            # Signature, expiry, audience and issuer are checked locally with cached Google keys.
            claims: Mapping[str, Any] = auth.verify_id_token(
                normalized_token,
                app=self._app,
                check_revoked=False,
            )
        except (
            auth.ExpiredIdTokenError,
            auth.InvalidIdTokenError,
            ValueError,
        ) as exc:
            raise TokenVerificationError("Bearer token is invalid.") from exc
        except Exception as exc:
            raise TokenVerificationUnavailableError(
                "Firebase token verification is unavailable."
            ) from exc
        if self._check_revoked:
            self._reject_revoked(claims)
        return dict(claims)

    # Function Name: _reject_revoked
    # Description:
    # - Apply Firebase's revocation rule: reject a disabled account, and a token issued before the
    #   account's tokens-valid-after time. The account state comes from the cache or one lookup.
    # Parameters:
    # - claims (Mapping[str, Any]): Locally verified token claims.
    # Returns:
    # - None; raises TokenVerificationError, DeletedIdentityTokenError or TokenVerificationUnavailableError.
    def _reject_revoked(self, claims: Mapping[str, Any]) -> None:
        uid = str(claims.get("uid") or claims.get("sub") or "")
        now = self._clock()
        state = _identity_states.get(uid, now) if self._cache_seconds else None
        if state is None:
            try:
                user = auth.get_user(uid, app=self._app)
            except auth.UserNotFoundError as exc:
                # The account is gone although the token itself is valid. A retried account deletion
                # whose first answer was lost can then finish; other requests still reject the token.
                raise DeletedIdentityTokenError(dict(claims)) from exc
            except Exception as exc:
                raise TokenVerificationUnavailableError(
                    "Firebase token verification is unavailable."
                ) from exc
            state = (bool(user.disabled), int(user.tokens_valid_after_timestamp or 0))
            if self._cache_seconds:
                _identity_states.put(uid, state[0], state[1], now, self._cache_seconds)
        disabled, valid_after_ms = state
        issued_at = claims.get("iat")
        if disabled or not isinstance(issued_at, int | float) or issued_at * 1000 < valid_after_ms:
            raise TokenVerificationError("Bearer token is invalid.")
