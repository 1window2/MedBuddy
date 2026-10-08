# File Name: test_chat_websocket_handshake.py
# Role: Connects to the chat stream of the application main.create_app() builds, through
#   Starlette's TestClient, and pins how the stream refuses a handshake and closes a socket.
#
# A handshake that is refused is closed BEFORE it is accepted. A real server answers such a
# close with HTTP 403, so the client sees a failed connection attempt (and backs off) and the
# code below is not delivered to it. The TestClient reports the code the application passed,
# which is what these tests pin; they fail if a refusal is accepted first. Codes sent on an
# accepted socket do reach the client.
#
# Close codes of the stream (api/chat_router.py):
# - 4401 authentication failed            - 4403 App Check or ownership refused
# - 4404 no active link for this user     - 4409 API contract header mismatch
# - 4429 connection attempts over quota (reason = seconds to wait), connection cap, or pings
#        sent faster than the minimum interval (no reason)
# - 1013 quota storage unavailable        - 1011 any other handshake failure
# - 4408 idle timeout    - 1009 frame too large    - 1003 anything that is not the text "ping"
#
# Routers, authentication, authorization, the link control and the connection manager are the
# production objects. Replaced: the database (foreign-key-enforcing in-memory SQLite) and the
# Redis client of the quota store (support.fakes.FakeRedis, a real counter).

import asyncio
from collections.abc import Callable, Iterator
from dataclasses import dataclass

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session, sessionmaker
from starlette.websockets import WebSocketDisconnect

import main
from api import chat_router
from core.config import settings
from core.request_rate_limits import RequestRateLimitStore
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from support.db import seed_account
from support.fakes import FakeRedis

_PATIENT = "patient-a"
_CAREGIVER = "caregiver-a"


# Class Name: _ChatStream
# Role: What the `chat_stream` fixture hands to a test.
# Attributes:
# - client (TestClient): Client of the application; the lifespan is not started.
# - app (FastAPI): Application built by main.create_app() for this test.
# - factory (sessionmaker[Session]): Session factory of the handshake's database.
# - link_id (int): Active link between the patient and the caregiver.
# - redis (FakeRedis): Counter backend of the quota store; set fail_with to simulate an outage.
# - headers (dict[str, str]): Headers of a current client: the API contract version.
@dataclass
class _ChatStream:
    client: TestClient
    app: FastAPI
    factory: sessionmaker[Session]
    link_id: int
    redis: FakeRedis
    headers: dict[str, str]

    # Function Name: path
    # Description:
    # - Builds the stream URL of a link for one development-mode user.
    # Parameters:
    # - user_hash (str): Account the connection claims in disabled-authentication mode.
    # - link_id (int | None): Link to open; the fixture's active link when omitted.
    # Returns:
    # - Request path with the user_hash query.
    def path(self, user_hash: str = _PATIENT, link_id: int | None = None) -> str:
        target = self.link_id if link_id is None else link_id
        return f"/api/v1/chat/links/{target}/stream?user_hash={user_hash}"


# Function Name: chat_stream
# Description:
# - Builds the application in disabled-authentication mode with quotas enabled on a fake Redis
#   that the store requires, points the handshake at the test database and seeds one active link.
# Parameters:
# - fk_session_factory (sessionmaker[Session]): Factory on the foreign-key-enforcing engine.
# - monkeypatch (pytest.MonkeyPatch): Restores settings and module state after the test.
# Returns:
# - Iterator yielding the _ChatStream.
@pytest.fixture
def chat_stream(
    fk_session_factory: sessionmaker[Session],
    monkeypatch: pytest.MonkeyPatch,
) -> Iterator[_ChatStream]:
    monkeypatch.setattr(settings, "AUTH_MODE", "disabled")
    monkeypatch.setattr(settings, "FIREBASE_APP_CHECK_REQUIRED", False)
    monkeypatch.setattr(settings, "RATE_LIMIT_ENABLED", True)
    redis = FakeRedis()
    store = RequestRateLimitStore(
        redis_url="redis://unused",
        require_redis=True,
        redis_client=redis,
    )
    monkeypatch.setattr(main, "RequestRateLimitStore", lambda **_options: store)
    monkeypatch.setattr(chat_router, "SessionLocal", fk_session_factory)
    app = main.create_app()

    with fk_session_factory() as db:
        seed_account(db, _PATIENT, _CAREGIVER)
        link = _PatientCaregiverLink(
            patient_hash=_PATIENT,
            caregiver_hash=_CAREGIVER,
            linked=True,
        )
        db.add(link)
        db.commit()
        link_id = int(link.id)

    yield _ChatStream(
        client=TestClient(app),
        app=app,
        factory=fk_session_factory,
        link_id=link_id,
        redis=redis,
        headers={"x-medbuddy-api-contract": settings.API_CONTRACT_VERSION},
    )


