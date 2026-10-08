# File Name: test_background_workers.py
# Role: Lifecycle and failure isolation of the three workers started by the application
#   lifespan: the caregiver alert outbox worker, the periodic data maintenance runner and the
#   chat notification worker, together with the durable chat job processor the last one drives.
#
# What is pinned here:
# - A cycle that raises never ends a worker loop, and the loop still waits its interval.
# - A failure while queueing missed-dose alerts does not skip delivery, and the reverse.
# - start() creates at most one task and stop() waits for it.
# - A chat push is sent with no pooled connection held, and a failure after the push has left
#   never puts the job back in the queue.

import asyncio
import time
from collections.abc import Callable
from unittest.mock import AsyncMock, patch

import pytest

from controls.manage_linked_chat_control import ManageLinkedChat
from controls.process_caregiver_alert_outbox_control import ProcessCaregiverAlertOutbox
from controls.process_chat_notifications_control import ProcessChatNotifications
from controls.queue_missed_dose_alerts_control import QueueMissedDoseAlerts
from entities.chat_notification_job_entity import ChatNotificationJob
from entities.device_push_token_entity import _DevicePushToken
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from services import data_maintenance
from services.caregiver_alert_outbox_worker import CaregiverAlertOutboxWorker
from services.chat_notification_worker import ChatNotificationWorker
from services.data_maintenance import PeriodicDataMaintenanceRunner
from support.db import make_engine, make_session_factory, seed_account
from support.fakes import RecordingPushBoundary

_PATIENT = "patient-a"
_CAREGIVER = "caregiver-a"


# Function Name: _wait_until
# Description:
# - Lets the event loop run until a condition holds, failing the test after a bounded wait.
# Parameters:
# - condition (Callable[[], bool]): Checked between short sleeps.
# - timeout (float): Seconds to wait before failing.
# Returns:
# - None.
async def _wait_until(condition: Callable[[], bool], timeout: float = 3.0) -> None:
    deadline = time.monotonic() + timeout
    while not condition():
        assert time.monotonic() < deadline, "the worker did not reach the expected state"
        await asyncio.sleep(0.005)


# Class Name: _BrokenSession
# Role: A session whose work and whose cleanup both fail, as after a connection lost in the
#   middle of a rollback.
# Attributes:
# - None.
class _BrokenSession:
    # Function Name: __getattr__
    # Description:
    # - Answers every session method with a callable that raises.
    # Parameters:
    # - name (str): Requested session attribute.
    # Returns:
    # - Callable raising RuntimeError.
    def __getattr__(self, name: str) -> Callable[..., None]:
        # Function Name: fail
        # Description: Raises for any use of the session.
        # Parameters: Ignored.
        # Returns: Never returns.
        def fail(*_args: object, **_kwargs: object) -> None:
            raise RuntimeError(f"connection lost during {name}")

        return fail


# Class Name: _FailingCycles
# Role: Replacement for a worker's synchronous cycle that counts its calls and always raises.
# Attributes:
# - calls (int): Number of cycles started.
class _FailingCycles:
    # Function Name: __init__
    # Description:
    # - Starts with no cycle run.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.calls = 0

    # Function Name: __call__
    # Description:
    # - Counts the cycle and fails it.
    # Parameters:
    # - None.
    # Returns:
    # - Never returns.
    def __call__(self) -> None:
        self.calls += 1
        raise RuntimeError("cycle failed")


# Function Name: test_outbox_cycle_with_a_broken_session_raises_out_of_the_cycle
# Description:
# - Documents why the loop needs its own guard: when rollback and close fail too, the cycle
#   itself cannot contain the error.
# Parameters:
# - None.
# Returns:
# - None.
def test_outbox_cycle_with_a_broken_session_raises_out_of_the_cycle() -> None:
    worker = CaregiverAlertOutboxWorker(_BrokenSession, RecordingPushBoundary, 3600)

    with pytest.raises(RuntimeError):
        worker._run_once()


