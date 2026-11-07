# 파일명: test_push_notification_gateway.py
# 역할: 필요시 복용 재전송의 기기 알림 식별자와 다른 푸시의 기존 페이로드를 검증한다.

from types import SimpleNamespace
from unittest.mock import patch

import pytest
from firebase_admin import messaging

from boundaries.push_notification_boundary import FirebasePushNotificationBoundary


# 함수이름: gateway
# 함수역할:
# - Firebase 초기화 없이 앱 대역을 주입한 경계를 만들어 전송 메시지 구성을 검사한다.
# 매개변수:
# - 없음.
# 반환값:
# - FirebasePushNotificationBoundary; 전송 함수만 테스트에서 교체할 경계.
@pytest.fixture
def gateway():
    boundary = FirebasePushNotificationBoundary.__new__(FirebasePushNotificationBoundary)
    boundary._app = object()
    return boundary


# 함수이름: test_completion_retry_reuses_platform_identifiers_but_new_event_is_distinct
# 함수역할:
# - 완료 재시도는 같은 Android tag·APNs collapse ID를 쓰고 새 이벤트는 분리하며 부분 실패와 원본 데이터를 보존하는지 확인한다.
# 매개변수:
# - gateway: FirebasePushNotificationBoundary; 실제 Firebase 초기화 없이 만든 전송 경계.
# - kind: str; 정기 슬롯 또는 필요시 복용 완료 종류.
# - slot: str; 알림 복용 슬롯.
# 반환값:
# - None.
@pytest.mark.parametrize(("kind", "slot"), [
    ("caregiver_dose_completed", "as_needed"),
    *[("caregiver_slot_completed", slot) for slot in ("morning", "lunch", "evening", "bedtime")],
])
def test_completion_retry_reuses_platform_identifiers_but_new_event_is_distinct(gateway, kind, slot):
    partial = SimpleNamespace(success_count=1, responses=[
        SimpleNamespace(success=True),
        SimpleNamespace(success=False, exception=messaging.QuotaExceededError("retry")),
    ])
    success = SimpleNamespace(success_count=2, responses=[SimpleNamespace(success=True)] * 2)
    payload = {
        "type": kind, "slot_key": slot, "event_key": "a1" * 32,
        "patient_hash": "patient-a", "recipient_hash": "caregiver-a",
        "schedule_date": "2026-10-17", "language": "ko",
    }
    original = dict(payload)
    with patch("boundaries.push_notification_boundary.messaging.send_each_for_multicast",
               side_effect=[partial, success, success]) as send:
        results = []
        for key in (payload["event_key"], payload["event_key"], "b2" * 32):
            results.append(gateway.send_notification(
                tokens=["device-a", "device-b"], title="title", body="body",
                data={**payload, "event_key": key},
            ))
    assert results[0].success_count == 1 and results[0].retryable_failure_count == 1
    assert all(result.success_count == 2 and result.all_valid_targets_succeeded for result in results[1:])
    messages = [call.args[0] for call in send.call_args_list]
    assert [message.android.notification.tag for message in messages] == ["a1" * 32, "a1" * 32, "b2" * 32]
    for message in messages:
        key = message.data["event_key"]
        assert message.apns.headers == {"apns-collapse-id": key}
        assert len(key.encode("utf-8")) == 64
        assert message.apns.payload is None
        assert message.android.priority == "high" and message.android.collapse_key is None
        assert message.android.notification.channel_id == "medbuddy_caregiver_updates"
        assert (message.notification.title, message.notification.body) == ("title", "body")
        assert message.data == {**payload, "event_key": key}
    assert payload == original


