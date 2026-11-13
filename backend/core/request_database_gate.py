# File Name: request_database_gate.py
# Role: Queues PostgreSQL request database work on the event loop so worker threads never wait for
#   an account turn or a pooled connection.

import asyncio
import logging
import threading
from collections import deque
from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager
from contextvars import ContextVar

from fastapi import HTTPException
from sqlalchemy.orm import Session

from core.account_database_lock import ACCOUNT_BUSY_DETAIL
from core.account_operation_locks import AccountOperationLocks

logger = logging.getLogger(__name__)

# 요청 하나의 DB 작업이 어느 입장권을 쓰는지 run_request_database_work가 찾을 수 있게 둔다.
_current_admission: ContextVar["RequestDatabaseAdmission | None"] = ContextVar(
    "request_database_admission", default=None,
)


# Class Name: DatabaseSlots
# Role: Counts the request transactions allowed to hold pooled connections at the same time.
# Responsibilities:
# - Let waiters queue on the event loop in arrival order, never in a worker thread.
# - Accept releases from any thread and hand a freed slot straight to the oldest waiter.
# Attributes:
# - _available (int): Free slots.
# - _waiters (deque[asyncio.Future[None]]): Waiters in arrival order; a popped waiter owns a slot.
# - _guard (threading.Lock): Protects the counter and the queue across threads.
class DatabaseSlots:
    # Function Name: __init__
    # Description:
    # - Creates a slot counter with every slot free.
    # Parameters:
    # - capacity (int): Number of slots; at least 1.
    # Returns:
    # - None; ValueError for a capacity below 1.
    def __init__(self, capacity: int) -> None:
        if capacity < 1:
            raise ValueError("Database slot capacity must be at least 1.")
        self.capacity = capacity
        self._available = capacity
        self._waiters: deque[asyncio.Future[None]] = deque()
        self._guard = threading.Lock()

    # Function Name: available
    # Description:
    # - Reports the free slots.
    # Parameters:
    # - None.
    # Returns:
    # - Number of free slots.
    @property
    def available(self) -> int:
        with self._guard:
            return self._available

    # Function Name: acquire
    # Description:
    # - Takes a free slot at once when nobody queues ahead, otherwise waits on the event loop.
    # Parameters:
    # - timeout (float): Maximum seconds to wait.
    # Returns:
    # - None once a slot is owned; TimeoutError or cancellation leaves no slot owned.
    async def acquire(self, *, timeout: float) -> None:
        with self._guard:
            if self._available > 0 and not self._waiters:
                self._available -= 1
                return
            if timeout <= 0:
                raise TimeoutError
            waiter = asyncio.get_running_loop().create_future()
            self._waiters.append(waiter)
        try:
            async with asyncio.timeout(timeout):
                await waiter
        except BaseException:
            # 꺼내진 대기자는 이미 자리를 넘겨받았으므로, 포기할 때 그 자리를 다시 돌려준다.
            with self._guard:
                still_waiting = waiter in self._waiters
                if still_waiting:
                    self._waiters.remove(waiter)
            if not still_waiting:
                self.release()
            raise

    # Function Name: release
    # Description:
    # - Hands one owned slot to the oldest live waiter, or frees it; safe from any thread.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def release(self) -> None:
        with self._guard:
            while self._waiters:
                waiter = self._waiters.popleft()
                try:
                    waiter.get_loop().call_soon_threadsafe(_grant, waiter)
                except RuntimeError:
                    # 이벤트 루프가 이미 닫힌 대기자에게는 넘기지 않는다.
                    continue
                return
            self._available += 1


# Function Name: _grant
# Description:
# - Wakes a waiter that was handed a slot; a waiter that has already given up returns it itself.
# Parameters:
# - waiter (asyncio.Future[None]): Popped waiter.
# Returns:
# - None.
def _grant(waiter: asyncio.Future[None]) -> None:
    if not waiter.done():
        waiter.set_result(None)


