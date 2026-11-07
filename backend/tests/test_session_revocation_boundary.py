# File Name: test_session_revocation_boundary.py
# Role: Checks the Firebase session-revocation lookup used to retire device registrations.

from datetime import datetime
from types import SimpleNamespace
from typing import NoReturn

import pytest

from boundaries import firebase_identity_boundary as boundary_module


# Function Name: test_revocation_time_is_naive_utc_and_failures_report_none
# Description: The revocation timestamp is returned as naive UTC; a missing value or a provider
#   failure reports no revocation, so registration never fails because of the lookup.
# Parameters: monkeypatch - replaces the Admin app and the user lookup.
# Returns: None.
def test_revocation_time_is_naive_utc_and_failures_report_none(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(boundary_module, "get_firebase_admin_app", lambda _project: object())
    lookup = boundary_module.FirebaseSessionRevocationBoundary("project")

    monkeypatch.setattr(boundary_module.auth, "get_user", lambda uid, app: SimpleNamespace(
        tokens_valid_after_timestamp=1_780_000_000_000,
    ))
    assert lookup.sessionsValidAfter(" uid-1 ") == datetime(2026, 5, 28, 20, 26, 40)

    monkeypatch.setattr(boundary_module.auth, "get_user", lambda uid, app: SimpleNamespace(
        tokens_valid_after_timestamp=None,
    ))
    assert lookup.sessionsValidAfter("uid-1") is None

    # Function Name: unavailable
    # Description:
    # - Simulates a provider outage during refresh-token revocation.
    # Parameters:
    # - uid: str; external user identifier, unused.
    # - app: object; Firebase app, unused.
    # Returns:
    # - Never returns; raises RuntimeError.
    def unavailable(uid: str, app: object) -> NoReturn:
        raise RuntimeError("provider down")

    monkeypatch.setattr(boundary_module.auth, "get_user", unavailable)
    assert lookup.sessionsValidAfter("uid-1") is None
