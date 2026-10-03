# File Name: test_request_database_work.py
# Role: Proves request-owned database work finishes before cleanup on success, failure and repeated cancellation.

import asyncio
import gc
import threading

import pytest
from anyio import CancelScope, to_thread

from core.request_database_work import run_request_database_work


# Function Name: anyio_backend
# Description: Selects the application's asyncio event loop for lifecycle regressions.
# Parameters: None.
# Returns: Asyncio backend name.
@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


# Function Name: _wait_for_worker
# Description: Waits for worker entry without blocking the event loop or hanging a failed test.
# Parameters: started (threading.Event): Worker-entry signal.
# Returns: None; fails if worker entry does not occur within one second.
async def _wait_for_worker(started: threading.Event) -> None:
    async with asyncio.timeout(1):
        while not started.is_set():
            await asyncio.sleep(0)


# Function Name: test_request_database_work_forwards_inputs_off_loop
# Description: Preserves positional/keyword inputs and results while permitting event-loop callbacks during database work.
# Parameters: None.
# Returns: None; fails if the operation runs on the event loop or loses its arguments.
@pytest.mark.anyio
async def test_request_database_work_forwards_inputs_off_loop() -> None:
    loop = asyncio.get_running_loop()
    loop_thread = threading.get_ident()

    # Function Name: operation
    # Description: Requires worker-thread execution and an event-loop acknowledgement before returning.
    # Parameters: number (int): Positional input; increment (int): Keyword-only input.
    # Returns: Sum of both inputs.
    def operation(number: int, *, increment: int) -> int:
        assert threading.get_ident() != loop_thread
        acknowledged = threading.Event()
        loop.call_soon_threadsafe(acknowledged.set)
        assert acknowledged.wait(1), "The event loop was blocked by database work."
        return number + increment

    assert await run_request_database_work(operation, 3, increment=4) == 7


# Function Name: test_request_database_work_preserves_operation_failures
# Description: Propagates a normal worker failure instead of converting it to cancellation or a successful result.
# Parameters: None.
# Returns: None; fails if the original operation error is lost.
@pytest.mark.anyio
async def test_request_database_work_preserves_operation_failures() -> None:
    error = ValueError("operation failed")

    # Function Name: operation
    # Description: Raises the designated operation failure from the worker.
    # Parameters: None.
    # Returns: No normal result.
    def operation() -> None:
        raise error

    with pytest.raises(ValueError) as rejected:
        await run_request_database_work(operation)
    assert rejected.value is error


# Function Name: test_request_cancellation_drains_worker_before_cleanup
# Description: Keeps session cleanup after worker exit under direct/repeated cancellation, including a failing worker.
# Parameters: cancellation_count (int): Number of direct cancels; worker_fails (bool): Whether delivery raises after finishing.
# Returns: None; fails if cleanup overlaps work or cancellation is replaced by a worker error.
@pytest.mark.anyio
@pytest.mark.parametrize("cancellation_count", [1, 3])
@pytest.mark.parametrize("worker_fails", [False, True])
async def test_request_cancellation_drains_worker_before_cleanup(
    cancellation_count: int, worker_fails: bool,
) -> None:
    started = threading.Event()
    release = threading.Event()
    calls: list[str] = []

    # Function Name: operation
    # Description: Holds a simulated request session until the test permits completion.
    # Parameters: None.
    # Returns: None; optionally raises only after its session work has stopped.
    def operation() -> None:
        calls.append("worker_start")
        started.set()
        if not release.wait(2):
            raise AssertionError("Cancellation drain did not release the worker.")
        calls.append("worker_end")
        if worker_fails:
            raise RuntimeError("private worker failure")

    # Function Name: request
    # Description: Simulates dependency teardown immediately after the adapter returns or raises.
    # Parameters: None.
    # Returns: None; cancellation propagates after cleanup can safely run.
    async def request() -> None:
        try:
            await run_request_database_work(operation)
        finally:
            calls.append("cleanup")

    task = asyncio.create_task(request())
    try:
        await _wait_for_worker(started)
        for index in range(cancellation_count):
            task.cancel("original cancellation" if index == 0 else "repeated cancellation")
            await asyncio.sleep(0)
            assert not task.done()
            assert calls == ["worker_start"]
    finally:
        release.set()
    with pytest.raises(asyncio.CancelledError) as rejected:
        await task
    assert rejected.value.args == ("original cancellation",)
    assert calls == ["worker_start", "worker_end", "cleanup"]


