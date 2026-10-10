# File Name: test_catalog_refresh_schedule.py
# Role: Covers the stored schedule of the periodic catalogue refresh: the wait computation, the
#   attempt and success records, the command line used by the refresh loop and the migration.

from datetime import datetime, timedelta
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect
from sqlalchemy.orm import Session

from entities.catalog_refresh_state_entity import (
    CATALOG_REFRESH_SCHEDULE_NAME,
    CatalogRefreshState,
)
from scripts import catalog_refresh_schedule as schedule

_NOW = datetime(2026, 10, 11, 12, 0, 0)
_WEEK = 604_800
_HOUR = 3_600


# Function Name: test_wait_follows_the_last_success_and_the_last_failed_attempt
# Description:
# - A refresh is due one interval after the last success, whatever happened to the process in
#   between; a failed attempt is repeated one retry period after it started; without any success
#   the first refresh waits one retry period; a stored time in the future cannot postpone the
#   refresh beyond one interval.
# Parameters:
# - last_success (timedelta | None): Age of the last success.
# - last_attempt (timedelta | None): Age of the last attempt.
# - expected (int): Expected wait in seconds.
# Returns:
# - None.
@pytest.mark.parametrize(
    ("last_success", "last_attempt", "expected"),
    [
        # Never refreshed: one retry period, counted from the last attempt when there is one.
        (None, None, _HOUR),
        (None, timedelta(minutes=20), 40 * 60),
        (None, timedelta(hours=3), 0),
        # Refreshed two days ago: five days are left, also right after a restart.
        (timedelta(days=2), timedelta(days=2, minutes=30), 5 * 86_400),
        # Overdue: refresh at once.
        (timedelta(days=9), timedelta(days=9), 0),
        # Overdue, and the attempt ten minutes ago did not succeed: wait out the retry period.
        (timedelta(days=9), timedelta(minutes=10), 50 * 60),
        # A failed attempt long before the refresh is due does not bring it forward.
        (timedelta(days=2), timedelta(days=1), 5 * 86_400),
        # A success stamped in the future (clock change) waits one interval at most.
        (timedelta(days=-30), None, _WEEK),
    ],
)
def test_wait_follows_the_last_success_and_the_last_failed_attempt(
    last_success, last_attempt, expected,
) -> None:
    assert schedule.seconds_until_next_refresh(
        now=_NOW,
        last_success_at=None if last_success is None else _NOW - last_success,
        last_attempt_at=None if last_attempt is None else _NOW - last_attempt,
        interval_seconds=_WEEK,
        retry_seconds=_HOUR,
    ) == expected


# Function Name: test_attempt_and_success_are_stored_and_drive_the_wait
# Description:
# - Walks one refresh cycle on a database: nothing stored, attempt recorded, success recorded,
#   and a later failed attempt, checking the wait after each step and that one row is reused.
# Parameters:
# - fk_db (Session): Test session on an empty schema.
# Returns:
# - None.
def test_attempt_and_success_are_stored_and_drive_the_wait(fk_db: Session) -> None:
    # Function Name: wait
    # Description: Reads the wait at a given time with the production periods.
    # Parameters: now (datetime) - Time of the reading.
    # Returns: Wait in seconds.
    def wait(now: datetime) -> int:
        return schedule.wait_seconds(
            fk_db, interval_seconds=_WEEK, retry_seconds=_HOUR, now=now,
        )

    assert wait(_NOW) == _HOUR
    assert fk_db.query(CatalogRefreshState).count() == 0

    schedule.mark_attempt(fk_db, now=_NOW)
    assert wait(_NOW + timedelta(minutes=15)) == 45 * 60

    schedule.mark_success(fk_db, now=_NOW + timedelta(minutes=20))
    assert wait(_NOW + timedelta(minutes=20)) == _WEEK
    assert wait(_NOW + timedelta(days=3, minutes=20)) == 4 * 86_400

    schedule.mark_attempt(fk_db, now=_NOW + timedelta(days=8))
    assert wait(_NOW + timedelta(days=8, minutes=5)) == 55 * 60

    row = fk_db.query(CatalogRefreshState).one()
    assert row.name == CATALOG_REFRESH_SCHEDULE_NAME
    assert row.last_success_at == _NOW + timedelta(minutes=20)
    assert row.last_attempt_at == _NOW + timedelta(days=8)


# Function Name: test_command_line_prints_only_the_wait
# Description:
# - The refresh loop passes the output of `wait-seconds` to `sleep`, so the command must print
#   the number and nothing else, and the two marking commands must print nothing.
# Parameters:
# - fk_session_factory: Session factory on an empty schema.
# - monkeypatch (pytest.MonkeyPatch): Points the script at the test database.
# - capsys (pytest.CaptureFixture[str]): Captures the command output.
# Returns:
# - None.
def test_command_line_prints_only_the_wait(fk_session_factory, monkeypatch, capsys) -> None:
    monkeypatch.setattr(schedule, "SessionLocal", fk_session_factory)

    schedule.main(["wait-seconds", "--interval-seconds", str(_WEEK), "--retry-seconds", "900"])
    assert capsys.readouterr().out == "900\n"

    schedule.main(["mark-attempt"])
    schedule.main(["mark-success"])
    assert capsys.readouterr().out == ""

    schedule.main(["wait-seconds", "--interval-seconds", str(_WEEK), "--retry-seconds", "900"])
    assert _WEEK - 60 <= int(capsys.readouterr().out) <= _WEEK


# Function Name: test_migration_adds_and_removes_only_the_schedule_table
# Description:
# - Upgrading from the previous head creates the empty schedule table and the downgrade removes
#   it again, leaving every other table in place.
# Parameters:
# - tmp_path (Path): Directory of the disposable SQLite database.
# Returns:
# - None.
def test_migration_adds_and_removes_only_the_schedule_table(tmp_path: Path) -> None:
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    url = f"sqlite:///{(tmp_path / 'schedule.db').as_posix()}"
    config.attributes["database_url"] = url
    engine = create_engine(url)
    try:
        command.upgrade(config, "b3a7d9e2f601")
        before = set(inspect(engine).get_table_names())
        assert "catalog_refresh_state" not in before

        command.upgrade(config, "c5e1a7f3b902")
        assert set(inspect(engine).get_table_names()) == before | {"catalog_refresh_state"}
        assert {column["name"] for column in inspect(engine).get_columns("catalog_refresh_state")} == {
            "name", "last_attempt_at", "last_success_at",
        }

        command.downgrade(config, "b3a7d9e2f601")
        assert set(inspect(engine).get_table_names()) == before
    finally:
        engine.dispose()
