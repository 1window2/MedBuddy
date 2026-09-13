# File Name: test_manage_user_setting_control.py
# Role: Regression coverage for user preference defaults, persistence, validation, and legacy
#   schema upgrades.

import sys
import unittest
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.manage_user_setting_control import ManageUserSetting  # noqa: E402
from core.database import Base  # noqa: E402
from entities.user_setting_entity import _UserSetting, ensure_user_setting_schema  # noqa: E402


# 클래스명: ManageUserSettingTest
# 역할: 사용자별 표시·음성·알림 설정과 기존 스키마 이행을 검증하는 테스트 모음이다.
# 주요 책임:
# - 설정이 없으면 한국어·24시간제·기본 글꼴·낭독속도·알림·복약 시각을 제공하되 DB 행은 생성하지 않는지 검증한다.
# - 범위를 벗어난 글꼴·속도와 잘못된 언어·시간 형식·알림 상세·복약 시각을 각각 400으로 거절하는지 검증한다.
# - 구형 설정 테이블에 누락 컬럼과 기본값을 채우고 동일 사용자 중복 행을 하나로 정리하는지 검증한다.
# 속성:
# - engine (Engine): 격리 인메모리 SQLite 엔진.
# - db (Session): 이 테스트의 DB 상태만 보관하는 SQLAlchemy 세션.
# - control (ManageUserSetting): 운영 상태와 분리하여 검증할 유스케이스 control.
class ManageUserSettingTest(unittest.TestCase):
    # Function Name: setUp
    # Description:
    # - Creates an isolated user-settings database, upgrades its schema, and prepares the
    #   settings control.
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
        ensure_user_setting_schema(self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.control = ManageUserSetting(self.db)

    # Function Name: tearDown
    # Description:
    # - Closes the settings-test session and disposes its database engine.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def tearDown(self) -> None:
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

    # 함수이름: test_schema_upgrade_adds_missing_columns_and_deduplicates_rows
    # 함수역할:
    # - 구형 설정 테이블에 누락 컬럼과 기본값을 채우고 동일 사용자 중복 행을 하나로 정리하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_schema_upgrade_adds_missing_columns_and_deduplicates_rows(self) -> None:
        legacy_engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        try:
            with legacy_engine.begin() as connection:
                connection.execute(
                    text(
                        "CREATE TABLE user_settings ("
                        "id INTEGER PRIMARY KEY, "
                        "user_hash VARCHAR"
                        ")"
                    )
                )
                connection.execute(
                    text(
                        "INSERT INTO user_settings "
                        "(id, user_hash) "
                        "VALUES "
                        "(1, 'user-a'), "
                        "(2, 'user-a')"
                    )
                )

            ensure_user_setting_schema(legacy_engine)

            with legacy_engine.connect() as connection:
                columns = {
                    row[1]
                    for row in connection.execute(text("PRAGMA table_info(user_settings)"))
                }
                self.assertIn("font_size", columns)
                self.assertIn("reading_speed", columns)
                self.assertIn("language", columns)
                self.assertTrue(
                    {
                        "language_mode",
                        "time_format",
                        "medication_notifications_enabled",
                        "caregiver_notifications_enabled",
                        "chat_notifications_enabled",
                        "notification_detail_mode",
                        "default_morning_time",
                        "default_lunch_time",
                        "default_evening_time",
                        "default_bedtime",
                    }.issubset(columns)
                )
                row_count = connection.execute(
                    text(
                        "SELECT COUNT(*) FROM user_settings "
                        "WHERE user_hash = 'user-a'"
                    )
                ).scalar_one()
                self.assertEqual(row_count, 1)
                migrated_row = connection.execute(
                    text(
                        "SELECT font_size, reading_speed, language "
                        "FROM user_settings WHERE user_hash = 'user-a'"
                    )
                ).first()
                self.assertEqual(migrated_row[0], 16)
                self.assertEqual(migrated_row[1], 1.0)
                self.assertEqual(migrated_row[2], "ko")
        finally:
            legacy_engine.dispose()


if __name__ == "__main__":
    unittest.main()
