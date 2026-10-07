# File Name: chat_notification_worker.py
# Role: Own the lifetime of the durable chat-notification polling loop.

import asyncio
import logging
from controls.process_chat_notifications_control import ProcessChatNotifications

logger = logging.getLogger(__name__)


# Class Name: ChatNotificationWorker
# Role: Poll committed work and stop gracefully without abandoning in-flight delivery.
# Attributes: processor - use-case controller; task/stop_event - lifecycle state.
class ChatNotificationWorker:
    # Function Name: __init__
    # Description: Prepare lifecycle state without starting background work.
    # Parameters: processor - durable job processor. Returns: Initialized worker.
    def __init__(self, processor: ProcessChatNotifications) -> None:
        self.processor = processor
        self.task: asyncio.Task[None] | None = None
        self.stop_event = asyncio.Event()

    # Function Name: start
    # Description: Start at most one polling loop.
    # Parameters: None. Returns: None.
    def start(self) -> None:
        if self.task is None:
            self.stop_event.clear()
            self.task = asyncio.create_task(self.run())

    # Function Name: stop
    # Description: Wake the polling delay and await the current bounded batch.
    # Parameters: None. Returns: Completion of shutdown.
    async def stop(self) -> None:
        self.stop_event.set()
        if self.task is not None:
            await self.task
            self.task = None

    # Function Name: run
    # Description: Retry polling errors without logging message bodies, credentials or DB parameters.
    # Parameters: None. Returns: Completion when stopped.
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
