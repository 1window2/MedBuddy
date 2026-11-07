# 파일명: test_slot_check_notification.py
# 역할: 보호자 복용 확인 요청의 서버 문맥, 동작 지원 기기 분리와 전송 결과를 검증한다.

"""보호자 확인 요청의 서버 검증·Android 데이터 전달·재전송 식별자를 검증한다."""
from collections.abc import Iterator
from datetime import timedelta
from types import SimpleNamespace
from typing import Any
from unittest.mock import patch

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from boundaries.push_notification_boundary import FirebasePushNotificationBoundary, PushDeliveryResult
from controls.dispatch_chat_message_alert_control import DispatchChatMessageAlert
from controls.manage_linked_chat_control import ManageLinkedChat  # noqa: F401
from core.application_clock import application_today
from core.database import Base
from entities.chat_message_entity import _ChatMessage
from entities.device_push_token_entity import _DevicePushToken
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.user_account_entity import _UserAccount, utc_now
from entities.user_setting_entity import _UserSetting
from support.fakes import RecordingPushBoundary
from controls.manage_push_token_control import ManagePushToken
from services.push_recipient_resolver import PushRecipientResolver
from schemas.medication import PushTokenRegistration


# 함수이름: fixture
# 함수역할:
# - 환자·보호자 연동과 당일 확인 요청, 지원 기능이 다른 세 기기를 만들고 세션·엔진을 정리한다.
# 매개변수:
# - 없음.
# 반환값:
# - Iterator[tuple]; 세션·연동 ID·메시지 ID.
@pytest.fixture
def fixture() -> Iterator[tuple[Session, int, int]]:
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        db.add_all([_UserAccount(user_hash=value) for value in ("patient", "caregiver")])
        db.flush()
        link = _PatientCaregiverLink(patient_hash="patient", caregiver_hash="caregiver", linked=True)
        db.add(link)
        db.flush()
        row = _ChatMessage(link_id=link.id, sender_hash="caregiver", client_message_id="check-request",
            body="아침 약 복용을 확인해 주세요.", message_kind="slot_check_request",
            context_payload={"schedule_context": {"slot_key": "morning", "schedule_date": application_today().isoformat()}})
        db.add(row)
        db.add_all([_DevicePushToken(user_hash="patient", token=token, platform=platform,
            enabled=True, supports_caregiver_actions=True, supports_slot_check_actions=actions)
            for token, platform, actions in (("android-actions", "android", True),
                                            ("legacy-android", "android", False),
                                            ("ios-fallback", "ios", False))])
        db.commit()
        yield db, link.id, row.id
    engine.dispose()


# 함수이름: dispatch
# 함수역할:
# - 저장 문맥과 충돌하는 호출 인수로 알림을 요청하여 서버 문맥 우선순위를 검증할 전송 기록을 모은다.
# 매개변수:
# - fixture: tuple[Session, int, int]; 격리 세션·연동 ID·확인 요청 메시지 ID.
# - kwargs: dict; 알림 발송의 추가 옵션.
# 반환값:
# - tuple; 푸시 호출 목록과 전달 결과.
def dispatch(fixture: tuple[Session, int, int], **kwargs: str) -> tuple[list[dict[str, Any]], PushDeliveryResult]:
    db, link_id, message_id = fixture
    boundary = RecordingPushBoundary()
    result = DispatchChatMessageAlert(db, boundary).notify_new_message(
        recipient_hash="patient", link_id=link_id, message_id=message_id,
        message_body="무시할 본문", slot_key="evening", **kwargs)
    return boundary.calls, result


# 함수이름: test_action_payload_uses_persisted_context_and_stable_event
# 함수역할:
# - 동작 지원 기기만 저장된 복용 문맥과 안정된 이벤트 ID를 받고 레거시 기기는 일반 알림으로 분리되는지 확인한다.
# 매개변수:
# - fixture: tuple[Session, int, int]; 격리 세션·연동 ID·확인 요청 메시지 ID.
# 반환값:
# - None.
def test_action_payload_uses_persisted_context_and_stable_event(fixture: tuple[Session, int, int]) -> None:
    first, _ = dispatch(fixture)
    second, _ = dispatch(fixture)
    assert len(first) == 2
    action, fallback = first
    assert action["tokens"] == ["android-actions"]
    assert set(fallback["tokens"]) == {"legacy-android", "ios-fallback"}
    assert "action_version" not in fallback["data"]
    data = action["data"]
    assert data["action_version"] == "1" and data["slot_key"] == "morning"
    assert data["patient_hash"] == data["recipient_hash"] == "patient"
    assert data["schedule_date"] == application_today().isoformat()
    assert data["message_id"] == str(fixture[2])
    assert data["event_id"] == second[0]["data"]["event_id"]
    assert "medication_ids" not in data


