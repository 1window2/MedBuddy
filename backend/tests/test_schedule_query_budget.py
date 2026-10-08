# File Name: test_schedule_query_budget.py
# Role: Statement budgets for the dose-recording and schedule paths, so a per-medication
#   lookup (N+1) or a per-tick re-evaluation cannot return unnoticed.
#
# Every budget counts the SQL statements one control call sends to the database
# (`before_cursor_execute`). Reads must not depend on how many medications share a slot; the
# only statements that grow with the slot are the INSERTs of new completion rows, one per
# medication on SQLite.

from collections.abc import Iterator
from contextlib import contextmanager

import pytest
from sqlalchemy import event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from controls.check_schedule_control import CheckSchedule
from controls.queue_missed_dose_alerts_control import QueueMissedDoseAlerts
from controls.set_notification_control import SetNotification
from core.application_clock import application_now
from entities.caregiver_alert_outbox_entity import _CaregiverAlertOutbox
from entities.caregiver_notification_entity import (
    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
    CAREGIVER_NOTIFICATION_SLOT_KEYS,
    _CaregiverNotification,
    encode_slot_settings,
)
from entities.medication_completion_entity import _MedicationCompletion
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.saved_medication_entity import _SavedMedication
from entities.user_setting_entity import _UserSetting
from services.saved_medication_retention import SavedMedicationRetentionPolicy
from support.db import seed_account, seed_medication

PATIENT_HASH = "budget-patient"


# Function Name: count_statements
# Description:
# - Records every SQL statement the engine executes inside the with-block.
# Parameters:
# - engine (Engine): Test engine whose statements are counted.
# Returns:
# - Iterator yielding the list that receives the statements in execution order.
@contextmanager
def count_statements(engine: Engine) -> Iterator[list[str]]:
    statements: list[str] = []

    # Function Name: record
    # Description:
    # - Appends the statement text of one cursor execution.
    # Parameters:
    # - _connection (object): Connection of the execution; unused.
    # - _cursor (object): DB-API cursor; unused.
    # - statement (str): SQL text about to be executed.
    # - _parameters (object): Bound parameters; unused.
    # - _context (object): Execution context; unused.
    # - _executemany (bool): Batch flag; unused.
    # Returns:
    # - None.
    def record(
        _connection: object,
        _cursor: object,
        statement: str,
        _parameters: object,
        _context: object,
        _executemany: bool,
    ) -> None:
        statements.append(" ".join(statement.split()))

    event.listen(engine, "before_cursor_execute", record)
    try:
        yield statements
    finally:
        event.remove(engine, "before_cursor_execute", record)


# Function Name: statements_of_kind
# Description:
# - Filters recorded statements by their leading SQL keyword.
# Parameters:
# - statements (list[str]): Statements recorded by count_statements.
# - keyword (str): Leading keyword such as SELECT or INSERT.
# Returns:
# - The statements that start with the keyword.
def statements_of_kind(statements: list[str], keyword: str) -> list[str]:
    return [
        statement
        for statement in statements
        if statement.upper().startswith(keyword.upper())
    ]


# Function Name: seed_slot
# Description:
# - Saves `in_slot` medications taken in the morning and evening plus three lunch-only
#   medications for the budget patient, all active today.
# Parameters:
# - db (Session): Session on the test database.
# - in_slot (int): Number of medications that share the morning slot.
# Returns:
# - Ids of the morning/evening medications in saving order.
def seed_slot(db: Session, in_slot: int) -> list[int]:
    medication_ids = [
        int(
            seed_medication(
                db,
                patient_hash=PATIENT_HASH,
                item_name=f"slot-tablet-{index}",
                daily_frequency="2 times",
                schedule_slot_keys='["morning","evening"]',
            ).id
        )
        for index in range(in_slot)
    ]
    for index in range(3):
        seed_medication(
            db,
            patient_hash=PATIENT_HASH,
            item_name=f"lunch-tablet-{index}",
            daily_frequency="1 time",
            schedule_slot_keys='["lunch"]',
        )
    return medication_ids


