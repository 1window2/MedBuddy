# File Name: test_missed_dose_alerts.py
# Role: Verifies server-owned missed-dose queueing and caregiver push delivery.

import sys
import unittest
from datetime import date, datetime, timedelta, UTC
from pathlib import Path
from unittest.mock import patch
from zoneinfo import ZoneInfo
from fastapi import HTTPException

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from boundaries.push_notification_boundary import PushDeliveryResult  # noqa: E402
from controls.process_caregiver_alert_outbox_control import (  # noqa: E402
    ProcessCaregiverAlertOutbox,
)
from controls.queue_missed_dose_alerts_control import (  # noqa: E402
    QueueMissedDoseAlerts,
)
from core.database import Base  # noqa: E402
from entities.caregiver_alert_outbox_entity import (  # noqa: E402
    CAREGIVER_ALERT_EVENT_MISSED_DEADLINE,
    CAREGIVER_ALERT_STATUS_SENT,
    _CaregiverAlertOutbox,
)
from entities.caregiver_notification_entity import (  # noqa: E402
    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
    _CaregiverNotification,
    encode_slot_settings,
)
from entities.device_push_token_entity import _DevicePushToken  # noqa: E402
from entities.medication_completion_entity import _MedicationCompletion  # noqa: E402
from entities.patient_caregiver_link_entity import (  # noqa: E402
    _PatientCaregiverLink,
)
from entities.saved_medication_entity import _SavedMedication  # noqa: E402
from entities.user_account_entity import _UserAccount  # noqa: E402
from controls.manage_caregiver_alert_control import ManageCaregiverAlert
from controls.manage_linked_chat_control import ManageLinkedChat
from entities.chat_message_entity import _ChatMessage
from entities.user_setting_entity import _UserSetting


# Class Name: _RecordingPushBoundary
# Role: Captures push requests without contacting Firebase.
# Attributes:
# - calls: Ordered push request payloads observed by the test.
class _RecordingPushBoundary:
    # Function Name: __init__
    # Description: Initializes an empty push-call ledger.
    # Parameters: None.
    # Returns: None.
    def __init__(self) -> None:
        self.calls: list[dict[str, object]] = []

    # Function Name: send_notification
    # Description: Records one push request and reports every token as successful.
    # Parameters:
    # - tokens: Destination device tokens.
    # - title: Notification title.
    # - body: Notification body.
    # - data: Routing metadata.
    # Returns:
    # - A successful delivery result for all supplied tokens.
    def send_notification(
        self,
        *,
        tokens: list[str],
        title: str,
        body: str,
        data: dict[str, str],
    ) -> PushDeliveryResult:
        self.calls.append(
            {"tokens": tokens, "title": title, "body": body, "data": data}
        )
        return PushDeliveryResult(success_count=len(tokens))