# 함수이름: test_untrusted_or_stale_context_has_no_completion_action
# 함수역할:
# - 과거·미래·잘못된 슬롯·발신자·메시지 종류에는 완료 동작을 부여하지 않는지 확인한다.
# 매개변수:
# - fixture: tuple[Session, int, int]; 격리 세션·연동 ID·확인 요청 메시지 ID.
# - change: str; 오래된 문맥 또는 알림 억제 조건.
# 반환값:
# - None.
@pytest.mark.parametrize("change", ["yesterday", "future", "invalid_slot", "patient_sender", "text"])
def test_untrusted_or_stale_context_has_no_completion_action(fixture: tuple[Session, int, int], change: str) -> None:
    db, _, message_id = fixture
    row = db.get(_ChatMessage, message_id)
    context = dict(row.context_payload["schedule_context"])
    if change in ("yesterday", "future"):
        context["schedule_date"] = (application_today() + timedelta(days=-1 if change == "yesterday" else 1)).isoformat()
    elif change == "invalid_slot":
        context["slot_key"] = "as_needed"
    elif change == "patient_sender":
        row.sender_hash = "patient"
    else:
        row.message_kind = "text"
    row.context_payload = {"schedule_context": context}
    db.commit()
    calls, _ = dispatch(fixture)
    assert all("action_version" not in call["data"] for call in calls)
    assert len(calls) == (0 if change == "patient_sender" else 1)


# 함수이름: test_suppressed_request_never_produces_an_action
# 함수역할:
# - 읽음·삭제·숨김·연동 해제·알림 비활성 상태에는 확인 동작과 푸시를 모두 보내지 않는지 확인한다.
# 매개변수:
# - fixture: tuple[Session, int, int]; 격리 세션·연동 ID·확인 요청 메시지 ID.
# - change: str; 오래된 문맥 또는 알림 억제 조건.
# 반환값:
# - None.
@pytest.mark.parametrize("change", ["read", "deleted", "hidden", "unlinked", "disabled"])
def test_suppressed_request_never_produces_an_action(fixture: tuple[Session, int, int], change: str) -> None:
    db, link_id, message_id = fixture
    row = db.get(_ChatMessage, message_id)
    if change == "read":
        row.read_at = utc_now()
    elif change == "deleted":
        row.deleted_for_everyone_at = utc_now()
    elif change == "hidden":
        row.patient_deleted_at = utc_now()
    elif change == "unlinked":
        db.get(_PatientCaregiverLink, link_id).linked = False
    else:
        db.add(_UserSetting(user_hash="patient", chat_notifications_enabled=False))
    db.commit()
    assert dispatch(fixture)[0] == []


# Function Name: test_type_only_keeps_private_preview_out_of_action_data
# Description:
# - Requires type-only privacy to remove the medication preview from every actionable data field.
# Parameters:
# - fixture: tuple[Session, int, int]; isolated session, link and slot-check message IDs.
# Returns:
# - None.
def test_type_only_keeps_private_preview_out_of_action_data(fixture: tuple[Session, int, int]) -> None:
    db, _, _ = fixture
    db.add(_UserSetting(user_hash="patient", notification_detail_mode="type_only"))
    db.commit()
    calls, _ = dispatch(fixture)
    assert calls[0]["data"]["message_preview"] == ""
    assert not any("아침 약" in str(value) for value in calls[0]["data"].values())


# 함수이름: test_gateway_uses_high_priority_data_only_for_slot_check_action
# 함수역할:
# - 슬롯 확인 동작은 OS 알림 없이 Android high 우선순위 데이터 메시지로 보내는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_gateway_uses_high_priority_data_only_for_slot_check_action() -> None:
    gateway = FirebasePushNotificationBoundary.__new__(FirebasePushNotificationBoundary)
    gateway._app = object()
    response = SimpleNamespace(success_count=1, responses=[SimpleNamespace(success=True)])
    data = {"type": "linked_chat_message", "message_kind": "slot_check_request", "action_version": "1"}
    with patch("boundaries.push_notification_boundary.messaging.send_each_for_multicast", return_value=response) as send:
        gateway.send_notification(tokens=["android"], title="title", body="body", data=data)
    message = send.call_args.args[0]
    assert message.notification is None and message.android.notification is None
    assert message.android.priority == "high" and message.data == data


