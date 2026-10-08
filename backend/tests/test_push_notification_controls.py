# 파일명: test_push_notification_controls.py
# 역할: 기기 토큰 소유권, 보호자 복약 푸시 정책 및 outbox 재시도·종료 처리를 검증한다.

import sys
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

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
from entities.saved_medication_entity import _SavedMedication  # noqa: E402
from entities.caregiver_notification_entity import (  # noqa: E402
    CAREGIVER_NOTIFICATION_MODE_DISABLED,
    CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
    CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
    _CaregiverNotification,
    encode_slot_settings,
)
from entities.device_push_token_entity import _DevicePushToken  # noqa: E402
from entities.caregiver_alert_outbox_entity import (  # noqa: E402
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


# 클래스명: PushNotificationControlTest
# 역할: 기기 토큰 등록부터 시간대별 보호자 알림과 outbox 전달 상태까지 검증하는 테스트 모음이다.
# 주요 책임:
# - 같은 기기 토큰의 소유자를 최신 사용자로 옮기고 다른 사용자의 해제는 무시하며 소유자 해제만 비활성화하는지 검증한다.
# - 성공한 outbox 전달을 sent와 전송 시각으로 기록하고 처리 시작 표시를 해제하며 해당 환자·시간대만 알리는지 검증한다.
# - 전달 예외 후 실패 유형과 시도 횟수를 기록하고 다음 실행 시각을 늦추며 처리 중 표시를 해제하는지 검증한다.
# 속성:
# - engine (Engine): 격리 인메모리 SQLite 엔진.
# - db (Session): 이 테스트의 DB 상태만 보관하는 SQLAlchemy 세션.
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

    # Function Name: test_fcm_permanent_token_error_is_disabled_without_retry
    # Description:
    # - Separates permanent malformed-token failures from retryable FCM failures and does
    #   not retry invalid tokens.
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

    def test_device_capability_is_opt_in_and_resets_for_legacy_registration(self) -> None:
        control = ManagePushToken(self.db)
        token = "capability-test-device-token-12345"
        control.registerPushToken("user-a", token, "android", True)
        self.assertTrue(self.db.query(_DevicePushToken).filter_by(token=token).one().supports_caregiver_actions)
        control.registerPushToken("user-a", token, "android")
        self.assertFalse(self.db.query(_DevicePushToken).filter_by(token=token).one().supports_caregiver_actions)

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
        )

    # 함수이름: test_outbox_retries_after_partial_push_delivery
    # 함수역할:
    # - 일부 푸시가 일시 실패하면 outbox를 실패·1회 시도로 기록하고 전송 완료 시각을 남기지 않는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_outbox_reschedules_failed_delivery
    # 함수역할:
    # - 전달 예외 후 실패 유형과 시도 횟수를 기록하고 다음 실행 시각을 늦추며 처리 중 표시를 해제하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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


# 함수이름: _seed_caregiver_alert_scene
# 함수역할:
# - 환자·보호자 연동, 아침 시간대 알림 설정, 미완료 아침 약과 보호자·타인의 기기 토큰을 저장한다.
# - 보호자에게는 일반·액션 지원·비활성 토큰을 하나씩 두어 수신 대상 선택을 검증할 수 있게 한다.
# 매개변수:
# - db (Session): 외래 키가 적용된 테스트 세션.
# - notification_type (str): 아침 시간대에 저장할 보호자 알림 모드.
# - user_setting (dict[str, object] | None): 보호자 user_settings 값; None이면 행을 만들지 않는다.
# - slot_settings (str | None): 저장할 시간대 JSON 원문; None이면 아침 시간대만 담아 저장한다.
# 반환값:
# - 없음 (None).
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


# 함수이름: _notify_missed_morning
# 함수역할:
# - 오늘 아침 시간대의 미복용 알림을 보호자에게 전송한다.
# 매개변수:
# - db (Session): 전송 제어가 사용할 테스트 세션.
# - boundary (object): 전송 요청을 기록하는 푸시 대체 경계.
# - alert_context (dict[str, str] | None): 액션 지원 기기에 함께 보낼 알림 문맥.
# 반환값:
# - PushDeliveryResult: 미복용 알림 전송 집계.
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


