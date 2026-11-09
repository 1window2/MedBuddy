# File Name: test_request_database_gate.py
# Role: Verifies that PostgreSQL request admission queues on the event loop, follows the request
#   transaction, and never leaks a slot or an account turn on timeout, failure or cancellation.

import asyncio
import threading
from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi import HTTPException
from sqlalchemy import Engine, text
from sqlalchemy.orm import Session

from core.account_database_lock import ACCOUNT_BUSY_DETAIL
from core.account_operation_locks import AccountOperationLocks
from core.request_database_gate import (
    DatabaseSlots,
    RequestDatabaseGate,
    current_request_database_admission,
)
from core.request_database_work import run_request_database_work
from support.db import make_engine, make_session


# Function Name: engine
# Description:
# - Provides a file-backed SQLite engine so worker threads use their own connections.
# Parameters:
# - tmp_path (Path): Per-test directory.
# Returns:
# - Iterator yielding the engine; disposed afterwards.
@pytest.fixture
def engine(tmp_path: Path) -> Iterator[Engine]:
    database = make_engine(tmp_path)
    yield database
    database.dispose()


# Function Name: gate
# Description:
# - Builds a gate with short waits for the tests.
# Parameters:
# - slots (int): Slot capacity.
# - wait (float): Account and slot wait in seconds.
# Returns:
# - RequestDatabaseGate.
def gate(slots: int = 1, wait: float = 1.0) -> RequestDatabaseGate:
    return RequestDatabaseGate(slots=slots, account_wait_seconds=wait, slot_wait_seconds=wait)


# Function Name: open_transaction
# Description:
# - Starts a read transaction on the session, as registration does.
# Parameters:
# - db (Session): Request session.
# Returns:
# - None.
def open_transaction(db: Session) -> None:
    db.execute(text("SELECT 1"))


# Function Name: settle
# Description:
# - Lets callbacks scheduled from worker threads run on the event loop.
# Parameters:
# - None.
# Returns:
# - None.
async def settle() -> None:
    for _ in range(5):
        await asyncio.sleep(0)


# Function Name: test_slots_hand_releases_to_waiters_in_arrival_order
# Description:
# - Gives a freed slot to the oldest waiter and never lets a newcomer jump the queue.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_slots_hand_releases_to_waiters_in_arrival_order() -> None:
    slots = DatabaseSlots(1)
    await slots.acquire(timeout=1)
    order: list[str] = []

    # Function Name: waiter
    # Description:
    # - Records its name once it owns a slot, then gives the slot back.
    # Parameters:
    # - name (str): Waiter name.
    # Returns:
    # - None.
    async def waiter(name: str) -> None:
        await slots.acquire(timeout=1)
        order.append(name)
        slots.release()

    first = asyncio.create_task(waiter("first"))
    await settle()
    second = asyncio.create_task(waiter("second"))
    await settle()
    assert order == []
    slots.release()
    await asyncio.gather(first, second)
    assert order == ["first", "second"]
    assert slots.available == 1


# Function Name: test_slot_released_from_a_worker_thread_wakes_the_waiter
# Description:
# - Accepts a release from a worker thread, as when a transaction ends inside an endpoint.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_slot_released_from_a_worker_thread_wakes_the_waiter() -> None:
    slots = DatabaseSlots(1)
    await slots.acquire(timeout=1)
    waiter = asyncio.create_task(slots.acquire(timeout=1))
    await settle()
    thread = threading.Thread(target=slots.release)
    thread.start()
    thread.join()
    await waiter
    assert slots.available == 0
    slots.release()
    assert slots.available == 1


# Function Name: test_slot_waiters_that_give_up_take_no_slot
# Description:
# - A timed-out waiter, a cancelled waiter and a waiter cancelled right after it was handed a
#   slot all leave every slot free.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_slot_waiters_that_give_up_take_no_slot() -> None:
    slots = DatabaseSlots(1)
    await slots.acquire(timeout=1)
    with pytest.raises(TimeoutError):
        await slots.acquire(timeout=0.01)
    cancelled = asyncio.create_task(slots.acquire(timeout=1))
    await settle()
    cancelled.cancel()
    with pytest.raises(asyncio.CancelledError):
        await cancelled
    handed_over = asyncio.create_task(slots.acquire(timeout=1))
    await settle()
    slots.release()
    handed_over.cancel()
    with pytest.raises(asyncio.CancelledError):
        await handed_over
    await settle()
    assert slots.available == 1


