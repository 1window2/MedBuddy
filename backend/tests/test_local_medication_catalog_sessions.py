# File Name: test_local_medication_catalog_sessions.py
# Role: Verifies detached approval-summary persistence, source identity and worker/session isolation.

import asyncio
import json
import logging
import os
import threading
from collections.abc import Generator
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest.mock import AsyncMock, Mock

import pytest
from sqlalchemy import create_engine, event, inspect
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from controls.check_medication_detail_control import CheckMedicationDetail
from entities.medication_detail_entity import (
    MedicationDetail,
    _DrugApprovalInfo,
    _DrugBasicInfo,
)
from services.local_medication_catalog import LocalMedicationCatalog


PRODUCT_NAME = "테스트정100mg"
PRODUCT_CODE = "200000001"


# Function Name: _approval_record
# Description:
# - Creates a synthetic approval product without any existing generated guidance.
# Parameters:
# - None.
# Returns:
# - Public-document ORM record ready to insert into the isolated test catalog.
def _approval_record() -> _DrugApprovalInfo:
    return _DrugApprovalInfo(
        item_seq=PRODUCT_CODE,
        item_name=PRODUCT_NAME,
        normalized_item_name=PRODUCT_NAME.lower(),
        entp_name="Synthetic Manufacturer",
        efficacy_doc="synthetic effect document",
        use_method_doc="synthetic usage document",
        warning_doc="synthetic warning document",
        raw_json=json.dumps({"ITEM_SEQ": PRODUCT_CODE, "ITEM_NAME": PRODUCT_NAME}),
    )


# Function Name: _summarize
# Description:
# - Returns deterministic guidance while preserving the approval product identity.
# Parameters:
# - drug_name (str): Synthetic search term; never sent to an external service.
# - raw_item (dict[str, Any]): Normalized approval documents received by the summary boundary.
# Returns:
# - Synthetic medication guidance for the exact catalog product.
async def _summarize(drug_name: str, raw_item: dict[str, Any]) -> MedicationDetail:
    return MedicationDetail(
        item_seq=raw_item["ITEM_SEQ"],
        item_name=raw_item["ITEM_NAME"],
        efficacy="generated effect",
        usage_method="generated usage",
        warning="generated warning",
        ai_guide="generated guide",
    )


# Function Name: catalog_engine
# Description:
# - Seeds a file-backed SQLite catalog shared by independently created worker connections.
# Parameters:
# - tmp_path (Path): Pytest-owned temporary directory containing only synthetic data.
# Returns:
# - Engine with two catalog tables; disposed after each test.
@pytest.fixture
def catalog_engine(tmp_path: Path) -> Generator[Engine, None, None]:
    engine = create_engine(
        f"sqlite:///{tmp_path / 'catalog.sqlite'}",
        connect_args={"check_same_thread": False},
    )
    _DrugBasicInfo.__table__.create(engine)
    _DrugApprovalInfo.__table__.create(engine)
    with Session(engine) as writer:
        writer.add(_approval_record())
        writer.commit()
    try:
        yield engine
    finally:
        engine.dispose()


