# File Name: test_prescription_verifier_sessions.py
# Role: Verifies catalog-read workers never retain a borrowed prescription request Session or Connection.

import asyncio
import os
import threading
from collections.abc import Generator
from pathlib import Path
from typing import Any
from unittest.mock import Mock

import pytest
from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from entities.medication_detail_entity import _DrugApprovalInfo, _DrugBasicInfo
from services.prescription_medication_name_verifier import (
    MedicationNameVerification,
    PrescriptionMedicationNameVerifier,
)


PRODUCT_NAME = "SyntheticMedicine100mg"


# Function Name: catalog_engine
# Description:
# - Seeds a file-backed catalog visible to independently created worker connections.
# Parameters:
# - tmp_path (Path): Pytest-owned temporary directory containing only synthetic data.
# Returns:
# - Engine with the two medication catalogs; disposed after each test.
@pytest.fixture
def catalog_engine(tmp_path: Path) -> Generator[Engine, None, None]:
    engine = create_engine(
        f"sqlite:///{tmp_path / 'verifier.sqlite'}",
        connect_args={"check_same_thread": False},
    )
    _DrugBasicInfo.__table__.create(engine)
    _DrugApprovalInfo.__table__.create(engine)
    with Session(engine) as writer:
        writer.add(_DrugBasicInfo(
            item_seq="200000001",
            item_name=PRODUCT_NAME,
            normalized_item_name=PRODUCT_NAME.lower(),
            raw_json="{}",
        ))
        writer.commit()
    try:
        yield engine
    finally:
        engine.dispose()


# Function Name: test_connection_bound_request_can_close_before_worker_verification
# Description:
# - Captures an Engine-only worker factory from valid Connection-bound composition before that connection closes.
# Parameters:
# - catalog_engine (Engine): File-backed synthetic medication catalog.
# Returns:
# - None; a closed borrowed Connection must not prevent exact local name verification.
def test_connection_bound_request_can_close_before_worker_verification(catalog_engine: Engine) -> None:
    with catalog_engine.connect() as connection:
        with Session(bind=connection) as request_db:
            verifier = PrescriptionMedicationNameVerifier(request_db)
    results = asyncio.run(verifier.verify_many([PRODUCT_NAME], object(), "unused-model"))
    assert results == [MedicationNameVerification(
        raw_name=PRODUCT_NAME,
        canonical_name=PRODUCT_NAME,
        confidence=1.0,
        source="local_catalog_exact",
    )]


# Function Name: test_connection_bound_request_transaction_remains_owned_by_caller
# Description:
# - Keeps an uncommitted catalog edit inside the caller's transaction while worker verification reads only committed catalog data.
# Parameters:
# - catalog_engine (Engine): File-backed synthetic medication catalog.
# Returns:
# - None; independent verification never commits, rolls back or joins the borrowed request transaction.
def test_connection_bound_request_transaction_remains_owned_by_caller(catalog_engine: Engine) -> None:
    with catalog_engine.connect() as connection:
        with connection.begin() as caller_transaction:
            with Session(bind=connection) as request_db:
                pending = request_db.query(_DrugBasicInfo).one()
                pending.item_name = "UncommittedProduct100mg"
                request_db.flush()
                verifier = PrescriptionMedicationNameVerifier(request_db)
                results = asyncio.run(verifier.verify_many([PRODUCT_NAME], object(), "unused-model"))
                assert results[0].canonical_name == PRODUCT_NAME
                assert results[0].confidence == 1.0
                assert pending.item_name == "UncommittedProduct100mg"
                assert caller_transaction.is_active and request_db.in_transaction()
                caller_transaction.rollback()
    with Session(catalog_engine) as reader:
        assert reader.query(_DrugBasicInfo).one().item_name == PRODUCT_NAME