# Function Name: test_account_acquire_releases_once_and_forgets_the_account
# Description:
# - The explicit release frees the account once and keeps no idle account identity.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_account_acquire_releases_once_and_forgets_the_account() -> None:
    locks = AccountOperationLocks()
    release = await locks.acquire("account", timeout=1)
    contender = asyncio.create_task(locks.acquire("account", timeout=1))
    await settle()
    assert not contender.done()
    release()
    release()
    second_release = await contender
    assert locks.active_scope_count == 1
    second_release()
    assert locks.active_scope_count == 0
    with pytest.raises(TimeoutError):
        await locks.acquire("account", timeout=0)
    assert locks.active_scope_count == 0


# Function Name: test_admission_is_given_back_after_work_that_leaves_no_transaction
# Description:
# - Holds the slot and account turn while the request transaction is open, and gives both back
#   after the work that committed, even though the request has not finished yet.
# Parameters:
# - engine (Engine): File-backed test engine.
# Returns:
# - None.
@pytest.mark.anyio
async def test_admission_is_given_back_after_work_that_leaves_no_transaction(
    engine: Engine,
) -> None:
    request_gate = gate()
    db = make_session(engine)
    try:
        async with request_gate.admit(db, "account") as admission:
            await run_request_database_work(open_transaction, db)
            assert admission.held
            assert request_gate.slots.available == 0
            await run_request_database_work(db.commit)
            await settle()
            assert not admission.held
            assert request_gate.slots.available == 1
            assert request_gate.accounts.active_scope_count == 0
    finally:
        db.close()


# Function Name: test_same_account_waits_only_while_the_first_transaction_is_open
# Description:
# - A second request of the account is admitted as soon as the first one's transaction ends,
#   as with the PostgreSQL transaction lock, not when the first request finishes.
# Parameters:
# - engine (Engine): File-backed test engine.
# Returns:
# - None.
@pytest.mark.anyio
async def test_same_account_waits_only_while_the_first_transaction_is_open(engine: Engine) -> None:
    request_gate = gate(slots=2)
    first_db, second_db = make_session(engine), make_session(engine)
    second_admitted = asyncio.Event()

    # Function Name: second_request
    # Description:
    # - Marks its admission and keeps the request open until the test ends.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def second_request() -> None:
        async with request_gate.admit(second_db, "account"):
            second_admitted.set()

    try:
        async with request_gate.admit(first_db, "account"):
            await run_request_database_work(open_transaction, first_db)
            second = asyncio.create_task(second_request())
            await settle()
            assert not second_admitted.is_set()
            await run_request_database_work(first_db.rollback)
            await asyncio.wait_for(second_admitted.wait(), 1)
            await second
    finally:
        first_db.close()
        second_db.close()
    assert request_gate.slots.available == 2
    assert request_gate.accounts.active_scope_count == 0


# Function Name: test_queued_requests_of_one_account_hold_no_slot
# Description:
# - Requests waiting for their own account's turn leave the slots to other accounts.
# Parameters:
# - engine (Engine): File-backed test engine.
# Returns:
# - None.
@pytest.mark.anyio
async def test_queued_requests_of_one_account_hold_no_slot(engine: Engine) -> None:
    request_gate = gate(slots=2)
    sessions = [make_session(engine) for _ in range(4)]

    # Function Name: queued_request
    # Description:
    # - Waits for admission of the busy account, then ends at once.
    # Parameters:
    # - db (Session): Request session.
    # Returns:
    # - None.
    async def queued_request(db: Session) -> None:
        async with request_gate.admit(db, "busy-account"):
            pass

    try:
        async with request_gate.admit(sessions[0], "busy-account"):
            await run_request_database_work(open_transaction, sessions[0])
            queued = [asyncio.create_task(queued_request(db)) for db in sessions[1:3]]
            await settle()
            assert request_gate.slots.available == 1
            async with request_gate.admit(sessions[3], "other-account") as other:
                assert other.held
            await run_request_database_work(sessions[0].rollback)
            await asyncio.gather(*queued)
    finally:
        for db in sessions:
            db.close()
    assert request_gate.slots.available == 2
    assert request_gate.accounts.active_scope_count == 0


# Function Name: test_later_database_work_is_admitted_again_and_given_back_when_idle
# Description:
# - Database work after the first transaction ended waits for admission again and gives it
#   back once it leaves no transaction open.
# Parameters:
# - engine (Engine): File-backed test engine.
# Returns:
# - None.
@pytest.mark.anyio
async def test_later_database_work_is_admitted_again_and_given_back_when_idle(engine: Engine) -> None:
    request_gate = gate()
    db = make_session(engine)
    observed: list[tuple[bool, int]] = []

    # Function Name: read_and_commit
    # Description:
    # - Records the admission state seen inside the worker thread, then commits.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def read_and_commit() -> None:
        admission = current_request_database_admission()
        observed.append((admission is not None and admission.held, request_gate.slots.available))
        db.execute(text("SELECT 1"))
        db.commit()

    try:
        async with request_gate.admit(db, "account") as admission:
            await run_request_database_work(db.commit)
            await settle()
            assert not admission.held
            await run_request_database_work(read_and_commit)
            await settle()
            assert observed == [(True, 0)]
            assert not admission.held
            assert request_gate.slots.available == 1
    finally:
        db.close()