# Function Name: test_detached_approval_summary_is_persisted_and_reused
# Description:
# - Persists generated fields from closed read-worker snapshots and reuses them without a second AI call.
# Parameters:
# - catalog_engine (Engine): File-backed synthetic catalog.
# Returns:
# - None; assertions verify identity, persisted guidance and no borrowed request transaction.
def test_detached_approval_summary_is_persisted_and_reused(catalog_engine: Engine) -> None:
    generator = SimpleNamespace(summarize_advanced_item=AsyncMock(side_effect=_summarize))
    with Session(catalog_engine) as request_db:
        catalog = LocalMedicationCatalog(request_db, generator)

        # Function Name: scenario
        # Description: Checks detached read results, then generates and reuses one persisted summary.
        # Parameters: None.
        # Returns: None; assertions verify both generated and cached responses.
        async def scenario() -> None:
            basic, approval = await catalog._search_catalog(PRODUCT_NAME)
            assert basic == []
            assert len(approval) == 1 and inspect(approval[0]).detached
            first = await catalog.fetch_drug_info(PRODUCT_NAME)
            second = await catalog.fetch_drug_info(PRODUCT_NAME)
            assert first[0].item_seq == second[0].item_seq == PRODUCT_CODE
            assert first[0].manufacturer == "Synthetic Manufacturer"
            assert "저장된 AI 요약" in second[0].source

        asyncio.run(scenario())
        assert not request_db.in_transaction()
    generator.summarize_advanced_item.assert_awaited_once()
    with Session(catalog_engine) as reader:
        stored = reader.query(_DrugApprovalInfo).one()
        assert (stored.summary_efficacy, stored.summary_use_method) == (
            "generated effect", "generated usage",
        )
        assert (stored.summary_warning_message, stored.ai_guide) == (
            "generated warning", "generated guide",
        )


