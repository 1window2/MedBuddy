# 파일명: background_loop_runner.py
# 역할: 서버 수명 동안 도는 반복 작업의 시작과 종료 대기를 한 곳에서 제공한다.

import asyncio
import logging


# Class Name: BackgroundLoopRunner
# Role: Owns a single repeating background task and its cooperative shutdown.
# Responsibilities: Runs synchronous cycles off the event loop, logs cycle exception types, and waits for the next interval or stop.
# Attributes: _task (Task | None) and _stop_event (Event) track lifetime; subclasses supply _cycle_logger and _cycle_failure_message.
# Note: Subclasses implement the cycle/interval hooks; stopped instances retain their stop signal.
class BackgroundLoopRunner:
    _cycle_logger: logging.Logger
    _cycle_failure_message: str

    # Function Name: __init__
    # Description: Allocates an unset stop event and empty task slot without scheduling work.
    # Parameters: None.
    # Returns: None; start must be called on a running event loop.
    def __init__(self) -> None:
        self._stop_event = asyncio.Event()
        self._task: asyncio.Task[None] | None = None

    # Function Name: start
    # Description: Schedules the loop only when no task is registered; does not reset an already-set stop event.
    # Parameters: None.
    # Returns: None; a new task requires a running event loop.
    def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(self._run_loop())

    # Function Name: stop
    # Description: Signals shutdown and awaits the existing loop, allowing its current threaded cycle to finish.
    # Parameters: None.
    # Returns: None after completion; unexpected task failures propagate and the stop event remains set.
    async def stop(self) -> None:
        self._stop_event.set()
        if self._task is not None:
            await self._task
            self._task = None

    # Function Name: _run_loop
    # Description: Runs synchronous cycles in a worker thread, logs their exception types on failure, and waits for the configured interval or stop.
    # Parameters: None; uses subclass hooks and the stop event.
    # Returns: None when stopped. Cycle exceptions are retried; cancellation and failures in interval/logging hooks propagate.
    async def _run_loop(self) -> None:
        while not self._stop_event.is_set():
            try:
                await asyncio.to_thread(self._run_once)
            except Exception as exc:
                self._cycle_logger.error(
                    self._cycle_failure_message,
                    type(exc).__name__,
                )
            try:
                await asyncio.wait_for(
                    self._stop_event.wait(),
                    timeout=self._cycle_interval_seconds(),
                )
            except TimeoutError:
                continue

    # Function Name: _run_once
    # Description: Declares the synchronous cycle hook each concrete worker must implement.
    # Parameters: None.
    # Returns: No result in this base implementation; always raises NotImplementedError.
    def _run_once(self) -> None:
        raise NotImplementedError

    # Function Name: _cycle_interval_seconds
    # Description: Declares the hook for the delay after each completed or failed cycle.
    # Parameters: None.
    # Returns: Concrete implementations supply seconds (float); this base implementation raises NotImplementedError.
    def _cycle_interval_seconds(self) -> float:
        raise NotImplementedError