# Class Name: MissedDoseAlertTest
# Role: Exercises queue idempotency and delivery-time state revalidation.
class MissedDoseAlertTest(unittest.TestCase):
    # Function Name: setUp
    # Description: Creates an active caregiver link, deadline, token, and medication.
    # Parameters: None.
    # Returns: None.
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(bind=self.engine)
        self.db = sessionmaker(bind=self.engine)()
        self.schedule_date = date(2026, 9, 9)
        self.current_time = datetime(
            2026,
            9,
            9,
            13,
            5,
            tzinfo=ZoneInfo("Asia/Seoul"),
        )
        self.db.add_all(
            [
                _UserAccount(user_hash="patient-a"),
                _UserAccount(user_hash="caregiver-a"),
                _PatientCaregiverLink(
                    patient_hash="patient-a",
                    caregiver_hash="caregiver-a",
                    linked=True,
                ),
                _CaregiverNotification(
                    patient_hash="patient-a",
                    caregiver_hash="caregiver-a",
                    enabled=True,
                    alert_option=CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
                    slot_settings=encode_slot_settings(
                        {
                            "lunch": {
                                "notification_type": (
                                    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE
                                ),
                                "deadline_hour": 13,
                                "deadline_minute": 0,
                            }
                        }
                    ),
                ),
                _DevicePushToken(
                    user_hash="caregiver-a",
                    token="caregiver-missed-token-value-12345",
                    platform="android",
                    enabled=True,
                ),
            ]
        )
        self.medication = _SavedMedication(
            patient_hash="patient-a",
            created_date=self.schedule_date,
            prescription_date=self.schedule_date,
            item_name="test medication",
            daily_frequency="1",
            total_days="7",
            schedule_slot_keys='["lunch"]',
            deduplication_key="missed-dose-test-medication",
        )
        self.db.add(self.medication)
        self.db.commit()

    # Function Name: tearDown
    # Description: Closes the isolated database session and engine.
    # Parameters: None.
    # Returns: None.
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # Function Name: test_due_missed_slot_is_queued_once_and_delivered
    # Description: Verifies one due event and one correctly routed caregiver push.
    # Parameters: None.
    # Returns: None; assertions fail the test when behavior differs.
    def test_due_missed_slot_is_queued_once_and_delivered(self) -> None:
        queue = QueueMissedDoseAlerts(self.db)

        self.assertEqual(queue.queueDue(now=self.current_time), 1)
        self.assertEqual(queue.queueDue(now=self.current_time), 0)

        row = self.db.query(_CaregiverAlertOutbox).one()
        self.assertEqual(row.event_type, CAREGIVER_ALERT_EVENT_MISSED_DEADLINE)
        self.assertEqual(row.caregiver_hash, "caregiver-a")
        self.assertEqual(row.schedule_date, self.schedule_date)
        push = _RecordingPushBoundary()
        with patch(
            "controls.dispatch_caregiver_alert_control.application_now",
            return_value=self.current_time,
        ):
            outcome = ProcessCaregiverAlertOutbox(self.db, push).processOne(
                int(row.id)
            )

        self.db.refresh(row)
        self.assertEqual(outcome, "sent")
        self.assertEqual(row.status, CAREGIVER_ALERT_STATUS_SENT)
        self.assertEqual(len(push.calls), 1)
        self.assertEqual(
            push.calls[0]["data"],
            {
                "type": "caregiver_slot_missed",
                "recipient_hash": "caregiver-a",
                "language": "ko",
                "patient_hash": "patient-a",
                "slot_key": "lunch",
            },
        )

    # Function Name: test_completion_after_queue_suppresses_stale_delivery
    # Description: Verifies a late completion prevents an already queued stale push.
    # Parameters: None.
    # Returns: None; assertions fail the test when behavior differs.
    def test_completion_after_queue_suppresses_stale_delivery(self) -> None:
        QueueMissedDoseAlerts(self.db).queueDue(now=self.current_time)
        row = self.db.query(_CaregiverAlertOutbox).one()
        self.db.add(
            _MedicationCompletion(
                saved_medication_id=int(self.medication.id),
                patient_hash="patient-a",
                schedule_date=self.schedule_date,
                slot_key="lunch",
                completed=True,
            )
        )
        self.db.commit()
        push = _RecordingPushBoundary()
        with patch(
            "controls.dispatch_caregiver_alert_control.application_now",
            return_value=self.current_time,
        ):
            outcome = ProcessCaregiverAlertOutbox(self.db, push).processOne(
                int(row.id)
            )

        self.db.refresh(row)
        self.assertEqual(outcome, "sent")
        self.assertEqual(row.status, CAREGIVER_ALERT_STATUS_SENT)
        self.assertEqual(push.calls, [])


