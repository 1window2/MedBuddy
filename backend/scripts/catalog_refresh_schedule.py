# File Name: catalog_refresh_schedule.py
# Role: Schedule state of the periodic catalogue refresh for the self-hosted refresh loop.
#   The loop asks how long to wait, records the start of each refresh and records its success,
#   so a container restart resumes the schedule instead of starting a full interval again.

import argparse
from datetime import datetime, timedelta
from pathlib import Path
import sys

from sqlalchemy.orm import Session


ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from core.database import SessionLocal  # noqa: E402
from entities.catalog_refresh_state_entity import (  # noqa: E402
    CATALOG_REFRESH_SCHEDULE_NAME,
    CatalogRefreshState,
)
from entities.user_account_entity import utc_now  # noqa: E402


# Function Name: seconds_until_next_refresh
# Description:
# - Computes how long the refresh loop must wait before its next refresh.
# - A refresh is due one interval after the last success. An attempt that did not succeed is
#   repeated one retry period after it started, so restarts cannot repeat a failing refresh
#   back to back. Without any recorded success the first refresh waits one retry period.
# Parameters:
# - now (datetime): Current time (UTC, naive).
# - last_success_at (datetime | None): Completion of the latest successful refresh.
# - last_attempt_at (datetime | None): Start of the latest refresh.
# - interval_seconds (int): Time between two successful refreshes.
# - retry_seconds (int): Time between a refresh that did not succeed and the next attempt.
# Returns:
# - Whole seconds to wait, from zero up to the interval.
def seconds_until_next_refresh(
    *,
    now: datetime,
    last_success_at: datetime | None,
    last_attempt_at: datetime | None,
    interval_seconds: int,
    retry_seconds: int,
) -> int:
    interval_seconds = max(1, interval_seconds)
    retry_seconds = max(1, min(retry_seconds, interval_seconds))
    if last_success_at is None:
        due_at = (last_attempt_at or now) + timedelta(seconds=retry_seconds)
    else:
        due_at = last_success_at + timedelta(seconds=interval_seconds)
        if last_attempt_at is not None and last_attempt_at > last_success_at:
            due_at = max(due_at, last_attempt_at + timedelta(seconds=retry_seconds))
    remaining = int((due_at - now).total_seconds())
    # A stored time in the future (clock change) must not postpone the refresh beyond one interval.
    return max(0, min(remaining, interval_seconds))


# Function Name: _state
# Description: Loads the schedule row, creating it in the session when it does not exist yet.
# Parameters: db (Session) - Open database session.
# Returns: The schedule row, attached to the session.
def _state(db: Session) -> CatalogRefreshState:
    state = db.get(CatalogRefreshState, CATALOG_REFRESH_SCHEDULE_NAME)
    if state is None:
        state = CatalogRefreshState(name=CATALOG_REFRESH_SCHEDULE_NAME)
        db.add(state)
    return state


# Function Name: wait_seconds
# Description: Reads the stored schedule state and returns the wait before the next refresh.
# Parameters:
# - db (Session): Open database session.
# - interval_seconds (int): Time between two successful refreshes.
# - retry_seconds (int): Time between a failed refresh and the next attempt.
# - now (datetime | None): Current time; defaults to the present.
# Returns:
# - Whole seconds to wait.
def wait_seconds(
    db: Session,
    *,
    interval_seconds: int,
    retry_seconds: int,
    now: datetime | None = None,
) -> int:
    state = db.get(CatalogRefreshState, CATALOG_REFRESH_SCHEDULE_NAME)
    return seconds_until_next_refresh(
        now=now or utc_now(),
        last_success_at=None if state is None else state.last_success_at,
        last_attempt_at=None if state is None else state.last_attempt_at,
        interval_seconds=interval_seconds,
        retry_seconds=retry_seconds,
    )


# Function Name: mark_attempt
# Description: Records that a refresh is starting.
# Parameters: db (Session) - Open database session; now (datetime | None) - Current time.
# Returns: None.
def mark_attempt(db: Session, *, now: datetime | None = None) -> None:
    _state(db).last_attempt_at = now or utc_now()
    db.commit()


# Function Name: mark_success
# Description: Records that every catalogue was synchronized by the refresh that just ended.
# Parameters: db (Session) - Open database session; now (datetime | None) - Current time.
# Returns: None.
def mark_success(db: Session, *, now: datetime | None = None) -> None:
    _state(db).last_success_at = now or utc_now()
    db.commit()


# Function Name: parse_args
# Description: Reads the command and, for the wait computation, the two periods in seconds.
# Parameters: argv (list[str] | None) - Arguments; defaults to the process arguments.
# Returns: Parsed arguments.
def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    wait = commands.add_parser("wait-seconds")
    wait.add_argument("--interval-seconds", type=int, required=True)
    wait.add_argument("--retry-seconds", type=int, required=True)
    commands.add_parser("mark-attempt")
    commands.add_parser("mark-success")
    return parser.parse_args(argv)


# Function Name: main
# Description: Runs one command against the database. `wait-seconds` prints the wait as its only
#   output so the loop can pass it to `sleep`.
# Parameters: argv (list[str] | None) - Arguments; defaults to the process arguments.
# Returns: None.
def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    db = SessionLocal()
    try:
        if args.command == "wait-seconds":
            print(
                wait_seconds(
                    db,
                    interval_seconds=args.interval_seconds,
                    retry_seconds=args.retry_seconds,
                )
            )
        elif args.command == "mark-attempt":
            mark_attempt(db)
        else:
            mark_success(db)
    finally:
        db.close()


if __name__ == "__main__":
    main()