# 함수이름: test_new_capability_is_independent_and_legacy_reregistration_resets_it
# 함수역할:
# - 슬롯 확인 기능은 보호자 동작 기능과 독립적으로 등록되며 레거시 재등록과 iOS에는 활성화되지 않는지 확인한다.
# 매개변수:
# - fixture: tuple[Session, int, int]; 격리 세션·연동 ID·확인 요청 메시지 ID.
# 반환값:
# - None.
def test_new_capability_is_independent_and_legacy_reregistration_resets_it(fixture: tuple[Session, int, int]) -> None:
    db, _, _ = fixture
    control = ManagePushToken(db)
    token = "separate-capability-token"
    control.registerPushToken("patient", token, "android", supports_slot_check_actions=True)
    recipient = PushRecipientResolver(db).resolve("patient")
    assert token in recipient.slot_check_action_tokens
    assert token not in recipient.action_tokens
    control.registerPushToken("patient", token, "android", supports_caregiver_actions=True)
    recipient = PushRecipientResolver(db).resolve("patient")
    assert token in recipient.action_tokens
    assert token not in recipient.slot_check_action_tokens
    assert PushTokenRegistration(token=token, supports_caregiver_actions=True).supports_slot_check_actions is False
    control.registerPushToken("patient", token, "ios", supports_slot_check_actions=True)
    assert token not in PushRecipientResolver(db).resolve("patient").slot_check_action_tokens


# 함수이름: test_capability_registration_route_uses_authenticated_owner
# 함수역할:
# - 토큰 등록 경로가 인증된 소유자에게 슬롯 확인 기능을 저장하는지 확인한다.
# 매개변수:
# - fixture: tuple[Session, int, int]; 격리 세션·연동 ID·확인 요청 메시지 ID.
# 반환값:
# - None.
def test_capability_registration_route_uses_authenticated_owner(fixture: tuple[Session, int, int]) -> None:
    from api.router import register_push_token
    from entities.authenticated_principal_entity import AuthenticatedPrincipal
    db, _, _ = fixture
    token = "new-capability-route-token"
    register_push_token(
        PushTokenRegistration(token=token, platform="android", supports_slot_check_actions=True),
        AuthenticatedPrincipal(subject="patient-subject", issuer="test", user_hash="patient"),
        ManagePushToken(db),
        revocation=None,
    )
    row = db.query(_DevicePushToken).filter_by(token=token).one()
    assert row.user_hash == "patient" and row.supports_slot_check_actions


# 함수이름: test_mixed_capability_delivery_preserves_retryable_and_invalid_results
# 함수역할:
# - 동작 지원 여부로 나눠 보내도 재시도 실패와 무효 토큰 결과를 합치고 무효 등록만 비활성화하는지 확인한다.
# 매개변수:
# - fixture: tuple[Session, int, int]; 격리 세션·연동 ID·확인 요청 메시지 ID.
# 반환값:
# - None.
def test_mixed_capability_delivery_preserves_retryable_and_invalid_results(fixture: tuple[Session, int, int]) -> None:
    db, link_id, message_id = fixture
    boundary = RecordingPushBoundary(invalid_tokens=("legacy-android",), retryable=1)
    result = DispatchChatMessageAlert(db, boundary).notify_new_message(
        recipient_hash="patient", link_id=link_id, message_id=message_id, message_body="")
    assert len(boundary.calls) == 2
    assert not result.all_valid_targets_succeeded
    assert result.invalid_tokens == ("legacy-android",)
    assert db.query(_DevicePushToken).filter_by(token="legacy-android").one().enabled is False


# 함수이름: test_old_action_capability_alone_keeps_os_notification
# 함수역할:
# - 기존 보호자 동작 지원만 있는 기기는 슬롯 확인 동작 대신 일반 OS 채팅 알림을 받는지 확인한다.
# 매개변수:
# - fixture: tuple[Session, int, int]; 격리 세션·연동 ID·확인 요청 메시지 ID.
# 반환값:
# - None.
def test_old_action_capability_alone_keeps_os_notification(fixture: tuple[Session, int, int]) -> None:
    db, _, _ = fixture
    db.query(_DevicePushToken).update({"supports_slot_check_actions": False})
    db.commit()
    calls, _ = dispatch(fixture)
    assert len(calls) == 1
    assert "action_version" not in calls[0]["data"]
    gateway = FirebasePushNotificationBoundary.__new__(FirebasePushNotificationBoundary)
    gateway._app = object()
    response = SimpleNamespace(success_count=3, responses=[SimpleNamespace(success=True)] * 3)
    with patch("boundaries.push_notification_boundary.messaging.send_each_for_multicast", return_value=response) as send:
        gateway.send_notification(**calls[0])
    message = send.call_args.args[0]
    assert message.notification is not None
    assert message.android.notification.channel_id == "medbuddy_linked_chat"