class CaregiverMissedActionTest(MissedDoseAlertTest):
    """Exercise real rows, action authorization and the existing delivery worker."""

    def setUp(self):
        super().setUp()
        self.now = self.current_time.astimezone(UTC).replace(tzinfo=None)
        for target, value in (
            ("controls.dispatch_caregiver_alert_control.application_now", self.current_time),
            ("core.application_clock.application_now", self.current_time),
            ("controls.manage_caregiver_alert_control.utc_now", self.now),
        ):
            patcher = patch(target, return_value=value)
            patcher.start()
            self.addCleanup(patcher.stop)
        QueueMissedDoseAlerts(self.db).queueDue(now=self.current_time)
        self.root = self.db.query(_CaregiverAlertOutbox).one()
        self.root.status = "sent"
        self.root.available_at = self.now
        self.db.commit()
        self.actions = ManageCaregiverAlert(self.db)

    # The parent cases have their own queue setup; keep them in the parent suite.
    test_due_missed_slot_is_queued_once_and_delivered = None
    test_completion_after_queue_suppresses_stale_delivery = None

    def complete(self):
        self.db.add(_MedicationCompletion(
            saved_medication_id=self.medication.id, patient_hash="patient-a",
            schedule_date=self.schedule_date, slot_key="lunch", completed=True,
        ))
        self.db.commit()

    def snooze(self):
        return self.actions.snooze(self.root.id, "caregiver-a")

    def chat(self, **overrides):
        values = dict(
            link_id=self.db.query(_PatientCaregiverLink).one().id,
            sender_hash="caregiver-a", client_message_id="random_request_1",
            body="Please check lunch", message_kind="slot_check_request",
            slot_key="lunch", source_alert_id=self.root.id,
        )
        values.update(overrides)
        return ManageLinkedChat(self.db).send_message(**values)

    def deliver(self, row_id):
        push = _RecordingPushBoundary()
        with patch("controls.process_caregiver_alert_outbox_control.utc_now",
                   return_value=self.now + timedelta(minutes=10)):
            outcome = ProcessCaregiverAlertOutbox(self.db, push).processOne(row_id)
        self.assertEqual(outcome, "sent")
        return push.calls

    def test_repeat_snooze_is_one_new_row_without_completion_or_setting_changes(self):
        setting = self.db.query(_CaregiverNotification).one().slot_settings
        first, repeat = self.snooze(), self.snooze()
        self.assertTrue(first["created"])
        self.assertFalse(repeat["created"])
        self.assertEqual(first["data"], repeat["data"])
        self.assertEqual(self.db.query(_CaregiverAlertOutbox).count(), 2)
        self.assertEqual(self.db.query(_MedicationCompletion).count(), 0)
        self.assertEqual(self.db.query(_CaregiverNotification).one().slot_settings, setting)
        child = self.db.get(_CaregiverAlertOutbox, first["data"]["alert_id"])
        self.assertEqual(child.available_at, self.now + timedelta(minutes=10))
        self.assertEqual(self.root.status, "sent")

    def test_snooze_child_cannot_be_snoozed_until_released_then_has_new_cycle(self):
        child = self.snooze()["data"]["alert_id"]
        with self.assertRaises(HTTPException):
            self.actions.snooze(child, "caregiver-a")
        self.assertEqual(len(self.deliver(child)), 1)
        with patch("controls.manage_caregiver_alert_control.utc_now",
                   return_value=self.now + timedelta(minutes=10)):
            second = self.actions.snooze(child, "caregiver-a")
        self.assertNotEqual(child, second["data"]["alert_id"])
        self.assertEqual(self.db.query(_CaregiverAlertOutbox).count(), 3)
        contexts = [self.actions.context(row) for row in self.db.query(_CaregiverAlertOutbox)]
        self.assertEqual(len({c["source_event_id"] for c in contexts}), 1)
        self.assertEqual(len({c["event_id"] for c in contexts}), 3)

    def test_completion_within_ten_minutes_suppresses_fcm_and_retry_is_idempotent(self):
        receipt = self.snooze()
        self.complete()
        self.assertFalse(self.snooze()["created"])
        self.assertEqual(self.deliver(receipt["data"]["alert_id"]), [])

    def test_completed_source_rejects_both_new_actions(self):
        self.complete()
        for action in (self.snooze, self.chat):
            with self.assertRaises(HTTPException) as error:
                action()
            self.assertEqual(error.exception.status_code, 409)
        self.assertEqual(self.db.query(_ChatMessage).count(), 0)

    def test_next_day_rejects_actions_and_suppresses_queued_delivery(self):
        child = self.snooze()["data"]["alert_id"]
        with patch("controls.dispatch_caregiver_alert_control.application_now",
                   return_value=self.current_time + timedelta(days=1)):
            with self.assertRaises(HTTPException):
                self.chat()
            self.assertEqual(self.deliver(child), [])
        self.root.schedule_date -= timedelta(days=1)
        self.db.commit()
        with self.assertRaises(HTTPException):
            self.snooze()

    def test_unlinked_source_rejects_actions_and_queued_delivery(self):
        child = self.snooze()["data"]["alert_id"]
        self.db.query(_PatientCaregiverLink).one().linked = False
        self.db.commit()
        for action in (self.snooze, self.chat):
            with self.assertRaises(HTTPException):
                action()
        self.assertEqual(self.deliver(child), [])

    def test_owner_and_slot_cannot_be_forged(self):
        with self.assertRaises(HTTPException):
            self.actions.snooze(self.root.id, "patient-a")
        for overrides in ({"sender_hash": "patient-a"}, {"slot_key": "morning"}, {"link_id": 99}):
            with self.assertRaises(HTTPException):
                self.chat(**overrides)

    def test_chat_retries_and_snooze_cycles_share_original_message(self):
        first = self.chat()
        self.assertTrue(first.created)
        child = self.snooze()["data"]["alert_id"]
        self.deliver(child)
        self.assertFalse(self.chat(source_alert_id=child, client_message_id="another_random").created)
        self.complete()
        retry = self.chat(client_message_id="response_was_lost")
        self.assertFalse(retry.created)
        self.assertEqual(first.message.message_id, retry.message.message_id)
        self.assertEqual(self.db.query(_ChatMessage).count(), 1)
        self.assertEqual(first.message.context_payload["schedule_context"]["schedule_date"], "2026-09-09")

    def test_delivery_rechecks_global_preference_and_active_tokens(self):
        child = self.snooze()["data"]["alert_id"]
        self.db.add(_UserSetting(user_hash="caregiver-a", caregiver_notifications_enabled=False))
        self.db.commit()
        self.assertEqual(self.deliver(child), [])

    def test_no_active_tokens_means_no_fcm(self):
        child = self.snooze()["data"]["alert_id"]
        self.db.query(_DevicePushToken).one().enabled = False
        self.db.commit()
        self.assertEqual(self.deliver(child), [])

    def test_capable_devices_get_context_and_legacy_devices_keep_os_notification(self):
        self.db.add(_DevicePushToken(user_hash="caregiver-a", token="new-device-token", platform="android",
                                     enabled=True, supports_caregiver_actions=True))
        self.db.commit()
        calls = self.deliver(self.snooze()["data"]["alert_id"])
        self.assertEqual(len(calls), 2)
        legacy = next(c for c in calls if "new-device-token" not in c["tokens"])
        modern = next(c for c in calls if "new-device-token" in c["tokens"])
        self.assertNotIn("action_version", legacy["data"])
        self.assertEqual(modern["data"]["source_alert_id"], str(self.root.id))
        self.assertNotEqual(modern["data"]["alert_id"], str(self.root.id))
        self.assertEqual(modern["data"]["schedule_date"], "2026-09-09")

    def test_local_delivery_reader_only_exposes_released_current_events(self):
        child = self.snooze()["data"]["alert_id"]
        self.assertEqual(len(self.actions.localDeliveries("caregiver-a")), 1)
        self.deliver(child)
        with patch("controls.manage_caregiver_alert_control.utc_now", return_value=self.now + timedelta(minutes=10)):
            self.assertEqual(len(self.actions.localDeliveries("caregiver-a")), 2)
        self.complete()
        self.assertEqual(self.actions.localDeliveries("caregiver-a"), [])

    def test_partial_delivery_failure_still_allows_received_notification_action(self):
        self.root.status = "failed"
        self.root.attempt_count = 1
        self.root.available_at = self.now + timedelta(minutes=1)
        self.db.commit()
        self.assertTrue(self.snooze()["created"])

    def test_snooze_http_uses_verified_principal_and_checks_auth_app_check(self):
        from fastapi import FastAPI
        from fastapi.testclient import TestClient
        from api.router import router
        from api.dependencies import get_authenticated_principal, get_registered_principal
        from core.config import settings
        from core.database import get_db
        from entities.authenticated_principal_entity import AuthenticatedPrincipal
        app = FastAPI()
        app.include_router(router, prefix="/api/v1/medication")
        app.dependency_overrides[get_db] = lambda: self.db
        app.dependency_overrides[get_registered_principal] = lambda: None
        principal = AuthenticatedPrincipal(subject="verified", issuer="test", user_hash="caregiver-a")
        path = f"/api/v1/medication/caregiver-alerts/{self.root.id}/snooze"
        with TestClient(app) as client, patch.object(settings, "AUTH_MODE", "firebase"):
            with patch.object(settings, "FIREBASE_APP_CHECK_REQUIRED", True):
                self.assertEqual(client.post(path).status_code, 403)
            with patch.object(settings, "FIREBASE_APP_CHECK_REQUIRED", False):
                self.assertEqual(client.post(path).status_code, 401)
                app.dependency_overrides[get_authenticated_principal] = lambda: principal
                result = client.post(path, params={"user_hash": "attacker"})
                self.assertEqual(result.status_code, 200, result.text)
                self.assertEqual(client.post(path).json()["created"], False)
                self.assertEqual(client.get("/api/v1/medication/caregiver-alerts/local-deliveries").status_code, 404)
                principal = principal.model_copy(update={"user_hash": "patient-a"})
                self.assertEqual(client.post(path, params={"user_hash": "caregiver-a"}).status_code, 404)

    def test_chat_http_reuses_broadcast_and_background_push_once(self):
        from fastapi import FastAPI
        from fastapi.testclient import TestClient
        from unittest.mock import AsyncMock
        from api.chat_router import router
        from api.dependencies import get_authenticated_app_principal, get_manage_linked_chat, get_authorization_control
        from controls.authorization_control import AuthorizationControl
        from entities.authenticated_principal_entity import AuthenticatedPrincipal
        app = FastAPI()
        app.include_router(router, prefix="/api/v1/chat")
        app.dependency_overrides[get_authenticated_app_principal] = lambda: AuthenticatedPrincipal(
            subject="verified", issuer="test", user_hash="caregiver-a")
        app.dependency_overrides[get_manage_linked_chat] = lambda: ManageLinkedChat(self.db)
        app.dependency_overrides[get_authorization_control] = lambda: AuthorizationControl(self.db)
        manager = AsyncMock()
        manager.is_user_connected.return_value = False
        link_id = self.db.query(_PatientCaregiverLink).one().id
        body = {"client_message_id": "arbitrary_client_id", "body": "Check lunch", "message_kind": "slot_check_request",
                "slot_key": "lunch", "source_alert_id": self.root.id}
        with patch("api.chat_router.get_chat_connection_manager", return_value=manager), \
             patch("api.chat_router._enforce_chat_daily_quota", new=AsyncMock()), \
             patch("api.chat_router._reserve_chat_push_notification", new=AsyncMock(return_value=True)), \
             patch("api.chat_router._dispatch_chat_notification") as push, TestClient(app) as client:
            response = client.post(f"/api/v1/chat/links/{link_id}/messages", json=body)
            self.assertEqual(response.status_code, 200, response.text)
            self.assertTrue(response.json()["created"])
            self.assertFalse(client.post(f"/api/v1/chat/links/{link_id}/messages", json=body).json()["created"])
            self.assertEqual(manager.broadcast.await_count, 1)
            self.assertEqual(push.call_count, 1)
            self.assertEqual(push.call_args.kwargs["recipient_hash"], "patient-a")
            self.assertEqual(push.call_args.kwargs["message_kind"], "slot_check_request")


if __name__ == "__main__":
    unittest.main()
