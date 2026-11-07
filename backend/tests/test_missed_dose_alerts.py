# File Name: test_missed_dose_alerts.py
# Role: Verifies server-owned missed-dose queueing and caregiver push delivery.

import sys
import unittest
from datetime import date, datetime, timedelta, UTC
from pathlib import Path
from typing import Any
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
    CAREGIVER_ALERT_STATUS_DEAD_LETTER,
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
from controls.manage_linked_chat_control import ChatSendResult, ManageLinkedChat
from entities.chat_message_entity import _ChatMessage
from entities.user_setting_entity import _UserSetting


# Class Name: _RecordingPushBoundary
# Role: Captures push requests without contacting Firebase.
# Responsibilities:
# - Record notification payloads and report successful delivery to every supplied token.
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
# Responsibilities:
# - Check one-time queuing and suppress delivery when completion makes an already queued alert stale.
# Attributes:
# - engine (Engine): isolated SQLite database. db (Session): test session. schedule_date (date), current_time (datetime): fixed deadline inputs. medication (_SavedMedication): seeded lunch dose.
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

    # 함수이름: test_due_missed_slot_is_queued_once_and_delivered
    # 함수역할:
    # - 기한이 지난 미복용 슬롯에 이벤트를 한 번만 생성하고 올바른 보호자에게 푸시를 전달하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - None.
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
        self.assertEqual(outcome, "skipped")
        self.assertEqual(row.status, CAREGIVER_ALERT_STATUS_DEAD_LETTER)
        self.assertEqual(row.last_error, "MissedDoseNoLongerCurrent")
        self.assertIsNone(row.sent_at)
        self.assertEqual(push.calls, [])