# Function Name: test_queued_request_cancellation_drains_worker_and_observes_failures
# Description: Retains the request while its worker awaits capacity, then drains success or failure before cleanup.
# Parameters: worker_fails (bool): Whether the queued operation fails after receiving the worker token.
# Returns: None; fails on early cleanup, lost original cancellation or an unretrieved worker exception.
@pytest.mark.anyio
@pytest.mark.parametrize("worker_fails", [False, True])
async def test_queued_request_cancellation_drains_worker_and_observes_failures(
    worker_fails: bool,
) -> None:
    limiter = to_thread.current_default_thread_limiter()
    original_capacity = limiter.total_tokens
    limiter.total_tokens = 1
    occupied = threading.Event()
    release_capacity = threading.Event()
    calls: list[str] = []
    loop_errors: list[dict[str, object]] = []
    loop = asyncio.get_running_loop()
    previous_handler = loop.get_exception_handler()

    # Function Name: record_loop_error
    # Description: Records unexpected task/worker errors instead of discarding them in event-loop logging.
    # Parameters: error_loop (AbstractEventLoop): Reporting loop; context (dict): Error details.
    # Returns: None.
    def record_loop_error(
        error_loop: asyncio.AbstractEventLoop, context: dict[str, object],
    ) -> None:
        assert error_loop is loop
        loop_errors.append(context)

    # Function Name: occupy_worker
    # Description: Holds the only worker token until cancellation assertions permit the queued job to start.
    # Parameters: None.
    # Returns: None; fails after two seconds instead of leaving the test's worker blocked.
    def occupy_worker() -> None:
        occupied.set()
        assert release_capacity.wait(2), "The test did not release worker capacity."

    # Function Name: operation
    # Description: Records queued worker completion and optionally raises after its session work ends.
    # Parameters: None.
    # Returns: None; optionally raises the designated worker failure.
    def operation() -> None:
        calls.extend(["worker_start", "worker_end"])
        if worker_fails:
            raise RuntimeError("private queued worker failure")

    # Function Name: request
    # Description: Simulates request-session teardown after the capacity-blocked operation has drained.
    # Parameters: None.
    # Returns: None; propagates request cancellation after cleanup.
    async def request() -> None:
        try:
            await run_request_database_work(operation)
        finally:
            calls.append("cleanup")

    loop.set_exception_handler(record_loop_error)
    blocker = asyncio.create_task(to_thread.run_sync(occupy_worker))
    task: asyncio.Task[None] | None = None
    try:
        await _wait_for_worker(occupied)
        task = asyncio.create_task(request())
        async with asyncio.timeout(1):
            while limiter.statistics().tasks_waiting == 0:
                await asyncio.sleep(0)
        for index in range(3):
            task.cancel("original cancellation" if index == 0 else "repeated cancellation")
            await asyncio.sleep(0)
            assert not task.done()
            assert calls == []
        release_capacity.set()
        await asyncio.wait_for(blocker, timeout=3)
        completed, _ = await asyncio.wait({task}, timeout=3)
        assert task in completed, "The queued request did not drain after capacity was released."
        with pytest.raises(asyncio.CancelledError) as rejected:
            await task
        assert rejected.value.args == ("original cancellation",)
        assert calls == ["worker_start", "worker_end", "cleanup"]
        # Drop traceback references so an unobserved worker failure cannot hide until after this test.
        rejected.value.__traceback__ = None
        del rejected
        gc.collect()
        await asyncio.sleep(0)
        assert loop_errors == []
    finally:
        release_capacity.set()
        pending = [blocker] if task is None else [blocker, task]
        try:
            await asyncio.wait_for(asyncio.gather(*pending, return_exceptions=True), timeout=3)
        finally:
            limiter.total_tokens = original_capacity
            loop.set_exception_handler(previous_handler)


# Function Name: test_anyio_scope_cancellation_drains_worker
# Description: Handles level-triggered AnyIO cancellation without spinning or cleaning up an active request session.
# Parameters: None.
# Returns: None; fails if worker completion is skipped before cancellation leaves the protected scope.
@pytest.mark.anyio
async def test_anyio_scope_cancellation_drains_worker() -> None:
    started = threading.Event()
    release = threading.Event()
    calls: list[str] = []
    scope = CancelScope()

    # Function Name: operation
    # Description: Holds a simulated session until the test observes scope cancellation and permits completion.
    # Parameters: None.
    # Returns: None once the event loop acknowledges cancellation and permits completion.
    def operation() -> None:
        calls.append("worker_start")
        started.set()
        if not release.wait(2):
            raise AssertionError("AnyIO cancellation blocked the event loop.")
        calls.append("worker_end")

    # Function Name: request
    # Description: Runs the request under an externally cancelled AnyIO scope without releasing its worker early.
    # Parameters: None.
    # Returns: None once scope cancellation is consumed after safe session cleanup.
    async def request() -> None:
        with scope:
            try:
                await run_request_database_work(operation)
            finally:
                calls.append("cleanup")

    task = asyncio.create_task(request())
    try:
        await _wait_for_worker(started)
        scope.cancel()
        async with asyncio.timeout(1):
            while not task.cancelling() and not task.done():
                await asyncio.sleep(0)
        await asyncio.sleep(0)
        assert not task.done()
        assert calls == ["worker_start"]
    finally:
        release.set()
        await asyncio.wait_for(task, timeout=3)
    assert scope.cancelled_caught
    assert calls == ["worker_start", "worker_end", "cleanup"]
