"""Selected chat deletion: ownership, UTC deadlines, redaction and persistence."""
from datetime import datetime, timedelta
from collections.abc import Iterator
from unittest.mock import Mock, patch

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.manage_linked_chat_control import ManageLinkedChat
from core.database import Base
from entities.chat_message_entity import _ChatMessage
from schemas.chat import ChatMessageDelete
from controls.manage_account_control import ManageAccount
from api.chat_router import router
from api.dependencies import get_authenticated_app_principal, get_authorization_control, get_manage_linked_chat
from controls.authorization_control import AuthorizationControl
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from services.chat_connection_manager import ChatConnectionManager
from controls.dispatch_chat_message_alert_control import DispatchChatMessageAlert

NOW = datetime(2026, 9, 9, 12)
ChatFixture = tuple[ManageLinkedChat, int]


@pytest.fixture
def chat() -> Iterator[ChatFixture]:
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        links = LinkPatientCaregiver(db)
        code = links.generatePatientHash("patient-a")["data"]["patient_code"]
        link_id = int(links.requestPatientCaregiverLink("caregiver-a", code)["data"]["id"])
        with patch("controls.manage_linked_chat_control.utc_now", return_value=NOW):
            yield ManageLinkedChat(db), link_id
    engine.dispose()


def send(chat: ChatFixture, *, sender: str = "patient-a", age: timedelta = timedelta(hours=1), key: str = "delete_test_001") -> int:
    control, link_id = chat
    result = control.send_message(link_id=link_id, sender_hash=sender,
                                  client_message_id=key, body="Private medication text")
    row = control.db.get(_ChatMessage, result.message.message_id)
    row.created_at = NOW - age
    row.context_payload = {"medication_contexts": [{"medication_name": "secret"}]}
    row.medication_name = "secret"
    control.db.commit()
    return int(row.id)


def history(chat: ChatFixture, user: str) -> list[dict[str, object]]:
    control, link_id = chat
    return control.request_history(link_id=link_id, user_hash=user,
                                   before_message_id=None, limit=50)["data"]


@pytest.mark.parametrize("user", ["patient-a", "caregiver-a"])
def test_private_deletion_hides_only_selected_user_and_unread(chat: ChatFixture, user: str) -> None:
    message_id = send(chat, sender="caregiver-a" if user == "patient-a" else "patient-a",
                      age=timedelta(days=10))
    control, link_id = chat
    for _ in range(2):
        control.delete_messages(link_id=link_id, user_hash=user,
                                message_ids=[message_id], scope="me")
    control.db.expire_all()
    own = history(chat, user)[0]
    peer = history(chat, "caregiver-a" if user == "patient-a" else "patient-a")[0]
    assert own["hidden_for_me"] and own["body"] == "" and own["context"] is None
    assert not peer["hidden_for_me"] and peer["body"] == "Private medication text"
    assert control.request_unread_count(link_id=link_id, user_hash=user)["data"]["unread_count"] == 0
    assert control.db.get(_ChatMessage, message_id).read_at is None
    export = ManageAccount(control.db).exportAccountData(user)
    assert export["data"]["chat_messages"] == []
    send(chat, key="new_after_delete")
    assert not history(chat, user)[-1]["hidden_for_me"]


@pytest.mark.parametrize("age,allowed", [
    (timedelta(hours=24, microseconds=-1), True),
    (timedelta(hours=24), False),
    (timedelta(hours=25), False),
    (timedelta(seconds=-1), False),
])
def test_shared_deletion_enforces_server_time_and_redacts_snapshots(chat: ChatFixture, age: timedelta, allowed: bool) -> None:
    message_id = send(chat, age=age)
    control, link_id = chat
    if not allowed:
        with pytest.raises(HTTPException) as exc:
            control.delete_messages(link_id=link_id, user_hash="patient-a",
                                    message_ids=[message_id], scope="everyone")
        assert exc.value.status_code == 409
        assert history(chat, "patient-a")[0]["body"] == "Private medication text"
        return
    control.delete_messages(link_id=link_id, user_hash="patient-a",
                            message_ids=[message_id], scope="everyone")
    row = control.db.get(_ChatMessage, message_id)
    assert row.body == "" and row.context_payload is None and row.medication_name is None
    for user in ("patient-a", "caregiver-a"):
        assert history(chat, user)[0]["deleted_for_everyone"]
        assert control.request_unread_count(link_id=link_id, user_hash=user)["data"]["unread_count"] == 0
    # Retries after the deadline remain idempotent and cannot restore the original.
    with patch("controls.manage_linked_chat_control.utc_now", return_value=NOW + timedelta(days=2)):
        control.delete_messages(link_id=link_id, user_hash="patient-a",
                                message_ids=[message_id], scope="everyone")
    retry = control.send_message(link_id=link_id, sender_hash="patient-a",
                                 client_message_id="delete_test_001", body="resurrect")
    assert not retry.created and retry.message.to_response_dict()["body"] == ""


