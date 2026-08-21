# 파일명: test_push_notification_controls.py
# 역할: 기기 푸시 토큰 생명주기와 보호자 복약 완료 알림 분배를 검증한다.

import sys
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from boundaries.push_notification_boundary import PushDeliveryResult  # noqa: E402
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
    CAREGIVER_ALERT_STATUS_FAILED,
    CAREGIVER_ALERT_STATUS_PENDING,
    CAREGIVER_ALERT_STATUS_SENT,
    _CaregiverAlertOutbox,
)
from entities.patient_caregiver_link_entity import (  # noqa: E402
    _PatientCaregiverLink,
)


class _RecordingPushBoundary:
    def __init__(self, invalid_tokens: tuple[str, ...] = ()) -> None:
        self.invalid_tokens = invalid_tokens
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
            success_count=len(tokens) - len(self.invalid_tokens),
            invalid_tokens=self.invalid_tokens,
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

        control.notifySlotCompleted(
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
        invalid_row = (
            self.db.query(_DevicePushToken)
            .filter(_DevicePushToken.token == invalid_token)
            .one()
        )
        self.assertFalse(invalid_row.enabled)

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
            "DispatchCaregiverAlert.notifySlotCompleted"
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


if __name__ == "__main__":
    unittest.main()
