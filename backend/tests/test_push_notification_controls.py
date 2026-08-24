# 파일명: test_push_notification_controls.py
# 역할: 기기 푸시 토큰 생명주기와 보호자 복약 완료 알림 분배를 검증한다.

import sys
import unittest
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from firebase_admin import exceptions as firebase_exceptions
from firebase_admin import messaging
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from boundaries.push_notification_boundary import (  # noqa: E402
    FirebasePushNotificationBoundary,
    PushDeliveryResult,
)
from controls.dispatch_caregiver_alert_control import (  # noqa: E402
    DispatchCaregiverAlert,
)
from controls.manage_push_token_control import ManagePushToken  # noqa: E402
from controls.process_caregiver_alert_outbox_control import (  # noqa: E402
    ProcessCaregiverAlertOutbox,
)
from core.database import Base  # noqa: E402
from entities.caregiver_notification_entity import (  # noqa: E402
    CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
    _CaregiverNotification,
    encode_slot_settings,
)
from entities.device_push_token_entity import _DevicePushToken  # noqa: E402
from entities.caregiver_alert_outbox_entity import (  # noqa: E402
    CAREGIVER_ALERT_STATUS_DEAD_LETTER,
    CAREGIVER_ALERT_STATUS_FAILED,
    CAREGIVER_ALERT_STATUS_PENDING,
    CAREGIVER_ALERT_STATUS_SENT,
    _CaregiverAlertOutbox,
)
from entities.patient_caregiver_link_entity import (  # noqa: E402
    _PatientCaregiverLink,
)
from entities.user_setting_entity import _UserSetting  # noqa: E402


class _RecordingPushBoundary:
    def __init__(
        self,
        invalid_tokens: tuple[str, ...] = (),
        retryable_failure_count: int = 0,
    ) -> None:
        self.invalid_tokens = invalid_tokens
        self.retryable_failure_count = retryable_failure_count
        self.calls: list[dict[str, object]] = []

    def send_notification(
        self,
        *,
        tokens: list[str],
        title: str,
        body: str,
        data: dict[str, str],
    ) -> PushDeliveryResult:
        self.calls.append(
            {
                "tokens": tokens,
                "title": title,
                "body": body,
                "data": data,
            }
        )
        return PushDeliveryResult(
            success_count=max(
                0,
                len(tokens)
                - len(self.invalid_tokens)
                - self.retryable_failure_count,
            ),
            invalid_tokens=self.invalid_tokens,
            retryable_failure_count=self.retryable_failure_count,
        )


