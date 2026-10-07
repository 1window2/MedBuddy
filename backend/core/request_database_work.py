# File Name: request_database_work.py
# Role: Offloads sequential request-session operations without allowing cancellation to race session cleanup.

import asyncio
from collections.abc import Callable
from typing import ParamSpec, TypeVar

from anyio import CancelScope
from starlette.concurrency import run_in_threadpool

_Parameters = ParamSpec("_Parameters")
_Result = TypeVar("_Result")


# Function Name: run_request_database_work
# Description:
# - Executes one blocking operation in the bounded worker pool and drains it before propagating request cancellation.
# - Preserves ordinary operation failures; after cancellation, consumes worker failures and re-raises the original cancellation.
# Parameters:
# - operation (Callable): Synchronous operation using the caller-owned request session.
# - args / kwargs: Positional and keyword inputs forwarded unchanged to the operation.
# Returns:
# - The operation result, or its original failure; cancellation is delayed until session work has stopped.
# Note: Call sequentially, never share the session with parallel work. Database deadlines remain the operation's responsibility.
async def run_request_database_work(
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
