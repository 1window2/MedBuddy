# File Name: test_manage_user_setting_control.py
# Role: Verifies user setting persistence and schema upgrade behavior.

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


class ManageUserSettingTest(unittest.TestCase):
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

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def test_request_returns_default_when_no_setting_exists(self) -> None:
        response = self.control.requestUserSetting("user-a")

        self.assertTrue(response["success"])
        self.assertEqual(response["data"]["user_hash"], "user-a")
        self.assertEqual(response["data"]["font_size"], 16)
        self.assertEqual(response["data"]["reading_speed"], 1.0)
        self.assertEqual(response["data"]["language"], "ko")
        self.assertEqual(self.db.query(_UserSetting).count(), 0)

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