# Function Name: test_outbox_worker_keeps_running_after_failing_cycles
# Description:
# - A real cycle on a broken session fails every time; the loop must go on to further cycles
#   instead of ending with the first exception.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_outbox_worker_keeps_running_after_failing_cycles() -> None:
    sessions_opened: list[_BrokenSession] = []

    # Function Name: open_broken_session
    # Description: Counts the cycle and hands out a session that fails on every use.
    # Parameters: None.
    # Returns: _BrokenSession.
    def open_broken_session() -> _BrokenSession:
        sessions_opened.append(_BrokenSession())
        return sessions_opened[-1]

    worker = CaregiverAlertOutboxWorker(
        open_broken_session, RecordingPushBoundary, interval_seconds=0.01,
    )

    worker.start()
    await _wait_until(lambda: len(sessions_opened) >= 3)

    assert not worker._task.done()
    await worker.stop()
    assert worker._task is None


# Function Name: test_outbox_worker_waits_its_interval_after_a_failing_cycle
# Description:
# - A failing cycle must not turn the loop into a busy retry: the next cycle starts only after
#   the configured interval, and stop() still ends the wait at once.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_outbox_worker_waits_its_interval_after_a_failing_cycle() -> None:
    worker = CaregiverAlertOutboxWorker(_BrokenSession, RecordingPushBoundary, 3600)
    cycles = _FailingCycles()
    worker._run_once = cycles

    worker.start()
    await _wait_until(lambda: cycles.calls == 1)
    await asyncio.sleep(0.1)

    assert cycles.calls == 1
    assert not worker._task.done()
    await asyncio.wait_for(worker.stop(), timeout=2)
    assert worker._task is None


# Function Name: test_outbox_worker_starts_one_task_and_stop_waits_for_it
# Description:
# - start() twice keeps the first task; stop() returns after the running cycle and clears it.
# Parameters:
# - fk_session_factory (sessionmaker[Session]): Factory on an empty in-memory database.
# Returns:
# - None.
@pytest.mark.anyio
async def test_outbox_worker_starts_one_task_and_stop_waits_for_it(
    fk_session_factory,
) -> None:
    worker = CaregiverAlertOutboxWorker(
        fk_session_factory, RecordingPushBoundary, interval_seconds=3600,
    )

    worker.start()
    first_task = worker._task
    worker.start()

    assert worker._task is first_task
    await asyncio.wait_for(worker.stop(), timeout=2)
    assert first_task.done() and first_task.exception() is None
    assert worker._task is None


# Function Name: test_outbox_worker_delivers_when_queueing_fails
# Description:
# - A failure while queueing missed-dose alerts is rolled back and logged; alerts that are
#   already queued are still processed in the same cycle and the session is closed.
# Parameters:
# - fk_session_factory (sessionmaker[Session]): Factory on an empty in-memory database.
# Returns:
# - None.
def test_outbox_worker_delivers_when_queueing_fails(fk_session_factory) -> None:
    opened = []

    # Function Name: open_session
    # Description: Opens a real session and keeps it so the test can check it was released.
    # Parameters: None.
    # Returns: Session.
    def open_session():
        opened.append(fk_session_factory())
        return opened[-1]

    worker = CaregiverAlertOutboxWorker(open_session, RecordingPushBoundary, 3600)

    with patch.object(
        QueueMissedDoseAlerts, "queueDue", side_effect=RuntimeError("queue failed"),
    ) as queue_due, patch.object(
        ProcessCaregiverAlertOutbox,
        "processDue",
        return_value={"sent": 1, "failed": 0, "skipped": 0},
    ) as process_due:
        worker._run_once()

    queue_due.assert_called_once_with()
    process_due.assert_called_once_with()
    assert len(opened) == 1
    assert not opened[0].in_transaction()


