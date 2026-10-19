# File Name: caregiver_alert_outbox_insert.py
# Role: Inserts one caregiver alert outbox event while letting an existing event key win.

import logging

from sqlalchemy.dialects.postgresql import insert as postgresql_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from entities.caregiver_alert_outbox_entity import _CaregiverAlertOutbox


# Function Name: insert_caregiver_alert_outbox_if_absent
# Description:
# - Inserts an outbox event without failing on an existing event key, so concurrent writers of
#   the same event leave one row and the caller's transaction stays usable.
# - PostgreSQL and SQLite use INSERT ... ON CONFLICT (event_key) DO NOTHING; other databases
#   add the row inside a savepoint and treat a unique-key violation as an existing row.
# Parameters:
# - db (Session): Caller's session; the caller commits.
# - values (dict[str, object]): Validated outbox column values for one event.
# - duplicate_logger (logging.Logger | None): Logger that records, at DEBUG level, a duplicate
#   found through the savepoint path; None records nothing.
# Returns:
# - True only when this call created a new row.
def insert_caregiver_alert_outbox_if_absent(
    db: Session,
    values: dict[str, object],
    *,
    duplicate_logger: logging.Logger | None = None,
) -> bool:
    dialect_name = db.get_bind().dialect.name
    if dialect_name == "postgresql":
        result = db.execute(
            postgresql_insert(_CaregiverAlertOutbox)
            .values(**values)
            .on_conflict_do_nothing(index_elements=["event_key"])
        )
        return result.rowcount == 1
    if dialect_name == "sqlite":
        result = db.execute(
            sqlite_insert(_CaregiverAlertOutbox)
            .values(**values)
            .on_conflict_do_nothing(index_elements=["event_key"])
        )
        return result.rowcount == 1
    try:
        with db.begin_nested():
            db.add(_CaregiverAlertOutbox(**values))
            db.flush()
        return True
    except IntegrityError:
        if duplicate_logger is not None:
            duplicate_logger.debug("A duplicate caregiver alert outbox event was reused.")
        return False