# Function Name: test_work_that_reads_after_its_commit_keeps_the_admission
# Description:
# - Work that commits and then reads again keeps its connection, so it keeps its admission and
#   its next step runs at once instead of waiting for a slot while holding that connection.
# Parameters:
# - engine (Engine): File-backed test engine.
# Returns:
# - None.
@pytest.mark.anyio
async def test_work_that_reads_after_its_commit_keeps_the_admission(engine: Engine) -> None:
    request_gate = gate(slots=1, wait=0.5)
    db, waiting_db = make_session(engine), make_session(engine)
    waiting_admitted = asyncio.Event()

    # Function Name: commit_then_read
    # Description:
    # - Commits and reads again, as a refresh after commit does.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def commit_then_read() -> None:
        db.execute(text("SELECT 1"))
        db.commit()
        db.execute(text("SELECT 1"))

    # Function Name: waiting_request
    # Description:
    # - Another account's request queued for the only slot.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def waiting_request() -> None:
        async with request_gate.admit(waiting_db, "other-account"):
            waiting_admitted.set()

    try:
        async with request_gate.admit(db, "account") as admission:
            await run_request_database_work(commit_then_read)
            assert admission.held
            waiting = asyncio.create_task(waiting_request())
            await settle()
            async with asyncio.timeout(0.2):
                await run_request_database_work(open_transaction, db)
            assert not waiting_admitted.is_set()
            await run_request_database_work(db.commit)
            await asyncio.wait_for(waiting_admitted.wait(), 1)
            await waiting
    finally:
        db.close()
        waiting_db.close()
    assert request_gate.slots.available == 1


# Function Name: test_synchronous_endpoint_keeps_the_admission_until_the_request_ends
# Description:
# - A commit inside a synchronous endpoint, which runs in one worker thread, does not give the
#   slot back; the endpoint may keep using its connection until the request ends.
# Parameters:
# - engine (Engine): File-backed test engine.
# Returns:
# - None.
@pytest.mark.anyio
async def test_synchronous_endpoint_keeps_the_admission_until_the_request_ends(engine: Engine) -> None:
    request_gate = gate()
    db = make_session(engine)

    # Function Name: endpoint
    # Description:
    # - Reads, commits and reads again in one thread.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def endpoint() -> None:
        db.execute(text("SELECT 1"))
        db.commit()
        db.execute(text("SELECT 1"))
        db.commit()

    try:
        async with request_gate.admit(db, "account") as admission:
            await run_request_database_work(open_transaction, db)
            await asyncio.to_thread(endpoint)
            assert admission.held
            assert request_gate.slots.available == 0
    finally:
        db.close()
    assert request_gate.slots.available == 1
    assert request_gate.accounts.active_scope_count == 0


# Function Name: test_session_holding_a_connection_is_not_queued
# Description:
# - Work of a request whose session already holds a connection (opened outside admitted work)
#   continues with it rather than waiting for a slot.
# Parameters:
# - engine (Engine): File-backed test engine.
# Returns:
# - None.
@pytest.mark.anyio
async def test_session_holding_a_connection_is_not_queued(engine: Engine) -> None:
    request_gate = gate(slots=1, wait=0.5)
    db, holder_db = make_session(engine), make_session(engine)
    try:
        async with request_gate.admit(db, "account") as admission:
            await run_request_database_work(db.commit)
            async with request_gate.admit(holder_db, "other-account"):
                await run_request_database_work(open_transaction, holder_db)
                await asyncio.to_thread(open_transaction, db)
                async with asyncio.timeout(0.2):
                    await run_request_database_work(open_transaction, db)
                assert not admission.held
    finally:
        db.close()
        holder_db.close()
    assert request_gate.slots.available == 1