# Function Name: test_worker_reads_never_consult_request_session_after_composition
# Description:
# - Rejects borrowed-session lookup/query/transaction work and confirms real catalog SELECTs run off-loop.
# Parameters:
# - catalog_engine (Engine): File-backed synthetic catalog.
# - monkeypatch (pytest.MonkeyPatch): Installs traps only after verifier composition.
# Returns:
# - None; exact matching works without a request transaction or worker access to its Session.
def test_worker_reads_never_consult_request_session_after_composition(
    catalog_engine: Engine,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    read_threads: list[int] = []

    # Function Name: observe_catalog_read
    # Description: Records only catalog-query execution threads, never setup operations.
    # Parameters: conn, cursor, statement, parameters, context, executemany: SQLAlchemy execution event inputs.
    # Returns: None; appends one thread identity per SELECT.
    def observe_catalog_read(
        conn: Any, cursor: Any, statement: str, parameters: Any, context: Any, executemany: bool,
    ) -> None:
        if statement.lstrip().upper().startswith("SELECT"):
            read_threads.append(threading.get_ident())

    event.listen(catalog_engine, "before_cursor_execute", observe_catalog_read)
    try:
        with Session(catalog_engine) as request_db:
            verifier = PrescriptionMedicationNameVerifier(request_db)
            trap = Mock(side_effect=AssertionError("borrowed request-session operation"))
            for operation in ("get_bind", "query", "commit", "rollback"):
                monkeypatch.setattr(request_db, operation, trap)
            results = asyncio.run(verifier.verify_many([PRODUCT_NAME], object(), "unused-model"))
            assert results[0].canonical_name == PRODUCT_NAME
            assert not request_db.in_transaction()
            trap.assert_not_called()
        assert read_threads and all(t != threading.get_ident() for t in read_threads)
    finally:
        event.remove(catalog_engine, "before_cursor_execute", observe_catalog_read)


# Function Name: test_cancelled_queued_worker_survives_request_session_cleanup
# Description:
# - Cancels before worker database setup, closes the request and verifies only an independent worker session is later used.
# Parameters:
# - catalog_engine (Engine): File-backed synthetic catalog.
# - monkeypatch (pytest.MonkeyPatch): Installs a worker-start gate and borrowed-session traps.
# Returns:
# - None; original cancellation is preserved while the owned worker finishes and closes normally.
def test_cancelled_queued_worker_survives_request_session_cleanup(
    catalog_engine: Engine,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    entered, release, completed, returned = (
        threading.Event(), threading.Event(), threading.Event(), threading.Event()
    )
    worker_errors: list[BaseException] = []
    worker_threads: list[int] = []

    # Function Name: observe_worker_checkin
    # Description: Confirms the catalog worker returns its independent connection before signaling completion.
    # Parameters: dbapi_connection, connection_record (Any): SQLAlchemy pool check-in event values.
    # Returns: None; sets the completion evidence only for the gated worker thread.
    def observe_worker_checkin(dbapi_connection: Any, connection_record: Any) -> None:
        if worker_threads and threading.get_ident() == worker_threads[0]:
            returned.set()

    event.listen(catalog_engine, "checkin", observe_worker_checkin)
    try:
        with Session(catalog_engine) as request_db:
            verifier = PrescriptionMedicationNameVerifier(request_db)
            original_worker = verifier._prepare_verifications_with_isolated_session

            # Function Name: paused_worker
            # Description: Delays database/session setup until cancellation and request cleanup have completed.
            # Parameters: raw_names (list[str]): Synthetic OCR medication names.
            # Returns: Local verification DTOs and bounded fallback requests, exactly as the original worker.
            def paused_worker(raw_names: list[str]) -> Any:
                worker_threads.append(threading.get_ident())
                entered.set()
                try:
                    assert release.wait(3), "cancelled verifier did not release its independent worker"
                    return original_worker(raw_names)
                except BaseException as exc:
                    worker_errors.append(exc)
                    raise
                finally:
                    completed.set()

            monkeypatch.setattr(verifier, "_prepare_verifications_with_isolated_session", paused_worker)
            trap = Mock(side_effect=AssertionError("borrowed request-session operation after cleanup"))

            # Function Name: scenario
            # Description: Closes/traps the request after cancellation, then allows the owned worker to continue.
            # Parameters: None.
            # Returns: None; errors and missing connection cleanup fail the regression.
            async def scenario() -> None:
                pending = asyncio.create_task(verifier.verify_many([PRODUCT_NAME], object(), "unused-model"))
                assert await asyncio.wait_for(asyncio.to_thread(entered.wait, 2), 3)
                pending.cancel()
                with pytest.raises(asyncio.CancelledError):
                    await pending
                request_db.close()
                for operation in ("get_bind", "query", "commit", "rollback"):
                    monkeypatch.setattr(request_db, operation, trap)
                release.set()
                assert await asyncio.wait_for(asyncio.to_thread(completed.wait, 2), 3)
                assert returned.is_set()
                assert worker_errors == []
                trap.assert_not_called()

            asyncio.run(scenario())
    finally:
        release.set()
        event.remove(catalog_engine, "checkin", observe_worker_checkin)


# Function Name: test_catalog_worker_failure_closes_session_and_preserves_original_error
# Description:
# - Forces a SELECT failure and verifies owned connection cleanup without swallowing errors or using the request transaction.
# Parameters:
# - catalog_engine (Engine): File-backed synthetic catalog.
# Returns:
# - None; cache-verification database errors retain the established caller-visible failure contract.
def test_catalog_worker_failure_closes_session_and_preserves_original_error(catalog_engine: Engine) -> None:
    returned = threading.Event()
    failure = RuntimeError("synthetic catalog failure")

    # Function Name: reject_catalog_read
    # Description: Raises the selected synthetic failure before any catalog query can return.
    # Parameters: conn, cursor, statement, parameters, context, executemany: SQLAlchemy execution event inputs.
    # Returns: None; raises only for SELECT statements.
    def reject_catalog_read(
        conn: Any, cursor: Any, statement: str, parameters: Any, context: Any, executemany: bool,
    ) -> None:
        if statement.lstrip().upper().startswith("SELECT"):
            raise failure

    # Function Name: observe_checkin
    # Description: Records connection cleanup following the failed catalog worker.
    # Parameters: dbapi_connection, connection_record (Any): SQLAlchemy pool check-in event values.
    # Returns: None.
    def observe_checkin(dbapi_connection: Any, connection_record: Any) -> None:
        returned.set()

    event.listen(catalog_engine, "before_cursor_execute", reject_catalog_read)
    event.listen(catalog_engine, "checkin", observe_checkin)
    try:
        with Session(catalog_engine) as request_db:
            verifier = PrescriptionMedicationNameVerifier(request_db)
            with pytest.raises(RuntimeError) as result:
                asyncio.run(verifier.verify_many([PRODUCT_NAME], object(), "unused-model"))
            assert result.value is failure
            assert returned.is_set()
            assert not request_db.in_transaction()
    finally:
        event.remove(catalog_engine, "before_cursor_execute", reject_catalog_read)
        event.remove(catalog_engine, "checkin", observe_checkin)


# Function Name: test_connection_bound_memory_catalog_keeps_same_thread_read_fallback
# Description:
# - Keeps connection-local synthetic rows visible without dispatching their borrowed Connection to a worker.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Rejects any attempted isolated-worker dispatch.
# Returns:
# - None; matching succeeds on the caller thread and does not commit its transaction.
def test_connection_bound_memory_catalog_keeps_same_thread_read_fallback(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    engine = create_engine("sqlite:///:memory:")
    _DrugBasicInfo.__table__.create(engine)
    _DrugApprovalInfo.__table__.create(engine)
    try:
        with engine.connect() as connection:
            with Session(bind=connection) as request_db:
                request_db.add(_DrugBasicInfo(
                    item_seq="200000001", item_name=PRODUCT_NAME,
                    normalized_item_name=PRODUCT_NAME.lower(), raw_json="{}",
                ))
                request_db.flush()
                verifier = PrescriptionMedicationNameVerifier(request_db)
                forbidden_worker = Mock(side_effect=AssertionError("memory Connection dispatched to worker"))
                monkeypatch.setattr(verifier, "_prepare_verifications_with_isolated_session", forbidden_worker)
                results = asyncio.run(verifier.verify_many([PRODUCT_NAME], object(), "unused-model"))
                assert results[0].canonical_name == PRODUCT_NAME
                assert request_db.in_transaction()
                forbidden_worker.assert_not_called()
    finally:
        engine.dispose()