# 클래스명: CaregiverMissedActionTest
# 역할: 실제 저장 행과 전달 작업자로 미복용 알림 동작의 권한·지연·재시도를 검사한다.
# 주요 책임:
# - 재알림과 채팅 요청의 멱등성, 전달 전 재검증 및 이전 복구를 확인한다.
# 속성:
# - now (datetime): 고정 UTC 시각; root (_CaregiverAlertOutbox): 원본 알림; actions (ManageCaregiverAlert): 동작 컨트롤; DB·복용 자료는 부모 클래스 상속.
class CaregiverMissedActionTest(MissedDoseAlertTest):
    """Exercise real rows, action authorization and the existing delivery worker."""

    # Function Name: setUp
    # Description:
    # - Extends the parent scene with fixed action clocks, one delivered missed-dose source and an action control.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def setUp(self) -> None:
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

    # Function Name: complete
    # Description:
    # - Persists completion of the fixture medication in the lunch slot on its schedule date.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def complete(self) -> None:
        self.db.add(_MedicationCompletion(
            saved_medication_id=self.medication.id, patient_hash="patient-a",
            schedule_date=self.schedule_date, slot_key="lunch", completed=True,
        ))
        self.db.commit()

    # Function Name: snooze
    # Description:
    # - Requests a ten-minute snooze of the original alert as its authorized caregiver.
    # Parameters:
    # - None.
    # Returns:
    # - dict; snooze receipt, or HTTPException when the action is no longer valid.
    def snooze(self) -> dict[str, Any]:
        return self.actions.snooze(self.root.id, "caregiver-a")

    # Function Name: chat
    # Description:
    # - Sends a lunch-check message tied to the source alert, applying supplied overrides for authorization tests.
    # Parameters:
    # - overrides: dict; fields replacing the default alert-linked message request.
    # Returns:
    # - Chat send result; invalid source or scope raises HTTPException.
    def chat(self, **overrides: str | int) -> ChatSendResult:
        values = dict(
            link_id=self.db.query(_PatientCaregiverLink).one().id,
            sender_hash="caregiver-a", client_message_id="random_request_1",
            body="Please check lunch", message_kind="slot_check_request",
            slot_key="lunch", source_alert_id=self.root.id,
        )
        values.update(overrides)
        return ManageLinkedChat(self.db).send_message(**values)

    # Function Name: deliver
    # Description:
    # - Processes the selected event ten minutes later, checking its expected outcome and stale-event dead-letter reason.
    # Parameters:
    # - row_id: int; queued alert ID.
    # - outcome: str; expected sent or skipped processing result.
    # Returns:
    # - list[dict]; captured push calls.
    def deliver(self, row_id: int, outcome: str = "sent") -> list[dict[str, Any]]:
        push = _RecordingPushBoundary()
        with patch("controls.process_caregiver_alert_outbox_control.utc_now",
                   return_value=self.now + timedelta(minutes=10)):
            result = ProcessCaregiverAlertOutbox(self.db, push).processOne(row_id)
        # An alert that is no longer needed is given up, not recorded as sent.
        self.assertEqual(result, outcome)
        if outcome == "skipped":
            row = self.db.get(_CaregiverAlertOutbox, row_id)
            self.db.refresh(row)
            self.assertEqual(row.status, CAREGIVER_ALERT_STATUS_DEAD_LETTER)
            self.assertEqual(row.last_error, "MissedDoseNoLongerCurrent")
        return push.calls

    # Function Name: test_repeat_snooze_is_one_new_row_without_completion_or_setting_changes
    # Description:
    # - Requires repeated snooze requests to reuse one child due in ten minutes without changing completion or notification settings.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_repeat_snooze_is_one_new_row_without_completion_or_setting_changes(self) -> None:
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

    # Function Name: test_snooze_child_cannot_be_snoozed_until_released_then_has_new_cycle
    # Description:
    # - Rejects snoozing an unreleased child; after delivery a new cycle gets its own event ID while retaining the original source.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_snooze_child_cannot_be_snoozed_until_released_then_has_new_cycle(self) -> None:
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

    # Function Name: test_completion_within_ten_minutes_suppresses_fcm_and_retry_is_idempotent
    # Description:
    # - Requires completion during the snooze delay to suppress delivery while duplicate snooze remains idempotent.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_completion_within_ten_minutes_suppresses_fcm_and_retry_is_idempotent(self) -> None:
        receipt = self.snooze()
        self.complete()
        self.assertFalse(self.snooze()["created"])
        self.assertEqual(self.deliver(receipt["data"]["alert_id"], outcome="skipped"), [])

    # Function Name: test_completed_source_rejects_both_new_actions
    # Description:
    # - Requires a completed source to reject new snooze and chat actions with 409 and persist no message.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_completed_source_rejects_both_new_actions(self) -> None:
        self.complete()
        for action in (self.snooze, self.chat):
            with self.assertRaises(HTTPException) as error:
                action()
            self.assertEqual(error.exception.status_code, 409)
        self.assertEqual(self.db.query(_ChatMessage).count(), 0)

    # Function Name: test_next_day_rejects_actions_and_suppresses_queued_delivery
    # Description:
    # - Requires next-day or stale-date actions to fail and queued missed-dose delivery to be abandoned.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_next_day_rejects_actions_and_suppresses_queued_delivery(self) -> None:
        child = self.snooze()["data"]["alert_id"]
        with patch("controls.dispatch_caregiver_alert_control.application_now",
                   return_value=self.current_time + timedelta(days=1)):
            with self.assertRaises(HTTPException):
                self.chat()
            self.assertEqual(self.deliver(child, outcome="skipped"), [])
        self.root.schedule_date -= timedelta(days=1)
        self.db.commit()
        with self.assertRaises(HTTPException):
            self.snooze()

    # Function Name: test_unlinked_source_rejects_actions_and_queued_delivery
    # Description:
    # - Requires unlinking to reject both actions and suppress the already queued child notification.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_unlinked_source_rejects_actions_and_queued_delivery(self) -> None:
        child = self.snooze()["data"]["alert_id"]
        self.db.query(_PatientCaregiverLink).one().linked = False
        self.db.commit()
        for action in (self.snooze, self.chat):
            with self.assertRaises(HTTPException):
                action()
        self.assertEqual(self.deliver(child, outcome="skipped"), [])

    # Function Name: test_owner_and_slot_cannot_be_forged
    # Description:
    # - Rejects forged caregiver ownership, schedule slot or conversation ID for alert actions.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_owner_and_slot_cannot_be_forged(self) -> None:
        with self.assertRaises(HTTPException):
            self.actions.snooze(self.root.id, "patient-a")
        for overrides in ({"sender_hash": "patient-a"}, {"slot_key": "morning"}, {"link_id": 99}):
            with self.assertRaises(HTTPException):
                self.chat(**overrides)

    # Function Name: test_chat_retries_and_snooze_cycles_share_original_message
    # Description:
    # - Requires chat retries and later snooze cycles to reuse the original message even after completion.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_chat_retries_and_snooze_cycles_share_original_message(self) -> None:
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

    # Function Name: test_delivery_rechecks_global_preference_and_active_tokens
    # Description:
    # - Requires delivery-time global opt-out to abandon the pending child without a push.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_delivery_rechecks_global_preference_and_active_tokens(self) -> None:
        child = self.snooze()["data"]["alert_id"]
        self.db.add(_UserSetting(user_hash="caregiver-a", caregiver_notifications_enabled=False))
        self.db.commit()
        self.assertEqual(self.deliver(child, outcome="skipped"), [])

    # Function Name: test_no_active_tokens_means_no_fcm
    # Description:
    # - Requires a released child with no active device token to finish without calling FCM.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_no_active_tokens_means_no_fcm(self) -> None:
        child = self.snooze()["data"]["alert_id"]
        self.db.query(_DevicePushToken).one().enabled = False
        self.db.commit()
        self.assertEqual(self.deliver(child), [])

    # Function Name: test_capable_devices_get_context_and_legacy_devices_keep_os_notification
    # Description:
    # - Requires action-capable Android devices to receive source context while legacy devices retain ordinary notification data.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_capable_devices_get_context_and_legacy_devices_keep_os_notification(self) -> None:
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

    # Function Name: test_local_delivery_reader_only_exposes_released_current_events
    # Description:
    # - Exposes only released, still-current events to local delivery readers and removes them after completion.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_local_delivery_reader_only_exposes_released_current_events(self) -> None:
        child = self.snooze()["data"]["alert_id"]
        self.assertEqual(len(self.actions.localDeliveries("caregiver-a")), 1)
        self.deliver(child)
        with patch("controls.manage_caregiver_alert_control.utc_now", return_value=self.now + timedelta(minutes=10)):
            self.assertEqual(len(self.actions.localDeliveries("caregiver-a")), 2)
        self.complete()
        self.assertEqual(self.actions.localDeliveries("caregiver-a"), [])

    # 함수이름: test_migration_alone_recovers_missing_capability_and_local_snooze_delivery
    # 함수역할:
    # - 과거 스키마의 누락 기능으로 실패한 알림이 실제 이전 후 복구되며 토큰 없이도 로컬 전달·재알림 주기를 유지하는지 확인한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - None.
    def test_migration_alone_recovers_missing_capability_and_local_snooze_delivery(self) -> None:
        from alembic import command
        from alembic.config import Config
        from boundaries.push_notification_boundary import DisabledPushNotificationBoundary

        # Reproduce a legacy create_all database with no FCM tokens, as in disabled auth.
        root_id = self.root.id
        self.db.query(_DevicePushToken).delete()
        self.root.status = "pending"
        self.db.commit()
        self.db.close()
        with self.engine.begin() as connection:
            connection.exec_driver_sql("ALTER TABLE device_push_tokens DROP COLUMN supports_caregiver_actions")
            # This historical baseline predates the durable chat queue.
            connection.exec_driver_sql("DROP TABLE chat_notification_jobs")
        processor = ProcessCaregiverAlertOutbox(self.db, DisabledPushNotificationBoundary())
        with patch("controls.process_caregiver_alert_outbox_control.utc_now", return_value=self.now):
            with self.assertLogs("controls.process_caregiver_alert_outbox_control", level="WARNING") as logs:
                self.assertEqual(processor.processOne(root_id), "failed")
        self.assertIn("no such column: device_push_tokens.supports_caregiver_actions", logs.output[0])
        self.assertNotIn("SELECT", logs.output[0])
        self.assertNotIn("caregiver-a", logs.output[0])
        self.assertEqual(self.actions.localDeliveries("caregiver-a"), [])
        self.db.close()

        # Adopt only this known test fixture's baseline, then use the real migration.
        config = Config(str(BACKEND_DIR / "alembic.ini"))
        with self.engine.begin() as connection:
            config.attributes["connection"] = connection
            # The historical fixture also predates version-checked settings writes.
            connection.exec_driver_sql("ALTER TABLE user_settings DROP COLUMN revision")
            # Keep the historical fixture older than the care-history migration too.
            connection.exec_driver_sql("DROP TABLE medication_care_audits")
            connection.exec_driver_sql("DROP TABLE medication_care_operations")
            for column in ("report_status", "actual_taken_at", "recorded_at", "reason", "revision"):
                connection.exec_driver_sql(f"ALTER TABLE medication_completions DROP COLUMN {column}")
            for column in ("dosing_mode", "regimen_revision", "regimen_effective_from", "stopped_on", "superseded_by_id"):
                connection.exec_driver_sql(f"ALTER TABLE saved_medications DROP COLUMN {column}")
            command.stamp(config, "a6e2d903bc71")
            command.upgrade(config, "head")

        retry_time = self.now + timedelta(seconds=20)
        with patch("controls.process_caregiver_alert_outbox_control.utc_now", return_value=retry_time), \
             patch("controls.manage_caregiver_alert_control.utc_now", return_value=retry_time):
            self.assertEqual(processor.processOne(root_id), "sent")
            self.assertEqual(len(self.actions.localDeliveries("caregiver-a")), 1)
            first = self.actions.snooze(root_id, "caregiver-a")
            self.assertFalse(self.actions.snooze(root_id, "caregiver-a")["created"])
            child_id = first["data"]["alert_id"]
            self.assertEqual(processor.processOne(child_id), "skipped")
        due = retry_time + timedelta(minutes=10)
        with patch("controls.process_caregiver_alert_outbox_control.utc_now", return_value=due), \
             patch("controls.manage_caregiver_alert_control.utc_now", return_value=due):
            self.assertEqual(processor.processOne(child_id), "sent")
            self.assertEqual(len(self.actions.localDeliveries("caregiver-a")), 2)
            self.assertTrue(self.actions.snooze(child_id, "caregiver-a")["created"])
        self.assertEqual(self.db.query(_MedicationCompletion).count(), 0)

    # Function Name: test_partial_delivery_failure_still_allows_received_notification_action
    # Description:
    # - Allows an action after partial delivery failure because some devices may already have received the alert.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_partial_delivery_failure_still_allows_received_notification_action(self) -> None:
        self.root.status = "failed"
        self.root.attempt_count = 1
        self.root.available_at = self.now + timedelta(minutes=1)
        self.db.commit()
        self.assertTrue(self.snooze()["created"])

    # Function Name: test_snooze_http_uses_verified_principal_and_checks_auth_app_check
    # Description:
    # - Checks App Check, authentication and verified ownership for HTTP snooze, including idempotent retries and the absent local-delivery route.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_snooze_http_uses_verified_principal_and_checks_auth_app_check(self) -> None:
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

    # Function Name: test_chat_http_broadcasts_and_queues_durable_push_once
    # Description:
    # - Requires a new HTTP check request to broadcast and queue one durable push; retries consume admission quota but create neither again.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_chat_http_broadcasts_and_queues_durable_push_once(self) -> None:
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
        quota = AsyncMock()
        with patch("api.route_support.get_chat_connection_manager", return_value=manager), \
             patch("api.chat_router.enforce_chat_daily_quota", new=quota), \
             TestClient(app) as client:
            response = client.post(f"/api/v1/chat/links/{link_id}/messages", json=body)
            self.assertEqual(response.status_code, 200, response.text)
            self.assertTrue(response.json()["created"])
            self.assertFalse(client.post(f"/api/v1/chat/links/{link_id}/messages", json=body).json()["created"])
            self.assertEqual(manager.broadcast.await_count, 1)
            self.assertEqual(quota.await_count, 2)
            from entities.chat_notification_job_entity import ChatNotificationJob
            jobs = self.db.query(ChatNotificationJob).all()
            self.assertEqual(len(jobs), 1)
            self.assertEqual(jobs[0].recipient_hash, "patient-a")


if __name__ == "__main__":
    unittest.main()
