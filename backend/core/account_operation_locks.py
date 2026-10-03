# File Name: account_operation_locks.py
# Role: Owns process-local account serialization and cancellation-safe lock cleanup.

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from threading import Lock


# Class Name: _AccountLockEntry
# Role: Tracks one account lock and all requests holding or awaiting it.
# Responsibilities:
# - Keep lock identity and reference lifetime together.
# Attributes:
# - lock (asyncio.Lock): Request-lifetime account mutex.
# - references (int): Number of active holders and waiters.
@dataclass
class _AccountLockEntry:
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)
    references: int = 0


# Class Name: AccountOperationLocks
# Role: Serializes SQLite account operations within one application event loop.
# Responsibilities:
# - Retain one lock per active account without storing idle account identities.
# - Release holders and waiter references on success, failure, timeout or cancellation.
# Attributes:
# - _entries (dict[str, _AccountLockEntry]): Active account holders and waiters.
# - _registry_guard (Lock): Protects registry reference updates, not database work.
# Note: PostgreSQL uses database transaction locks instead; this is process-local only.
class AccountOperationLocks:
    # Function Name: __init__
    # Description:
    # - Initializes an empty lock registry for one application runtime.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self._entries: dict[str, _AccountLockEntry] = {}
        self._registry_guard = Lock()

    # Function Name: active_scope_count
    # Description:
    # - Reports active lock scopes without exposing account identities.
    # Parameters:
    # - None.
    # Returns:
    # - Number of account scopes with a holder or waiter.
    @property
    def active_scope_count(self) -> int:
        with self._registry_guard:
            return len(self._entries)

    # Function Name: hold
    # Description:
    # - Retains and acquires an account lock, cleaning up even a cancelled waiter.
    # Parameters:
    # - user_hash (str): Server-verified account serialization scope.
    # - timeout (float): Maximum seconds to await ownership.
    # Returns:
    # - Yields while ownership is held; propagates timeout, cancellation or body errors.
    @asynccontextmanager
    async def hold(self, user_hash: str, *, timeout: float) -> AsyncIterator[None]:
        # Step 1: Retain the same entry for every holder and waiter in this scope.
        with self._registry_guard:
            entry = self._entries.setdefault(user_hash, _AccountLockEntry())
            entry.references += 1
        acquired = False
        try:
            # Step 2: Bound the asynchronous wait and hold through endpoint execution.
            if timeout <= 0:
                raise TimeoutError
            # Inline acquisition preserves cancellation at ownership handoff;
            # wait_for can swallow it when its acquisition child has just finished.
            async with asyncio.timeout(timeout):
                await entry.lock.acquire()
            acquired = True
            yield
        finally:
            # Step 3: Release ownership and always drop the waiter/holder reference.
            if acquired:
                entry.lock.release()
            with self._registry_guard:
                entry.references -= 1
                if entry.references == 0:
                    del self._entries[user_hash]