# 함수이름: test_completed_alert_follows_recipient_language_and_detail_mode
# 함수역할:
# - 완료 알림의 제목·본문·언어 데이터가 보호자의 언어와 종류만 표시 설정을 따르는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# - user_setting (dict[str, object] | None): 보호자 설정 값 또는 행 없음.
# - language (str): 기대하는 알림 언어 코드.
# - show_details (bool): 시간대가 드러나는 상세 문구를 기대하는지 여부.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_missed_alert_follows_recipient_language_and_detail_mode
# 함수역할:
# - 미복용 알림의 제목·본문·언어 데이터가 보호자의 언어와 종류만 표시 설정을 따르는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# - user_setting (dict[str, object] | None): 보호자 설정 값 또는 행 없음.
# - language (str): 기대하는 알림 언어 코드.
# - show_details (bool): 시간대가 드러나는 상세 문구를 기대하는지 여부.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_missed_alert_sends_action_data_only_to_action_capable_devices
# 함수역할:
# - 알림 문맥이 있으면 액션 지원 기기에만 문맥·제목·본문 데이터를 보내고 나머지 기기는 기존 알림을 받는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_caregiver_switch_blocks_both_caregiver_alerts_but_chat_switch_does_not
# 함수역할:
# - 보호자 알림 전역 설정을 끄면 완료·미복용 알림을 모두 보내지 않고, 채팅 알림 설정은 보호자 알림에 영향을 주지 않는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# - notification_type (str): 검증할 보호자 알림 모드.
# 반환값:
# - 없음 (None).
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

    # 함수이름: send
    # 함수역할: 검증 중인 알림 모드에 맞는 전송을 한 번 수행한다.
    # 매개변수: 없음.
    # 반환값: 전송 요청을 기록한 푸시 대체 경계.
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


# 함수이름: file_sessions
# 함수역할:
# - 파일 SQLite 엔진의 세션 팩터리를 제공한다. 세션마다 다른 연결을 쓰므로 두 번째 세션은 커밋된 값만 읽는다.
# 매개변수:
# - tmp_path (Path): pytest가 제공하는 테스트별 임시 디렉터리.
# 반환값:
# - 외래 키가 적용된 파일 엔진의 sessionmaker; 테스트가 끝나면 엔진을 닫는다.
@pytest.fixture
def file_sessions(tmp_path):
    engine = make_engine(tmp_path)
    try:
        yield make_session_factory(engine)
    finally:
        engine.dispose()


# 함수이름: _send_alert
# 함수역할:
# - 알림 모드에 맞는 보호자 알림을 전송 제어로 직접 한 번 보낸다.
# 매개변수:
# - db (Session): 전송 제어가 사용할 테스트 세션.
# - boundary (object): 전송 요청을 기록하는 푸시 대체 경계.
# - notification_type (str): 완료 또는 미복용 알림 모드.
# 반환값:
# - PushDeliveryResult: 전송 집계.
def _send_alert(db, boundary, notification_type: str) -> PushDeliveryResult:
    if notification_type == CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED:
        return DispatchCaregiverAlert(db, boundary).notifySlotCompleted(
            patient_hash=_PATIENT, slot_key="morning",
        )
    return _notify_missed_morning(db, boundary)


# 함수이름: _queue_outbox_event
# 함수역할:
# - 오늘 아침 시간대의 아웃박스 요청을 대기 상태로 저장한다. 완료 요청이면 아침 약도 복용 완료로 바꾼다.
# 매개변수:
# - db (Session): 장면이 저장된 테스트 세션.
# - notification_type (str): 완료 또는 미복용 알림 모드.
# 반환값:
# - 저장된 아웃박스 행의 기본키.
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


# 함수이름: _fail_next_commits
# 함수역할:
# - 세션의 다음 커밋을 지정한 횟수만큼 DB 장애처럼 실패시키고 그 뒤에는 원래대로 동작하게 한다.
# 매개변수:
# - db (Session): 커밋을 실패시킬 테스트 세션.
# - count (int): 실패시킬 커밋 횟수.
# 반환값:
# - 없음 (None).
def _fail_next_commits(db, count: int = 1) -> None:
    original_commit = db.commit
    remaining = [count]

    # 함수이름: failing_commit
    # 함수역할: 남은 실패 횟수 동안 OperationalError를 올리고 이후에는 실제 커밋을 수행한다.
    # 매개변수: 없음.
    # 반환값: 없음 (None).
    def failing_commit() -> None:
        if remaining[0] > 0:
            remaining[0] -= 1
            raise OperationalError("COMMIT", None, Exception("database is unavailable"))
        original_commit()

    db.commit = failing_commit


# 함수이름: _fail_commits_after_first_send
# 함수역할:
# - 첫 전송이 일어난 직후부터 세션의 커밋을 지정한 횟수만큼 실패시키는 전송 훅을 만든다.
# 매개변수:
# - db (Session): 커밋을 실패시킬 테스트 세션.
# - count (int): 실패시킬 커밋 횟수.
# 반환값:
# - RecordingPushBoundary의 on_send에 넘길 훅.
def _fail_commits_after_first_send(db, count: int = 1):
    armed: list[bool] = []

    # 함수이름: hook
    # 함수역할: 첫 전송에서만 커밋 실패를 예약한다.
    # 매개변수: call (dict[str, object]): 기록된 전송 요청.
    # 반환값: 없음 (None).
    def hook(call: dict[str, object]) -> None:
        if not armed:
            armed.append(True)
            _fail_next_commits(db, count)

    return hook


