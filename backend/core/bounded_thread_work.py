# File Name: bounded_thread_work.py
# Role: Runs blocking work in a worker thread under a semaphore slot that stays reserved until the thread really exits.

import asyncio
import functools
from collections.abc import Callable
from typing import TypeVar

_Result = TypeVar("_Result")


# Function Name: run_thread_keeping_capacity
# Description:
# - Acquires one semaphore slot and runs one blocking operation in a worker thread.
# - Shields the thread from cancellation, so a cancelled or timed-out caller keeps the slot
#   reserved until the thread has really finished; the slot is then released by a callback.
# Parameters:
# - semaphore (asyncio.Semaphore): Capacity gate shared by every caller of the same kind of work.
# - operation (Callable[..., _Result]): Blocking function to run off the event loop.
# - args (object): Positional arguments passed to the operation.
# Returns:
# - The operation's result; its exceptions propagate, and caller cancellation propagates after
#   the deferred release is registered.
async def run_thread_keeping_capacity(
    semaphore: asyncio.Semaphore,
    operation: Callable[..., _Result],
    *args: object,
) -> _Result:
    """Keeps capacity reserved until a timed-out worker really exits."""

    await semaphore.acquire()
    worker = asyncio.create_task(asyncio.to_thread(operation, *args))
    release_on_exit = True
    try:
        try:
            return await asyncio.shield(worker)
        except asyncio.CancelledError:
            worker.add_done_callback(functools.partial(_release_after_worker, semaphore))
            release_on_exit = False
            raise
    finally:
        if release_on_exit:
            semaphore.release()


# Function Name: _release_after_worker
# Description:
# - Consumes a detached worker's exception so it is not reported as unretrieved, then returns
#   the slot the cancelled caller reserved.
# Parameters:
# - semaphore (asyncio.Semaphore): Capacity gate whose slot the worker held.
# - worker (asyncio.Task[object]): Completed worker task detached by a cancelled caller.
# Returns:
# - None; releases one semaphore slot.
def _release_after_worker(
    semaphore: asyncio.Semaphore,
    worker: asyncio.Task[object],
) -> None:
    """Consumes a detached worker result and releases its capacity slot."""

    try:
        worker.exception()
    except asyncio.CancelledError:
        pass
    semaphore.release()
