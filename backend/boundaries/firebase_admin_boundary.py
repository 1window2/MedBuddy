# File Name: firebase_admin_boundary.py
# Role: Shares one locked, project-scoped Firebase Admin application and probes its credentials.
"""Shared Firebase Admin application boundary."""

from threading import Lock

import firebase_admin
from firebase_admin import App


_FIREBASE_APP_NAME = "medbuddy-backend"
_firebase_app_lock = Lock()


# Function Name: get_firebase_admin_app
# Description:
# - Reuse or initialize the named Admin app under a lock; reject a blank or conflicting project ID.
# Parameters:
# - project_id (str): Firebase project ID used by the shared Admin app.
# Returns:
# - The shared App for the requested project.
def get_firebase_admin_app(project_id: str) -> App:
    """Return the process-wide Firebase Admin app for the configured project."""
    normalized_project_id = project_id.strip()
    if not normalized_project_id:
        raise ValueError("Firebase project ID is required.")

    with _firebase_app_lock:
        try:
            app = firebase_admin.get_app(_FIREBASE_APP_NAME)
        except ValueError:
            return firebase_admin.initialize_app(
                options={"projectId": normalized_project_id},
                name=_FIREBASE_APP_NAME,
            )

        configured_project_id = str(app.options.get("projectId", "")).strip()
        if configured_project_id != normalized_project_id:
            raise ValueError("Firebase project ID does not match the initialized app.")
        return app


# Function Name: verify_firebase_admin_credentials
# Description:
# - Forces Firebase Admin's lazy application-default credential loader to read and parse the configured credential during the production readiness probe.
# - Prevents the API from reporting ready when its runtime user cannot read the mounted Firebase credential.
# Parameters:
# - project_id (str): Firebase project identifier expected by the backend.
# Returns:
# - None when the configured credential can be loaded.
def verify_firebase_admin_credentials(project_id: str) -> None:
    app = get_firebase_admin_app(project_id)
    app.credential.get_credential()