# 함수이름: test_invalid_or_missing_completion_key_leaves_platform_identifiers_unset
# 함수역할:
# - 잘못된 완료 키는 기기별 식별자로 사용하지 않고 원래 알림·데이터를 유지하는지 확인한다.
# 매개변수:
# - gateway: FirebasePushNotificationBoundary; 실제 Firebase 초기화 없이 만든 전송 경계.
# - event_key: str | None; 누락되거나 잘못된 완료 이벤트 키.
# - kind: str; 정기 슬롯 또는 필요시 복용 완료 종류.
# - slot: str; 알림 복용 슬롯.
# 반환값:
# - None.
@pytest.mark.parametrize("event_key", [None, "", "a" * 63, "a" * 65, "A" * 64, "g" * 64, "a" * 64 + "\n", " " + "a" * 64])
@pytest.mark.parametrize(("kind", "slot"), [
    ("caregiver_dose_completed", "as_needed"), ("caregiver_slot_completed", "morning"),
])
def test_invalid_or_missing_completion_key_leaves_platform_identifiers_unset(gateway, event_key, kind, slot):
    payload = {"type": kind, "slot_key": slot}
    if event_key is not None:
        payload["event_key"] = event_key
    response = SimpleNamespace(success_count=1, responses=[SimpleNamespace(success=True)])
    with patch("boundaries.push_notification_boundary.messaging.send_each_for_multicast", return_value=response) as send:
        gateway.send_notification(tokens=["device"], title="title", body="body", data=payload)
    message = send.call_args.args[0]
    assert message.android.notification.tag is None
    assert message.apns is None
    assert message.data == payload
    assert (message.notification.title, message.notification.body) == ("title", "body")


# 함수이름: test_non_prn_payload_behavior_is_unchanged_even_with_valid_key
# 함수역할:
# - 완료 종류·슬롯 조합이 대상이 아니면 유효한 키가 있어도 기존 일반·동작 알림 구성을 유지하는지 확인한다.
# 매개변수:
# - gateway: FirebasePushNotificationBoundary; 실제 Firebase 초기화 없이 만든 전송 경계.
# - payload: dict; 완료 식별자 적용 대상이 아닌 알림 데이터.
# 반환값:
# - None.
@pytest.mark.parametrize("payload", [
    {"type": "caregiver_slot_completed", "slot_key": "as_needed"},
    {"type": "caregiver_slot_completed", "slot_key": "unknown"},
    {"type": "caregiver_slot_completed"},
    {"type": "caregiver_dose_completed", "slot_key": "morning"},
    {"type": "caregiver_dose_completed"},
    {"type": "caregiver_slot_missed", "slot_key": "as_needed"},
    {"type": "caregiver_slot_missed", "slot_key": "morning", "action_version": "1"},
    {"type": "linked_chat_message", "slot_key": "as_needed"},
])
def test_non_prn_payload_behavior_is_unchanged_even_with_valid_key(gateway, payload):
    payload = {**payload, "event_key": "ab" * 32}
    response = SimpleNamespace(success_count=1, responses=[SimpleNamespace(success=True)])
    with patch("boundaries.push_notification_boundary.messaging.send_each_for_multicast", return_value=response) as send:
        gateway.send_notification(tokens=["device"], title="title", body="body", data=payload)
    message = send.call_args.args[0]
    assert message.apns is None and message.android.collapse_key is None
    assert message.data == payload and message.android.priority == "high"
    if payload.get("action_version") == "1":
        assert message.notification is None and message.android.notification is None
    else:
        assert message.android.notification.tag is None
        assert message.android.notification.channel_id == (
            "medbuddy_linked_chat" if payload["type"] == "linked_chat_message"
            else "medbuddy_caregiver_updates"
        )
        assert (message.notification.title, message.notification.body) == ("title", "body")


# 함수이름: test_chat_updates_one_notification_per_conversation_with_count
# 함수역할:
# - 같은 대화의 푸시는 Android 알림 tag와 APNs thread ID를 유지하면서 메시지 수를 갱신하는지 확인한다.
# 매개변수:
# - gateway: FirebasePushNotificationBoundary; 실제 Firebase 초기화 없이 만든 전송 경계.
# 반환값:
# - None.
def test_chat_updates_one_notification_per_conversation_with_count(gateway):
    response = SimpleNamespace(success_count=1, responses=[SimpleNamespace(success=True)])
    tag = "medbuddy-chat-" + "a1" * 16
    with patch("boundaries.push_notification_boundary.messaging.send_each_for_multicast", return_value=response) as send:
        for count in (1, 2, 3):
            gateway.send_notification(tokens=["device"], title=f"Patient ({count})", body="one\ntwo\nthree",
                data={"type": "linked_chat_message", "chat_group": tag, "chat_count": str(count)})
    messages = [call.args[0] for call in send.call_args_list]
    assert [m.android.notification.tag for m in messages] == [tag] * 3
    assert [m.android.notification.notification_count for m in messages] == [1, 2, 3]
    assert all(m.android.notification.channel_id == "medbuddy_linked_chat" for m in messages)
    assert all(m.apns.payload.aps.thread_id == tag for m in messages)