# Function Name: test_outbox_worker_queues_again_after_delivery_failed
# Description:
# - A delivery failure is contained in its cycle, so the next cycle queues and delivers again.
# Parameters:
# - fk_session_factory (sessionmaker[Session]): Factory on an empty in-memory database.
# Returns:
# - None.
def test_outbox_worker_queues_again_after_delivery_failed(fk_session_factory) -> None:
    worker = CaregiverAlertOutboxWorker(fk_session_factory, RecordingPushBoundary, 3600)

    with patch.object(QueueMissedDoseAlerts, "queueDue", return_value=0) as queue_due, patch.object(
        ProcessCaregiverAlertOutbox,
        "processDue",
        side_effect=[
            RuntimeError("delivery failed"),
            {"sent": 0, "failed": 0, "skipped": 0},
        ],
    ) as process_due:
        worker._run_once()
        worker._run_once()

    assert queue_due.call_count == 2
    assert process_due.call_count == 2


# Class Name: _CountingMaintenance
# Role: Maintenance service double that counts its runs and can fail them.
# Attributes:
# - runs (int): Number of runOnce calls.
# - error (Exception | None): Raised by every run when set.
class _CountingMaintenance:
    # Function Name: __init__
    # Description:
    # - Stores the configured failure and starts with no run.
    # Parameters:
    # - error (Exception | None): Exception raised by every run.
    # Returns:
    # - None.
    def __init__(self, error: Exception | None = None) -> None:
        self.runs = 0
        self.error = error

    # Function Name: runOnce
    # Description:
    # - Counts the run, then fails or reports that nothing was deleted.
    # Parameters:
    # - db (Session): Session opened by the runner for this cycle.
    # Returns:
    # - Empty deletion counts.
    def runOnce(self, db: object) -> dict[str, int]:
        self.runs += 1
        if self.error is not None:
            raise self.error
        return {}


# Function Name: test_maintenance_runner_keeps_running_after_failing_cycles
# Description:
# - Neither a failing cleanup nor a session that cannot be opened ends the maintenance loop.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Shortens the maintenance interval for this test.
# - fk_session_factory (sessionmaker[Session]): Factory on an empty in-memory database.
# - session_fails (bool): Whether opening the session itself fails.
# Returns:
# - None.
@pytest.mark.anyio
@pytest.mark.parametrize("session_fails", (False, True))
async def test_maintenance_runner_keeps_running_after_failing_cycles(
    monkeypatch, fk_session_factory, session_fails,
) -> None:
    monkeypatch.setattr(
        data_maintenance.settings, "PERIODIC_MAINTENANCE_INTERVAL_SECONDS", 0.01,
    )
    cycles = {"count": 0}

    # Function Name: open_session
    # Description: Counts the cycle and either fails or opens a real session.
    # Parameters: None.
    # Returns: Session.
    def open_session():
        cycles["count"] += 1
        if session_fails:
            raise RuntimeError("database is unavailable")
        return fk_session_factory()

    runner = PeriodicDataMaintenanceRunner(
        open_session, _CountingMaintenance(RuntimeError("cleanup failed")),
    )

    runner.start()
    await _wait_until(lambda: cycles["count"] >= 3)

    assert not runner._task.done()
    await runner.stop()
    assert runner._task is None


# Function Name: test_maintenance_runner_starts_one_task_and_stop_ends_the_wait
# Description:
# - start() twice keeps the first task, the cleanup runs once per cycle, and stop() ends the
#   six-hour wait immediately.
# Parameters:
# - fk_session_factory (sessionmaker[Session]): Factory on an empty in-memory database.
# Returns:
# - None.
@pytest.mark.anyio
async def test_maintenance_runner_starts_one_task_and_stop_ends_the_wait(
    fk_session_factory,
) -> None:
    service = _CountingMaintenance()
    runner = PeriodicDataMaintenanceRunner(fk_session_factory, service)

    runner.start()
    first_task = runner._task
    runner.start()
    await _wait_until(lambda: service.runs == 1)

    assert runner._task is first_task
    await asyncio.wait_for(runner.stop(), timeout=2)
    assert service.runs == 1
    assert first_task.done() and first_task.exception() is None
    assert runner._task is None


