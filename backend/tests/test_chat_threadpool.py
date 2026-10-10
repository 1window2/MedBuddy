# File Name: test_chat_threadpool.py
# Role: Ensure chat persistence and handshake work never occupy the event-loop thread.

import asyncio
import threading
from functools import partial
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest
from fastapi import BackgroundTasks, HTTPException, WebSocketDisconnect

from api import chat_router
from services.chat_connection_manager import ChatConnectionManager


# Function Name: test_rest_chat_operations_leave_event_loop_responsive
# Description: Exercise each async write route, including ownership checks and dose refresh.
#   The two message-creating routes must also consume the daily chat quota exactly once.
# Parameters: operation - route and synchronous control operation under test.
# Returns: None; fails if a DB call runs on the loop or prevents a loop callback.
@pytest.mark.parametrize("operation", ["send_message", "delete_messages", "mark_read", "record_medication_taken"])
def test_rest_chat_operations_leave_event_loop_responsive(operation: str) -> None:
    # Function Name: exercise
    # Description: Run a route against blocking fakes and preserve async publication.
    # Parameters: None. Returns: Completion of thread and response assertions.
    async def exercise() -> None:
        loop = asyncio.get_running_loop()
        loop_thread = threading.get_ident()
        calls = []

        # Function Name: blocking
        # Description: Require a worker thread and a responsive event-loop callback.
        # Parameters: name/result - recorded operation and response; args/kwargs - route inputs.
        # Returns: The supplied control result after the loop has responded.
        def blocking(name: str, result: object, *args: object, **kwargs: object) -> object:
            assert threading.get_ident() != loop_thread
            pulse = threading.Event()
            loop.call_soon_threadsafe(pulse.set)
            assert pulse.wait(2), "event loop blocked during database work"
            calls.append(name)
            return result

        authorization = SimpleNamespace(resolveOwnUserHash=partial(blocking, "authorize", "patient"))
        result = ({"data": {"updated_count": 1}} if operation == "mark_read" else {"data": {}})
        if operation == "record_medication_taken":
            result = (object(), [])
        chat = SimpleNamespace(db=object(), **{operation: partial(blocking, operation, result)})
        payload = SimpleNamespace(
            client_message_id="test_message", body="Hello", medication_id=None,
            medication_ids=[1], message_ids=[1], scope="me", message_kind="text",
            slot_key="morning", pharmacy_id=None, source_alert_id=None,
            schedule_date="2026-09-26", through_message_id=1,
        )
        kwargs = dict(link_id=1, payload=payload, request=object(), user_hash="patient",
                      principal=object(), authorization=authorization, chat=chat)
        manager = SimpleNamespace(broadcast=AsyncMock())
        quota = AsyncMock()
        with patch.object(chat_router, "enforce_chat_daily_quota", quota), \
             patch.object(chat_router, "publish_saved_message", AsyncMock(return_value={"success": True})), \
             patch.object(chat_router, "get_chat_connection_manager", return_value=manager), \
             patch.object(chat_router, "CheckSchedule", return_value=SimpleNamespace(
                 requestTodayMedicationSchedule=partial(blocking, "schedule", {"data": []}))):
            if operation == "record_medication_taken":
                kwargs["background_tasks"] = BackgroundTasks()
            route = {"send_message": chat_router.post_chat_message,
                     "delete_messages": chat_router.delete_chat_messages,
                     "mark_read": chat_router.mark_chat_read,
                     "record_medication_taken": chat_router.record_chat_medication_taken}[operation]
            await route(**kwargs)
        assert calls == ["authorize", operation] + (["schedule"] if operation == "record_medication_taken" else [])
        assert quota.await_count == (1 if operation in ("send_message", "record_medication_taken") else 0)
    asyncio.run(exercise())


