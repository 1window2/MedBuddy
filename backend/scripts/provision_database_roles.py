# File Name: provision_database_roles.py
# Role: Creates or updates the PostgreSQL login role that the API and catalog jobs use, so that only
#   the migration runs with the database owner's rights. Runs after `alembic upgrade head` as the
#   owner. Without MEDBUDDY_APP_DB_USER and MEDBUDDY_APP_DB_PASSWORD it changes nothing, and the
#   services keep using the owner role until both are set.

import os
from pathlib import Path
import re
import sys

from sqlalchemy import text
from sqlalchemy.engine import Connection


ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from core.database import engine  # noqa: E402


# Role names are interpolated by PostgreSQL's own format('%I'); this pattern only keeps them plain.
_ROLE_NAME = re.compile(r"^[a-z_][a-z0-9_]{0,62}$")

# Statements run as the owner inside one transaction. The role name and password are read from
# transaction-local settings, so neither is ever spliced into SQL text by Python.
_PROVISION_SQL = """
DO $provision$
DECLARE
    app_role text := current_setting('medbuddy.app_role');
    app_password text := current_setting('medbuddy.app_password');
    owner_role text := current_user;
BEGIN
    IF app_role = owner_role THEN
        RAISE EXCEPTION 'The application role must differ from the database owner.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = app_role) THEN
        EXECUTE format('CREATE ROLE %I LOGIN', app_role);
    END IF;
    EXECUTE format(
        'ALTER ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS '
        'NOINHERIT CONNECTION LIMIT 40 PASSWORD %L',
        app_role, app_password
    );
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), app_role);
    EXECUTE format('REVOKE CREATE ON SCHEMA public FROM PUBLIC');
    EXECUTE format('GRANT USAGE ON SCHEMA public TO %I', app_role);
    EXECUTE format(
        'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO %I', app_role
    );
    EXECUTE format('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO %I', app_role);
    -- Tables and sequences that later migrations create are covered without another grant.
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public '
        'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I', owner_role, app_role
    );
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public '
        'GRANT USAGE, SELECT ON SEQUENCES TO %I', owner_role, app_role
    );
    -- The services read the migration head at start-up; only the migration may move it.
    IF to_regclass('public.alembic_version') IS NOT NULL THEN
        EXECUTE format('REVOKE INSERT, UPDATE, DELETE ON public.alembic_version FROM %I', app_role);
    END IF;
END
$provision$;
"""


# Function Name: provision_application_role
# Description:
# - Creates the application role if needed, sets its password and attributes, and grants it data
#   access to the public schema without schema changes or ownership.
# Parameters:
# - connection (Connection): Owner connection inside an open transaction.
# - role (str): Application role name.
# - password (str): Application role password.
# Returns:
# - None.
def provision_application_role(connection: Connection, role: str, password: str) -> None:
    if not _ROLE_NAME.fullmatch(role):
        raise ValueError("MEDBUDDY_APP_DB_USER must be a plain lower-case role name.")
    if len(password) < 16:
        raise ValueError("MEDBUDDY_APP_DB_PASSWORD must be at least 16 characters.")
    connection.execute(
        text("SELECT set_config('medbuddy.app_role', :role, true)"), {"role": role}
    )
    connection.execute(
        text("SELECT set_config('medbuddy.app_password', :password, true)"),
        {"password": password},
    )
    connection.execute(text(_PROVISION_SQL))


# Function Name: main
# Description:
# - Reads the role settings from the environment and provisions the role on PostgreSQL.
# Parameters:
# - None.
# Returns:
# - Process exit status.
def main() -> int:
    role = os.environ.get("MEDBUDDY_APP_DB_USER", "").strip()
    password = os.environ.get("MEDBUDDY_APP_DB_PASSWORD", "")
    if not role and not password:
        print("Application database role not configured; services keep the owner role.")
        return 0
    if not role or not password:
        print(
            "Set both MEDBUDDY_APP_DB_USER and MEDBUDDY_APP_DB_PASSWORD, or neither.",
            file=sys.stderr,
        )
        return 2
    if engine.dialect.name != "postgresql":
        print("Application database roles are provisioned on PostgreSQL only.", file=sys.stderr)
        return 2
    with engine.begin() as connection:
        provision_application_role(connection, role, password)
    print(f"Application database role {role} is provisioned.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
