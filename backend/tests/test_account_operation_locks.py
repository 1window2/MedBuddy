# File Name: test_account_operation_locks.py
# Role: Verifies account-lock isolation and bounded, cancellation-safe registry lifetimes.

import asyncio
import pytest

from core.account_operation_locks import AccountOperationLocks


# Function Name: anyio_backend
# Description:
# - Runs lock tests on the application's asyncio runtime.
# Parameters:
# - None.
# Returns:
# - Asyncio backend name.
@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


# Function Name: test_same_account_serializes_until_scope_exit
# Description:
# - Blocks a competing account operation until its predecessor releases ownership.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_same_account_serializes_until_scope_exit() -> None:
    locks = AccountOperationLocks()
    entered = asyncio.Event()

    # Function Name: contender
    # Description:
    # - Marks entry only after acquiring the same account scope.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def contender() -> None:
        async with locks.hold("account", timeout=1):
            entered.set()

    async with locks.hold("account", timeout=1):
        task = asyncio.create_task(contender())
        await asyncio.sleep(0)
        assert not entered.is_set()
        assert locks.active_scope_count == 1
    await task
    assert entered.is_set()
    assert locks.active_scope_count == 0


# Function Name: test_different_accounts_do_not_block_each_other
# Description:
# - Allows independent account scopes to acquire ownership concurrently.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_different_accounts_do_not_block_each_other() -> None:
    locks = AccountOperationLocks()
    async with locks.hold("first", timeout=1):
        async with locks.hold("second", timeout=1):
            assert locks.active_scope_count == 2
        assert locks.active_scope_count == 1
    assert locks.active_scope_count == 0


# Function Name: test_cancelled_waiter_does_not_retain_account_identity
# Description:
# - Drops a cancelled waiter's reference without unlocking the current holder.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_cancelled_waiter_does_not_retain_account_identity() -> None:
    locks = AccountOperationLocks()
    started = asyncio.Event()

    # Function Name: wait_for_scope
    # Description:
    # - Signals a waiting request and fails if it unexpectedly acquires ownership.
    # Parameters:
    # - None.
    # Returns:
    # - None; cancellation interrupts the acquisition.
    async def wait_for_scope() -> None:
        started.set()
        async with locks.hold("account", timeout=1):
            pytest.fail("Cancelled waiter must not enter the protected scope")

    async with locks.hold("account", timeout=1):
        waiter = asyncio.create_task(wait_for_scope())
        await started.wait()
        waiter.cancel()
        with pytest.raises(asyncio.CancelledError):
            await waiter
        with pytest.raises(TimeoutError):
            async with locks.hold("account", timeout=0.01):
                pytest.fail("Waiter cancellation must not unlock the holder")
    assert locks.active_scope_count == 0


# Function Name: test_timed_out_waiter_releases_its_reference
# Description:
# - Removes a timed-out waiter's reference when the owning request exits.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_timed_out_waiter_releases_its_reference() -> None:
    locks = AccountOperationLocks()
    async with locks.hold("account", timeout=1):
        with pytest.raises(TimeoutError):
            async with locks.hold("account", timeout=0.01):
                pytest.fail("Contender must time out while the account is owned")
        assert locks.active_scope_count == 1
    assert locks.active_scope_count == 0


# Function Name: test_failed_scope_releases_ownership
# Description:
# - Drops ownership on a protected operation failure so a retry can proceed.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_failed_scope_releases_ownership() -> None:
    locks = AccountOperationLocks()
    with pytest.raises(ValueError, match="operation failed"):
        async with locks.hold("account", timeout=1):
            raise ValueError("operation failed")
    assert locks.active_scope_count == 0
    async with locks.hold("account", timeout=1):
        assert locks.active_scope_count == 1
    assert locks.active_scope_count == 0


# Function Name: test_cancelled_holder_releases_ownership
# Description:
# - Removes a holder's scope when cancellation interrupts endpoint execution.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_cancelled_holder_releases_ownership() -> None:
    locks = AccountOperationLocks()
    entered = asyncio.Event()

    # Function Name: hold_until_cancelled
    # Description:
    # - Keeps ownership while waiting for request cancellation.
    # Parameters:
    # - None.
    # Returns:
    # - None; cancellation interrupts the protected operation.
    async def hold_until_cancelled() -> None:
        async with locks.hold("account", timeout=1):
            entered.set()
            await asyncio.Event().wait()

    holder = asyncio.create_task(hold_until_cancelled())
    await entered.wait()
    holder.cancel()
    with pytest.raises(asyncio.CancelledError):
        await holder
    assert locks.active_scope_count == 0
