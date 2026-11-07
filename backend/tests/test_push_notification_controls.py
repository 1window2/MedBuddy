# 파일명: test_push_notification_controls.py
# 역할: 기기 토큰 소유권, 보호자 복약 푸시 정책 및 outbox 재시도·종료 처리를 검증한다.

import sys
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import ANY, patch

import pytest
from firebase_admin import exceptions as firebase_exceptions
from firebase_admin import messaging
from sqlalchemy import create_engine, event
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from support.db import (  # noqa: E402
    make_engine,
    make_session_factory,
    seed_account,
    seed_medication,
)
from support.fakes import RecordingPushBoundary  # noqa: E402

from boundaries.push_notification_boundary import (  # noqa: E402
    FirebasePushNotificationBoundary,
    PushDeliveryResult,
)
from controls.check_schedule_control import CheckSchedule  # noqa: E402
from controls.dispatch_caregiver_alert_control import (  # noqa: E402
    DispatchCaregiverAlert,
)
from controls.manage_push_token_control import ManagePushToken  # noqa: E402
from controls.process_caregiver_alert_outbox_control import (  # noqa: E402
    ProcessCaregiverAlertOutbox,
)
from controls.queue_missed_dose_alerts_control import (  # noqa: E402
    QueueMissedDoseAlerts,
    missed_event_key,
)
from core.database import Base  # noqa: E402
from core.application_clock import application_today  # noqa: E402
from core.config import settings  # noqa: E402
from entities.saved_medication_entity import _SavedMedication  # noqa: E402
from entities.caregiver_notification_entity import (  # noqa: E402
    CAREGIVER_NOTIFICATION_MODE_DISABLED,
    CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
    _CaregiverNotification,
    encode_slot_settings,
)
from entities.device_push_token_entity import _DevicePushToken  # noqa: E402
from entities.medication_alarm_entity import _MedicationAlarm  # noqa: E402
from entities.chat_message_entity import _ChatMessage  # noqa: E402
from entities.user_account_entity import utc_now  # noqa: E402
from entities.caregiver_alert_outbox_entity import (  # noqa: E402
    CAREGIVER_ALERT_EVENT_LATE_LINK_COMPLETED,
    CAREGIVER_ALERT_EVENT_DOSE_COMPLETED,
    CAREGIVER_ALERT_EVENT_MISSED_DEADLINE,
    CAREGIVER_ALERT_STATUS_DEAD_LETTER,
    CAREGIVER_ALERT_STATUS_FAILED,
    CAREGIVER_ALERT_STATUS_PENDING,
    CAREGIVER_ALERT_STATUS_PROCESSING,
    CAREGIVER_ALERT_STATUS_SENT,
    _CaregiverAlertOutbox,
)
from entities.patient_caregiver_link_entity import (  # noqa: E402
    _PatientCaregiverLink,
)
from entities.user_setting_entity import _UserSetting  # noqa: E402


# 클래스명: _RecordingPushBoundary
# 역할: 푸시 요청을 기록하고 무효 토큰 및 일시 실패 건수를 지정할 수 있는 대체 경계다.
# 주요 책임:
# - 푸시 내용을 기록하고 무효·일시 실패를 제외한 성공 건수와 실패 정보를 반환한다.
# 속성:
# - invalid_tokens (tuple[str, ...]): 푸시 대체 객체가 영구 무효로 분류할 토큰.
# - retryable_failure_count (int): 재시도가 필요한 일시 푸시 실패 건수.
# - calls (list[dict[str, object]]): 후속 검증을 위해 순서대로 기록한 요청.
class _RecordingPushBoundary:
    # 함수이름: __init__
    # 함수역할:
    # - 무효 토큰·재시도 가능 실패 건수와 빈 요청 이력을 준비한다.
    # 매개변수:
    # - invalid_tokens (tuple[str, ...]): 영구적으로 무효하다고 보고할 기기 토큰 목록.
    # - retryable_failure_count (int): 추가 시도가 필요한 일시 푸시 실패 건수.
    # 반환값:
    # - 없음 (None).
    def __init__(
        self,
        invalid_tokens: tuple[str, ...] = (),
        retryable_failure_count: int = 0,
    ) -> None:
        self.invalid_tokens = invalid_tokens
        self.retryable_failure_count = retryable_failure_count
        self.calls: list[dict[str, object]] = []

    # 함수이름: send_notification
    # 함수역할:
    # - 푸시 내용을 기록하고 무효·일시 실패를 제외한 성공 건수와 실패 정보를 반환한다.
    # 매개변수:
    # - tokens (list[str]): 푸시 전달 대상으로 제출할 수신 기기 토큰 목록.
    # - title (str): 푸시 대체 객체가 기록할 알림 제목.
    # - body (str): 기록할 알림 본문.
    # - data (dict[str, str]): 기록할 알림 라우팅 및 맥락 데이터.
    # 반환값:
    # - PushDeliveryResult: 대체 객체에 지정한 전송 성공 건수와 영구·일시 토큰 실패 정보.
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


