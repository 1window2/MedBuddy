# File Name: test_postgres_app_role.py
# Role: Checks that the application database role can read and write data but cannot change the
#   schema, the migration head or role settings, and that provisioning is opt-in.

import os
from uuid import uuid4

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from sqlalchemy.exc import DBAPIError

from scripts import provision_database_roles as provisioning

POSTGRES = os.getenv("MEDBUDDY_RUN_POSTGRES_INTEGRATION") == "1"


# Function Name: test_provisioning_is_skipped_until_both_settings_are_present
# Description: Without settings nothing changes; one setting alone is refused.
# Parameters: monkeypatch - environment isolation; capsys - captured output.
# Returns: None.
def test_provisioning_is_skipped_until_both_settings_are_present(monkeypatch, capsys) -> None:
    monkeypatch.delenv("MEDBUDDY_APP_DB_USER", raising=False)
    monkeypatch.delenv("MEDBUDDY_APP_DB_PASSWORD", raising=False)
    assert provisioning.main() == 0
    assert "keep the owner role" in capsys.readouterr().out

    monkeypatch.setenv("MEDBUDDY_APP_DB_USER", "medbuddy_app")
    assert provisioning.main() == 2


# Function Name: test_role_name_and_password_are_checked_before_any_statement
# Description: A quoted or upper-case role name and a short password are refused in Python.
# Parameters: None. Returns: None.
def test_role_name_and_password_are_checked_before_any_statement() -> None:
    class _NoConnection:
        def execute(self, *_args, **_kwargs):
            raise AssertionError("no statement may run")

    for role, password in (('app"; DROP', "x" * 20), ("App", "x" * 20), ("medbuddy_app", "short")):
        with pytest.raises(ValueError):
            provisioning.provision_application_role(_NoConnection(), role, password)


# Function Name: test_application_role_has_data_access_only
# Description: Provisions a disposable role on the migrated PostgreSQL database and checks its
#   rights as that role, then removes it.
# Parameters: None. Returns: None.
@pytest.mark.skipif(not POSTGRES, reason="needs the migrated PostgreSQL database")
def test_application_role_has_data_access_only() -> None:
    owner_url = make_url(os.environ["DATABASE_URL"])
    role = f"medbuddy_app_test_{uuid4().hex[:12]}"
    password = uuid4().hex + uuid4().hex
    owner = create_engine(owner_url)
    app = create_engine(owner_url.set(username=role, password=password))
    try:
        with owner.begin() as connection:
            provisioning.provision_application_role(connection, role, password)

        with app.connect() as connection:
            assert connection.execute(
                text("SELECT rolsuper, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname = current_user")
            ).one() == (False, False, False)
            assert connection.execute(text("SELECT count(*) FROM alembic_version")).scalar() == 1
            connection.execute(
                text("INSERT INTO user_accounts (user_hash, created_at, updated_at) VALUES (:user_hash, now(), now())"),
                {"user_hash": f"role-test-{uuid4().hex}"},
            )
            connection.rollback()
        for statement in (
            "CREATE TABLE role_test_table (id integer)",
            "UPDATE alembic_version SET version_num = version_num",
            "DROP TABLE user_accounts",
            f"ALTER ROLE {role} SUPERUSER",
        ):
            with app.connect() as connection, pytest.raises(DBAPIError):
                connection.execute(text(statement))

        # A table that a later migration creates is readable without another grant.
        table = f"role_test_{uuid4().hex[:12]}"
        with owner.begin() as connection:
            connection.execute(text(f"CREATE TABLE {table} (id integer)"))
        try:
            with app.connect() as connection:
                assert connection.execute(text(f"SELECT count(*) FROM {table}")).scalar() == 0
        finally:
            with owner.begin() as connection:
                connection.execute(text(f"DROP TABLE {table}"))
    finally:
        app.dispose()
        with owner.begin() as connection:
            connection.execute(text(f'DROP OWNED BY "{role}"'))
            connection.execute(text(f'DROP ROLE IF EXISTS "{role}"'))
        owner.dispose()