# Function Name: test_closing_does_not_queue_behind_an_outer_admission
# Description:
# - Ending a request closes its session without waiting for any admission, even when the
#   context still carries another request's admission that holds nothing.
# Parameters:
# - engine (Engine): File-backed test engine.
# Returns:
# - None.
@pytest.mark.anyio
async def test_closing_does_not_queue_behind_an_outer_admission(engine: Engine) -> None:
    request_gate = gate(slots=1, wait=0.5)
    outer_db, inner_db = make_session(engine), make_session(engine)
    try:
        async with request_gate.admit(outer_db, "outer-account"):
            await run_request_database_work(outer_db.commit)
            async with asyncio.timeout(0.2):
                async with request_gate.admit(inner_db, "inner-account"):
                    await run_request_database_work(open_transaction, inner_db)
            assert not inner_db.in_transaction()
    finally:
        outer_db.close()
        inner_db.close()
    assert request_gate.slots.available == 1
    assert request_gate.accounts.active_scope_count == 0


# Function Name: test_admission_timeouts_answer_busy_and_leak_nothing
# Description:
# - A request that cannot get its account turn or a slot in time gets the retryable 503 used
#   for busy accounts, and neither wait leaves anything held.
# Parameters:
# - engine (Engine): File-backed test engine.
# Returns:
# - None.
@pytest.mark.anyio
async def test_admission_timeouts_answer_busy_and_leak_nothing(engine: Engine) -> None:
    request_gate = gate(slots=1, wait=0.05)
    holder_db, same_db, other_db = (make_session(engine) for _ in range(3))
    try:
        async with request_gate.admit(holder_db, "account"):
            await run_request_database_work(open_transaction, holder_db)
            for db, owner in ((same_db, "account"), (other_db, "other-account")):
                with pytest.raises(HTTPException) as busy:
                    async with request_gate.admit(db, owner):
                        pass
                assert busy.value.status_code == 503
                assert busy.value.detail == ACCOUNT_BUSY_DETAIL
                assert busy.value.headers == {"Retry-After": "5"}
            assert request_gate.accounts.active_scope_count == 1
    finally:
        for db in (holder_db, same_db, other_db):
            db.close()
    assert request_gate.slots.available == 1
    assert request_gate.accounts.active_scope_count == 0


# Function Name: test_cancelled_admission_wait_leaks_nothing
# Description:
# - A request cancelled while queued (client gone) leaves no slot or account turn behind.
# Parameters:
# - engine (Engine): File-backed test engine.
# Returns:
# - None.
@pytest.mark.anyio
async def test_cancelled_admission_wait_leaks_nothing(engine: Engine) -> None:
    request_gate = gate(slots=1)
    holder_db, waiting_db = make_session(engine), make_session(engine)

    # Function Name: waiting_request
    # Description:
    # - Waits for admission behind the holder.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def waiting_request() -> None:
        async with request_gate.admit(waiting_db, "other-account"):
            pass

    try:
        async with request_gate.admit(holder_db, "account"):
            await run_request_database_work(open_transaction, holder_db)
            waiting = asyncio.create_task(waiting_request())
            await settle()
            waiting.cancel()
            with pytest.raises(asyncio.CancelledError):
                await waiting
    finally:
        holder_db.close()
        waiting_db.close()
    assert request_gate.slots.available == 1
    assert request_gate.accounts.active_scope_count == 0


# Function Name: test_finished_request_closes_its_transaction_before_giving_back
# Description:
# - Ending the request closes an open transaction first, stops following the session and
#   admits no later work of the finished request.
# Parameters:
# - engine (Engine): File-backed test engine.
# Returns:
# - None.
@pytest.mark.anyio
async def test_finished_request_closes_its_transaction_before_giving_back(engine: Engine) -> None:
    request_gate = gate()
    db = make_session(engine)
    try:
        async with request_gate.admit(db, "account") as admission:
            await run_request_database_work(open_transaction, db)
        assert not db.in_transaction()
        assert not admission.held
        assert current_request_database_admission() is None
        await admission.ensure_admitted()
        assert not admission.held
        db.execute(text("SELECT 1"))
        db.commit()
        assert request_gate.slots.available == 1
        assert request_gate.accounts.active_scope_count == 0
    finally:
        db.close()


# Function Name: test_failed_request_gives_everything_back
# Description:
# - An endpoint failure with an open transaction still closes it and frees the slot and turn.
# Parameters:
# - engine (Engine): File-backed test engine.
# Returns:
# - None.
@pytest.mark.anyio
async def test_failed_request_gives_everything_back(engine: Engine) -> None:
    request_gate = gate()
    db = make_session(engine)
    try:
        with pytest.raises(RuntimeError):
            async with request_gate.admit(db, "account"):
                await run_request_database_work(open_transaction, db)
                raise RuntimeError("endpoint failed")
        assert not db.in_transaction()
    finally:
        db.close()
    assert request_gate.slots.available == 1
    assert request_gate.accounts.active_scope_count == 0
