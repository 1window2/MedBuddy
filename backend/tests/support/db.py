# File Name: db.py
# Role: Shared database helpers for NEW backend tests: an isolated SQLite engine that enforces
#   foreign keys like the application engine, sessions configured like SessionLocal, and seed
#   builders for the rows almost every test needs.
#
# Usage:
#   from support.db import make_engine, make_session, make_session_factory
#   from support.db import seed_account, seed_medication
#
#   engine = make_engine()            # in-memory, one shared connection, schema created
#   engine = make_engine(tmp_path)    # file under tmp_path, WAL, one connection per thread
#   db = make_session(engine)         # autoflush off, as in production
#   seed_account(db, "patient-a", "caregiver-a")
#   medication = seed_medication(db, patient_hash="patient-a", item_name="aspirin")
#   ...
#   db.close(); engine.dispose()      # the caller owns both
#
# pytest-style tests can request the fixtures `fk_engine`, `fk_session_factory` and `fk_db`
# from tests/conftest.py instead of calling make_engine / make_session themselves.
#
# Foreign keys are ON, so every row that references user_accounts needs its account first
# (registration creates it in production): call seed_account before adding such rows.
# Existing test files keep their own engines; do not migrate them as a side effect.

import importlib
import pkgutil
from pathlib import Path

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

import entities
from core.application_clock import application_today
from core.database import Base
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import _UserAccount

_TEST_DATABASE_FILE_NAME = "medbuddy-test.db"


# Function Name: _register_all_entities
# Description:
# - Imports every module of the entities package so Base.metadata holds all tables, whichever
#   entity modules the calling test file imported itself.
# Parameters:
# - None.
# Returns:
# - None.
def _register_all_entities() -> None:
    for module in pkgutil.iter_modules(entities.__path__):
        importlib.import_module(f"{entities.__name__}.{module.name}")


# Function Name: make_engine
# Description:
# - Builds an isolated SQLite engine with PRAGMA foreign_keys=ON on every connection, as
#   core/database.py does for the application engine, and creates the ORM schema on it.
# - Without tmp_path the database lives in memory behind one shared connection (StaticPool),
#   so every session and thread sees the same data.
# - With tmp_path the database is a file with WAL and the application's busy timeout; use it
#   when a test needs real concurrent connections, BEGIN IMMEDIATE or a second process.
# Parameters:
# - tmp_path (Path | None): Directory for a file-backed database, normally pytest's tmp_path.
# Returns:
# - Engine with the full schema; the caller disposes it.
def make_engine(tmp_path: Path | None = None) -> Engine:
    if tmp_path is None:
        engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
    else:
        database_path = Path(tmp_path) / _TEST_DATABASE_FILE_NAME
        engine = create_engine(
            f"sqlite:///{database_path.as_posix()}",
            connect_args={"check_same_thread": False, "timeout": 15},
        )

    # Function Name: _configure_sqlite_connection
    # Description:
    # - Applies the application's SQLite settings to each new connection of this engine.
    # Parameters:
    # - dbapi_connection (object): Raw DB-API connection from the connect event.
    # - _record (object): Pool record; unused.
    # Returns:
    # - None.
    @event.listens_for(engine, "connect")
    def _configure_sqlite_connection(dbapi_connection: object, _record: object) -> None:
        cursor = dbapi_connection.cursor()
        try:
            cursor.execute("PRAGMA foreign_keys=ON")
            if tmp_path is not None:
                cursor.execute("PRAGMA journal_mode=WAL")
                cursor.execute("PRAGMA busy_timeout=15000")
        finally:
            cursor.close()

    _register_all_entities()
    Base.metadata.create_all(bind=engine)
    return engine


# Function Name: make_session_factory
# Description:
# - Builds a session factory with the options of core.database.SessionLocal (no autocommit,
#   no autoflush), for controls and workers that take a factory.
# Parameters:
# - engine (Engine): Engine returned by make_engine.
# Returns:
# - sessionmaker bound to the engine.
def make_session_factory(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(autocommit=False, autoflush=False, bind=engine)


# Function Name: make_session
# Description:
# - Opens one session configured like a request session. Autoflush is off as in production,
#   so query-after-add in a test needs an explicit flush or commit.
# Parameters:
# - engine (Engine): Engine returned by make_engine.
# Returns:
# - New Session; the caller closes it.
def make_session(engine: Engine) -> Session:
    return make_session_factory(engine)()


# Function Name: seed_account
# Description:
# - Inserts the user_accounts row for each given hash that does not exist yet and commits,
#   so rows that reference the account pass the foreign-key check.
# Parameters:
# - db (Session): Session on a make_engine database.
# - *hashes (str): Patient or caregiver hashes that need an account.
# Returns:
# - None.
def seed_account(db: Session, *hashes: str) -> None:
    for user_hash in dict.fromkeys(hashes):
        if db.get(_UserAccount, user_hash) is None:
            db.add(_UserAccount(user_hash=user_hash))
    db.commit()


# Function Name: seed_medication
# Description:
# - Inserts one saved medication with complete default text fields and commits. The owner's
#   account is created first when it is missing. The defaults describe a course saved today,
#   three times a day for seven days, with no slot selection and no dose taken.
# Parameters:
# - db (Session): Session on a make_engine database.
# - **overrides (object): _SavedMedication column values that replace the defaults, for
#   example patient_hash, item_name, created_date, total_days or schedule_slot_keys.
# Returns:
# - The persisted _SavedMedication with its id loaded.
def seed_medication(db: Session, **overrides: object) -> _SavedMedication:
    values: dict[str, object] = {
        "patient_hash": "patient-a",
        "created_date": application_today(),
        "item_name": "test-tablet",
        "efficacy": "effect",
        "use_method": "usage",
        "warning_message": "warning",
        "dosage_per_time": "1 tablet",
        "daily_frequency": "3 times",
        "total_days": "7 days",
        "schedule_slot_keys": "[]",
        "medication_status": False,
        "ai_guide": "guide",
        "image_url": "https://nedrug.mfds.go.kr/medicine.jpg",
    }
    values.update(overrides)
    seed_account(db, str(values["patient_hash"]))
    medication = _SavedMedication(**values)
    db.add(medication)
    db.commit()
    db.refresh(medication)
    return medication
