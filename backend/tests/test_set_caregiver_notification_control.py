# File Name: test_set_caregiver_notification_control.py
# Role: Regression coverage for linked-caregiver notification defaults, per-slot settings,
#   validation, and legacy migration.

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.link_patient_caregiver_control import LinkPatientCaregiver  # noqa: E402
from controls.queue_missed_dose_alerts_control import (  # noqa: E402
    QueueMissedDoseAlerts,
)
from controls.set_caregiver_notification_control import (  # noqa: E402
    SetCaregiverNotification,
)
from core.application_clock import application_now  # noqa: E402
from core.database import Base  # noqa: E402
from entities.caregiver_alert_outbox_entity import (  # noqa: E402
    CAREGIVER_ALERT_EVENT_MISSED_DEADLINE,
    _CaregiverAlertOutbox,
)
from entities.caregiver_notification_entity import (  # noqa: E402
    _CaregiverNotification,
    effective_slot_settings,
)
from entities.saved_medication_entity import _SavedMedication  # noqa: E402


# 클래스명: SetCaregiverNotificationTest
# 역할: 연동된 보호자의 시간대별 완료·미복약 알림과 저장·검증 정책을 확인하는 테스트 모음이다.
# 주요 책임:
# - 설정 없는 연동 조회가 아침 비활성 기본값을 반환하고 읽기만으로 설정 행을 저장하지 않는지 검증한다.
# - 미복약 마감 알림에는 시각이 필수이며 누락은 400으로 거절하고 20:30 설정은 보존하는지 검증한다.
# - 구형 보호자 알림 테이블에 활성·유형·마감·시간대 컬럼과 기본값을 추가하고 중복 행을 하나로 정리하는지 검증한다.
# 속성:
# - engine (Engine): 격리 인메모리 SQLite 엔진.
# - db (Session): 이 테스트의 DB 상태만 보관하는 SQLAlchemy 세션.
# - link_control (LinkPatientCaregiver): fixture의 환자·보호자 관계를 생성할 연동 control.
# - control (SetCaregiverNotification): 운영 상태와 분리하여 검증할 유스케이스 control.
class SetCaregiverNotificationTest(unittest.TestCase):
    # Function Name: setUp
    # Description:
    # - Creates an isolated linking/notification database, upgrades its schema, and prepares
    #   both controls.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.link_control = LinkPatientCaregiver(self.db)
        self.control = SetCaregiverNotification(self.db)

    # Function Name: tearDown
    # Description:
    # - Closes the caregiver-notification session and disposes its database engine.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # Function Name: _link_caregiver
    # Description:
    # - Creates the standard patient-a/caregiver-a active link through a generated patient
    #   code.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def _link_caregiver(self) -> None:
        code_response = self.link_control.generatePatientHash("patient-a")
        self.link_control.requestPatientCaregiverLink(
            "caregiver-a",
            code_response["data"]["patient_code"],
        )

    # 함수이름: test_request_returns_disabled_default_without_persisting_read_state
    # 함수역할:
    # - 설정 없는 연동 조회가 아침 비활성 기본값을 반환하고 읽기만으로 설정 행을 저장하지 않는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_request_returns_disabled_default_without_persisting_read_state(self) -> None:
        self._link_caregiver()

        response = self.control.requestCaregiverNotificationSetting(
            "caregiver-a",
            "patient-a",
        )

        self.assertTrue(response["success"])
        self.assertEqual(response["data"]["caregiver_hash"], "caregiver-a")
        self.assertEqual(response["data"]["patient_hash"], "patient-a")
        self.assertFalse(response["data"]["is_enabled"])
        self.assertEqual(response["data"]["alert_option"], "disabled")
        self.assertEqual(response["data"]["slot_key"], "morning")
        self.assertEqual(self.db.query(_CaregiverNotification).count(), 0)

    # 함수이름: test_update_persists_enable_and_disable_options
    # 함수역할:
    # - 완료 알림 활성·비활성 전환을 응답과 동일 DB 행에 함께 반영하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_update_persists_enable_and_disable_options(self) -> None:
        self._link_caregiver()

        enable_response = self.control.saveCaregiverNotificationSetting(
            "caregiver-a",
            "patient-a",
            enabled=True,
        )

        self.assertTrue(enable_response["success"])
        self.assertTrue(enable_response["data"]["is_enabled"])
        self.assertEqual(
            enable_response["data"]["alert_option"],
            "dose_completed",
        )

        row = self.db.query(_CaregiverNotification).first()
        self.assertIsNotNone(row)
        self.assertTrue(row.enabled)
        self.assertEqual(row.alert_option, "dose_completed")

        disable_response = self.control.saveCaregiverNotificationSetting(
            "caregiver-a",
            "patient-a",
            alert_option="disable",
        )

        self.assertFalse(disable_response["data"]["is_enabled"])
        self.assertEqual(disable_response["data"]["alert_option"], "disabled")
        self.db.refresh(row)
        self.assertFalse(row.enabled)
        self.assertEqual(row.alert_option, "disabled")

    # Function Name: test_unlinked_caregiver_cannot_read_or_update_setting
    # Description:
    # - Rejects both reading and updating caregiver settings without an active link using
    #   HTTP 404.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_unlinked_caregiver_cannot_read_or_update_setting(self) -> None:
        with self.assertRaises(HTTPException) as read_context:
            self.control.requestCaregiverNotificationSetting("caregiver-a", "patient-a")
        self.assertEqual(read_context.exception.status_code, 404)

        with self.assertRaises(HTTPException) as update_context:
            self.control.saveCaregiverNotificationSetting(
                "caregiver-a",
                "patient-a",
                enabled=True,
            )
        self.assertEqual(update_context.exception.status_code, 404)

    # Function Name: test_invalid_alert_option_is_rejected
    # Description:
    # - Rejects an unsupported caregiver alert option with HTTP 400.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_invalid_alert_option_is_rejected(self) -> None:
        self._link_caregiver()

        with self.assertRaises(HTTPException) as context:
            self.control.saveCaregiverNotificationSetting(
                "caregiver-a",
                "patient-a",
                alert_option="later",
            )

        self.assertEqual(context.exception.status_code, 400)

    # 함수이름: test_string_enabled_value_is_parsed_without_truthiness_bug
    # 함수역할:
    # - 문자열로 전달된 비활성 값을 참으로 오해하지 않고 disabled 설정으로 저장하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_string_enabled_value_is_parsed_without_truthiness_bug(self) -> None:
        self._link_caregiver()

        response = self.control.saveCaregiverNotificationSetting(
            "caregiver-a",
            "patient-a",
            enabled="false",  # type: ignore[arg-type]
        )

        self.assertFalse(response["data"]["is_enabled"])
        self.assertEqual(response["data"]["alert_option"], "disabled")

    # 함수이름: test_missed_deadline_mode_requires_and_persists_time
    # 함수역할:
    # - 미복약 마감 알림에는 시각이 필수이며 누락은 400으로 거절하고 20:30 설정은 보존하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_missed_deadline_mode_requires_and_persists_time(self) -> None:
        self._link_caregiver()

        with self.assertRaises(HTTPException) as context:
            self.control.saveCaregiverNotificationSetting(
                "caregiver-a",
                "patient-a",
                alert_option="missed_deadline",
            )
        self.assertEqual(context.exception.status_code, 400)

        response = self.control.saveCaregiverNotificationSetting(
            "caregiver-a",
            "patient-a",
            alert_option="missed_deadline",
            deadline_hour=20,
            deadline_minute=30,
        )

        self.assertEqual(response["data"]["alert_option"], "missed_deadline")
        self.assertEqual(response["data"]["deadline_hour"], 20)
        self.assertEqual(response["data"]["deadline_minute"], 30)

    # 함수이름: test_each_medication_slot_keeps_an_independent_setting
    # 함수역할:
    # - 한 DB 행 안에서 아침 완료·저녁 미복약·다른 시간대 비활성 설정을 독립적으로 유지하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_each_medication_slot_keeps_an_independent_setting(self) -> None:
        self._link_caregiver()

        self.control.saveCaregiverNotificationSetting(
            "caregiver-a",
            "patient-a",
            alert_option="dose_completed",
            slot_key="morning",
        )
        self.control.saveCaregiverNotificationSetting(
            "caregiver-a",
            "patient-a",
            alert_option="missed_deadline",
            deadline_hour=21,
            deadline_minute=15,
            slot_key="evening",
        )

        response = self.control.requestCaregiverNotificationSettings(
            "caregiver-a",
            "patient-a",
        )
        settings = {
            setting["slot_key"]: setting
            for setting in response["data"]
        }

        self.assertEqual(settings["morning"]["alert_option"], "dose_completed")
        self.assertEqual(settings["lunch"]["alert_option"], "disabled")
        self.assertEqual(settings["evening"]["alert_option"], "missed_deadline")
        self.assertEqual(settings["evening"]["deadline_hour"], 21)
        self.assertEqual(settings["bedtime"]["alert_option"], "disabled")
        self.assertEqual(self.db.query(_CaregiverNotification).count(), 1)

    # 함수이름: test_invalid_medication_slot_is_rejected
    # 함수역할:
    # - 지원하지 않는 복약 시간대 키를 HTTP 400으로 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_invalid_medication_slot_is_rejected(self) -> None:
        self._link_caregiver()

        with self.assertRaises(HTTPException) as context:
            self.control.saveCaregiverNotificationSetting(
                "caregiver-a",
                "patient-a",
                enabled=True,
                slot_key="snack",
            )

        self.assertEqual(context.exception.status_code, 400)

    # 함수이름: test_legacy_row_shows_the_settings_the_workers_apply
    # 함수역할:
    # - 시간대 JSON이 비어 있는 기존 행에서 설정 화면 응답과 알림 작업이 읽는 effective_slot_settings가
    #   네 시간대 모두 같은 값이고, 일부 시간대만 저장된 행은 누락 시간대만 기존 열로 채우며 읽기만으로는
    #   행을 바꾸지 않는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_legacy_row_shows_the_settings_the_workers_apply(self) -> None:
        self._link_caregiver()
        legacy_rows = {
            "completion flag only": (
                {"enabled": True, "alert_option": "enable", "slot_settings": "{}"},
                {
                    slot_key: ("dose_completed", None, None)
                    for slot_key in ("morning", "lunch", "evening", "bedtime")
                },
            ),
            "single deadline with one saved slot": (
                {
                    "enabled": True,
                    "alert_option": "missed_deadline",
                    "deadline_hour": 21,
                    "deadline_minute": 10,
                    "slot_settings": '{"lunch":{"notification_type":"disabled"}}',
                },
                {
                    "morning": ("missed_deadline", 21, 10),
                    "lunch": ("disabled", None, None),
                    "evening": ("missed_deadline", 21, 10),
                    "bedtime": ("missed_deadline", 21, 10),
                },
            ),
        }

        for name, (columns, expected) in legacy_rows.items():
            with self.subTest(row=name):
                self.db.query(_CaregiverNotification).delete()
                row = _CaregiverNotification(
                    caregiver_hash="caregiver-a",
                    patient_hash="patient-a",
                    **columns,
                )
                self.db.add(row)
                self.db.commit()

                shown = self.control.requestCaregiverNotificationSettings(
                    "caregiver-a",
                    "patient-a",
                )["data"]
                applied = effective_slot_settings(row)

                self.assertEqual(
                    {
                        setting["slot_key"]: (
                            setting["notification_type"],
                            setting["deadline_hour"],
                            setting["deadline_minute"],
                        )
                        for setting in shown
                    },
                    expected,
                )
                self.assertEqual(
                    {
                        slot_key: (
                            setting["notification_type"],
                            setting["deadline_hour"],
                            setting["deadline_minute"],
                        )
                        for slot_key, setting in applied.items()
                    },
                    expected,
                )
                self.db.refresh(row)
                self.assertEqual(row.slot_settings, columns["slot_settings"])

    # 함수이름: test_legacy_missed_deadline_row_is_queued_like_the_screen_shows
    # 함수역할:
    # - 시간대 JSON 없이 기존 미복약 마감 열만 가진 행도 설정 화면에 보이는 마감 시각이 지나면
    #   미복약 알림 큐에 들어가고, 마감 전에는 들어가지 않는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_legacy_missed_deadline_row_is_queued_like_the_screen_shows(self) -> None:
        self._link_caregiver()
        due_time = application_now().replace(hour=9, minute=5, second=0, microsecond=0)
        self.db.add(
            _CaregiverNotification(
                caregiver_hash="caregiver-a",
                patient_hash="patient-a",
                enabled=True,
                alert_option="missed_deadline",
                deadline_hour=9,
                deadline_minute=0,
                slot_settings="{}",
            )
        )
        self.db.add(
            _SavedMedication(
                patient_hash="patient-a",
                created_date=due_time.date(),
                item_name="morning-tablet",
                daily_frequency="1 time",
                total_days="7 days",
                schedule_slot_keys='["morning"]',
            )
        )
        self.db.commit()
        shown = self.control.requestCaregiverNotificationSetting(
            "caregiver-a",
            "patient-a",
            "morning",
        )["data"]
        queue = QueueMissedDoseAlerts(self.db)

        self.assertEqual(
            (shown["alert_option"], shown["deadline_hour"], shown["deadline_minute"]),
            ("missed_deadline", 9, 0),
        )
        self.assertEqual(queue.queueDue(now=due_time.replace(hour=8, minute=55)), 0)
        self.assertEqual(queue.queueDue(now=due_time), 1)
        event = self.db.query(_CaregiverAlertOutbox).one()
        self.assertEqual(event.event_type, CAREGIVER_ALERT_EVENT_MISSED_DEADLINE)
        self.assertEqual(
            (event.caregiver_hash, event.patient_hash, event.slot_key),
            ("caregiver-a", "patient-a", "morning"),
        )

    # 함수이름: test_concurrent_create_conflict_updates_the_existing_row
    # 함수역할:
    # - 첫 조회가 행을 보지 못해 새 행 삽입이 고유 제약에 걸려도 롤백 후 기존 행에 요청한 시간대
    #   설정을 적용하고, 이미 저장된 다른 시간대 설정과 단일 행을 유지하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_concurrent_create_conflict_updates_the_existing_row(self) -> None:
        self._link_caregiver()
        self.control.saveCaregiverNotificationSetting(
            "caregiver-a",
            "patient-a",
            alert_option="missed_deadline",
            deadline_hour=20,
            deadline_minute=30,
            slot_key="morning",
        )
        find_setting = self.control._find_setting
        lookups: list[object] = []

        # 함수이름: miss_first_lookup
        # 함수역할:
        # - 다른 요청이 같은 순간 행을 만든 상황처럼 첫 조회만 행이 없다고 답하고 이후 조회는 실제 행을 돌려준다.
        # 매개변수:
        # - caregiver_hash (str): 조회할 보호자 계정 식별자.
        # - patient_hash (str): 조회할 환자 식별자.
        # 반환값:
        # - 첫 호출은 None, 이후 호출은 저장된 알림 설정 행.
        def miss_first_lookup(
            caregiver_hash: str,
            patient_hash: str,
        ) -> _CaregiverNotification | None:
            lookups.append((caregiver_hash, patient_hash))
            if len(lookups) == 1:
                return None
            return find_setting(caregiver_hash, patient_hash)

        with patch.object(self.control, "_find_setting", side_effect=miss_first_lookup):
            response = self.control.saveCaregiverNotificationSetting(
                "caregiver-a",
                "patient-a",
                alert_option="dose_completed",
                slot_key="evening",
            )

        self.assertEqual(len(lookups), 2)
        self.assertTrue(response["success"])
        self.assertEqual(response["data"]["slot_key"], "evening")
        self.assertEqual(response["data"]["alert_option"], "dose_completed")
        settings = {
            setting["slot_key"]: setting
            for setting in self.control.requestCaregiverNotificationSettings(
                "caregiver-a",
                "patient-a",
            )["data"]
        }
        self.assertEqual(settings["evening"]["alert_option"], "dose_completed")
        self.assertEqual(settings["morning"]["alert_option"], "missed_deadline")
        self.assertEqual(settings["morning"]["deadline_hour"], 20)
        self.assertEqual(settings["morning"]["deadline_minute"], 30)
        self.assertEqual(self.db.query(_CaregiverNotification).count(), 1)


if __name__ == "__main__":
    unittest.main()