# 함수이름: test_caregiver_push_is_sent_after_the_session_released_its_transaction
# 함수역할:
# - 완료·미복용 알림 모두 Firebase 호출 시점에 세션이 트랜잭션을 잡고 있지 않은지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# - notification_type (str): 검증할 보호자 알림 모드.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_outbox_event_is_claimed_before_send_and_recorded_after_it
# 함수역할:
# - 아웃박스 요청이 전송 전에 처리 중으로 커밋되고, 전송 중에는 풀 연결을 하나도 잡지 않으며, 전송 뒤 별도 트랜잭션으로 완료가 기록되는지 검증한다.
# 매개변수:
# - file_sessions (sessionmaker): 세션마다 다른 연결을 쓰는 파일 엔진 팩터리.
# - notification_type (str): 검증할 보호자 알림 모드.
# 반환값:
# - 없음 (None).
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

        # 함수이름: observe
        # 함수역할: 전송 시점에 대여 중인 풀 연결 수, 작업 세션 트랜잭션 여부와 다른 연결이 보는 아웃박스 상태를 기록한다.
        # 매개변수: call (dict[str, object]): 기록된 전송 요청.
        # 반환값: 없음 (None).
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


# 함수이름: test_rejected_tokens_are_disabled_in_a_committed_transaction
# 함수역할:
# - 완료·미복용 알림에서 Firebase가 거부한 토큰만 비활성화하고 그 변경이 다른 연결에서 보이도록 커밋되는지 검증한다.
# 매개변수:
# - file_sessions (sessionmaker): 세션마다 다른 연결을 쓰는 파일 엔진 팩터리.
# - notification_type (str): 검증할 보호자 알림 모드.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_delivered_event_stays_sent_when_token_cleanup_fails
# 함수역할:
# - 전송 직후 무효 토큰 정리가 DB 장애로 실패해도 전달된 요청을 실패로 되돌려 다시 보내지 않는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# - notification_type (str): 검증할 보호자 알림 모드.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_delivered_event_is_recorded_on_the_second_attempt
# 함수역할:
# - 전송 뒤 완료 기록이 한 번 실패하면 실패 상태로 바꾸지 않고 완료 기록만 다시 시도하는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# - notification_type (str): 검증할 보호자 알림 모드.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_delivered_event_keeps_its_lease_when_the_result_cannot_be_written
# 함수역할:
# - 전송 뒤 완료 기록이 거듭 실패하면 예외를 올리고 요청을 처리 중으로 남겨, 선점 시간이 끝나기 전에는 다시 보내지 않는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_event_whose_send_failed_is_retried_and_never_recorded_as_sent
# 함수역할:
# - Firebase 호출이 실패한 요청은 전송 완료로 기록하지 않고 재시도 상태로 남기며, 다음 시도에서 한 번만 전달되는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# - notification_type (str): 검증할 보호자 알림 모드.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_legacy_setting_without_slot_json_receives_completed_alert
# 함수역할:
# - 시간대 JSON이 비어 있고 기존 단일 설정 열만 켜진 행의 보호자도 완료 알림을 받는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_legacy_missed_deadline_setting_is_queued_and_delivered
# 함수역할:
# - 시간대 JSON이 비어 있는 기존 미복용 설정 행이 큐에 적재되고 실제 푸시까지 전달되는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# 반환값:
# - 없음 (None).
def test_legacy_missed_deadline_setting_is_queued_and_delivered(fk_db) -> None:
    _seed_caregiver_alert_scene(
        fk_db,
        notification_type=CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE,
        slot_settings="{}",
    )
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


# 함수이름: test_slot_disabled_by_the_caregiver_gets_no_alert
# 함수역할:
# - 기존 단일 설정 열이 켜져 있어도 보호자가 시간대 설정에서 직접 끈 시간대에는 큐 적재도 푸시도 없는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# - notification_type (str): 기존 단일 설정 열에 남아 있는 알림 모드.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_missed_event_delivery_stays_within_statement_budget
# 함수역할:
# - 미복용 요청 한 건의 선점부터 완료 기록까지 SQL 문 수가 상한을 넘지 않고 수신자 설정과 토큰을 한 번씩만 읽는지 검증한다.
# 매개변수:
# - fk_db (Session): 외래 키가 적용된 테스트 세션.
# 반환값:
# - 없음 (None).
def test_missed_event_delivery_stays_within_statement_budget(fk_db) -> None:
    notification_type = CAREGIVER_NOTIFICATION_MODE_MISSED_DEADLINE
    _seed_caregiver_alert_scene(fk_db, notification_type=notification_type)
    outbox_id = _queue_outbox_event(fk_db, notification_type)
    boundary = RecordingPushBoundary()
    processor = ProcessCaregiverAlertOutbox(fk_db, boundary)
    statements: list[str] = []
    engine = fk_db.get_bind()

    # 함수이름: record_statement
    # 함수역할: 실행되는 SQL 문을 순서대로 기록한다.
    # 매개변수: SQLAlchemy before_cursor_execute 이벤트 인자.
    # 반환값: 없음 (None).
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
