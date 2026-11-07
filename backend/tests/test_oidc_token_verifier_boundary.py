# File Name: test_oidc_token_verifier_boundary.py
# Role: Regression coverage for invalid Firebase ID tokens versus unavailable certificate
#   verification, and for the short-lived cache of account revocation state.
"""Focused tests for Firebase token-verification failure classification."""

from types import SimpleNamespace
from unittest.mock import patch

import pytest
from firebase_admin import auth

import boundaries.oidc_token_verifier_boundary as boundary_module
from boundaries.oidc_token_verifier_boundary import (
    DeletedIdentityTokenError,
    OIDCTokenVerifier,
    TokenVerificationError,
    TokenVerificationUnavailableError,
    forget_identity_state,
)

_CLAIMS = {"uid": "user-1", "iss": "https://securetoken.google.com/medbuddy-test", "iat": 1_000}


# Function Name: fresh_identity_cache
# Description: Gives every test an empty account-state cache.
# Parameters: monkeypatch (pytest.MonkeyPatch): Restores the module cache afterwards.
# Returns: None.
@pytest.fixture(autouse=True)
def fresh_identity_cache(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(boundary_module, "_identity_states", boundary_module._IdentityStateCache())


# Class Name: _Clock
# Role: Manually advanced monotonic clock.
# Attributes: now (float): Current time in seconds.
class _Clock:
    # Function Name: __init__
    # Description: Starts the clock at 100 s. Parameters: None. Returns: None.
    def __init__(self) -> None:
        self.now = 100.0

    # Function Name: __call__
    # Description: Reads the clock. Parameters: None. Returns: float: current time.
    def __call__(self) -> float:
        return self.now


# Function Name: _verifier
# Description:
# - Creates an ID-token verifier with revocation checking enabled and a placeholder app,
#   avoiding Firebase initialization.
# Parameters:
# - cache_seconds (float): Reuse time of an account's revocation state.
# - clock (_Clock | None): Monotonic clock replacement.
# Returns:
# - OIDCTokenVerifier: Verifier with a placeholder Firebase app and no initialization side
#   effects.
def _verifier(cache_seconds: float = 0, clock: _Clock | None = None) -> OIDCTokenVerifier:
    verifier = object.__new__(OIDCTokenVerifier)
    verifier._app = object()
    verifier._check_revoked = True
    verifier._cache_seconds = cache_seconds
    verifier._clock = clock or _Clock()
    return verifier


# Function Name: _user
# Description: Builds the account fields the revocation rule reads.
# Parameters: disabled (bool); valid_after_ms (int): tokens-valid-after time in milliseconds.
# Returns: SimpleNamespace: Stand-in for a Firebase UserRecord.
def _user(disabled: bool = False, valid_after_ms: int = 0) -> SimpleNamespace:
    return SimpleNamespace(disabled=disabled, tokens_valid_after_timestamp=valid_after_ms)


# Function Name: test_invalid_or_expired_token_is_classified_as_untrusted
# Description: Local signature or expiry failures reject the token without an account lookup.
# Parameters: verification_error (Exception): Error raised by local verification.
# Returns: None.
@pytest.mark.parametrize(
    "verification_error",
    [
        auth.InvalidIdTokenError("invalid"),
        auth.ExpiredIdTokenError("expired", RuntimeError("expired")),
    ],
)
def test_invalid_or_expired_token_is_classified_as_untrusted(
    verification_error: Exception,
) -> None:
    with (
        patch.object(boundary_module.auth, "verify_id_token", side_effect=verification_error),
        patch.object(boundary_module.auth, "get_user") as get_user,
    ):
        with pytest.raises(TokenVerificationError):
            _verifier().verifyIdToken("token")
    get_user.assert_not_called()


# Function Name: test_revoked_or_disabled_account_is_classified_as_untrusted
# Description: Firebase's rule applies: a disabled account, or a token issued before the
#   revocation time, is rejected; a token issued at or after it is accepted.
# Parameters: user (SimpleNamespace): Account state; accepted (bool): expected outcome.
# Returns: None.
@pytest.mark.parametrize(
    ("user", "accepted"),
    [
        (_user(disabled=True), False),
        (_user(valid_after_ms=1_000_001), False),
        (_user(valid_after_ms=1_000_000), True),
        (_user(), True),
    ],
)
def test_revoked_or_disabled_account_is_classified_as_untrusted(
    user: SimpleNamespace, accepted: bool
) -> None:
    with (
        patch.object(boundary_module.auth, "verify_id_token", return_value=dict(_CLAIMS)),
        patch.object(boundary_module.auth, "get_user", return_value=user),
    ):
        if accepted:
            assert _verifier().verifyIdToken("token") == _CLAIMS
        else:
            with pytest.raises(TokenVerificationError):
                _verifier().verifyIdToken("token")


# Function Name: test_certificate_fetch_failure_is_classified_as_unavailable
# Description: A key download failure is a temporary outage, not an invalid token.
# Parameters: None.
# Returns: None.
def test_certificate_fetch_failure_is_classified_as_unavailable() -> None:
    with patch.object(
        boundary_module.auth,
        "verify_id_token",
        side_effect=auth.CertificateFetchError(
            "certificate service unavailable",
            RuntimeError("network failure"),
        ),
    ):
        with pytest.raises(TokenVerificationUnavailableError):
            _verifier().verifyIdToken("token")


# Function Name: test_account_lookup_failure_is_classified_as_unavailable
# Description: A failed revocation lookup is a temporary outage and is not cached.
# Parameters: None.
# Returns: None.
def test_account_lookup_failure_is_classified_as_unavailable() -> None:
    verifier = _verifier(cache_seconds=30)
    with (
        patch.object(boundary_module.auth, "verify_id_token", return_value=dict(_CLAIMS)),
        patch.object(
            boundary_module.auth, "get_user", side_effect=[RuntimeError("down"), _user()]
        ) as get_user,
    ):
        with pytest.raises(TokenVerificationUnavailableError):
            verifier.verifyIdToken("token")
        assert verifier.verifyIdToken("token") == _CLAIMS
    assert get_user.call_count == 2


# Function Name: test_deleted_account_token_keeps_its_verified_claims
# Description: A valid token of a deleted account carries its claims for a retried deletion.
# Parameters: None.
# Returns: None.
def test_deleted_account_token_keeps_its_verified_claims() -> None:
    with (
        patch.object(boundary_module.auth, "verify_id_token", return_value=dict(_CLAIMS)),
        patch.object(
            boundary_module.auth, "get_user", side_effect=auth.UserNotFoundError("deleted")
        ),
    ):
        with pytest.raises(DeletedIdentityTokenError) as rejected:
            _verifier(cache_seconds=30).verifyIdToken("token")

    assert isinstance(rejected.value, TokenVerificationError)
    assert rejected.value.claims == _CLAIMS


# Function Name: test_account_state_is_reused_within_the_cache_time
# Description: Repeated requests reuse the account state; a revocation made in Firebase applies
#   once the cache time has passed.
# Parameters: None.
# Returns: None.
def test_account_state_is_reused_within_the_cache_time() -> None:
    clock = _Clock()
    verifier = _verifier(cache_seconds=30, clock=clock)
    with (
        patch.object(boundary_module.auth, "verify_id_token", return_value=dict(_CLAIMS)),
        patch.object(
            boundary_module.auth,
            "get_user",
            side_effect=[_user(), _user(valid_after_ms=2_000_000)],
        ) as get_user,
    ):
        verifier.verifyIdToken("token")
        clock.now += 29
        verifier.verifyIdToken("token")
        assert get_user.call_count == 1
        clock.now += 1
        with pytest.raises(TokenVerificationError):
            verifier.verifyIdToken("token")
    assert get_user.call_count == 2


# Function Name: test_zero_cache_time_looks_the_account_up_every_time
# Description: With caching off every request asks Firebase, as before.
# Parameters: None.
# Returns: None.
def test_zero_cache_time_looks_the_account_up_every_time() -> None:
    verifier = _verifier(cache_seconds=0)
    with (
        patch.object(boundary_module.auth, "verify_id_token", return_value=dict(_CLAIMS)),
        patch.object(boundary_module.auth, "get_user", return_value=_user()) as get_user,
    ):
        verifier.verifyIdToken("token")
        verifier.verifyIdToken("token")
    assert get_user.call_count == 2


# Function Name: test_deleting_the_identity_forgets_the_cached_state
# Description: After this server deletes an identity, the next request looks the account up at once.
# Parameters: None.
# Returns: None.
def test_deleting_the_identity_forgets_the_cached_state() -> None:
    verifier = _verifier(cache_seconds=30)
    verifier._clock = boundary_module.time.monotonic
    with (
        patch.object(boundary_module.auth, "verify_id_token", return_value=dict(_CLAIMS)),
        patch.object(
            boundary_module.auth,
            "get_user",
            side_effect=[_user(), auth.UserNotFoundError("deleted")],
        ),
    ):
        verifier.verifyIdToken("token")
        forget_identity_state("user-1")
        with pytest.raises(DeletedIdentityTokenError):
            verifier.verifyIdToken("token")


# Function Name: test_lookup_started_before_a_deletion_is_not_cached
# Description: A lookup that began before the identity was deleted does not refill the cache.
# Parameters: None.
# Returns: None.
def test_lookup_started_before_a_deletion_is_not_cached() -> None:
    verifier = _verifier(cache_seconds=30)
    verifier._clock = boundary_module.time.monotonic

    # Function Name: lookup_racing_deletion
    # Description: Returns the old account state after the identity was deleted meanwhile.
    # Parameters: uid (str); app (object). Returns: SimpleNamespace: pre-deletion state.
    def lookup_racing_deletion(uid: str, *, app: object) -> SimpleNamespace:
        forget_identity_state(uid)
        return _user()

    calls = iter([lookup_racing_deletion, auth.UserNotFoundError("deleted")])

    # Function Name: get_user
    # Description: Plays the racing lookup first, then the deleted account.
    # Parameters: uid (str); app (object). Returns: SimpleNamespace or raises UserNotFoundError.
    def get_user(uid: str, *, app: object) -> SimpleNamespace:
        step = next(calls)
        if isinstance(step, Exception):
            raise step
        return step(uid, app=app)

    with (
        patch.object(boundary_module.auth, "verify_id_token", return_value=dict(_CLAIMS)),
        patch.object(boundary_module.auth, "get_user", side_effect=get_user),
    ):
        verifier.verifyIdToken("token")
        with pytest.raises(DeletedIdentityTokenError):
            verifier.verifyIdToken("token")