# Function Name: test_control_does_not_reuse_closed_request_session_after_summary_wait
# Description:
# - Closes the borrowed session during the LLM wait and still returns an exact-product detail through the control.
# Parameters:
# - catalog_engine (Engine): File-backed synthetic catalog.
# - monkeypatch (pytest.MonkeyPatch): Installs request-session access traps after composition.
# Returns:
# - None; failures identify worker access to the closed borrowed session.
def test_control_does_not_reuse_closed_request_session_after_summary_wait(
    catalog_engine: Engine,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    with Session(catalog_engine) as request_db:
        # Function Name: scenario
        # Description: Suspends summarization, closes the request session and resumes the isolated write.
        # Parameters: None.
        # Returns: None; checks authoritative API identity and persistence after request closure.
        async def scenario() -> None:
            started, release = asyncio.Event(), asyncio.Event()

            # Function Name: paused_summary
            # Description: Marks the LLM phase and waits until the request session is closed.
            # Parameters: drug_name (str), raw_item (dict[str, Any]): Synthetic summary inputs.
            # Returns: Synthetic guidance after the test releases the wait.
            async def paused_summary(drug_name: str, raw_item: dict[str, Any]) -> MedicationDetail:
                started.set()
                await release.wait()
                return await _summarize(drug_name, raw_item)

            generator = SimpleNamespace(summarize_advanced_item=AsyncMock(side_effect=paused_summary))
            catalog = LocalMedicationCatalog(request_db, generator)
            trap = Mock(side_effect=AssertionError("borrowed request-session operation"))
            for operation in ("get_bind", "query", "commit", "rollback"):
                monkeypatch.setattr(request_db, operation, trap)
            control = CheckMedicationDetail(
                db=request_db,
                local_medication_catalog=catalog,
                summary_generator=generator,
                medication_cache=SimpleNamespace(get=AsyncMock(return_value=None), set=AsyncMock()),
                public_drug_small_api=SimpleNamespace(searchMedication=AsyncMock(return_value=[])),
                public_drug_large_api=SimpleNamespace(searchMedication=AsyncMock(return_value=[])),
                pill_image_api=SimpleNamespace(searchMedicationImage=AsyncMock(return_value="")),
            )
            lookup = asyncio.create_task(control.requestMedicationDetail(PRODUCT_NAME))
            await asyncio.wait_for(started.wait(), 2)
            request_db.close()
            release.set()
            response = await asyncio.wait_for(lookup, 2)
            assert response.success and not response.requires_confirmation
            assert response.data[0].item_seq == PRODUCT_CODE
            trap.assert_not_called()

        asyncio.run(scenario())
    with Session(catalog_engine) as reader:
        assert reader.query(_DrugApprovalInfo).one().summary_efficacy == "generated effect"


# Function Name: test_connection_bound_request_is_not_retained_by_workers
# Description:
# - Composes from a request Connection, closes it and verifies workers use independent Engine connections.
# Parameters:
# - catalog_engine (Engine): File-backed synthetic catalog.
# Returns:
# - None; assertions fail if a closed request Connection reaches read or write workers.
def test_connection_bound_request_is_not_retained_by_workers(catalog_engine: Engine) -> None:
    generator = SimpleNamespace(summarize_advanced_item=AsyncMock(side_effect=_summarize))
    with catalog_engine.connect() as connection:
        with Session(bind=connection) as request_db:
            catalog = LocalMedicationCatalog(request_db, generator)
    details = asyncio.run(catalog.fetch_drug_info(PRODUCT_NAME))
    assert details[0].item_seq == PRODUCT_CODE
    with Session(catalog_engine) as reader:
        assert reader.query(_DrugApprovalInfo).one().summary_efficacy == "generated effect"


# Function Name: test_summary_is_not_written_over_changed_catalog_documents
# Description:
# - Changes the authoritative product documents during the LLM wait and rejects stale guidance caching.
# Parameters:
# - catalog_engine (Engine): File-backed synthetic catalog.
# - changed_field (str | None): Product/source column replaced, or None to delete the row during generation.
# Returns:
# - None; current request guidance remains available, but deleted/refreshed records receive no stale cache fields.
@pytest.mark.parametrize("changed_field", [
    "item_seq", "item_name", "entp_name", "efficacy_doc", "use_method_doc", "warning_doc", "raw_json", None,
])
def test_summary_is_not_written_over_changed_catalog_documents(
    catalog_engine: Engine,
    changed_field: str | None,
) -> None:
    # Function Name: change_before_summary
    # Description: Refreshes one authoritative field before completing the stale generated summary.
    # Parameters: drug_name (str), raw_item (dict[str, Any]): Synthetic summary inputs.
    # Returns: Guidance for the original snapshot without persisting it onto the refreshed record.
    async def change_before_summary(drug_name: str, raw_item: dict[str, Any]) -> MedicationDetail:
        with Session(catalog_engine) as writer:
            if changed_field is None:
                writer.query(_DrugApprovalInfo).delete()
            else:
                writer.query(_DrugApprovalInfo).update({changed_field: "refreshed value"})
            writer.commit()
        return await _summarize(drug_name, raw_item)

    generator = SimpleNamespace(summarize_advanced_item=AsyncMock(side_effect=change_before_summary))
    with Session(catalog_engine) as request_db:
        details = asyncio.run(LocalMedicationCatalog(request_db, generator).fetch_drug_info(PRODUCT_NAME))
    assert details[0].efficacy == "generated effect"
    with Session(catalog_engine) as reader:
        stored = reader.query(_DrugApprovalInfo).one_or_none()
        if changed_field is None:
            assert stored is None
        else:
            assert stored is not None and stored.summary_efficacy is None


# Function Name: test_summary_cache_failure_keeps_guidance_and_sanitizes_logs
# Description:
# - Rejects cache UPDATE and verifies the transaction is rolled back without exposing payloads or failing guidance.
# Parameters:
# - catalog_engine (Engine): File-backed synthetic catalog.
# - caplog (pytest.LogCaptureFixture): Captured catalog warning messages.
# Returns:
# - None; generated guidance survives and failed cache fields remain empty.
def test_summary_cache_failure_keeps_guidance_and_sanitizes_logs(
    catalog_engine: Engine,
    caplog: pytest.LogCaptureFixture,
) -> None:
    # Function Name: reject_summary_update
    # Description: Simulates a database failure containing text that must never appear in logs.
    # Parameters: conn, cursor, statement, parameters, context, executemany: SQLAlchemy execution event inputs.
    # Returns: None; raises only for the isolated summary-cache UPDATE.
    def reject_summary_update(
        conn: Any, cursor: Any, statement: str, parameters: Any, context: Any, executemany: bool,
    ) -> None:
        if statement.lstrip().upper().startswith("UPDATE"):
            raise RuntimeError("sensitive-patient-or-OCR-payload")

    event.listen(catalog_engine, "before_cursor_execute", reject_summary_update)
    try:
        generator = SimpleNamespace(summarize_advanced_item=AsyncMock(side_effect=_summarize))
        with Session(catalog_engine) as request_db:
            with caplog.at_level(logging.WARNING, logger="services.local_medication_catalog"):
                details = asyncio.run(LocalMedicationCatalog(request_db, generator).fetch_drug_info(PRODUCT_NAME))
        assert details[0].efficacy == "generated effect"
        assert "RuntimeError" in caplog.text
        assert "sensitive-patient-or-OCR-payload" not in caplog.text
        with Session(catalog_engine) as reader:
            assert reader.query(_DrugApprovalInfo).one().summary_efficacy is None
    finally:
        event.remove(catalog_engine, "before_cursor_execute", reject_summary_update)


# Function Name: test_summary_write_runs_off_loop_and_keeps_request_session_unused
# Description:
# - Blocks a real cache UPDATE in a worker and confirms the event loop and request session remain independent.
# Parameters:
# - catalog_engine (Engine): File-backed synthetic catalog.
# Returns:
# - None; verifies worker thread ownership, response completion and no request transaction.
def test_summary_write_runs_off_loop_and_keeps_request_session_unused(catalog_engine: Engine) -> None:
    entered, release = threading.Event(), threading.Event()
    worker_threads: list[int] = []

    # Function Name: hold_summary_update
    # Description: Holds worker persistence until an independent event-loop action releases it.
    # Parameters: conn, cursor, statement, parameters, context, executemany: SQLAlchemy execution event inputs.
    # Returns: None; the bounded wait fails loudly if the event loop cannot continue.
    def hold_summary_update(
        conn: Any, cursor: Any, statement: str, parameters: Any, context: Any, executemany: bool,
    ) -> None:
        if statement.lstrip().upper().startswith("UPDATE"):
            worker_threads.append(threading.get_ident())
            entered.set()
            assert release.wait(2), "event loop did not release worker persistence"

    event.listen(catalog_engine, "before_cursor_execute", hold_summary_update)
    try:
        generator = SimpleNamespace(summarize_advanced_item=AsyncMock(side_effect=_summarize))
        with Session(catalog_engine) as request_db:
            catalog = LocalMedicationCatalog(request_db, generator)

            # Function Name: scenario
            # Description: Keeps running on-loop while persistence is blocked outside it.
            # Parameters: None.
            # Returns: None; the worker must finish only after this coroutine releases it.
            async def scenario() -> None:
                lookup = asyncio.create_task(catalog.fetch_drug_info(PRODUCT_NAME))
                assert await asyncio.wait_for(asyncio.to_thread(entered.wait, 2), 3)
                assert len(worker_threads) == 1
                assert worker_threads[0] != threading.get_ident()
                assert not request_db.in_transaction()
                assert not lookup.done()
                release.set()
                assert (await asyncio.wait_for(lookup, 2))[0].item_seq == PRODUCT_CODE

            asyncio.run(scenario())
    finally:
        release.set()
        event.remove(catalog_engine, "before_cursor_execute", hold_summary_update)


# Function Name: test_cancelled_lookup_closes_its_worker_without_reusing_request_session
# Description:
# - Cancels a lookup during a blocked isolated UPDATE, then closes the request session before the worker completes.
# Parameters:
# - catalog_engine (Engine): File-backed synthetic catalog.
# - monkeypatch (pytest.MonkeyPatch): Rejects all borrowed-session database operations after composition.
# Returns:
# - None; cancellation stays visible and the independent worker connection returns to the pool.
def test_cancelled_lookup_closes_its_worker_without_reusing_request_session(
    catalog_engine: Engine,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    entered, release, returned = threading.Event(), threading.Event(), threading.Event()
    worker_threads: list[int] = []

    # Function Name: hold_summary_update
    # Description: Holds the owned write worker so cancellation and request cleanup happen before its completion.
    # Parameters: conn, cursor, statement, parameters, context, executemany: SQLAlchemy execution event inputs.
    # Returns: None; bounded waiting prevents a cancellation failure from hanging the suite.
    def hold_summary_update(
        conn: Any, cursor: Any, statement: str, parameters: Any, context: Any, executemany: bool,
    ) -> None:
        if statement.lstrip().upper().startswith("UPDATE"):
            worker_threads.append(threading.get_ident())
            entered.set()
            assert release.wait(3), "cancelled lookup did not release its independent worker"

    # Function Name: observe_worker_checkin
    # Description: Confirms the write worker's connection is returned after transaction and session cleanup.
    # Parameters: dbapi_connection, connection_record (Any): SQLAlchemy pool check-in event values.
    # Returns: None; records only the known write-worker thread, never earlier read-worker cleanup.
    def observe_worker_checkin(dbapi_connection: Any, connection_record: Any) -> None:
        if worker_threads and threading.get_ident() == worker_threads[0]:
            returned.set()

    event.listen(catalog_engine, "before_cursor_execute", hold_summary_update)
    event.listen(catalog_engine, "checkin", observe_worker_checkin)
    try:
        generator = SimpleNamespace(summarize_advanced_item=AsyncMock(side_effect=_summarize))
        with Session(catalog_engine) as request_db:
            catalog = LocalMedicationCatalog(request_db, generator)
            trap = Mock(side_effect=AssertionError("borrowed request-session operation"))
            for operation in ("get_bind", "query", "commit", "rollback"):
                monkeypatch.setattr(request_db, operation, trap)

            # Function Name: scenario
            # Description: Cancels while the worker is blocked and releases it only after request cleanup.
            # Parameters: None.
            # Returns: None; verifies cancellation ordering and eventual worker-owned cleanup.
            async def scenario() -> None:
                lookup = asyncio.create_task(catalog.fetch_drug_info(PRODUCT_NAME))
                assert await asyncio.wait_for(asyncio.to_thread(entered.wait, 2), 3)
                lookup.cancel()
                with pytest.raises(asyncio.CancelledError):
                    await lookup
                request_db.close()
                assert not returned.is_set()
                release.set()
                assert await asyncio.wait_for(asyncio.to_thread(returned.wait, 2), 3)
                trap.assert_not_called()

            asyncio.run(scenario())
        with Session(catalog_engine) as reader:
            assert reader.query(_DrugApprovalInfo).one().summary_efficacy == "generated effect"
    finally:
        release.set()
        event.remove(catalog_engine, "before_cursor_execute", hold_summary_update)
        event.remove(catalog_engine, "checkin", observe_worker_checkin)


# Function Name: test_connection_local_memory_catalog_never_commits_request_session
# Description:
# - Retains the local in-memory read fallback while skipping unsafe optional summary persistence.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Rejects borrowed-session commits after synthetic data insertion.
# Returns:
# - None; guidance is returned without committing the caller's still-open read transaction.
def test_connection_local_memory_catalog_never_commits_request_session(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    engine = create_engine("sqlite:///:memory:")
    _DrugBasicInfo.__table__.create(engine)
    _DrugApprovalInfo.__table__.create(engine)
    try:
        with Session(engine) as request_db:
            request_db.add(_approval_record())
            request_db.commit()
            catalog = LocalMedicationCatalog(
                request_db,
                SimpleNamespace(summarize_advanced_item=AsyncMock(side_effect=_summarize)),
            )
            forbidden_commit = Mock(side_effect=AssertionError("borrowed session commit"))
            monkeypatch.setattr(request_db, "commit", forbidden_commit)
            details = asyncio.run(catalog.fetch_drug_info(PRODUCT_NAME))
            assert details[0].efficacy == "generated effect"
            assert request_db.in_transaction()
            assert request_db.query(_DrugApprovalInfo).one().summary_efficacy is None
            forbidden_commit.assert_not_called()
    finally:
        engine.dispose()
