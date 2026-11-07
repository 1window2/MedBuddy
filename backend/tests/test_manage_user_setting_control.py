# File Name: test_manage_user_setting_control.py
# Role: Regression coverage for user preference defaults, persistence, validation, and legacy
#   schema upgrades.

import sys
import unittest
from collections.abc import Sequence
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy import event
from sqlalchemy.orm import Session, UOWTransaction, sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.manage_user_setting_control import ManageUserSetting  # noqa: E402
from core.database import Base  # noqa: E402
from entities.user_setting_entity import _UserSetting  # noqa: E402


# Class Name: ManageUserSettingTest
# Role: Tests per-user display, voice, notification, and schedule preferences.
# Responsibilities:
# - Verify nonpersisting defaults, validation, legacy requests, revision advancement, and conflicting concurrent saves.
# Attributes:
# - engine (Engine): isolated SQLite engine. db (Session): test session. extra_sessions (list[Session]): concurrent sessions to close. control (ManageUserSetting): settings control.
class ManageUserSettingTest(unittest.TestCase):
    # 함수역할: 최신 저장 뒤 늦게 도착한 요청은 거절하고 알림 끄기를 유지한다.
    # 함수이름: test_late_save_cannot_overwrite_newer_setting
    # 함수역할:
    # - 오래된 개정으로 저장하면 최신 개정과 409를 반환하고 기존 알림 값·다른 계정 기본값을 보존하는지 확인한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - None.
    def test_late_save_cannot_overwrite_newer_setting(self) -> None:
        self.assertEqual(self.control.requestUserSetting("user-a")["revision"], 0)
        saved = self.control.saveUserSetting(
            "user-a", 16, 1.0, "ko",
            medication_notifications_enabled=False, expected_revision=0,
        )
        self.assertEqual(saved["revision"], 1)
        with self.assertRaises(HTTPException) as error:
            self.control.saveUserSetting(
                "user-a", 16, 1.0, "ko",
                medication_notifications_enabled=True, expected_revision=0,
            )
        self.assertEqual(error.exception.status_code, 409)
        self.assertEqual(error.exception.detail, {
            "code": "settings_revision_conflict", "revision": 1,
        })
        self.assertFalse(self.control.requestUserSetting("user-a")["data"]["medication_notifications_enabled"])
        self.assertEqual(self.control.requestUserSetting("user-b")["revision"], 0)

    # 함수역할: 같은 값 저장도 새 버전이며 구형 앱 저장 후에는 버전 기반 요청을 다시 확인한다.
    # 함수이름: test_identical_and_legacy_saves_advance_revision
    # 함수역할:
    # - 같은 값과 이전 형식 저장도 개정을 증가시키며 최신 개정으로만 후속 저장이 허용되는지 확인한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - None.
    def test_identical_and_legacy_saves_advance_revision(self) -> None:
        first = self.control.saveUserSetting("user-a", 16, 1.0, "ko", expected_revision=0)
        same = self.control.saveUserSetting("user-a", 16, 1.0, "ko", expected_revision=first["revision"])
        self.assertEqual(same["revision"], 2)
        legacy = self.control.saveUserSetting("user-a", 20, 1.0, "ko")
        self.assertEqual(legacy["revision"], 3)
        with self.assertRaises(HTTPException) as error:
            self.control.saveUserSetting("user-a", 16, 1.0, "ko", expected_revision=2)
        self.assertEqual(error.exception.status_code, 409)
        retried = self.control.saveUserSetting("user-a", 24, 1.0, "ko", expected_revision=3)
        self.assertEqual(retried["revision"], 4)
        self.assertEqual(retried["data"]["font_size"], 24)

    # 함수역할: 버전 확인과 커밋 사이에 다른 세션이 저장해도 SQL 조건으로 오래된 변경을 거절한다.
    # 함수이름: test_concurrent_update_after_revision_check_is_rejected
    # 함수역할:
    # - 개정 확인 뒤 다른 세션이 먼저 저장하면 409로 거부하고 승리한 설정을 유지하는지 확인한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - None.
    def test_concurrent_update_after_revision_check_is_rejected(self) -> None:
        self.control.saveUserSetting("user-a", 16, 1.0, "ko", expected_revision=0)
        other_db = sessionmaker(bind=self.engine)()
        self.extra_sessions.append(other_db)
        other = ManageUserSetting(other_db)

        # 함수이름: save_newer
        # 함수역할:
        # - 현재 flush 직전에 다른 세션에서 개정 1의 설정을 먼저 저장한다.
        # 매개변수:
        # - session: Session; flush 중인 세션(사용하지 않음).
        # - context: UOWTransaction; flush 문맥(사용하지 않음).
        # - instances: object; flush 대상(사용하지 않음).
        # 반환값:
        # - None.
        def save_newer(session: Session, context: UOWTransaction, instances: Sequence[object] | None) -> None:
            other.saveUserSetting(
                "user-a", 20, 1.0, "ko",
                medication_notifications_enabled=False, expected_revision=1,
            )

        event.listen(self.db, "before_flush", save_newer, once=True)
        with self.assertRaises(HTTPException) as error:
            self.control.saveUserSetting("user-a", 24, 1.0, "ko", expected_revision=1)
        self.assertEqual(error.exception.status_code, 409)
        actual = self.control.requestUserSetting("user-a")
        self.assertEqual(actual["revision"], 2)
        self.assertEqual(actual["data"]["font_size"], 20)
        self.assertFalse(actual["data"]["medication_notifications_enabled"])

    # Function Name: test_legacy_save_losing_twice_returns_conflict
    # Description:
    # - Requires a legacy save that loses both update attempts to return 409 while retaining the winning revision and values.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_legacy_save_losing_twice_returns_conflict(self) -> None:
        self.control.saveUserSetting("user-a", 16, 1.0, "ko")
        other_db = sessionmaker(bind=self.engine)()
        self.extra_sessions.append(other_db)
        other = ManageUserSetting(other_db)
        flushes = []

        # Function Name: save_newer
        # Description:
        # - Wins the first two flush races from a second session to exhaust the legacy save retry.
        # Parameters:
        # - session: Session; flushing session, unused.
        # - context: UOWTransaction; flush context, unused.
        # - instances: object; flush targets, unused.
        # Returns:
        # - None.
        def save_newer(session: Session, context: UOWTransaction, instances: Sequence[object] | None) -> None:
            flushes.append(1)
            if len(flushes) <= 2:
                other.saveUserSetting("user-a", 18 + len(flushes), 1.0, "ko")

        event.listen(self.db, "before_flush", save_newer)
        with self.assertRaises(HTTPException) as error:
            self.control.saveUserSetting("user-a", 24, 1.0, "ko")
        event.remove(self.db, "before_flush", save_newer)
        self.assertEqual(error.exception.status_code, 409)
        actual = self.control.requestUserSetting("user-a")
        self.assertEqual(actual["revision"], 3)
        self.assertEqual(actual["data"]["font_size"], 20)

    # 함수역할: 처음 저장하는 두 요청도 한 요청만 생성하고 나머지는 충돌로 반환한다.
    # 함수이름: test_concurrent_initial_save_is_rejected
    # 함수역할:
    # - 최초 설정 생성 경합에서도 먼저 저장된 행을 덮어쓰지 않고 409로 거부하는지 확인한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - None.
    def test_concurrent_initial_save_is_rejected(self) -> None:
        other_db = sessionmaker(bind=self.engine)()
        self.extra_sessions.append(other_db)

        # 함수이름: save_newer
        # 함수역할:
        # - 현재 최초 삽입 직전에 다른 세션에서 개정 0의 설정을 생성한다.
        # 매개변수:
        # - session: Session; flush 중인 세션(사용하지 않음).
        # - context: UOWTransaction; flush 문맥(사용하지 않음).
        # - instances: object; flush 대상(사용하지 않음).
        # 반환값:
        # - None.
        def save_newer(session: Session, context: UOWTransaction, instances: Sequence[object] | None) -> None:
            ManageUserSetting(other_db).saveUserSetting(
                "user-a", 20, 1.0, "ko", expected_revision=0,
            )

        event.listen(self.db, "before_flush", save_newer, once=True)
        with self.assertRaises(HTTPException) as error:
            self.control.saveUserSetting("user-a", 24, 1.0, "ko", expected_revision=0)
        self.assertEqual(error.exception.status_code, 409)
        self.assertEqual(self.control.requestUserSetting("user-a")["data"]["font_size"], 20)

    # 함수역할: 홈 선택을 계정별로 저장하며 구형 앱 저장에서도 보존하는지 검증한다.
    # 함수이름: test_home_schedule_source_persists_and_preserves_legacy_requests
    # 함수역할:
    # - 홈 일정 출처는 계정별로 저장되고 생략한 이전 요청에도 유지되며 잘못된 출처는 거부되는지 확인한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - None.
    def test_home_schedule_source_persists_and_preserves_legacy_requests(self) -> None:
        self.assertEqual(self.control.requestUserSetting("user-a")["data"]["home_schedule_source"], "self")
        saved = self.control.saveUserSetting("user-a", 16, 1.0, "ko", home_schedule_source="patients")
        self.assertEqual(saved["data"]["home_schedule_source"], "patients")
        self.assertEqual(self.control.requestUserSetting("user-a")["data"]["home_schedule_source"], "patients")
        self.assertEqual(self.control.requestUserSetting("user-b")["data"]["home_schedule_source"], "self")
        legacy = self.control.saveUserSetting("user-a", 20, 1.0, "ko")
        self.assertEqual(legacy["data"]["home_schedule_source"], "patients")
        updated = self.control.saveUserSetting("user-a", 20, 1.0, "ko", home_schedule_source="self")
        self.assertEqual(updated["data"]["home_schedule_source"], "self")
        with self.assertRaises(HTTPException) as error:
            self.control.saveUserSetting("user-a", 16, 1.0, "ko", home_schedule_source="automatic")
        self.assertEqual(error.exception.status_code, 400)


    # 함수이름: setUp
    # 함수역할:
    # - 격리된 메모리 DB에 현행 테이블과 설정 제어 객체를 만들고 추가 세션 정리 목록을 준비한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - None.
    def setUp(self) -> None:
        self.extra_sessions = []
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
        self.control = ManageUserSetting(self.db)

    # 함수이름: tearDown
    # 함수역할:
    # - 추가 세션과 기본 설정 세션을 닫고 테스트 엔진을 해제한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - None.
    def tearDown(self) -> None:
        for session in self.extra_sessions:
            session.close()
        self.db.close()
        self.engine.dispose()

    # 함수이름: test_request_returns_default_when_no_setting_exists
    # 함수역할:
    # - 설정이 없으면 한국어·24시간제·기본 글꼴·낭독속도·알림·복약 시각을 제공하되 DB 행은 생성하지 않는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_request_returns_default_when_no_setting_exists(self) -> None:
        response = self.control.requestUserSetting("user-a")

        self.assertTrue(response["success"])
        self.assertEqual(response["data"]["user_hash"], "user-a")
        self.assertEqual(response["data"]["font_size"], 16)
        self.assertEqual(response["data"]["reading_speed"], 1.0)
        self.assertEqual(response["data"]["language"], "ko")
        self.assertEqual(response["data"]["language_mode"], "ko")
        self.assertEqual(response["data"]["time_format"], "24h")
        self.assertTrue(response["data"]["medication_notifications_enabled"])
        self.assertTrue(response["data"]["caregiver_notifications_enabled"])
        self.assertTrue(response["data"]["chat_notifications_enabled"])
        self.assertEqual(response["data"]["notification_detail_mode"], "full")
        self.assertEqual(response["data"]["default_morning_time"], "08:00")
        self.assertEqual(response["data"]["default_lunch_time"], "12:00")
        self.assertEqual(response["data"]["default_evening_time"], "18:00")
        self.assertEqual(response["data"]["default_bedtime"], "22:00")
        self.assertEqual(self.db.query(_UserSetting).count(), 0)

    # Function Name: test_save_user_setting_persists_and_updates_values
    # Description:
    # - Persists changed font, reading speed, and language values while reusing one
    #   user-settings row on update.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_save_user_setting_persists_and_updates_values(self) -> None:
        save_response = self.control.saveUserSetting("user-a", 20, 1.2, "en")

        self.assertTrue(save_response["success"])
        self.assertEqual(save_response["data"]["font_size"], 20)
        self.assertEqual(save_response["data"]["reading_speed"], 1.2)
        self.assertEqual(save_response["data"]["language"], "en")
        self.assertEqual(self.db.query(_UserSetting).count(), 1)

        update_response = self.control.saveUserSetting("user-a", 14, 0.8, "ko")

        self.assertEqual(update_response["data"]["font_size"], 14)
        self.assertEqual(update_response["data"]["reading_speed"], 0.8)
        self.assertEqual(update_response["data"]["language"], "ko")
        self.assertEqual(self.db.query(_UserSetting).count(), 1)

    # 함수이름: test_save_user_setting_persists_notification_and_display_options
    # 함수역할:
    # - 시스템 언어·12시간제·알림 비활성·종류만 표시 및 사용자 지정 복약 시각이 저장 후 그대로 복원되는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_save_user_setting_persists_notification_and_display_options(self) -> None:
        response = self.control.saveUserSetting(
            "user-a",
            20,
            1.2,
            "en",
            language_mode="system",
            time_format="12h",
            medication_notifications_enabled=False,
            caregiver_notifications_enabled=False,
            chat_notifications_enabled=False,
            notification_detail_mode="type_only",
            default_morning_time="07:10",
            default_lunch_time="12:10",
            default_evening_time="19:10",
            default_bedtime="23:10",
        )

        data = response["data"]
        self.assertEqual(data["language_mode"], "system")
        self.assertEqual(data["time_format"], "12h")
        self.assertFalse(data["medication_notifications_enabled"])
        self.assertFalse(data["caregiver_notifications_enabled"])
        self.assertFalse(data["chat_notifications_enabled"])
        self.assertEqual(data["notification_detail_mode"], "type_only")
        self.assertEqual(data["default_morning_time"], "07:10")
        self.assertEqual(data["default_lunch_time"], "12:10")
        self.assertEqual(data["default_evening_time"], "19:10")
        self.assertEqual(data["default_bedtime"], "23:10")

        restored = self.control.requestUserSetting("user-a")["data"]
        self.assertEqual(restored, data)

    # 함수이름: test_invalid_user_setting_values_are_rejected
    # 함수역할:
    # - 범위를 벗어난 글꼴·속도와 잘못된 언어·시간 형식·알림 상세·복약 시각을 각각 400으로 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_invalid_user_setting_values_are_rejected(self) -> None:
        with self.assertRaises(HTTPException) as font_context:
            self.control.saveUserSetting("user-a", 40, 1.0, "ko")
        self.assertEqual(font_context.exception.status_code, 400)

        with self.assertRaises(HTTPException) as speed_context:
            self.control.saveUserSetting("user-a", 16, 3.0, "ko")
        self.assertEqual(speed_context.exception.status_code, 400)

        with self.assertRaises(HTTPException) as language_context:
            self.control.saveUserSetting("user-a", 16, 1.0, "jp")
        self.assertEqual(language_context.exception.status_code, 400)

        with self.assertRaises(HTTPException) as language_mode_context:
            self.control.saveUserSetting(
                "user-a",
                16,
                1.0,
                "ko",
                language_mode="automatic",
            )
        self.assertEqual(language_mode_context.exception.status_code, 400)

        with self.assertRaises(HTTPException) as time_format_context:
            self.control.saveUserSetting(
                "user-a",
                16,
                1.0,
                "ko",
                time_format="locale",
            )
        self.assertEqual(time_format_context.exception.status_code, 400)

        with self.assertRaises(HTTPException) as detail_mode_context:
            self.control.saveUserSetting(
                "user-a",
                16,
                1.0,
                "ko",
                notification_detail_mode="hidden",
            )
        self.assertEqual(detail_mode_context.exception.status_code, 400)

        with self.assertRaises(HTTPException) as default_time_context:
            self.control.saveUserSetting(
                "user-a",
                16,
                1.0,
                "ko",
                default_morning_time="25:00",
            )
        self.assertEqual(default_time_context.exception.status_code, 400)


if __name__ == "__main__":
    unittest.main()
