# File Name: request_database_work.py
# Role: Offloads sequential request-session operations without allowing cancellation to race session cleanup.

import asyncio
from collections.abc import Callable
from typing import ParamSpec, TypeVar

from anyio import CancelScope
from starlette.concurrency import run_in_threadpool

from core.request_database_gate import current_request_database_admission

_Parameters = ParamSpec("_Parameters")
_Result = TypeVar("_Result")


# Function Name: run_request_database_work
# Description:
# - Executes one blocking operation in the bounded worker pool and drains it before propagating request cancellation.
# - Preserves ordinary operation failures; after cancellation, consumes worker failures and re-raises the original cancellation.
# - In an admitted PostgreSQL request, first waits on the event loop for the account turn and a
#   database slot, and gives them back afterwards when no transaction stays open.
# Parameters:
# - operation (Callable): Synchronous operation using the caller-owned request session.
# - args / kwargs: Positional and keyword inputs forwarded unchanged to the operation.
# Returns:
# - The operation result, or its original failure; cancellation is delayed until session work has stopped.
#   HTTP 503 when the admission wait times out.
# Note: Call sequentially, never share the session with parallel work. Database deadlines remain the operation's responsibility.
async def run_request_database_work(
    operation: Callable[_Parameters, _Result],
    *args: _Parameters.args,
    **kwargs: _Parameters.kwargs,
) -> _Result:
    # Step 1: Queue on the event loop, not in a worker thread, before touching the database.
    admission = current_request_database_admission()
    if admission is not None:
        await admission.ensure_admitted()
    try:
        return await drain_database_work(operation, *args, **kwargs)
    finally:
        # Step 2: The worker has stopped; give the turn and slot back unless a transaction stays open.
        if admission is not None:
            admission.release_if_idle()


# Function Name: drain_database_work
# Description:
# - Runs one blocking operation in the worker pool without request admission and waits for it to
#   stop even when the caller is cancelled; also used to close an admitted session.
# Parameters:
# - operation (Callable): Synchronous session operation.
# - args / kwargs: Positional and keyword inputs forwarded unchanged to the operation.
# Returns:
# - The operation result, or its original failure; cancellation is delayed until the work has stopped.
async def drain_database_work(
    operation: Callable[_Parameters, _Result],
    *args: _Parameters.args,
    **kwargs: _Parameters.kwargs,
) -> _Result:
    # Step 1: Shield the worker task so direct asyncio cancellation cannot abandon its session.
    worker = asyncio.create_task(run_in_threadpool(operation, *args, **kwargs))
    try:
        return await asyncio.shield(worker)
    except asyncio.CancelledError as cancellation:
        # Step 2: Shield AnyIO cancellation too; repeated direct cancellation must not interrupt draining.
        with CancelScope(shield=True):
            while not worker.done():
                try:
                    await asyncio.shield(worker)
                except asyncio.CancelledError:
                    continue
                except BaseException:
                    break
            # Step 3: Observe the worker result without replacing the original request cancellation.
            try:
                worker.result()
            except BaseException:
                pass
        raise cancellation