# Function Name: _refusal_before_accept
# Description:
# - Attempts the handshake and returns the close the application answered it with. The
#   connection must never open: an accepted handshake fails the test.
# Parameters:
# - stream (_ChatStream): Application and client under test.
# - path (str): Stream URL to open.
# - headers (dict[str, str]): Handshake headers.
# Returns:
# - WebSocketDisconnect carrying the close code and reason the application passed.
def _refusal_before_accept(
    stream: _ChatStream,
    path: str,
    headers: dict[str, str],
) -> WebSocketDisconnect:
    with pytest.raises(WebSocketDisconnect) as refused:
        with stream.client.websocket_connect(path, headers=headers):
            pytest.fail("A refused handshake must not be accepted.")
    return refused.value


# Function Name: _is_connected
# Description:
# - Asks the application's connection manager whether the user still has a registered socket.
# Parameters:
# - stream (_ChatStream): Application under test.
# - user_hash (str): Participant to look up on the fixture's link.
# Returns:
# - True while at least one socket of the user is registered.
def _is_connected(stream: _ChatStream, user_hash: str = _PATIENT) -> bool:
    return asyncio.run(
        stream.app.state.chat_connection_manager.is_user_connected(
            link_id=stream.link_id,
            user_hash=user_hash,
        )
    )


# Function Name: _without_contract_header
# Description:
# - Arranges a client that does not send the API contract header.
# Parameters:
# - stream (_ChatStream): Application and client under test.
# - monkeypatch (pytest.MonkeyPatch): Unused.
# Returns:
# - Stream URL and handshake headers.
def _without_contract_header(
    stream: _ChatStream,
    monkeypatch: pytest.MonkeyPatch,
) -> tuple[str, dict[str, str]]:
    return stream.path(), {}


# Function Name: _with_malformed_authorization
# Description:
# - Arranges an Authorization header that names a scheme but carries no token.
# Parameters:
# - stream (_ChatStream): Application and client under test.
# - monkeypatch (pytest.MonkeyPatch): Unused.
# Returns:
# - Stream URL and handshake headers.
def _with_malformed_authorization(
    stream: _ChatStream,
    monkeypatch: pytest.MonkeyPatch,
) -> tuple[str, dict[str, str]]:
    return stream.path(), {**stream.headers, "Authorization": "Bearer"}


# Function Name: _without_app_check_token
# Description:
# - Arranges a deployment that requires App Check and a client that sends no token.
# Parameters:
# - stream (_ChatStream): Application and client under test.
# - monkeypatch (pytest.MonkeyPatch): Turns the App Check requirement on for this test.
# Returns:
# - Stream URL and handshake headers.
def _without_app_check_token(
    stream: _ChatStream,
    monkeypatch: pytest.MonkeyPatch,
) -> tuple[str, dict[str, str]]:
    monkeypatch.setattr(settings, "FIREBASE_APP_CHECK_REQUIRED", True)
    return stream.path(), stream.headers


# Function Name: _after_unlinking
# Description:
# - Arranges a link that was removed after the client opened the chat.
# Parameters:
# - stream (_ChatStream): Application and client under test.
# - monkeypatch (pytest.MonkeyPatch): Unused.
# Returns:
# - Stream URL and handshake headers.
def _after_unlinking(
    stream: _ChatStream,
    monkeypatch: pytest.MonkeyPatch,
) -> tuple[str, dict[str, str]]:
    with stream.factory() as db:
        db.get(_PatientCaregiverLink, stream.link_id).linked = False
        db.commit()
    return stream.path(), stream.headers