# Function Name: test_slot_update_statements_stay_within_budget
# Description:
# - Completing a slot reads the day once: at most three SELECTs (medications, completion
#   rows, the outbox event) however many medications share the slot, and at most 14
#   statements for eight medications. Repeating the same state and unchecking the slot
#   insert nothing and stay within four statements.
# Parameters:
# - fk_engine (Engine): Foreign-key-enforcing test engine.
# - fk_session_factory (sessionmaker[Session]): Factory bound to the test engine.
# - in_slot (int): Number of medications in the updated slot.
# Returns:
# - None.
@pytest.mark.parametrize("in_slot", [2, 8, 16])
def test_slot_update_statements_stay_within_budget(
    fk_engine: Engine,
    fk_session_factory: sessionmaker[Session],
    in_slot: int,
) -> None:
    with fk_session_factory() as seed_db:
        seed_slot(seed_db, in_slot)

    with fk_session_factory() as db:
        control = CheckSchedule(db)
        with count_statements(fk_engine) as first:
            response = control.updateMedicationSlotStatus("morning", True, PATIENT_HASH)
        with count_statements(fk_engine) as repeated:
            control.updateMedicationSlotStatus("morning", True, PATIENT_HASH)
        with count_statements(fk_engine) as unchecked:
            control.updateMedicationSlotStatus("morning", False, PATIENT_HASH)

        assert len(response["data"]) == in_slot
        assert db.query(_MedicationCompletion).count() == in_slot
        assert db.query(_CaregiverAlertOutbox).count() == 1

    assert len(statements_of_kind(first, "SELECT")) <= 3, first
    assert len(first) <= in_slot + 6, first
    if in_slot == 8:
        assert len(first) <= 14, first
    for later in (repeated, unchecked):
        assert len(later) <= 4, later
        assert statements_of_kind(later, "INSERT") == [], later


# Function Name: test_single_medication_update_statements_stay_within_budget
# Description:
# - Completing one medication in one slot loads the medication and the day once, also when
#   seven other medications share the slot: at most three SELECTs and five statements
#   (one INSERT for the completion row, one UPDATE for the medication's status date).
# Parameters:
# - fk_engine (Engine): Foreign-key-enforcing test engine.
# - fk_session_factory (sessionmaker[Session]): Factory bound to the test engine.
# Returns:
# - None.
def test_single_medication_update_statements_stay_within_budget(
    fk_engine: Engine,
    fk_session_factory: sessionmaker[Session],
) -> None:
    with fk_session_factory() as seed_db:
        medication_ids = seed_slot(seed_db, 8)

    with fk_session_factory() as db:
        with count_statements(fk_engine) as statements:
            response = CheckSchedule(db).updateMedicationStatus(
                medication_ids[0],
                True,
                PATIENT_HASH,
                "evening",
            )

    assert response["data"]["slot_statuses"] == {"morning": False, "evening": True}
    assert len(statements_of_kind(statements, "SELECT")) <= 3, statements
    assert len(statements) <= 5, statements


# Function Name: test_schedule_reads_use_two_statements
# Description:
# - Today's schedule and the slot predicates of the missed-dose and outbox workers each
#   read the medications and the day's completion rows once, with eight medications that
#   all have completion rows.
# Parameters:
# - fk_engine (Engine): Foreign-key-enforcing test engine.
# - fk_session_factory (sessionmaker[Session]): Factory bound to the test engine.
# Returns:
# - None.
def test_schedule_reads_use_two_statements(
    fk_engine: Engine,
    fk_session_factory: sessionmaker[Session],
) -> None:
    with fk_session_factory() as seed_db:
        seed_slot(seed_db, 8)
        CheckSchedule(seed_db).updateMedicationSlotStatus("morning", True, PATIENT_HASH)

    today = application_now().date()
    with fk_session_factory() as db:
        control = CheckSchedule(db)
        with count_statements(fk_engine) as schedule_statements:
            schedule = control.requestTodayMedicationSchedule(PATIENT_HASH)
        with count_statements(fk_engine) as incomplete_statements:
            evening_incomplete = control.isMedicationSlotIncomplete(
                patient_hash=PATIENT_HASH,
                schedule_date=today,
                slot_key="evening",
            )
        with count_statements(fk_engine) as complete_statements:
            morning_complete = control.is_medication_slot_complete(
                patient_hash=PATIENT_HASH,
                schedule_date=today,
                slot_key="morning",
            )

    assert len(schedule["data"]) == 11
    assert evening_incomplete is True
    assert morning_complete is True
    assert len(schedule_statements) <= 2, schedule_statements
    assert len(incomplete_statements) <= 2, incomplete_statements
    assert len(complete_statements) <= 2, complete_statements


