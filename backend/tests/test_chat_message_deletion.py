# 파일명: test_chat_message_deletion.py
# 역할: 채팅 개인·전체 삭제의 시간 제한, 원자성, 인증 범위 및 개인정보 제거를 검증한다.
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


# 함수이름: chat
# 함수역할:
# - 활성 환자·보호자 연동과 고정 서버 시간을 가진 격리 채팅 DB를 제공하고 종료 시 자원을 해제한다.
# 매개변수:
# - 없음.
# 반환값:
# - 고정 서버 시간에서 채팅 control과 활성 연동 ID를 제공함.
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


# 함수이름: send
# 함수역할:
# - 지정 발신자의 메시지를 저장한 뒤 작성 시각과 민감한 약 스냅샷을 설정하여 삭제 조건을 준비한다.
# 매개변수:
# - chat (ChatFixture): 격리 채팅 control과 활성 환자·보호자 연동 ID.
# - sender (str): 채팅 메시지를 보낼 환자 또는 보호자 해시.
# - age (timedelta): 메시지 전송 후 지난 시간.
# - key (str): 재전송을 구분할 클라이언트 메시지 식별자.
# 반환값:
# - int: 작성 시각과 스냅샷을 설정한 저장 메시지 ID.
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


# 함수이름: history
# 함수역할:
# - 지정 사용자의 연동 채팅 기록을 최대 50건 조회하여 응답 데이터만 반환한다.
# 매개변수:
# - chat (ChatFixture): 격리 채팅 control과 활성 환자·보호자 연동 ID.
# - user (str): 기록·미읽음·삭제 상태를 확인할 연동 참여자 해시.
# 반환값:
# - list[dict[str, object]]: 선택한 참여자에게 보이는 메시지 응답 사전 목록.
def history(chat: ChatFixture, user: str) -> list[dict[str, object]]:
    control, link_id = chat
    return control.request_history(link_id=link_id, user_hash=user,
                                   before_message_id=None, limit=50)["data"]


# 함수이름: test_private_deletion_hides_only_selected_user_and_unread
# 함수역할:
# - 개인 삭제가 본인 기록·미읽음·내보내기에서만 숨겨지고 상대 내용과 원본 읽음 상태는 유지되는지 검증한다.
# 매개변수:
# - chat (ChatFixture): 격리 채팅 control과 활성 환자·보호자 연동 ID.
# - user (str): 기록·미읽음·삭제 상태를 확인할 연동 참여자 해시.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_shared_deletion_enforces_server_time_and_redacts_snapshots
# 함수역할:
# - 전체 삭제의 서버 시간 경계를 검증하고, 허용 시 양측 본문·약 스냅샷·미읽음 및 재전송 응답이 삭제 상태를 유지하는지 확인한다.
# 매개변수:
# - chat (ChatFixture): 격리 채팅 control과 활성 환자·보호자 연동 ID.
# - age (timedelta): 메시지 전송 후 지난 시간.
# - allowed (bool): 해당 메시지 경과 시간이 전체 삭제 허용 기간에 속하는지 여부.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_shared_selection_is_atomic_and_other_sender_cannot_be_deleted
# 함수역할:
# - 다른 발신자나 없는 메시지가 섞인 삭제 선택을 거절하고 선택된 정상 메시지도 부분 삭제하지 않는지 검증한다.
# 매개변수:
# - chat (ChatFixture): 격리 채팅 control과 활성 환자·보호자 연동 ID.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_delete_request_is_bounded_and_typed
# 함수역할:
# - 메시지 ID 목록과 삭제 범위가 스키마의 크기·타입 제약을 어기면 ValidationError가 발생하는지 검증한다.
# 매개변수:
# - ids (list[int]): 요청 유효성을 검증할 선택 채팅 메시지 ID 목록.
# - scope (str): 요청한 개인 또는 전체 채팅 삭제 범위.
# 반환값:
# - 없음 (None).
@pytest.mark.parametrize("ids,scope", [([], "me"), ([0], "me"), ([True], "me"),
                                       ([1] * 51, "me"), ([1], "all")])
def test_delete_request_is_bounded_and_typed(ids: list[int], scope: str) -> None:
    with pytest.raises(ValidationError):
        ChatMessageDelete(message_ids=ids, scope=scope)


# 함수이름: test_api_uses_verified_identity_not_requested_user_hash
# 함수역할:
# - 요청의 user_hash 대신 인증된 사용자에게만 삭제를 적용하고 잘못된 권한·빈 선택은 거절하는지 검증한다.
# 매개변수:
# - chat (ChatFixture): 격리 채팅 control과 활성 환자·보호자 연동 ID.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_foreign_link_selection_cannot_delete_a_row
# 함수역할:
# - 다른 연동의 메시지를 선택하면 404로 거절하고 기존 메시지의 개인 숨김 상태를 유지하는지 검증한다.
# 매개변수:
# - chat (ChatFixture): 격리 채팅 control과 활성 환자·보호자 연동 ID.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_queued_push_rechecks_deletion_before_delivery
# 함수역할:
# - 예약 후 삭제된 메시지는 실제 푸시 전달 전에 재확인하여 전송하지 않는지 검증한다.
# 매개변수:
# - chat (ChatFixture): 격리 채팅 control과 활성 환자·보호자 연동 ID.
# 반환값:
# - 없음 (None).
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