# Function Name: _for_unknown_link
# Description:
# - Arranges a link identifier that was never issued.
# Parameters:
# - stream (_ChatStream): Application and client under test.
# - monkeypatch (pytest.MonkeyPatch): Unused.
# Returns:
# - Stream URL and handshake headers.
def _for_unknown_link(
    stream: _ChatStream,
    monkeypatch: pytest.MonkeyPatch,
) -> tuple[str, dict[str, str]]:
    return stream.path(link_id=stream.link_id + 999), stream.headers


# Function Name: _as_outsider
# Description:
# - Arranges an account that takes no part in the link.
# Parameters:
# - stream (_ChatStream): Application and client under test.
# - monkeypatch (pytest.MonkeyPatch): Unused.
# Returns:
# - Stream URL and handshake headers.
def _as_outsider(
    stream: _ChatStream,
    monkeypatch: pytest.MonkeyPatch,
) -> tuple[str, dict[str, str]]:
    return stream.path(user_hash="outsider-a"), stream.headers


# Function Name: _during_quota_storage_outage
# Description:
# - Arranges an outage of the Redis the quota store requires.
# Parameters:
# - stream (_ChatStream): Application and client under test.
# - monkeypatch (pytest.MonkeyPatch): Unused.
# Returns:
# - Stream URL and handshake headers.
def _during_quota_storage_outage(
    stream: _ChatStream,
    monkeypatch: pytest.MonkeyPatch,
) -> tuple[str, dict[str, str]]:
    stream.redis.fail_with = ConnectionError("redis is down")
    return stream.path(), stream.headers


# Function Name: _without_connection_manager
# Description:
# - Arranges an application whose connection manager was never initialized.
# Parameters:
# - stream (_ChatStream): Application and client under test.
# - monkeypatch (pytest.MonkeyPatch): Unused.
# Returns:
# - Stream URL and handshake headers.
def _without_connection_manager(
    stream: _ChatStream,
    monkeypatch: pytest.MonkeyPatch,
) -> tuple[str, dict[str, str]]:
    stream.app.state.chat_connection_manager = None
    return stream.path(), stream.headers


# Function Name: _with_failing_database
# Description:
# - Arranges an unexpected failure while the handshake resolves the account.
# Parameters:
# - stream (_ChatStream): Application and client under test.
# - monkeypatch (pytest.MonkeyPatch): Replaces the authorization control with a failing one.
# Returns:
# - Stream URL and handshake headers.
def _with_failing_database(
    stream: _ChatStream,
    monkeypatch: pytest.MonkeyPatch,
) -> tuple[str, dict[str, str]]:
    # Function Name: fail
    # Description:
    # - Stands in for AuthorizationControl and fails like a lost database connection.
    # Parameters:
    # - _db (Session): Handshake session; unused.
    # Returns:
    # - No normal result; raises RuntimeError.
    def fail(_db: Session) -> object:
        raise RuntimeError("database connection lost")

    monkeypatch.setattr(chat_router, "AuthorizationControl", fail)
    return stream.path(), stream.headers


_Arrange = Callable[[_ChatStream, pytest.MonkeyPatch], tuple[str, dict[str, str]]]


# Function Name: test_linked_participant_gets_ready_event_and_pong
# Description:
# - A participant of an active link is connected, told the stream is ready and answered on
#   ping; the registration is released when the client leaves.
# Parameters:
# - chat_stream (_ChatStream): Application and client under test.
# Returns:
# - None.
def test_linked_participant_gets_ready_event_and_pong(chat_stream: _ChatStream) -> None:
    with chat_stream.client.websocket_connect(
        chat_stream.path(), headers=chat_stream.headers
    ) as socket:
        assert socket.receive_json() == {
            "type": "chat_ready",
            "link_id": chat_stream.link_id,
        }
        assert _is_connected(chat_stream)
        socket.send_text("ping")
        assert socket.receive_json() == {"type": "pong"}

    assert not _is_connected(chat_stream)


