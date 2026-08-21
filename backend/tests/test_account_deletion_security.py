# File Name: test_account_deletion_security.py
# Role: Regression coverage for recent-authenticated, transaction-safe deletion.

from datetime import UTC, datetime, timedelta
import os
from pathlib import Path
import sys
import tempfile
from threading import Event, Thread

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from api.dependencies import (
    _lock_account_operation,
    get_recently_authenticated_principal,
)
from controls.manage_account_control import ManageAccount
from core.database import Base
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.health_recommendation_cache_entity import (
    _HealthRecommendationCache,
)


class _RecordingIdentityDeletionBoundary:
    """Records the verified Firebase subject used by account deletion."""

    def __init__(self) -> None:
        self.subjects: list[str] = []

    def deleteIdentity(self, subject: str) -> None:
        self.subjects.append(subject)


# Function Name: _principal
# Description:
# - Builds a verified Firebase principal with an explicit authentication time.
# Parameters:
# - authenticated_at: Authentication instant to encode in Firebase auth_time.
# - provider: Firebase sign-in provider under test.
# Returns:
# - A server-derived authenticated principal.
def _principal(
    authenticated_at: datetime | None,
    *,
    provider: str = "password",
) -> AuthenticatedPrincipal:
    claims: dict[str, object] = {
        "uid": f"{provider}-deletion-user",
        "iss": "https://securetoken.google.com/medbuddy-test",
        "email": "patient@example.com",
        "email_verified": True,
        "firebase": {"sign_in_provider": provider},
    }
    if authenticated_at is not None:
        claims["auth_time"] = authenticated_at.timestamp()
    return AuthenticatedPrincipal.from_verified_claims(claims)


def test_recent_authentication_is_required_before_permanent_deletion() -> None:
    now = datetime.now(UTC)
    fresh = _principal(now - timedelta(seconds=30))
    stale = _principal(now - timedelta(days=30))
    missing = _principal(None)

    assert get_recently_authenticated_principal(fresh) is fresh
    for principal in (stale, missing):
        with pytest.raises(HTTPException) as denied:
            get_recently_authenticated_principal(principal)
        assert denied.value.status_code == 401
        assert denied.value.headers == {"WWW-Authenticate": "Bearer"}


def test_anonymous_guest_deletion_has_an_explicit_freshness_exception() -> None:
    guest = _principal(
        datetime.now(UTC) - timedelta(days=30),
        provider="anonymous",
    )

    assert guest.anonymous is True
    assert get_recently_authenticated_principal(guest) is guest


def test_invalid_firebase_auth_time_is_rejected() -> None:
    with pytest.raises(ValueError, match="auth_time"):
        AuthenticatedPrincipal.from_verified_claims(
            {
                "uid": "invalid-auth-time",
                "iss": "https://securetoken.google.com/medbuddy-test",
                "auth_time": "yesterday",
            }
        )


def test_account_lock_orders_inflight_write_before_deletion() -> None:
    database_fd, database_path_value = tempfile.mkstemp(
        prefix="medbuddy-account-deletion-",
        suffix=".db",
    )
    os.close(database_fd)
    database_path = Path(database_path_value)
    engine = create_engine(
        f"sqlite:///{database_path.as_posix()}",
        connect_args={"check_same_thread": False, "timeout": 5},
    )
    Base.metadata.create_all(bind=engine)
    session_factory = sessionmaker(bind=engine)
    setup_session: Session = session_factory()
    writer_session: Session = session_factory()
    deletion_session: Session = session_factory()
    user_hash = "usr_transaction_locked_deletion"
    ManageAccount(setup_session).ensureAccount(user_hash, commit=True)
    setup_session.close()

    writer_locked = Event()
    deletion_attempted = Event()
    failures: list[BaseException] = []
    deletion_results: list[dict[str, object]] = []
    identity_boundary = _RecordingIdentityDeletionBoundary()

    # Step 1: The writer holds the same account transaction lock used by requests.
    # Step 2: Deletion attempts the lock and waits instead of purging concurrently.
    # Step 3: The writer commits, then deletion acquires the lock and purges the row.
    def write_medical_row() -> None:
        try:
            _lock_account_operation(writer_session, user_hash)
            ManageAccount(writer_session).ensureAccount(user_hash)
            writer_locked.set()
            if not deletion_attempted.wait(timeout=2):
                raise TimeoutError("Deletion did not attempt the account lock.")
            writer_session.add(
                _HealthRecommendationCache(
                    patient_hash=user_hash,
                    recommendation_key="inflight-write",
                    payload="{}",
                )
            )
            writer_session.commit()
        except BaseException as exc:  # pragma: no cover - asserted in parent
            failures.append(exc)
            writer_session.rollback()

    def delete_account() -> None:
        try:
            if not writer_locked.wait(timeout=2):
                raise TimeoutError("Writer did not acquire the account lock.")
            deletion_attempted.set()
            _lock_account_operation(deletion_session, user_hash)
            deletion_results.append(
                ManageAccount(
                    deletion_session,
                    identity_deletion_boundary=identity_boundary,
                ).deleteAccountData(
                    user_hash,
                    external_subject="firebase-deletion-subject",
                )
            )
        except BaseException as exc:  # pragma: no cover - asserted in parent
            failures.append(exc)
            deletion_session.rollback()

    writer = Thread(target=write_medical_row, daemon=True)
    deleter = Thread(target=delete_account, daemon=True)
    writer.start()
    deleter.start()
    writer.join(timeout=8)
    deleter.join(timeout=8)

    verification_session: Session = session_factory()
    try:
        assert not writer.is_alive()
        assert not deleter.is_alive()
        assert failures == []
        assert deletion_results[0]["success"] is True
        assert identity_boundary.subjects == ["firebase-deletion-subject"]
        assert (
            verification_session.query(_HealthRecommendationCache).count()
            == 0
        )
    finally:
        verification_session.close()
        writer_session.close()
        deletion_session.close()
        engine.dispose()
        database_path.unlink(missing_ok=True)