# Class Name: RequestDatabaseAdmission
# Role: Holds one request's account turn and database slot while its request session may hold a
#   pooled connection.
# Responsibilities:
# - Keep both through each unit of request database work (registration, a synchronous endpoint,
#   one run_request_database_work operation) and give them back after a unit that left no
#   transaction open, so external calls between units hold neither.
# - Take them again, turn first, before later work, but never while the session still holds a
#   connection, so a request never waits for a slot while it keeps one.
# Attributes:
# - _gate (RequestDatabaseGate): Gate that issued the admission.
# - _db (Session): Request session the admission follows.
# - _user_hash (str): Server-verified account of the request.
# - _release_turn (Callable[[], None] | None): Release of the held account turn.
# - _closed (bool): Whether the request has finished with the database.
# Note: Used only on the request's event loop.
class RequestDatabaseAdmission:
    # Function Name: __init__
    # Description:
    # - Prepares an admission that holds nothing yet.
    # Parameters:
    # - gate (RequestDatabaseGate): Issuing gate.
    # - db (Session): Request session.
    # - user_hash (str): Server-verified account of the request.
    # Returns:
    # - None.
    def __init__(self, gate: "RequestDatabaseGate", db: Session, user_hash: str) -> None:
        self._gate = gate
        self._db = db
        self._user_hash = user_hash
        self._release_turn: Callable[[], None] | None = None
        self._closed = False

    # Function Name: held
    # Description:
    # - Reports whether the account turn and a slot are held.
    # Parameters:
    # - None.
    # Returns:
    # - True while both are held.
    @property
    def held(self) -> bool:
        return self._release_turn is not None

    # Function Name: ensure_admitted
    # Description:
    # - Waits on the event loop for the account turn, then for a slot, unless both are held, the
    #   session still holds a connection, or the request has finished with the database.
    # Parameters:
    # - None.
    # Returns:
    # - None; HTTP 503 with Retry-After when either wait times out.
    async def ensure_admitted(self) -> None:
        # 연결을 쥔 채 자리를 기다리면 자리를 가진 요청과 서로 막힌다. 그 연결로 계속한다.
        if self._closed or self.held or self._db.in_transaction():
            return
        try:
            release_turn = await self._gate.accounts.acquire(
                self._user_hash, timeout=self._gate.account_wait_seconds,
            )
        except TimeoutError as exc:
            logger.warning("Request database admission timed out waiting for the account turn.")
            raise _busy() from exc
        try:
            await self._gate.slots.acquire(timeout=self._gate.slot_wait_seconds)
        except BaseException as exc:
            release_turn()
            if isinstance(exc, TimeoutError):
                logger.warning("Request database admission timed out waiting for a database slot.")
                raise _busy() from exc
            raise
        self._release_turn = release_turn

    # Function Name: release
    # Description:
    # - Gives back the slot and the account turn once.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def release(self) -> None:
        release_turn = self._release_turn
        self._release_turn = None
        if release_turn is None:
            return
        self._gate.slots.release()
        release_turn()

    # Function Name: release_if_idle
    # Description:
    # - Gives both back after a unit of database work that left no transaction open; the
    #   connection and the PostgreSQL account lock have gone back by then.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def release_if_idle(self) -> None:
        if not self._db.in_transaction():
            self.release()

    # Function Name: finish
    # Description:
    # - Stops later admissions and gives both back after the request session is closed.
    # Parameters:
    # - None.
    # Returns:
    # - None; session close errors propagate after both are given back.
    async def finish(self) -> None:
        # 순환 import를 피한다. 입장 없이, 요청 취소에도 정리를 끝까지 기다리는 경로로 닫는다.
        from core.request_database_work import drain_database_work

        self._closed = True
        try:
            if self._db.in_transaction():
                # 연결과 계정 잠금이 실제로 돌아간 뒤에 자리를 비운다.
                await drain_database_work(self._db.close)
        finally:
            self.release()


# Class Name: RequestDatabaseGate
# Role: Admits authenticated PostgreSQL requests to the database one account at a time and at
#   most `slots` requests at once.
# Responsibilities:
# - Keep waiting requests on the event loop so pooled-connection holders always find a worker thread.
# - Keep the account turn ahead of the slot so one account's queued requests never hold slots.
# Attributes:
# - accounts (AccountOperationLocks): Process-local account turns.
# - slots (DatabaseSlots): Request database slots.
# - account_wait_seconds (float): Longest wait for the account turn.
# - slot_wait_seconds (float): Longest wait for a slot.
# Note: PostgreSQL account locks stay in place behind the gate for other processes and services.
class RequestDatabaseGate:
    # Function Name: __init__
    # Description:
    # - Creates a gate with its own account turns and slots.
    # Parameters:
    # - slots (int): Request transactions allowed to hold connections at once.
    # - account_wait_seconds (float): Longest wait for the account turn.
    # - slot_wait_seconds (float): Longest wait for a slot.
    # Returns:
    # - None.
    def __init__(
        self,
        *,
        slots: int,
        account_wait_seconds: float,
        slot_wait_seconds: float,
    ) -> None:
        self.accounts = AccountOperationLocks()
        self.slots = DatabaseSlots(slots)
        self.account_wait_seconds = account_wait_seconds
        self.slot_wait_seconds = slot_wait_seconds

    # Function Name: admit
    # Description:
    # - Admits one request session for its registration and following work, and gives everything
    #   back when the request finishes, fails or is cancelled.
    # Parameters:
    # - db (Session): Fresh request session.
    # - user_hash (str): Server-verified account of the request.
    # Returns:
    # - Yields while the request may use the database; HTTP 503 when admission times out.
    @asynccontextmanager
    async def admit(self, db: Session, user_hash: str) -> AsyncIterator[RequestDatabaseAdmission]:
        admission = RequestDatabaseAdmission(self, db, user_hash)
        await admission.ensure_admitted()
        previous = _current_admission.set(admission)
        try:
            yield admission
        finally:
            try:
                _current_admission.reset(previous)
            except ValueError:
                # 다른 context에서 정리되면 되돌릴 값이 없다. 닫힌 입장권은 더 쓰이지 않는다.
                pass
            await admission.finish()


# Function Name: current_request_database_admission
# Description:
# - Returns the admission of the request running in this context, if it has one.
# Parameters:
# - None.
# Returns:
# - RequestDatabaseAdmission or None outside admitted requests.
def current_request_database_admission() -> RequestDatabaseAdmission | None:
    return _current_admission.get()


# Function Name: _busy
# Description:
# - Builds the retryable answer shared with busy accounts and exhausted connection pools.
# Parameters:
# - None.
# Returns:
# - HTTP 503 exception with Retry-After.
def _busy() -> HTTPException:
    return HTTPException(
        status_code=503, detail=ACCOUNT_BUSY_DETAIL, headers={"Retry-After": "5"},
    )