# Function Name: test_steady_missed_dose_tick_issues_no_insert
# Description:
# - After every due slot has been queued, the next scan of the missed-dose worker reads the
#   settings and today's queued keys and stops: no schedule lookup, no conflicting INSERT.
#   A slot that becomes due later is still queued by that scan.
# Parameters:
# - fk_engine (Engine): Foreign-key-enforcing test engine.
# - fk_session_factory (sessionmaker[Session]): Factory bound to the test engine.
# Returns:
# - None.
def test_steady_missed_dose_tick_issues_no_insert(
    fk_engine: Engine,
    fk_session_factory: sessionmaker[Session],
) -> None:
    now = application_now().replace(hour=12, minute=0, second=0, microsecond=0)
    later = now.replace(hour=21)
    caregivers = ("budget-caregiver-a", "budget-caregiver-b")
    with fk_session_factory() as seed_db:
        seed_account(seed_db, PATIENT_HASH, *caregivers)
        for slot_key in CAREGIVER_NOTIFICATION_SLOT_KEYS:
            seed_medication(
                seed_db,
                patient_hash=PATIENT_HASH,
                item_name=f"{slot_key}-tablet",
                created_date=now.date(),
                daily_frequency="1 time",
                schedule_slot_keys=f'["{slot_key}"]',
            )
        for caregiver_hash in caregivers:
            seed_db.add(
                _PatientCaregiverLink(
                    patient_hash=PATIENT_HASH,
                    caregiver_hash=caregiver_hash,
                    linked=True,
                )
            )
            seed_db.add(
                _CaregiverNotification(
                    patient_hash=PATIENT_HASH,
                    caregiver_hash=caregiver_hash,
                    enabled=True,
                    alert_option=CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
                    slot_settings=encode_slot_settings(
                        {
                            slot_key: {
                                "notification_type": (
                                    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE
                                ),
                                # Bedtime is due only at the later scan.
                                "deadline_hour": 20 if slot_key == "bedtime" else 0,
                                "deadline_minute": 0,
                            }
                            for slot_key in CAREGIVER_NOTIFICATION_SLOT_KEYS
                        }
                    ),
                )
            )
        seed_db.commit()

    with fk_session_factory() as db:
        queue = QueueMissedDoseAlerts(db)
        assert queue.queueDue(now=now) == 6
        with count_statements(fk_engine) as steady:
            queued_again = queue.queueDue(now=now)
        queued_later = queue.queueDue(now=later)
        with count_statements(fk_engine) as steady_later:
            queued_later_again = queue.queueDue(now=later)
        assert db.query(_CaregiverAlertOutbox).count() == 8

    assert queued_again == 0
    assert queued_later == 2
    assert queued_later_again == 0
    for steady_statements in (steady, steady_later):
        assert len(steady_statements) <= 2, steady_statements
        assert statements_of_kind(steady_statements, "INSERT") == [], steady_statements


# Function Name: test_alarm_list_reads_preferences_once
# Description:
# - Listing the four alarm slots of a patient without saved alarms reads the alarm rows and
#   the preference row once each, instead of one preference read per missing slot.
# Parameters:
# - fk_engine (Engine): Foreign-key-enforcing test engine.
# - fk_session_factory (sessionmaker[Session]): Factory bound to the test engine.
# Returns:
# - None.
def test_alarm_list_reads_preferences_once(
    fk_engine: Engine,
    fk_session_factory: sessionmaker[Session],
) -> None:
    with fk_session_factory() as seed_db:
        seed_account(seed_db, PATIENT_HASH)
        seed_db.add(_UserSetting(user_hash=PATIENT_HASH, default_morning_time="07:30"))
        seed_db.commit()

    with fk_session_factory() as db:
        with count_statements(fk_engine) as statements:
            alarms = SetNotification(db).requestMedicationAlarm(PATIENT_HASH)["data"]

    assert [(alarm["hour"], alarm["minute"]) for alarm in alarms] == [
        (7, 30),
        (12, 0),
        (18, 0),
        (22, 0),
    ]
    assert len(statements) <= 2, statements


# Function Name: test_disabled_retention_reads_no_medication
# Description:
# - With retention switched off (0 days, the default) the cleanup that runs before every
#   pillbox save and in periodic maintenance deletes nothing and does not load the saved
#   medications at all, for one patient or for everyone.
# Parameters:
# - fk_engine (Engine): Foreign-key-enforcing test engine.
# - fk_session_factory (sessionmaker[Session]): Factory bound to the test engine.
# Returns:
# - None.
def test_disabled_retention_reads_no_medication(
    fk_engine: Engine,
    fk_session_factory: sessionmaker[Session],
) -> None:
    with fk_session_factory() as seed_db:
        seed_slot(seed_db, 2)

    policy = SavedMedicationRetentionPolicy(retention_days_after_end=0)
    with fk_session_factory() as db:
        with count_statements(fk_engine) as statements:
            deleted_for_patient = policy.cleanup_expired_medications(db, PATIENT_HASH)
            deleted_for_everyone = policy.cleanup_expired_medications(db)
        remaining = db.query(_SavedMedication).count()

    assert (deleted_for_patient, deleted_for_everyone) == (0, 0)
    assert remaining == 5
    assert statements == []
