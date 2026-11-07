# File Name: chat_notification_worker.py
# Role: Own the lifetime of the durable chat-notification polling loop.

import asyncio
import logging
from controls.process_chat_notifications_control import ProcessChatNotifications

logger = logging.getLogger(__name__)


# Class Name: ChatNotificationWorker
# Role: Polls committed chat notification jobs while supporting graceful shutdown.
# Responsibilities: Runs bounded delivery batches, retries polling failures and wakes the delay when stopped.
# Attributes: processor (ProcessChatNotifications) handles jobs; task (Task | None) and stop_event (Event) track lifecycle.
class ChatNotificationWorker:
    # Function Name: __init__
    # Description: Binds the durable processor and allocates lifecycle state without starting delivery.
    # Parameters: processor (ProcessChatNotifications) handles each polling batch.
    # Returns: None.
    def __init__(self, processor: ProcessChatNotifications) -> None:
        self.processor = processor
        self.task: asyncio.Task[None] | None = None
        self.stop_event = asyncio.Event()

    # Function Name: start
    # Description: Clears the stop signal and starts one polling task only when none is registered.
    # Parameters: None.
    # Returns: None; scheduling requires a running event loop.
    def start(self) -> None:
        if self.task is None:
            self.stop_event.clear()
            self.task = asyncio.create_task(self.run())

    # Function Name: stop
    # Description: Wakes the polling delay and waits for the current bounded batch before clearing the task reference.
    # Parameters: None.
    # Returns: None after shutdown; unexpected task termination propagates.
    async def stop(self) -> None:
        self.stop_event.set()
        if self.task is not None:
            await self.task
            self.task = None

    # Function Name: run
    # Description: Processes batches until stopped, logging only exception types on failure and waiting up to five seconds between attempts.
    # Parameters: None; uses the bound processor and stop event.
    # Returns: None when stopped; ordinary processing exceptions are retried, while cancellation propagates.
    async def run(self) -> None:
        while not self.stop_event.is_set():
            try:
                await self.processor.run_once()
            except Exception as exc:
                logger.warning("Chat notification polling failed: %s", type(exc).__name__)
            try:
                await asyncio.wait_for(self.stop_event.wait(), timeout=5)
            except TimeoutError:
                pass