# Class Name: _CountingChatProcessor
# Role: Chat job processor double that counts polls and can fail them.
# Attributes:
# - polls (int): Number of run_once calls.
# - error (Exception | None): Raised by every poll when set.
class _CountingChatProcessor:
    # Function Name: __init__
    # Description:
    # - Stores the configured failure and starts with no poll.
    # Parameters:
    # - error (Exception | None): Exception raised by every poll.
    # Returns:
    # - None.
    def __init__(self, error: Exception | None = None) -> None:
        self.polls = 0
        self.error = error

    # Function Name: run_once
    # Description:
    # - Counts the poll, then fails or reports that no job was handled.
    # Parameters:
    # - None.
    # Returns:
    # - 0.
    async def run_once(self) -> int:
        self.polls += 1
        if self.error is not None:
            raise self.error
        return 0


# Function Name: test_chat_worker_lifecycle_survives_a_failing_poll
# Description:
# - start() twice keeps the first task, a failing poll leaves the loop alive, and stop() ends
#   the polling delay and clears the task.
# Parameters:
# - error (Exception | None): Failure of every poll, or None for a healthy processor.
# Returns:
# - None.
@pytest.mark.anyio
@pytest.mark.parametrize("error", (None, RuntimeError("poll failed")))
async def test_chat_worker_lifecycle_survives_a_failing_poll(error) -> None:
    processor = _CountingChatProcessor(error)
    worker = ChatNotificationWorker(processor)

    worker.start()
    first_task = worker.task
    worker.start()
    await _wait_until(lambda: processor.polls == 1)

    assert worker.task is first_task
    assert not first_task.done()
    await asyncio.wait_for(worker.stop(), timeout=2)
    assert first_task.done() and first_task.exception() is None
    assert worker.task is None


# Function Name: chat_database
# Description:
# - Provides a file-backed engine (one pooled connection per session, so connections held
#   during a push can be counted) with one queued chat notification job.
# Parameters:
# - tmp_path (Path): Per-test directory for the database file.
# Returns:
# - Iterator yielding (engine, session factory, message id of the queued job).
@pytest.fixture
def chat_database(tmp_path):
    engine = make_engine(tmp_path)
    sessions = make_session_factory(engine)
    with sessions() as db:
        seed_account(db, _PATIENT, _CAREGIVER)
        link = _PatientCaregiverLink(
            patient_hash=_PATIENT, caregiver_hash=_CAREGIVER, linked=True,
        )
        db.add_all([link, _DevicePushToken(user_hash=_CAREGIVER, token="caregiver-a-chat-device-token-123")])
        db.commit()
        message_id = int(
            ManageLinkedChat(db).send_message(
                link_id=int(link.id),
                sender_hash=_PATIENT,
                client_message_id="background_worker_message_1",
                body="I took the morning medication.",
            ).message.message_id
        )
    try:
        yield engine, sessions, message_id
    finally:
        engine.dispose()


# Function Name: _chat_processor
# Description:
# - Builds the durable chat job processor for an offline recipient whose push quota is free.
# Parameters:
# - sessions (sessionmaker[Session]): Factory the processor opens its short sessions from.
# - boundary (RecordingPushBoundary): Push double shared by every delivery.
# Returns:
# - ProcessChatNotifications.
def _chat_processor(sessions, boundary: RecordingPushBoundary) -> ProcessChatNotifications:
    return ProcessChatNotifications(
        sessions,
        lambda: boundary,
        AsyncMock(return_value=False),
        AsyncMock(return_value=True),
    )


# Function Name: _job_state
# Description:
# - Reads the committed state of the queued chat job through a fresh session.
# Parameters:
# - sessions (sessionmaker[Session]): Factory on the test database.
# - message_id (int): Primary key of the job.
# Returns:
# - (status, attempts, last_error).
def _job_state(sessions, message_id: int) -> tuple[str, int, str | None]:
    with sessions() as db:
        job = db.get(ChatNotificationJob, message_id)
        return str(job.status), int(job.attempts), job.last_error