class PushNotificationControlTest(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=self.engine)
        session_factory = sessionmaker(bind=self.engine)
        self.db = session_factory()

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def test_push_token_registration_moves_ownership_and_unregisters(self) -> None:
        control = ManagePushToken(self.db)
        token = "test-fcm-token-value-123456"

        control.registerPushToken("user-a", token, "android")
        control.registerPushToken("user-b", token, "ios")

        rows = self.db.query(_DevicePushToken).all()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].user_hash, "user-b")
        self.assertEqual(rows[0].platform, "ios")
        self.assertTrue(rows[0].enabled)

        control.unregisterPushToken("user-a", token)
        self.db.refresh(rows[0])
        self.assertTrue(rows[0].enabled)

        control.unregisterPushToken("user-b", token)
        self.db.refresh(rows[0])
        self.assertFalse(rows[0].enabled)

    def test_completed_dose_is_sent_only_for_matching_slot_setting(self) -> None:
        invalid_token = "expired-fcm-token-value-1234"
        active_token = "active-fcm-token-value-12345"
        self.db.add(
            _PatientCaregiverLink(
                patient_hash="patient-a",
                caregiver_hash="caregiver-a",
                linked=True,
            )
        )
        self.db.add(
            _CaregiverNotification(
                patient_hash="patient-a",
                caregiver_hash="caregiver-a",
                enabled=True,
                alert_option=CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
                slot_settings=encode_slot_settings(
                    {
                        "morning": {
                            "notification_type": (
                                CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED
                            ),
                            "deadline_hour": None,
                            "deadline_minute": None,
                        },
                        "lunch": {
                            "notification_type": (
                                CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE
                            ),
                            "deadline_hour": 13,
                            "deadline_minute": 0,
                        },
                    }
                ),
            )
        )
        self.db.add_all(
            [
                _DevicePushToken(
                    user_hash="caregiver-a",
                    token=active_token,
                    platform="android",
                    enabled=True,
                ),
                _DevicePushToken(
                    user_hash="caregiver-a",
                    token=invalid_token,
                    platform="android",
                    enabled=True,
                ),
            ]
        )
        self.db.commit()
        push_boundary = _RecordingPushBoundary(invalid_tokens=(invalid_token,))
        control = DispatchCaregiverAlert(self.db, push_boundary)

        control.notifySlotCompleted(
            patient_hash="patient-a",
            slot_key="lunch",
        )
        self.assertEqual(push_boundary.calls, [])

        delivery_result = control.notifySlotCompleted(
            patient_hash="patient-a",
            slot_key="morning",
        )

        self.assertEqual(len(push_boundary.calls), 1)
        self.assertCountEqual(
            push_boundary.calls[0]["tokens"],
            [active_token, invalid_token],
        )
        self.assertEqual(
            push_boundary.calls[0]["data"],
            {
                "type": "caregiver_slot_completed",
                "patient_hash": "patient-a",
                "slot_key": "morning",
            },
        )
        self.assertEqual(push_boundary.calls[0]["title"], "환자 복약 완료")
        self.assertEqual(
            push_boundary.calls[0]["body"],
            "환자가 아침에 복용할 약을 모두 복용했습니다.",
        )
        self.assertEqual(delivery_result.success_count, 1)
        self.assertTrue(delivery_result.all_valid_targets_succeeded)
        invalid_row = (
            self.db.query(_DevicePushToken)
            .filter(_DevicePushToken.token == invalid_token)
            .one()
        )
        self.assertFalse(invalid_row.enabled)

    def test_fcm_permanent_token_error_is_disabled_without_retry(self) -> None:
        malformed_token = "malformed-fcm-token-value-1234"
        throttled_token = "throttled-fcm-token-value-1234"
        response = SimpleNamespace(
            success_count=0,
            responses=[
                SimpleNamespace(
                    success=False,
                    exception=firebase_exceptions.InvalidArgumentError(
                        "Invalid registration token."
                    ),
                ),
                SimpleNamespace(
                    success=False,
                    exception=messaging.QuotaExceededError("Quota exceeded."),
                ),
            ],
        )
        boundary = FirebasePushNotificationBoundary.__new__(
            FirebasePushNotificationBoundary
        )
        boundary._app = object()

        with patch(
            "boundaries.push_notification_boundary.messaging."
            "send_each_for_multicast",
            return_value=response,
        ):
            result = boundary.send_notification(
                tokens=[malformed_token, throttled_token],
                title="Patient dose completed",
                body="The scheduled dose was completed.",
                data={"type": "caregiver_slot_completed"},
            )

        self.assertEqual(result.invalid_tokens, (malformed_token,))
        self.assertEqual(result.retryable_failure_count, 1)
        self.assertFalse(result.all_valid_targets_succeeded)

    def test_caregiver_global_setting_controls_completed_dose_push(self) -> None:
        self.db.add_all(
            [
                _PatientCaregiverLink(
                    patient_hash="patient-a",
                    caregiver_hash="caregiver-a",
                    linked=True,
                ),
                _CaregiverNotification(
                    patient_hash="patient-a",
                    caregiver_hash="caregiver-a",
                    enabled=True,
                    alert_option=CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
                    slot_settings=encode_slot_settings(
                        {
                            "evening": {
                                "notification_type": (
                                    CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED
                                ),
                                "deadline_hour": None,
                                "deadline_minute": None,
                            }
                        }
                    ),
                ),
                _DevicePushToken(
                    user_hash="caregiver-a",
                    token="caregiver-setting-token-value-12345",
                    platform="android",
                    enabled=True,
                ),
                _UserSetting(
                    user_hash="caregiver-a",
                    caregiver_notifications_enabled=False,
                ),
            ]
        )
        self.db.commit()
        boundary = _RecordingPushBoundary()
        control = DispatchCaregiverAlert(self.db, boundary)

        disabled_result = control.notifySlotCompleted(
            patient_hash="patient-a",
            slot_key="evening",
        )

        self.assertEqual(disabled_result.success_count, 0)
        self.assertEqual(boundary.calls, [])

        setting = self.db.query(_UserSetting).filter_by(user_hash="caregiver-a").one()
        setting.caregiver_notifications_enabled = True
        setting.notification_detail_mode = "type_only"
        self.db.commit()

        enabled_result = control.notifySlotCompleted(
            patient_hash="patient-a",
            slot_key="evening",
        )

        self.assertEqual(enabled_result.success_count, 1)
        self.assertEqual(
            boundary.calls[0]["body"],
            "연동된 환자의 복약 상태가 변경되었습니다.",
        )

    def test_outbox_marks_successful_delivery_as_sent(self) -> None:
        row = _CaregiverAlertOutbox(
            event_key="event-success",
            patient_hash="patient-a",
            slot_key="morning",
            status=CAREGIVER_ALERT_STATUS_PENDING,
        )
        self.db.add(row)
        self.db.commit()

        with patch(
            "controls.process_caregiver_alert_outbox_control."
            "DispatchCaregiverAlert.notifySlotCompleted",
            return_value=PushDeliveryResult(success_count=1),
        ) as notify:
            result = ProcessCaregiverAlertOutbox(
                self.db,
                _RecordingPushBoundary(),
            ).processOne(int(row.id))

        self.db.refresh(row)
        self.assertEqual(result, "sent")
        self.assertEqual(row.status, CAREGIVER_ALERT_STATUS_SENT)
        self.assertIsNotNone(row.sent_at)
        self.assertIsNone(row.processing_started_at)
        notify.assert_called_once_with(
            patient_hash="patient-a",
            slot_key="morning",
        )

    def test_outbox_retries_after_partial_push_delivery(self) -> None:
        row = _CaregiverAlertOutbox(
            event_key="event-partial-delivery",
            patient_hash="patient-a",
            slot_key="lunch",
            status=CAREGIVER_ALERT_STATUS_PENDING,
        )
        self.db.add(row)
        self.db.commit()

        with patch(
            "controls.process_caregiver_alert_outbox_control."
            "DispatchCaregiverAlert.notifySlotCompleted",
            return_value=PushDeliveryResult(
                success_count=1,
                retryable_failure_count=1,
            ),
        ):
            result = ProcessCaregiverAlertOutbox(
                self.db,
                _RecordingPushBoundary(),
            ).processOne(int(row.id))

        self.db.refresh(row)
        self.assertEqual(result, "failed")
        self.assertEqual(row.status, CAREGIVER_ALERT_STATUS_FAILED)
        self.assertEqual(row.attempt_count, 1)
        self.assertEqual(row.last_error, "_RetryablePushDeliveryError")
        self.assertIsNone(row.sent_at)

    def test_outbox_reschedules_failed_delivery(self) -> None:
        row = _CaregiverAlertOutbox(
            event_key="event-failure",
            patient_hash="patient-a",
            slot_key="evening",
            status=CAREGIVER_ALERT_STATUS_PENDING,
        )
        self.db.add(row)
        self.db.commit()
        attempted_at = datetime.utcnow()

        with patch(
            "controls.process_caregiver_alert_outbox_control."
            "DispatchCaregiverAlert.notifySlotCompleted",
            side_effect=RuntimeError("temporary push failure"),
        ):
            result = ProcessCaregiverAlertOutbox(
                self.db,
                _RecordingPushBoundary(),
            ).processOne(int(row.id))

        self.db.refresh(row)
        self.assertEqual(result, "failed")
        self.assertEqual(row.status, CAREGIVER_ALERT_STATUS_FAILED)
        self.assertEqual(row.attempt_count, 1)
        self.assertGreater(row.available_at, attempted_at)
        self.assertEqual(row.last_error, "RuntimeError")
        self.assertIsNone(row.processing_started_at)

    def test_outbox_dead_letters_after_retry_budget_is_exhausted(self) -> None:
        row = _CaregiverAlertOutbox(
            event_key="event-retry-exhausted",
            patient_hash="patient-a",
            slot_key="bedtime",
            status=CAREGIVER_ALERT_STATUS_PENDING,
            attempt_count=7,
        )
        self.db.add(row)
        self.db.commit()

        with patch(
            "controls.process_caregiver_alert_outbox_control."
            "DispatchCaregiverAlert.notifySlotCompleted",
            side_effect=RuntimeError("permanent delivery failure"),
        ):
            result = ProcessCaregiverAlertOutbox(
                self.db,
                _RecordingPushBoundary(),
            ).processOne(int(row.id))

        self.db.refresh(row)
        self.assertEqual(result, "failed")
        self.assertEqual(row.status, CAREGIVER_ALERT_STATUS_DEAD_LETTER)
        self.assertEqual(row.attempt_count, 8)
        self.assertEqual(row.last_error, "RuntimeError")

        with patch(
            "controls.process_caregiver_alert_outbox_control."
            "DispatchCaregiverAlert.notifySlotCompleted"
        ) as notify:
            due_result = ProcessCaregiverAlertOutbox(
                self.db,
                _RecordingPushBoundary(),
            ).processDue()

        self.assertEqual(due_result, {"sent": 0, "failed": 0, "skipped": 0})
        notify.assert_not_called()


if __name__ == "__main__":
    unittest.main()