# Class Name: PushNotificationControlTest
# Role: Tests device registration, caregiver slot alerts, and outbox delivery state.
# Responsibilities:
# - Verify token ownership and revocation, recipient scoping, delivery retries, and terminal outbox outcomes.
# Attributes:
# - engine (Engine): isolated SQLite engine. db (Session): test session.
class PushNotificationControlTest(unittest.TestCase):
    # 함수이름: setUp
    # 함수역할:
    # - 격리된 SQLite 데이터베이스와 푸시·계정 엔티티용 세션을 준비한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=self.engine)
        session_factory = sessionmaker(bind=self.engine)
        self.db = session_factory()

    # 함수이름: tearDown
    # 함수역할:
    # - 푸시 전달 테스트의 DB 세션과 엔진을 닫는다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # 함수이름: test_push_token_registration_moves_ownership_and_unregisters
    # 함수역할:
    # - 같은 기기 토큰의 소유자를 최신 사용자로 옮기고 다른 사용자의 해제는 무시하며 소유자 해제만 비활성화하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # Function Name: test_registration_after_session_revocation_retires_older_devices
    # Description:
    # - Retire same-account devices not registered since revocation while preserving newer and unrelated devices; leave all enabled when revocation time is unknown.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_registration_after_session_revocation_retires_older_devices(self) -> None:
        control = ManagePushToken(self.db)
        for user, token in (("user-a", "stolen-device-token-0001"),
                            ("user-a", "second-device-token-0002"),
                            ("user-b", "other-account-token-0003")):
            control.registerPushToken(user, token, "android")
        rows = {row.token: row for row in self.db.query(_DevicePushToken).all()}
        long_ago = datetime(2026, 1, 1)
        for row in rows.values():
            row.updated_at = long_ago
        self.db.commit()
        revoked_at = datetime(2026, 6, 1)

        control.registerPushToken("user-a", "second-device-token-0002", "android",
                                  sessions_valid_after=None)
        self.db.refresh(rows["stolen-device-token-0001"])
        self.assertTrue(rows["stolen-device-token-0001"].enabled)

        control.registerPushToken("user-a", "new-phone-token-0004", "android",
                                  sessions_valid_after=revoked_at)
        for row in rows.values():
            self.db.refresh(row)
        # 두 번째 기기는 바로 위에서 다시 등록해 취소 시각보다 새로우므로 남는다.
        self.assertFalse(rows["stolen-device-token-0001"].enabled)
        self.assertTrue(rows["second-device-token-0002"].enabled)
        self.assertTrue(rows["other-account-token-0003"].enabled)

    # 함수이름: test_completed_dose_is_sent_only_for_matching_slot_setting
    # 함수역할:
    # - 완료 알림이 설정된 시간대에만 발송되고 무효 토큰은 비활성화하되 유효 대상 성공은 정상 집계하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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
                "recipient_hash": "caregiver-a",
                "language": "ko",
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

    # Function Name: test_action_capable_missed_is_data_only_but_other_notifications_are_unchanged
    # Description:
    # - Omits both notification payloads for action-version-1 missed-dose alerts while
    #   preserving titled notification payloads for legacy missed, chat, and completed alerts.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_action_capable_missed_is_data_only_but_other_notifications_are_unchanged(self) -> None:
        boundary = FirebasePushNotificationBoundary.__new__(FirebasePushNotificationBoundary)
        boundary._app = object()
        response = SimpleNamespace(success_count=1, responses=[SimpleNamespace(success=True)])
        with patch("boundaries.push_notification_boundary.messaging.send_each_for_multicast", return_value=response) as send:
            for payload in (
                {"type": "caregiver_slot_missed", "action_version": "1"},
                {"type": "caregiver_slot_missed"},
                {"type": "linked_chat_message"},
                {"type": "caregiver_slot_completed"},
            ):
                boundary.send_notification(tokens=["test-token"], title="title", body="body", data=payload)
                message = send.call_args.args[0]
                if payload.get("action_version") == "1":
                    self.assertIsNone(message.notification)
                    self.assertIsNone(message.android.notification)
                else:
                    self.assertEqual(message.notification.title, "title")
                    self.assertIsNotNone(message.android.notification)

    # Function Name: test_device_capability_is_opt_in_and_resets_for_legacy_registration
    # Description:
    # - Requires explicit action capability opt-in and clears it when the device re-registers through the legacy contract.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_device_capability_is_opt_in_and_resets_for_legacy_registration(self) -> None:
        control = ManagePushToken(self.db)
        token = "capability-test-device-token-12345"
        control.registerPushToken("user-a", token, "android", True)
        self.assertTrue(self.db.query(_DevicePushToken).filter_by(token=token).one().supports_caregiver_actions)
        control.registerPushToken("user-a", token, "android")
        self.assertFalse(self.db.query(_DevicePushToken).filter_by(token=token).one().supports_caregiver_actions)

    # Function Name: test_fcm_permanent_token_error_is_disabled_without_retry
    # Description:
    # - Classifies a permanently malformed FCM token as invalid while retaining a throttled token as retryable.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

    # 함수이름: test_caregiver_global_setting_controls_completed_dose_push
    # 함수역할:
    # - 보호자 전역 알림 비활성 시 전송을 생략하고 종류만 표시 모드에서는 구체적 복약 내용 대신 일반 안내를 보내는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_outbox_marks_successful_delivery_as_sent
    # 함수역할:
    # - 성공한 outbox 전달을 sent와 전송 시각으로 기록하고 처리 시작 표시를 해제하며 해당 환자·시간대만 알리는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_outbox_marks_successful_delivery_as_sent(self) -> None:
        self._completed_slot("morning")
        row = _CaregiverAlertOutbox(
            event_key="event-success",
            schedule_date=application_today(),
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
            event_key=ANY,
        )
        self.assertRegex(notify.call_args.kwargs["event_key"], r"^[0-9a-f]{64}$")

    # Function Name: test_outbox_gives_up_a_row_that_keeps_stalling_in_processing
    # Description:
    # - Count stalled processing recoveries as attempts and dead-letter the row at the limit without sending.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_outbox_gives_up_a_row_that_keeps_stalling_in_processing(self) -> None:
        self._completed_slot("evening")
        row = _CaregiverAlertOutbox(
            event_key="event-stalled",
            schedule_date=application_today(),
            patient_hash="patient-a",
            slot_key="evening",
            status=CAREGIVER_ALERT_STATUS_PROCESSING,
            processing_started_at=utc_now() - timedelta(hours=1),
            attempt_count=7,
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
        self.assertEqual(result, "failed")
        self.assertEqual(row.attempt_count, 8)
        self.assertEqual(row.status, CAREGIVER_ALERT_STATUS_DEAD_LETTER)
        self.assertEqual(row.last_error, "StalledProcessing")
        self.assertIsNone(row.sent_at)
        notify.assert_not_called()

    # Function Name: test_outbox_retries_after_partial_push_delivery
    # Description:
    # - Mark partial transient push delivery failed with one attempt and no sent timestamp.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_outbox_retries_after_partial_push_delivery(self) -> None:
        self._completed_slot("lunch")
        row = _CaregiverAlertOutbox(
            event_key="event-partial-delivery",
            schedule_date=application_today(),
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

    # Function Name: test_outbox_reschedules_failed_delivery
    # Description:
    # - Record the delivery exception and attempt count, delay the next attempt, and clear the processing marker.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_outbox_reschedules_failed_delivery(self) -> None:
        self._completed_slot("evening")
        row = _CaregiverAlertOutbox(
            event_key="event-failure",
            schedule_date=application_today(),
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

    # Function Name: test_outbox_dead_letters_after_retry_budget_is_exhausted
    # Description:
    # - Dead-letters an outbox event after eight failed attempts and prevents later
    #   due-event processing from retrying it.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_outbox_dead_letters_after_retry_budget_is_exhausted(self) -> None:
        self._completed_slot("bedtime")
        row = _CaregiverAlertOutbox(
            event_key="event-retry-exhausted",
            schedule_date=application_today(),
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

    # Function Name: _completed_slot
    # Description: Persist a real, active completed dose for outbox delivery tests.
    # Parameters: slot_key: Slot to complete.
    # Returns: Saved fixture medication.
    def _completed_slot(self, slot_key: str) -> _SavedMedication:
        row = _SavedMedication(
            patient_hash="patient-a", item_name="test-only-tablet",
            created_date=application_today(), total_days="7 days",
            schedule_slot_keys=f'["{slot_key}"]',
            medication_status=True, medication_status_date=application_today(),
        )
        self.db.add(row)
        self.db.commit()
        return row

    # Function Name: test_outbox_suppresses_stale_future_and_undated_completion
    # Description: Delayed work cannot create today's chat or push from another
    # day's event, even if today's slot happens to be complete.
    # Parameters: self: Test case instance.
    # Returns: None.
    def test_outbox_suppresses_stale_future_and_undated_completion(self) -> None:
        self._completed_slot("morning")
        for offset in (-1, 1, None):
            with self.subTest(offset=offset):
                row = _CaregiverAlertOutbox(
                    event_key=f"stale-{offset}", patient_hash="patient-a",
                    slot_key="morning",
                    schedule_date=(application_today() + timedelta(days=offset)
                                   if offset is not None else None),
                )
                self.db.add(row)
                self.db.commit()
                with patch.object(DispatchCaregiverAlert, "notifySlotCompleted") as notify, patch(
                    "controls.process_caregiver_alert_outbox_control.ManageLinkedChat.publish_slot_completion"
                ) as publish:
                    result = ProcessCaregiverAlertOutbox(self.db, _RecordingPushBoundary()).processOne(row.id)
                self.assertEqual(result, "skipped")
                self.assertEqual(row.status, CAREGIVER_ALERT_STATUS_DEAD_LETTER)
                self.assertEqual(row.last_error, "StaleOrUndatedCompletion")
                self.assertIsNone(row.sent_at)
                notify.assert_not_called()
                publish.assert_not_called()

    # Function Name: test_outbox_suppresses_corrected_or_deleted_completion
    # Description: Reversing or deleting a dose before delivery suppresses its
    # queued completion claim without changing the patient's correction.
    # Parameters: self: Test case instance.
    # Returns: None.
    def test_outbox_suppresses_corrected_or_deleted_completion(self) -> None:
        medication = self._completed_slot("morning")
        medication.medication_status = False
        self.db.commit()
        for deleted in (False, True):
            with self.subTest(deleted=deleted):
                if deleted:
                    self.db.delete(medication)
                    self.db.commit()
                row = _CaregiverAlertOutbox(
                    event_key=f"corrected-{deleted}", patient_hash="patient-a",
                    slot_key="morning", schedule_date=application_today(),
                )
                self.db.add(row)
                self.db.commit()
                with patch.object(DispatchCaregiverAlert, "notifySlotCompleted") as notify, patch(
                    "controls.process_caregiver_alert_outbox_control.ManageLinkedChat.publish_slot_completion"
                ) as publish:
                    result = ProcessCaregiverAlertOutbox(self.db, _RecordingPushBoundary()).processOne(row.id)
                self.assertEqual(result, "skipped")
                self.assertEqual(row.last_error, "CompletionNoLongerCurrent")
                self.assertEqual(row.status, CAREGIVER_ALERT_STATUS_DEAD_LETTER)
                notify.assert_not_called()
                publish.assert_not_called()


_PATIENT = "patient-a"
_CAREGIVER = "caregiver-a"
_OTHER_USER = "caregiver-b"
_PLAIN_TOKEN = "caregiver-a-plain-device-token-12345"
_ACTION_TOKEN = "caregiver-a-action-device-token-1234"
_DISABLED_TOKEN = "caregiver-a-disabled-device-token-12"
_OTHER_USER_TOKEN = "caregiver-b-device-token-value-12345"

# (user_settings 값 또는 행 없음, 기대 언어, 상세 문구 노출 여부)
_RECIPIENT_PREFERENCE_CASES = (
    (None, "ko", True),
    ({"language": "en"}, "en", True),
    ({"language": " EN "}, "en", True),
    ({"language": "fr"}, "ko", True),
    ({"notification_detail_mode": "type_only"}, "ko", False),
    ({"language": "en", "notification_detail_mode": "type_only"}, "en", False),
)
_COMPLETED_TEXT = {
    ("ko", True): ("환자 복약 완료", "환자가 아침에 복용할 약을 모두 복용했습니다."),
    ("ko", False): ("환자 복약 완료", "연동된 환자의 복약 상태가 변경되었습니다."),
    ("en", True): (
        "Medication completed",
        "The patient completed all morning medications.",
    ),
    ("en", False): (
        "Medication completed",
        "A linked patient's medication status was updated.",
    ),
}
_MISSED_TEXT = {
    ("ko", True): (
        "미복용 일정 확인",
        "연동된 환자의 아침 복약이 아직 확인되지 않았습니다. 필요하면 연락해 주세요.",
    ),
    ("ko", False): ("미복용 일정 확인", "연동된 환자의 복약 상태를 확인해 주세요."),
    ("en", True): (
        "Medication not checked",
        "The linked patient's morning medication is not checked yet. "
        "Please contact them if needed.",
    ),
    ("en", False): (
        "Medication not checked",
        "A linked patient has a medication update.",
    ),
}


# Function Name: _seed_caregiver_alert_scene
# Description:
# - Seed a linked caregiver, morning alert preferences, an incomplete morning dose, and active, action-capable, disabled, and unrelated device tokens.
# Parameters:
# - db: Session; isolated database with foreign keys.
# - notification_type: str; morning alert mode.
# - user_setting: dict[str, object] | None; caregiver preferences, or no row.
# - slot_settings: str | None; raw slot JSON, or the default morning-only mapping.
# Returns:
# - None.
def _seed_caregiver_alert_scene(
    db,
    *,
    notification_type: str,
    user_setting: dict[str, object] | None = None,
    slot_settings: str | None = None,
) -> None:
    seed_account(db, _PATIENT, _CAREGIVER, _OTHER_USER)
    seed_medication(db, patient_hash=_PATIENT, schedule_slot_keys='["morning"]')
    db.add_all(
        [
            _PatientCaregiverLink(
                patient_hash=_PATIENT, caregiver_hash=_CAREGIVER, linked=True,
            ),
            _CaregiverNotification(
                patient_hash=_PATIENT,
                caregiver_hash=_CAREGIVER,
                enabled=True,
                alert_option=notification_type,
                deadline_hour=0,
                deadline_minute=0,
                slot_settings=(
                    slot_settings
                    if slot_settings is not None
                    else encode_slot_settings(
                        {
                            "morning": {
                                "notification_type": notification_type,
                                "deadline_hour": 0,
                                "deadline_minute": 0,
                            }
                        }
                    )
                ),
            ),
            _DevicePushToken(user_hash=_CAREGIVER, token=_PLAIN_TOKEN),
            _DevicePushToken(
                user_hash=_CAREGIVER,
                token=_ACTION_TOKEN,
                supports_caregiver_actions=True,
            ),
            _DevicePushToken(
                user_hash=_CAREGIVER, token=_DISABLED_TOKEN, enabled=False,
            ),
            _DevicePushToken(user_hash=_OTHER_USER, token=_OTHER_USER_TOKEN),
        ]
    )
    if user_setting is not None:
        db.add(_UserSetting(user_hash=_CAREGIVER, **user_setting))
    db.commit()


# Function Name: _notify_missed_morning
# Description:
# - Send the caregiver a missed-dose alert for this morning.
# Parameters:
# - db: Session; delivery control session.
# - boundary: object; recording push fake.
# - alert_context: dict[str, str] | None; optional action context for capable devices.
# Returns:
# - PushDeliveryResult; aggregated missed-dose delivery outcome.
def _notify_missed_morning(
    db, boundary, alert_context: dict[str, str] | None = None,
) -> PushDeliveryResult:
    return DispatchCaregiverAlert(db, boundary).notifySlotMissed(
        caregiver_hash=_CAREGIVER,
        patient_hash=_PATIENT,
        slot_key="morning",
        schedule_date=application_today(),
        alert_context=alert_context,
    )


# Function Name: test_completed_alert_follows_recipient_language_and_detail_mode
# Description:
# - Format completed-dose push title, body, and language data according to the recipient's language and privacy preferences.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# - user_setting: dict[str, object] | None; recipient settings or no settings row.
# - language: str; expected notification language.
# - show_details: bool; whether slot-specific details should be visible.
# Returns:
# - None.
@pytest.mark.parametrize(
    ("user_setting", "language", "show_details"), _RECIPIENT_PREFERENCE_CASES,
)
def test_completed_alert_follows_recipient_language_and_detail_mode(
    fk_db, user_setting, language, show_details,
) -> None:
    _seed_caregiver_alert_scene(
        fk_db,
        notification_type=CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
        user_setting=user_setting,
    )
    boundary = RecordingPushBoundary()

    result = DispatchCaregiverAlert(fk_db, boundary).notifySlotCompleted(
        patient_hash=_PATIENT, slot_key="morning",
    )

    assert result.success_count == 2
    assert len(boundary.calls) == 1
    call = boundary.calls[0]
    assert (call["title"], call["body"]) == _COMPLETED_TEXT[(language, show_details)]
    assert call["data"] == {
        "type": "caregiver_slot_completed",
        "recipient_hash": _CAREGIVER,
        "language": language,
        "patient_hash": _PATIENT,
        "slot_key": "morning",
    }
    # 비활성 토큰과 다른 사용자의 토큰은 수신 대상이 아니다.
    assert sorted(call["tokens"]) == sorted([_PLAIN_TOKEN, _ACTION_TOKEN])


# Function Name: test_missed_alert_follows_recipient_language_and_detail_mode
# Description:
# - Format missed-dose push title, body, and language data according to the recipient's language and privacy preferences.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# - user_setting: dict[str, object] | None; recipient settings or no settings row.
# - language: str; expected notification language.
# - show_details: bool; whether slot-specific details should be visible.
# Returns:
# - None.
@pytest.mark.parametrize(
    ("user_setting", "language", "show_details"), _RECIPIENT_PREFERENCE_CASES,
)
def test_missed_alert_follows_recipient_language_and_detail_mode(
    fk_db, user_setting, language, show_details,
) -> None:
    _seed_caregiver_alert_scene(
        fk_db,
        notification_type=CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
        user_setting=user_setting,
    )
    boundary = RecordingPushBoundary()

    result = _notify_missed_morning(fk_db, boundary)

    assert result.success_count == 2
    assert len(boundary.calls) == 1
    call = boundary.calls[0]
    assert (call["title"], call["body"]) == _MISSED_TEXT[(language, show_details)]
    assert call["data"] == {
        "type": "caregiver_slot_missed",
        "recipient_hash": _CAREGIVER,
        "language": language,
        "patient_hash": _PATIENT,
        "slot_key": "morning",
    }
    assert sorted(call["tokens"]) == sorted([_PLAIN_TOKEN, _ACTION_TOKEN])


# Function Name: test_missed_alert_sends_action_data_only_to_action_capable_devices
# Description:
# - Include action context, title, and body data only for action-capable devices while retaining legacy notification data for others.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# Returns:
# - None.
def test_missed_alert_sends_action_data_only_to_action_capable_devices(fk_db) -> None:
    _seed_caregiver_alert_scene(
        fk_db,
        notification_type=CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
        user_setting={"notification_detail_mode": "type_only"},
    )
    boundary = RecordingPushBoundary()
    title, body = _MISSED_TEXT[("ko", False)]

    result = _notify_missed_morning(
        fk_db, boundary, alert_context={"alert_id": "7", "link_id": "3"},
    )

    assert result.success_count == 2
    plain_call, action_call = boundary.calls
    base_data = {
        "type": "caregiver_slot_missed",
        "recipient_hash": _CAREGIVER,
        "language": "ko",
        "patient_hash": _PATIENT,
        "slot_key": "morning",
    }
    assert plain_call["tokens"] == [_PLAIN_TOKEN]
    assert plain_call["data"] == base_data
    assert action_call["tokens"] == [_ACTION_TOKEN]
    assert action_call["data"] == {
        **base_data,
        "alert_id": "7",
        "link_id": "3",
        "action_version": "1",
        "title": title,
        "body": body,
    }
    assert (action_call["title"], action_call["body"]) == (title, body)


# Function Name: test_caregiver_switch_blocks_both_caregiver_alerts_but_chat_switch_does_not
# Description:
# - Suppress both caregiver alert modes when their global switch is off, independently of the chat-alert switch.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# - notification_type: str; completed-dose or missed-dose alert mode.
# Returns:
# - None.
@pytest.mark.parametrize(
    "notification_type",
    (
        CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
        CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
    ),
)
def test_caregiver_switch_blocks_both_caregiver_alerts_but_chat_switch_does_not(
    fk_db, notification_type,
) -> None:
    _seed_caregiver_alert_scene(
        fk_db,
        notification_type=notification_type,
        user_setting={
            "caregiver_notifications_enabled": False,
            "chat_notifications_enabled": True,
        },
    )

    # Function Name: send
    # Description:
    # - Send one alert using the selected caregiver notification mode.
    # Parameters:
    # - None.
    # Returns:
    # - RecordingPushBoundary; fake containing the recorded requests.
    def send() -> RecordingPushBoundary:
        boundary = RecordingPushBoundary()
        if notification_type == CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED:
            DispatchCaregiverAlert(fk_db, boundary).notifySlotCompleted(
                patient_hash=_PATIENT, slot_key="morning",
            )
        else:
            _notify_missed_morning(fk_db, boundary)
        return boundary

    assert send().calls == []

    setting = fk_db.query(_UserSetting).filter_by(user_hash=_CAREGIVER).one()
    setting.caregiver_notifications_enabled = True
    setting.chat_notifications_enabled = False
    fk_db.commit()

    assert len(send().calls) == 1


_ALERT_MODES = (
    CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
)
# 아웃박스 요청 한 건이 만드는 전송 횟수. 미복용 요청은 알림 문맥이 붙어 일반 기기와 액션 지원 기기에 따로 보낸다.
_OUTBOX_PUSH_COUNT = {
    CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED: 1,
    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE: 2,
}


# Function Name: file_sessions
# Description:
# - Yield a foreign-key-enabled file database factory so independent sessions observe only committed changes.
# Parameters:
# - tmp_path: Path; isolated temporary directory.
# Returns:
# - Iterator[sessionmaker]; session factory, with the engine disposed after use.
@pytest.fixture
def file_sessions(tmp_path):
    engine = make_engine(tmp_path)
    try:
        yield make_session_factory(engine)
    finally:
        engine.dispose()


# Function Name: _send_alert
# Description:
# - Dispatch one completed or missed caregiver alert through the matching delivery method.
# Parameters:
# - db: Session; delivery control session.
# - boundary: object; recording push fake.
# - notification_type: str; completed-dose or missed-dose alert mode.
# Returns:
# - PushDeliveryResult; aggregated delivery result.
def _send_alert(db, boundary, notification_type: str) -> PushDeliveryResult:
    if notification_type == CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED:
        return DispatchCaregiverAlert(db, boundary).notifySlotCompleted(
            patient_hash=_PATIENT, slot_key="morning",
        )
    return _notify_missed_morning(db, boundary)


# Function Name: _queue_outbox_event
# Description:
# - Persist a pending morning outbox event and mark the medication complete for completed-dose events.
# Parameters:
# - db: Session; database containing the seeded scene.
# - notification_type: str; completed-dose or missed-dose alert mode.
# Returns:
# - int; persisted outbox identifier.
def _queue_outbox_event(db, notification_type: str) -> int:
    today = application_today()
    if notification_type == CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED:
        db.query(_SavedMedication).update(
            {"medication_status": True, "medication_status_date": today}
        )
        row = _CaregiverAlertOutbox(
            event_key="completed-morning-event",
            event_type=CAREGIVER_ALERT_EVENT_DOSE_COMPLETED,
            patient_hash=_PATIENT,
            slot_key="morning",
            schedule_date=today,
        )
    else:
        row = _CaregiverAlertOutbox(
            event_key=missed_event_key(_CAREGIVER, _PATIENT, today, "morning"),
            event_type=CAREGIVER_ALERT_EVENT_MISSED_DEADLINE,
            caregiver_hash=_CAREGIVER,
            patient_hash=_PATIENT,
            slot_key="morning",
            schedule_date=today,
        )
    db.add(row)
    db.commit()
    return int(row.id)


# 함수이름: test_completed_outbox_retry_keeps_event_identity_and_new_event_does_not_collapse
# 함수역할:
# - 완료 알림은 작업자가 바뀐 재시도에도 같은 기기 식별자를 쓰고 같은 날짜·슬롯의 새 이벤트는 별도로 구분하는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# - late_link: bool; 뒤늦은 연동 완료 이벤트로 검사할지 지정한다.
# 반환값:
# - None.
@pytest.mark.parametrize("late_link", [False, True])
def test_completed_outbox_retry_keeps_event_identity_and_new_event_does_not_collapse(fk_db, late_link):
    _seed_caregiver_alert_scene(fk_db, notification_type=CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED)
    outbox_id = _queue_outbox_event(fk_db, CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED)
    row = fk_db.get(_CaregiverAlertOutbox, outbox_id)
    if late_link:
        row.event_type = CAREGIVER_ALERT_EVENT_LATE_LINK_COMPLETED
        row.caregiver_hash = _CAREGIVER
        fk_db.commit()
    partial = SimpleNamespace(success_count=1, responses=[
        SimpleNamespace(success=True),
        SimpleNamespace(success=False, exception=messaging.QuotaExceededError("retry")),
    ])
    success = SimpleNamespace(success_count=2, responses=[SimpleNamespace(success=True)] * 2)
    boundary = FirebasePushNotificationBoundary.__new__(FirebasePushNotificationBoundary)
    boundary._app = object()
    with patch("boundaries.push_notification_boundary.messaging.send_each_for_multicast",
               side_effect=[partial, success, success]) as send:
        assert ProcessCaregiverAlertOutbox(fk_db, boundary).processOne(outbox_id) == "failed"
        row = fk_db.get(_CaregiverAlertOutbox, outbox_id)
        row.available_at = utc_now() - timedelta(seconds=1)
        fk_db.commit()
        # 새 작업자에서도 첫 전송과 같은 이벤트 식별자를 사용한다.
        assert ProcessCaregiverAlertOutbox(fk_db, boundary).processOne(outbox_id) == "sent"
        replacement = _CaregiverAlertOutbox(
            event_key="new-event-same-day-and-slot",
            event_type=row.event_type,
            caregiver_hash=row.caregiver_hash,
            patient_hash=_PATIENT, slot_key="morning", schedule_date=application_today(),
        )
        fk_db.add(replacement)
        fk_db.commit()
        assert ProcessCaregiverAlertOutbox(fk_db, boundary).processOne(replacement.id) == "sent"
    messages = [call.args[0] for call in send.call_args_list]
    keys = [message.data["event_key"] for message in messages]
    assert keys[0] == keys[1] != keys[2]
    for message in messages:
        key = message.data["event_key"]
        assert len(key) == 64 and set(key) <= set("0123456789abcdef")
        assert message.android.notification.tag == key
        assert message.apns.headers == {"apns-collapse-id": key}
        assert sorted(message.tokens) == sorted([_PLAIN_TOKEN, _ACTION_TOKEN])
        assert message.data == {
            "type": "caregiver_slot_completed", "recipient_hash": _CAREGIVER,
            "patient_hash": _PATIENT, "slot_key": "morning", "language": "ko",
            "event_key": key,
        }


# Function Name: _fail_next_commits
# Description:
# - Replace session commit with a bounded OperationalError injector, then resume normal commits.
# Parameters:
# - db: Session; session whose commit is replaced.
# - count: int; number of upcoming commits to fail.
# Returns:
# - None.
def _fail_next_commits(db, count: int = 1) -> None:
    original_commit = db.commit
    remaining = [count]

    # Function Name: failing_commit
    # Description:
    # - Raise OperationalError for the remaining injected failures, then delegate to the original commit.
    # Parameters:
    # - None.
    # Returns:
    # - None; raises OperationalError while failures remain.
    def failing_commit() -> None:
        if remaining[0] > 0:
            remaining[0] -= 1
            raise OperationalError("COMMIT", None, Exception("database is unavailable"))
        original_commit()

    db.commit = failing_commit


# Function Name: _fail_commits_after_first_send
# Description:
# - Create a send hook that arms commit failures only after the first push.
# Parameters:
# - db: Session; session whose commits will fail.
# - count: int; number of post-send commits to fail.
# Returns:
# - Callable; hook accepted by RecordingPushBoundary.on_send.
def _fail_commits_after_first_send(db, count: int = 1):
    armed: list[bool] = []

    # Function Name: hook
    # Description:
    # - Arm the configured commit failures on the first push only.
    # Parameters:
    # - call: dict[str, object]; recorded push request, unused.
    # Returns:
    # - None.
    def hook(call: dict[str, object]) -> None:
        if not armed:
            armed.append(True)
            _fail_next_commits(db, count)

    return hook


# Function Name: test_caregiver_push_is_sent_after_the_session_released_its_transaction
# Description:
# - Release the session transaction before Firebase delivery for either caregiver alert mode.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# - notification_type: str; completed-dose or missed-dose alert mode.
# Returns:
# - None.
@pytest.mark.parametrize("notification_type", _ALERT_MODES)
def test_caregiver_push_is_sent_after_the_session_released_its_transaction(
    fk_db, notification_type,
) -> None:
    _seed_caregiver_alert_scene(fk_db, notification_type=notification_type)
    open_transactions: list[bool] = []
    boundary = RecordingPushBoundary(
        on_send=lambda call: open_transactions.append(fk_db.in_transaction()),
    )

    result = _send_alert(fk_db, boundary, notification_type)

    assert result.success_count == 2
    assert open_transactions == [False]


# Function Name: test_outbox_event_is_claimed_before_send_and_recorded_after_it
# Description:
# - Commit the outbox claim before sending, hold no pooled connection during delivery, and persist completion in a later transaction.
# Parameters:
# - file_sessions: sessionmaker; isolated file database with independent session connections.
# - notification_type: str; completed-dose or missed-dose alert mode.
# Returns:
# - None.
@pytest.mark.parametrize("notification_type", _ALERT_MODES)
def test_outbox_event_is_claimed_before_send_and_recorded_after_it(
    file_sessions, notification_type,
) -> None:
    db = file_sessions()
    observer = file_sessions()
    try:
        _seed_caregiver_alert_scene(db, notification_type=notification_type)
        outbox_id = _queue_outbox_event(db, notification_type)
        pool = file_sessions.kw["bind"].pool
        seen_at_send: list[tuple[int, bool, str, object]] = []

        # Function Name: observe
        # Description:
        # - Observe checked-out connections, worker transaction state, and independently committed outbox state at send time.
        # Parameters:
        # - call: dict[str, object]; recorded push request, unused.
        # Returns:
        # - None.
        def observe(call: dict[str, object]) -> None:
            observer.rollback()
            checked_out = pool.checkedout()
            committed = observer.get(_CaregiverAlertOutbox, outbox_id)
            seen_at_send.append(
                (
                    checked_out,
                    db.in_transaction(),
                    str(committed.status),
                    committed.sent_at,
                )
            )

        boundary = RecordingPushBoundary(on_send=observe)

        outcome = ProcessCaregiverAlertOutbox(db, boundary).processOne(outbox_id)

        assert outcome == "sent"
        assert seen_at_send == [
            (0, False, CAREGIVER_ALERT_STATUS_PROCESSING, None)
        ] * _OUTBOX_PUSH_COUNT[notification_type]
        observer.rollback()
        committed = observer.get(_CaregiverAlertOutbox, outbox_id)
        assert committed.status == CAREGIVER_ALERT_STATUS_SENT
        assert committed.sent_at is not None
        assert committed.processing_started_at is None
        assert not db.in_transaction()
    finally:
        observer.close()
        db.close()


# Function Name: test_rejected_tokens_are_disabled_in_a_committed_transaction
# Description:
# - Commit deactivation of only Firebase-rejected tokens so independent sessions observe the change.
# Parameters:
# - file_sessions: sessionmaker; isolated file database with independent session connections.
# - notification_type: str; completed-dose or missed-dose alert mode.
# Returns:
# - None.
@pytest.mark.parametrize("notification_type", _ALERT_MODES)
def test_rejected_tokens_are_disabled_in_a_committed_transaction(
    file_sessions, notification_type,
) -> None:
    db = file_sessions()
    observer = file_sessions()
    try:
        _seed_caregiver_alert_scene(db, notification_type=notification_type)
        boundary = RecordingPushBoundary(invalid_tokens=(_PLAIN_TOKEN,))

        result = _send_alert(db, boundary, notification_type)

        assert result.success_count == 1
        assert result.invalid_tokens == (_PLAIN_TOKEN,)
        assert result.all_valid_targets_succeeded
        enabled_by_token = {
            str(row.token): bool(row.enabled)
            for row in observer.query(_DevicePushToken).all()
        }
        assert enabled_by_token == {
            _PLAIN_TOKEN: False,
            _ACTION_TOKEN: True,
            _DISABLED_TOKEN: False,
            _OTHER_USER_TOKEN: True,
        }
        assert not db.in_transaction()
    finally:
        observer.close()
        db.close()


# Function Name: test_delivered_event_stays_sent_when_token_cleanup_fails
# Description:
# - Keep successfully delivered events sent when invalid-token cleanup fails, without resending.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# - notification_type: str; completed-dose or missed-dose alert mode.
# Returns:
# - None.
@pytest.mark.parametrize("notification_type", _ALERT_MODES)
def test_delivered_event_stays_sent_when_token_cleanup_fails(
    fk_db, notification_type,
) -> None:
    _seed_caregiver_alert_scene(fk_db, notification_type=notification_type)
    outbox_id = _queue_outbox_event(fk_db, notification_type)
    boundary = RecordingPushBoundary(
        invalid_tokens=(_PLAIN_TOKEN,),
        on_send=_fail_commits_after_first_send(fk_db),
    )
    processor = ProcessCaregiverAlertOutbox(fk_db, boundary)

    outcome = processor.processOne(outbox_id)

    row = fk_db.get(_CaregiverAlertOutbox, outbox_id)
    assert outcome == "sent"
    assert row.status == CAREGIVER_ALERT_STATUS_SENT
    assert row.attempt_count == 0
    assert len(boundary.calls) == _OUTBOX_PUSH_COUNT[notification_type]
    # 정리 트랜잭션은 되돌려졌으므로 토큰은 다음 전송에서 다시 거부될 때 정리된다.
    assert fk_db.query(_DevicePushToken).filter_by(token=_PLAIN_TOKEN).one().enabled
    assert processor.processDue() == {"sent": 0, "failed": 0, "skipped": 0}
    assert len(boundary.calls) == _OUTBOX_PUSH_COUNT[notification_type]


# Function Name: test_delivered_event_is_recorded_on_the_second_attempt
# Description:
# - Retry only the completion-state write after its first failure, without recording delivery failure or sending again.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# - notification_type: str; completed-dose or missed-dose alert mode.
# Returns:
# - None.
@pytest.mark.parametrize("notification_type", _ALERT_MODES)
def test_delivered_event_is_recorded_on_the_second_attempt(
    fk_db, notification_type,
) -> None:
    _seed_caregiver_alert_scene(fk_db, notification_type=notification_type)
    outbox_id = _queue_outbox_event(fk_db, notification_type)
    boundary = RecordingPushBoundary(
        on_send=_fail_commits_after_first_send(fk_db),
    )
    processor = ProcessCaregiverAlertOutbox(fk_db, boundary)

    outcome = processor.processOne(outbox_id)

    row = fk_db.get(_CaregiverAlertOutbox, outbox_id)
    assert outcome == "sent"
    assert row.status == CAREGIVER_ALERT_STATUS_SENT
    assert row.sent_at is not None
    assert row.attempt_count == 0
    assert processor.processDue() == {"sent": 0, "failed": 0, "skipped": 0}
    assert len(boundary.calls) == _OUTBOX_PUSH_COUNT[notification_type]


# Function Name: test_delivered_event_keeps_its_lease_when_the_result_cannot_be_written
# Description:
# - Raise on repeated result-write failure and retain the processing lease so delivery is not retried before lease expiry.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# Returns:
# - None.
def test_delivered_event_keeps_its_lease_when_the_result_cannot_be_written(
    fk_db,
) -> None:
    notification_type = CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED
    _seed_caregiver_alert_scene(fk_db, notification_type=notification_type)
    outbox_id = _queue_outbox_event(fk_db, notification_type)
    boundary = RecordingPushBoundary(
        on_send=_fail_commits_after_first_send(fk_db, count=2),
    )
    processor = ProcessCaregiverAlertOutbox(fk_db, boundary)

    with pytest.raises(OperationalError):
        processor.processOne(outbox_id)

    fk_db.rollback()
    row = fk_db.get(_CaregiverAlertOutbox, outbox_id)
    assert row.status == CAREGIVER_ALERT_STATUS_PROCESSING
    assert row.sent_at is None
    assert row.attempt_count == 0
    assert processor.processDue() == {"sent": 0, "failed": 0, "skipped": 0}
    assert len(boundary.calls) == 1


# Function Name: test_event_whose_send_failed_is_retried_and_never_recorded_as_sent
# Description:
# - Keep a failed Firebase send retryable and unsent until a later successful delivery.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# - notification_type: str; completed-dose or missed-dose alert mode.
# Returns:
# - None.
@pytest.mark.parametrize("notification_type", _ALERT_MODES)
def test_event_whose_send_failed_is_retried_and_never_recorded_as_sent(
    fk_db, notification_type,
) -> None:
    _seed_caregiver_alert_scene(fk_db, notification_type=notification_type)
    outbox_id = _queue_outbox_event(fk_db, notification_type)

    outcome = ProcessCaregiverAlertOutbox(
        fk_db, RecordingPushBoundary(raises=RuntimeError("push provider is down")),
    ).processOne(outbox_id)

    row = fk_db.get(_CaregiverAlertOutbox, outbox_id)
    assert outcome == "failed"
    assert row.status == CAREGIVER_ALERT_STATUS_FAILED
    assert row.sent_at is None
    assert row.attempt_count == 1

    row.available_at = datetime.utcnow() - timedelta(seconds=1)
    fk_db.commit()
    boundary = RecordingPushBoundary()

    assert ProcessCaregiverAlertOutbox(fk_db, boundary).processDue() == {
        "sent": 1, "failed": 0, "skipped": 0,
    }
    assert len(boundary.calls) == _OUTBOX_PUSH_COUNT[notification_type]
    assert fk_db.get(_CaregiverAlertOutbox, outbox_id).status == CAREGIVER_ALERT_STATUS_SENT


# Function Name: test_legacy_setting_without_slot_json_receives_completed_alert
# Description:
# - Deliver completion alerts using enabled legacy preferences when slot JSON is absent.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# Returns:
# - None.
def test_legacy_setting_without_slot_json_receives_completed_alert(fk_db) -> None:
    _seed_caregiver_alert_scene(fk_db, notification_type="enable", slot_settings="{}")
    boundary = RecordingPushBoundary()

    result = DispatchCaregiverAlert(fk_db, boundary).notifySlotCompleted(
        patient_hash=_PATIENT, slot_key="morning",
    )

    assert result.success_count == 2
    assert [call["data"]["type"] for call in boundary.calls] == [
        "caregiver_slot_completed"
    ]


# Function Name: _link_late_caregiver
# Description:
# - Add a new caregiver link after the original completion push and enable its morning completion alerts.
# Parameters:
# - db: Session; database containing the completed-dose scene.
# - linked_at: datetime; creation timestamp for the new link.
# Returns:
# - int; newly persisted link identifier.
def _link_late_caregiver(db, linked_at: datetime) -> int:
    link = _PatientCaregiverLink(
        patient_hash=_PATIENT, caregiver_hash=_OTHER_USER, linked=True,
        created_at=linked_at,
    )
    db.add_all(
        [
            link,
            _CaregiverNotification(
                patient_hash=_PATIENT,
                caregiver_hash=_OTHER_USER,
                enabled=True,
                alert_option=CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
                slot_settings=encode_slot_settings(
                    {
                        "morning": {
                            "notification_type": CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
                            "deadline_hour": None,
                            "deadline_minute": None,
                        }
                    }
                ),
            ),
        ]
    )
    db.commit()
    return int(link.id)


# Function Name: test_caregiver_linked_after_the_sent_completion_alert_gets_it_once
# Description:
# - On recompletion, notify a newly linked caregiver and create its receipt once without notifying previous recipients again.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# Returns:
# - None.
def test_caregiver_linked_after_the_sent_completion_alert_gets_it_once(fk_db) -> None:
    _seed_caregiver_alert_scene(
        fk_db, notification_type=CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
    )
    schedule = CheckSchedule(fk_db)
    first_boundary = RecordingPushBoundary()
    schedule.updateMedicationSlotStatus("morning", True, _PATIENT)
    outbox_id = int(schedule.consumeCompletionEvents()[0]["outbox_id"])
    assert ProcessCaregiverAlertOutbox(fk_db, first_boundary).processOne(outbox_id) == "sent"
    assert [call["tokens"] for call in first_boundary.calls] == [
        [_PLAIN_TOKEN, _ACTION_TOKEN],
    ]
    sent_at = fk_db.get(_CaregiverAlertOutbox, outbox_id).sent_at
    late_link_id = _link_late_caregiver(fk_db, sent_at + timedelta(seconds=1))

    boundary = RecordingPushBoundary()
    worker = ProcessCaregiverAlertOutbox(fk_db, boundary)
    schedule.updateMedicationSlotStatus("morning", False, _PATIENT)
    schedule.updateMedicationSlotStatus("morning", True, _PATIENT)

    assert [
        int(event["outbox_id"]) for event in schedule.consumeCompletionEvents()
    ] == [outbox_id]
    late_row = (
        fk_db.query(_CaregiverAlertOutbox)
        .filter(_CaregiverAlertOutbox.id != outbox_id)
        .one()
    )
    assert late_row.event_type == CAREGIVER_ALERT_EVENT_LATE_LINK_COMPLETED
    assert (late_row.caregiver_hash, late_row.patient_hash) == (_OTHER_USER, _PATIENT)
    assert (late_row.slot_key, late_row.schedule_date) == ("morning", application_today())
    assert worker.processDue() == {"sent": 1, "failed": 0, "skipped": 0}
    assert [call["tokens"] for call in boundary.calls] == [[_OTHER_USER_TOKEN]]
    assert boundary.calls[0]["data"]["type"] == "caregiver_slot_completed"
    assert boundary.calls[0]["data"]["recipient_hash"] == _OTHER_USER
    assert fk_db.query(_ChatMessage).filter_by(link_id=late_link_id).count() == 1
    assert fk_db.query(_ChatMessage).filter(_ChatMessage.link_id != late_link_id).count() == 1

    schedule.updateMedicationSlotStatus("morning", False, _PATIENT)
    schedule.updateMedicationSlotStatus("morning", True, _PATIENT)

    assert worker.processDue() == {"sent": 0, "failed": 0, "skipped": 0}
    assert len(boundary.calls) == 1
    assert fk_db.query(_CaregiverAlertOutbox).count() == 2


# Function Name: test_link_older_than_the_sent_completion_alert_gets_no_second_alert
# Description:
# - Do not create a second completion alert for a link older than the original sent event, including a reactivated link.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# Returns:
# - None.
def test_link_older_than_the_sent_completion_alert_gets_no_second_alert(fk_db) -> None:
    _seed_caregiver_alert_scene(
        fk_db, notification_type=CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
    )
    schedule = CheckSchedule(fk_db)
    boundary = RecordingPushBoundary()
    worker = ProcessCaregiverAlertOutbox(fk_db, boundary)
    schedule.updateMedicationSlotStatus("morning", True, _PATIENT)
    outbox_id = int(schedule.consumeCompletionEvents()[0]["outbox_id"])
    assert worker.processOne(outbox_id) == "sent"
    link = fk_db.query(_PatientCaregiverLink).one()
    link.linked = False
    fk_db.commit()
    link.linked = True
    fk_db.commit()

    schedule.updateMedicationSlotStatus("morning", False, _PATIENT)
    schedule.updateMedicationSlotStatus("morning", True, _PATIENT)

    assert fk_db.query(_CaregiverAlertOutbox).count() == 1
    assert worker.processDue() == {"sent": 0, "failed": 0, "skipped": 0}
    assert len(boundary.calls) == 1


# Function Name: test_late_link_event_undone_before_delivery_is_sent_after_recompletion
# Description:
# - Skip a late-link event if the dose is undone before delivery, then send that same event once after recompletion.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# Returns:
# - None.
def test_late_link_event_undone_before_delivery_is_sent_after_recompletion(fk_db) -> None:
    _seed_caregiver_alert_scene(
        fk_db, notification_type=CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
    )
    schedule = CheckSchedule(fk_db)
    schedule.updateMedicationSlotStatus("morning", True, _PATIENT)
    outbox_id = int(schedule.consumeCompletionEvents()[0]["outbox_id"])
    ProcessCaregiverAlertOutbox(fk_db, RecordingPushBoundary()).processOne(outbox_id)
    sent_at = fk_db.get(_CaregiverAlertOutbox, outbox_id).sent_at
    _link_late_caregiver(fk_db, sent_at + timedelta(seconds=1))
    boundary = RecordingPushBoundary()
    worker = ProcessCaregiverAlertOutbox(fk_db, boundary)

    schedule.updateMedicationSlotStatus("morning", False, _PATIENT)
    schedule.updateMedicationSlotStatus("morning", True, _PATIENT)
    schedule.updateMedicationSlotStatus("morning", False, _PATIENT)

    assert worker.processDue() == {"sent": 0, "failed": 0, "skipped": 1}
    assert boundary.calls == []

    schedule.updateMedicationSlotStatus("morning", True, _PATIENT)

    assert worker.processDue() == {"sent": 1, "failed": 0, "skipped": 0}
    assert [call["tokens"] for call in boundary.calls] == [[_OTHER_USER_TOKEN]]
    assert fk_db.query(_CaregiverAlertOutbox).count() == 2


# Function Name: test_legacy_missed_deadline_setting_is_queued_and_delivered
# Description:
# - Queue and deliver a legacy missed-dose preference without slot JSON using a midnight deadline and zero grace period.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# - monkeypatch: pytest.MonkeyPatch; restores temporary dependency replacements.
# Returns:
# - None.
def test_legacy_missed_deadline_setting_is_queued_and_delivered(fk_db, monkeypatch) -> None:
    monkeypatch.setattr(settings, "CAREGIVER_MISSED_DOSE_GRACE_MINUTES", 0)
    _seed_caregiver_alert_scene(
        fk_db,
        notification_type=CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
        slot_settings="{}",
    )
    fk_db.add(
        _MedicationAlarm(
            patient_hash=_PATIENT, slot_key="morning", hour=0, minute=0, enabled=True,
        )
    )
    fk_db.commit()
    boundary = RecordingPushBoundary()

    assert QueueMissedDoseAlerts(fk_db).queueDue() == 1
    assert ProcessCaregiverAlertOutbox(fk_db, boundary).processDue() == {
        "sent": 1, "failed": 0, "skipped": 0,
    }

    assert [call["tokens"] for call in boundary.calls] == [
        [_PLAIN_TOKEN], [_ACTION_TOKEN],
    ]
    for call in boundary.calls:
        assert call["data"]["type"] == "caregiver_slot_missed"
        assert call["data"]["slot_key"] == "morning"


# Function Name: test_slot_disabled_by_the_caregiver_gets_no_alert
# Description:
# - Honor explicitly disabled slots even when the legacy single-mode preference remains enabled.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# - notification_type: str; completed-dose or missed-dose alert mode.
# Returns:
# - None.
@pytest.mark.parametrize("notification_type", _ALERT_MODES)
def test_slot_disabled_by_the_caregiver_gets_no_alert(fk_db, notification_type) -> None:
    _seed_caregiver_alert_scene(
        fk_db,
        notification_type=notification_type,
        slot_settings=encode_slot_settings(
            {
                "morning": {
                    "notification_type": CAREGIVER_NOTIFICATION_MODE_DISABLED,
                    "deadline_hour": None,
                    "deadline_minute": None,
                }
            }
        ),
    )
    boundary = RecordingPushBoundary()

    assert QueueMissedDoseAlerts(fk_db).queueDue() == 0
    _send_alert(fk_db, boundary, CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED)
    _send_alert(fk_db, boundary, CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE)

    assert boundary.calls == []


# Function Name: test_missed_event_delivery_stays_within_statement_budget
# Description:
# - Complete missed-dose outbox delivery within ten SQL statements, reading recipient preferences and tokens only once each.
# Parameters:
# - fk_db: Session; isolated database with foreign keys enabled.
# Returns:
# - None.
def test_missed_event_delivery_stays_within_statement_budget(fk_db) -> None:
    notification_type = CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE
    _seed_caregiver_alert_scene(fk_db, notification_type=notification_type)
    outbox_id = _queue_outbox_event(fk_db, notification_type)
    boundary = RecordingPushBoundary()
    processor = ProcessCaregiverAlertOutbox(fk_db, boundary)
    statements: list[str] = []
    engine = fk_db.get_bind()

    # Function Name: record_statement
    # Description:
    # - Record SQL statements in execution order for the outbox delivery query budget.
    # Parameters:
    # - conn: Connection; event connection, unused.
    # - cursor: DBAPI cursor; execution cursor, unused.
    # - statement: str; SQL text to append.
    # - parameters: object; bound values, unused.
    # - context: ExecutionContext; execution metadata, unused.
    # - executemany: bool; batch flag, unused.
    # Returns:
    # - None.
    def record_statement(conn, cursor, statement, parameters, context, executemany):
        statements.append(" ".join(statement.split()))

    event.listen(engine, "before_cursor_execute", record_statement)
    try:
        outcome = processor.processOne(outbox_id)
    finally:
        event.remove(engine, "before_cursor_execute", record_statement)

    assert outcome == "sent"
    assert len(boundary.calls) == _OUTBOX_PUSH_COUNT[notification_type]
    assert len(statements) <= 10, statements
    assert sum("FROM user_settings" in statement for statement in statements) == 1
    assert sum("FROM device_push_tokens" in statement for statement in statements) == 1


if __name__ == "__main__":
    unittest.main()
