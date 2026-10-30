# 파일명: test_push_notification_gateway.py
# 역할: 필요시 복용 재전송의 기기 알림 식별자와 다른 푸시의 기존 페이로드를 검증한다.

from types import SimpleNamespace
from unittest.mock import patch

import pytest
from firebase_admin import messaging

from boundaries.push_notification_boundary import FirebasePushNotificationBoundary


@pytest.fixture
def gateway():
    boundary = FirebasePushNotificationBoundary.__new__(FirebasePushNotificationBoundary)
    boundary._app = object()
    return boundary


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