# Function Name: test_refused_handshake_is_closed_before_accept_with_its_code
# Description:
# - Each refusal is answered without accepting the connection, with the close code of its
#   cause, and registers no connection.
# Parameters:
# - chat_stream (_ChatStream): Application and client under test.
# - monkeypatch (pytest.MonkeyPatch): Passed to the arrangement of the case.
# - arrange (_Arrange): Prepares the refusal and returns the URL and headers to connect with.
# - expected_code (int): Close code the application must pass.
# Returns:
# - None.
@pytest.mark.parametrize(
    ("arrange", "expected_code"),
    [
        pytest.param(_with_malformed_authorization, 4401, id="authentication-4401"),
        pytest.param(_without_app_check_token, 4403, id="app-check-4403"),
        pytest.param(_after_unlinking, 4404, id="unlinked-4404"),
        pytest.param(_for_unknown_link, 4404, id="unknown-link-4404"),
        pytest.param(_as_outsider, 4404, id="outsider-4404"),
        pytest.param(_without_contract_header, 4409, id="contract-4409"),
        pytest.param(_during_quota_storage_outage, 1013, id="quota-storage-1013"),
        pytest.param(_without_connection_manager, 1011, id="no-manager-1011"),
        pytest.param(_with_failing_database, 1011, id="unexpected-1011"),
    ],
)
def test_refused_handshake_is_closed_before_accept_with_its_code(
    chat_stream: _ChatStream,
    monkeypatch: pytest.MonkeyPatch,
    arrange: _Arrange,
    expected_code: int,
) -> None:
    manager = chat_stream.app.state.chat_connection_manager
    path, headers = arrange(chat_stream, monkeypatch)

    refused = _refusal_before_accept(chat_stream, path, headers)

    assert refused.code == expected_code
    assert refused.reason == ""
    chat_stream.app.state.chat_connection_manager = manager
    assert not _is_connected(chat_stream)
    assert not _is_connected(chat_stream, "outsider-a")


# Function Name: test_connection_quota_refusal_carries_the_wait_as_reason
# Description:
# - With one connection attempt allowed per minute, the second attempt of the same account is
#   refused before accept with 4429 and the seconds left in the quota window as the reason.
# Parameters:
# - chat_stream (_ChatStream): Application and client under test.
# - monkeypatch (pytest.MonkeyPatch): Lowers the per-minute connection quota.
# Returns:
# - None.
def test_connection_quota_refusal_carries_the_wait_as_reason(
    chat_stream: _ChatStream,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "CHAT_WEBSOCKET_CONNECTIONS_PER_MINUTE", 1)
    with chat_stream.client.websocket_connect(
        chat_stream.path(), headers=chat_stream.headers
    ) as socket:
        assert socket.receive_json()["type"] == "chat_ready"

    refused = _refusal_before_accept(chat_stream, chat_stream.path(), chat_stream.headers)

    assert refused.code == 4429
    assert refused.reason.isdigit()
    assert 1 <= int(refused.reason) <= 60
    assert not _is_connected(chat_stream)


# Function Name: test_frames_other_than_a_text_ping_close_the_stream
# Description:
# - On an established stream a binary frame and a text other than "ping" are closed with 1003,
#   an oversized text with 1009 and a ping inside the minimum interval with 4429; none of them
#   escapes as a server error and each releases the registration.
# Parameters:
# - chat_stream (_ChatStream): Application and client under test.
# - frame (str): Kind of frame the client sends after the ready event.
# - expected_code (int): Close code the client must receive.
# Returns:
# - None.
@pytest.mark.parametrize(
    ("frame", "expected_code"),
    [
        ("binary", 1003),
        ("other_text", 1003),
        ("oversized_text", 1009),
        ("second_ping", 4429),
    ],
)
def test_frames_other_than_a_text_ping_close_the_stream(
    chat_stream: _ChatStream,
    frame: str,
    expected_code: int,
) -> None:
    with chat_stream.client.websocket_connect(
        chat_stream.path(), headers=chat_stream.headers
    ) as socket:
        assert socket.receive_json()["type"] == "chat_ready"
        if frame == "binary":
            socket.send_bytes(b"\x00\x01")
        elif frame == "other_text":
            socket.send_text("hello")
        elif frame == "oversized_text":
            socket.send_text("x" * (settings.CHAT_WEBSOCKET_MAX_FRAME_BYTES + 1))
        else:
            socket.send_text("ping")
            assert socket.receive_json() == {"type": "pong"}
            socket.send_text("ping")
        with pytest.raises(WebSocketDisconnect) as closed:
            socket.receive_json()

    assert closed.value.code == expected_code
    assert not _is_connected(chat_stream)