# Function Name: test_chat_push_is_sent_with_the_job_claimed_and_no_connection_held
# Description:
# - While Firebase is called the job is already leased in the database and the worker holds
#   no pooled connection; the completed state is written afterwards.
# Parameters:
# - chat_database (tuple): Engine, session factory and queued message id.
# Returns:
# - None.
@pytest.mark.anyio
async def test_chat_push_is_sent_with_the_job_claimed_and_no_connection_held(
    chat_database,
) -> None:
    engine, sessions, message_id = chat_database
    seen_at_send: list[tuple[int, tuple[str, int, str | None]]] = []
    boundary = RecordingPushBoundary(
        on_send=lambda call: seen_at_send.append(
            (engine.pool.checkedout(), _job_state(sessions, message_id))
        ),
    )

    handled = await _chat_processor(sessions, boundary).run_once()

    assert handled == 1
    assert seen_at_send == [(0, ("processing", 1, None))]
    assert _job_state(sessions, message_id) == ("completed", 1, None)


# Function Name: test_delivered_chat_job_is_not_requeued_when_its_completion_write_fails
# Description:
# - When the first write of the completed state fails after the push has left, the job is
#   completed on the retry instead of going back to "pending", which would send it twice.
# Parameters:
# - chat_database (tuple): Engine, session factory and queued message id.
# Returns:
# - None.
@pytest.mark.anyio
async def test_delivered_chat_job_is_not_requeued_when_its_completion_write_fails(
    chat_database,
) -> None:
    _engine, sessions, message_id = chat_database
    boundary = RecordingPushBoundary()
    processor = _chat_processor(sessions, boundary)
    real_finish = processor.finish
    finish_statuses: list[str] = []

    # Function Name: finish_failing_once
    # Description: Fails the first state write and delegates the following ones.
    # Parameters: claim - lease; status - requested state; error - diagnostic.
    # Returns: None.
    def finish_failing_once(claim, status, error=None) -> None:
        finish_statuses.append(status)
        if len(finish_statuses) == 1:
            raise RuntimeError("database is unavailable")
        real_finish(claim, status, error)

    processor.finish = finish_failing_once

    assert await processor.run_once() == 1

    assert finish_statuses == ["completed", "completed"]
    assert _job_state(sessions, message_id) == ("completed", 1, None)
    assert await processor.run_once() == 0
    assert len(boundary.calls) == 1


# Function Name: test_delivered_chat_job_keeps_its_lease_when_no_state_can_be_written
# Description:
# - When the completed state cannot be written at all, the error leaves the batch and the job
#   stays leased, so it is not sent again before the five-minute lease expires.
# Parameters:
# - chat_database (tuple): Engine, session factory and queued message id.
# Returns:
# - None.
@pytest.mark.anyio
async def test_delivered_chat_job_keeps_its_lease_when_no_state_can_be_written(
    chat_database,
) -> None:
    _engine, sessions, message_id = chat_database
    boundary = RecordingPushBoundary()
    processor = _chat_processor(sessions, boundary)
    real_finish = processor.finish
    processor.finish = lambda claim, status, error=None: (_ for _ in ()).throw(
        RuntimeError("database is unavailable")
    )

    with pytest.raises(RuntimeError):
        await processor.run_once()

    processor.finish = real_finish
    assert _job_state(sessions, message_id) == ("processing", 1, None)
    assert await processor.run_once() == 0
    assert len(boundary.calls) == 1


# Function Name: test_chat_job_whose_push_failed_goes_back_to_the_queue
# Description:
# - A push that never left is still retried: the job returns to "pending" with the error name.
# Parameters:
# - chat_database (tuple): Engine, session factory and queued message id.
# Returns:
# - None.
@pytest.mark.anyio
async def test_chat_job_whose_push_failed_goes_back_to_the_queue(chat_database) -> None:
    _engine, sessions, message_id = chat_database
    boundary = RecordingPushBoundary(raises=RuntimeError("push provider is down"))

    assert await _chat_processor(sessions, boundary).run_once() == 1

    assert _job_state(sessions, message_id) == ("pending", 1, "RuntimeError")