# Function Name: test_cancelled_websocket_handshake_finishes_database_work_before_close
# Description: Cancels an active handshake and requires worker completion before its session is closed, without accepting the socket.
# Parameters: None.
# Returns: None; fails if cancellation overlaps session use with cleanup.
def test_cancelled_websocket_handshake_finishes_database_work_before_close() -> None:
    # Function Name: exercise
    # Description: Holds a simulated authorization operation while cancelling the socket task.
    # Parameters: None.
    # Returns: Completion of cleanup-order assertions.
    async def exercise() -> None:
        started = threading.Event()
        release = threading.Event()
        calls: list[str] = []
        loop_thread = threading.get_ident()

        # Function Name: authorize
        # Description: Retains simulated session work until cancellation has reached the route.
        # Parameters: principal (object): Verified caller; user_hash (str): Requested account scope.
        # Returns: Verified user hash after its blocking work has finished.
        def authorize(principal: object, user_hash: str) -> str:
            assert threading.get_ident() != loop_thread
            started.set()
            if not release.wait(2):
                raise AssertionError("Handshake cancellation did not release database work.")
            calls.append("database_complete")
            return "patient"

        # Function Name: close_session
        # Description: Requires database completion before worker-thread session cleanup.
        # Parameters: None.
        # Returns: None.
        def close_session() -> None:
            assert threading.get_ident() != loop_thread
            assert calls == ["database_complete"]
            calls.append("close")

        db = SimpleNamespace(commit=lambda: None, rollback=lambda: None, close=close_session)
        manager = ChatConnectionManager()
        manager.connect = AsyncMock(return_value=True)
        socket = SimpleNamespace(
            app=SimpleNamespace(state=SimpleNamespace(chat_connection_manager=manager)),
            close=AsyncMock(), send_json=AsyncMock(),
        )
        with (
            patch.object(chat_router, "SessionLocal", return_value=db),
            patch.object(chat_router, "_authenticate_websocket", return_value=SimpleNamespace(expires_at=None)),
            patch.object(chat_router, "AuthorizationControl", return_value=SimpleNamespace(resolveOwnUserHash=authorize)),
        ):
            task = asyncio.create_task(chat_router.stream_chat_events(socket, 1, "patient"))
            try:
                async with asyncio.timeout(1):
                    while not started.is_set():
                        await asyncio.sleep(0)
                task.cancel()
                await asyncio.sleep(0)
                assert not task.done() and calls == []
            finally:
                release.set()
            with pytest.raises(asyncio.CancelledError):
                await task
        assert calls == ["database_complete", "close"]
        manager.connect.assert_not_awaited()
        socket.send_json.assert_not_awaited()

    asyncio.run(exercise())


# Function Name: test_websocket_handshake_offloads_auth_and_closes_session
# Description: Bound DB lifetime to the handshake and preserve failure close codes.
#   A rejected handshake is closed without being accepted.
# Parameters: failure - successful handshake, rejected quota, or authorization failure.
# Returns: None; fails on event-loop I/O, leaked sessions, or incorrect rejection codes.
@pytest.mark.parametrize("failure", [None, "quota", "authorization"])
def test_websocket_handshake_offloads_auth_and_closes_session(failure: str | None) -> None:
    # Function Name: exercise
    # Description: Exercise a fake socket with worker-only authentication and DB hooks.
    # Parameters: None. Returns: Completion of lifecycle assertions.
    async def exercise() -> None:
        loop_thread = threading.get_ident()
        calls = []

        # Function Name: blocking
        # Description: Track DB/auth operations and reject execution on the event loop.
        # Parameters: name/result - operation and response; args/kwargs - delegated inputs.
        # Returns: Supplied value, or HTTP 403 for the rejected ownership scenario.
        def blocking(name: str, result: object = None, *args: object, **kwargs: object) -> object:
            assert threading.get_ident() != loop_thread
            calls.append(name)
            if name == "authorize" and failure == "authorization":
                raise HTTPException(403, "Forbidden")
            return result

        db = SimpleNamespace(commit=partial(blocking, "commit"),
                             rollback=partial(blocking, "rollback"), close=partial(blocking, "close"))
        transport = []
        socket = SimpleNamespace(
            app=SimpleNamespace(state=SimpleNamespace(chat_connection_manager=ChatConnectionManager())),
            accept=AsyncMock(side_effect=lambda: transport.append("accept")),
            close=AsyncMock(side_effect=lambda **_: transport.append("close")),
            send_json=AsyncMock(),
            receive_text=AsyncMock(side_effect=WebSocketDisconnect()),
        )
        # SimpleNamespace is not hashable; a socket registry requires identity hashing.
        socket.app.state.chat_connection_manager.connect = AsyncMock(return_value=True)
        socket.app.state.chat_connection_manager.disconnect = AsyncMock()
        with patch.object(chat_router, "SessionLocal", return_value=db), \
             patch.object(chat_router, "_authenticate_websocket", partial(blocking, "authenticate", SimpleNamespace(expires_at=None))), \
             patch.object(chat_router, "AuthorizationControl", return_value=SimpleNamespace(
                 resolveOwnUserHash=partial(blocking, "authorize", "patient"))), \
             patch.object(chat_router, "ManageLinkedChat", return_value=SimpleNamespace(
                 require_active_link=partial(blocking, "link"))), \
             patch.object(chat_router, "_reserve_websocket_connection", AsyncMock(return_value=(failure != "quota", 5))):
            await chat_router.stream_chat_events(socket, 1, "patient")
        assert calls.count("close") == 1
        if failure is None:
            assert calls == ["authenticate", "authorize", "link", "commit", "close"]
            socket.send_json.assert_awaited_once()
            socket.accept.assert_not_awaited()
        else:
            assert "commit" not in calls
            assert transport == ["close"]
            assert socket.close.await_args.kwargs == (
                {"code": 4429, "reason": "5"} if failure == "quota" else {"code": 4403}
            )
    asyncio.run(exercise())