def test_shared_selection_is_atomic_and_other_sender_cannot_be_deleted(chat: ChatFixture) -> None:
    own = send(chat)
    peer = send(chat, sender="caregiver-a", key="peer_delete_test")
    control, link_id = chat
    with pytest.raises(HTTPException) as exc:
        control.delete_messages(link_id=link_id, user_hash="patient-a",
                                message_ids=[own, peer], scope="everyone")
    assert exc.value.status_code == 403
    assert all(not item["deleted_for_everyone"] for item in history(chat, "patient-a"))
    with pytest.raises(HTTPException):
        control.delete_messages(link_id=link_id, user_hash="stranger",
                                message_ids=[own], scope="me")
    with pytest.raises(HTTPException) as missing:
        control.delete_messages(link_id=link_id, user_hash="patient-a",
                                message_ids=[own, 9999], scope="me")
    assert missing.value.status_code == 404
    assert not history(chat, "patient-a")[0]["hidden_for_me"]


@pytest.mark.parametrize("ids,scope", [([], "me"), ([0], "me"), ([True], "me"),
                                       ([1] * 51, "me"), ([1], "all")])
def test_delete_request_is_bounded_and_typed(ids: list[int], scope: str) -> None:
    with pytest.raises(ValidationError):
        ChatMessageDelete(message_ids=ids, scope=scope)


def test_api_uses_verified_identity_not_requested_user_hash(chat: ChatFixture) -> None:
    message_id = send(chat)
    control, link_id = chat
    app = FastAPI()
    app.state.chat_connection_manager = ChatConnectionManager()
    app.include_router(router, prefix="/api/v1/chat")
    app.dependency_overrides[get_authenticated_app_principal] = lambda: AuthenticatedPrincipal(
        subject="caregiver", issuer="test", user_hash="caregiver-a",
    )
    app.dependency_overrides[get_authorization_control] = lambda: AuthorizationControl(control.db)
    app.dependency_overrides[get_manage_linked_chat] = lambda: control
    with TestClient(app) as client:
        url = f"/api/v1/chat/links/{link_id}/messages/delete?user_hash=patient-a"
        rejected = client.post(url, json={"message_ids": [message_id], "scope": "everyone"})
        assert rejected.status_code == 403
        accepted = client.post(url, json={"message_ids": [message_id], "scope": "me"})
        assert accepted.status_code == 200
        assert client.post(url, json={"message_ids": [], "scope": "me"}).status_code == 422
    assert history(chat, "caregiver-a")[0]["hidden_for_me"]
    assert not history(chat, "patient-a")[0]["hidden_for_me"]


def test_foreign_link_selection_cannot_delete_a_row(chat: ChatFixture) -> None:
    message_id = send(chat)
    control, link_id = chat
    links = LinkPatientCaregiver(control.db)
    code = links.generatePatientHash("other-patient")["data"]["patient_code"]
    other_id = int(links.requestPatientCaregiverLink("caregiver-a", code)["data"]["id"])
    with pytest.raises(HTTPException) as exc:
        control.delete_messages(link_id=other_id, user_hash="caregiver-a",
                                message_ids=[message_id], scope="me")
    assert exc.value.status_code == 404
    assert not history(chat, "caregiver-a")[0]["hidden_for_me"]


def test_queued_push_rechecks_deletion_before_delivery(chat: ChatFixture) -> None:
    message_id = send(chat)
    control, link_id = chat
    control.delete_messages(link_id=link_id, user_hash="patient-a", message_ids=[message_id], scope="everyone")
    push = Mock()
    result = DispatchChatMessageAlert(control.db, push).notify_new_message(
        recipient_hash="caregiver-a", link_id=link_id, message_id=message_id,
        message_body="stale sensitive preview",
    )
    assert result.success_count == 0
    push.send_notification.assert_not_called()
