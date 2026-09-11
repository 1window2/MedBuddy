# File Name: test_missed_dose_alerts.py
# Role: Verifies server-owned missed-dose queueing and caregiver push delivery.

import sys
import unittest
from datetime import date, datetime
from pathlib import Path
from unittest.mock import patch
from zoneinfo import ZoneInfo

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

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


if __name__ == "__main__":
    unittest.main()
