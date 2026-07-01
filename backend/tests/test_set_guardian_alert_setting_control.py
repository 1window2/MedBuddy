# File Name: test_set_guardian_alert_setting_control.py
# Role: Verifies guardian alert setting persistence and scoping.

import sys
import unittest
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.patient_guardian_link_control import PatientGuardianLinkControl  # noqa: E402
from controls.set_guardian_alert_setting_control import (  # noqa: E402
    SetGuardianAlertSetting,
)
from core.database import Base  # noqa: E402
from entities.guardian_alert_setting_entity import (  # noqa: E402
    _GuardianAlertSetting,
    ensure_guardian_alert_setting_schema,
)


class SetGuardianAlertSettingTest(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=self.engine)
        ensure_guardian_alert_setting_schema(self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.link_control = PatientGuardianLinkControl(self.db)
        self.control = SetGuardianAlertSetting(self.db)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def _link_guardian(self) -> None:
        code_response = self.link_control.request_patient_code("patient-a")
        self.link_control.register_patient_code(
            "guardian-a",
            code_response["data"]["patient_code"],
        )

    def test_request_initializes_disabled_default_for_linked_guardian(self) -> None:
        self._link_guardian()

        response = self.control.request_guardian_alert_setting(
            "guardian-a",
            "patient-a",
        )

        self.assertTrue(response["success"])
        self.assertEqual(response["data"]["guardian_hash"], "guardian-a")
        self.assertEqual(response["data"]["patient_hash"], "patient-a")
        self.assertFalse(response["data"]["is_enabled"])
        self.assertEqual(response["data"]["alert_option"], "disable")
        self.assertEqual(self.db.query(_GuardianAlertSetting).count(), 1)

    def test_update_persists_enable_and_disable_options(self) -> None:
        self._link_guardian()

        enable_response = self.control.update_guardian_alert_setting(
            "guardian-a",
            "patient-a",
            enabled=True,
        )

        self.assertTrue(enable_response["success"])
        self.assertTrue(enable_response["data"]["is_enabled"])
        self.assertEqual(enable_response["data"]["alert_option"], "enable")

        row = self.db.query(_GuardianAlertSetting).first()
        self.assertIsNotNone(row)
        self.assertTrue(row.enabled)
        self.assertEqual(row.alert_option, "enable")

        disable_response = self.control.update_guardian_alert_setting(
            "guardian-a",
            "patient-a",
            alert_option="disable",
        )

        self.assertFalse(disable_response["data"]["is_enabled"])
        self.assertEqual(disable_response["data"]["alert_option"], "disable")
        self.db.refresh(row)
        self.assertFalse(row.enabled)
        self.assertEqual(row.alert_option, "disable")

    def test_unlinked_guardian_cannot_read_or_update_setting(self) -> None:
        with self.assertRaises(HTTPException) as read_context:
            self.control.request_guardian_alert_setting("guardian-a", "patient-a")
        self.assertEqual(read_context.exception.status_code, 404)

        with self.assertRaises(HTTPException) as update_context:
            self.control.update_guardian_alert_setting(
                "guardian-a",
                "patient-a",
                enabled=True,
            )
        self.assertEqual(update_context.exception.status_code, 404)

    def test_invalid_alert_option_is_rejected(self) -> None:
        self._link_guardian()

        with self.assertRaises(HTTPException) as context:
            self.control.update_guardian_alert_setting(
                "guardian-a",
                "patient-a",
                alert_option="later",
            )

        self.assertEqual(context.exception.status_code, 400)

    def test_schema_upgrade_adds_missing_columns_and_deduplicates_rows(self) -> None:
        legacy_engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        try:
            with legacy_engine.begin() as connection:
                connection.execute(
                    text(
                        "CREATE TABLE guardian_alert_settings ("
                        "id INTEGER PRIMARY KEY, "
                        "guardian_hash VARCHAR, "
                        "patient_hash VARCHAR"
                        ")"
                    )
                )
                connection.execute(
                    text(
                        "INSERT INTO guardian_alert_settings "
                        "(id, guardian_hash, patient_hash) "
                        "VALUES "
                        "(1, 'guardian-a', 'patient-a'), "
                        "(2, 'guardian-a', 'patient-a')"
                    )
                )

            ensure_guardian_alert_setting_schema(legacy_engine)

            with legacy_engine.connect() as connection:
                columns = {
                    row[1]
                    for row in connection.execute(
                        text("PRAGMA table_info(guardian_alert_settings)")
                    )
                }
                self.assertIn("enabled", columns)
                self.assertIn("alert_option", columns)
                row_count = connection.execute(
                    text("SELECT COUNT(*) FROM guardian_alert_settings")
                ).scalar_one()
                self.assertEqual(row_count, 1)
                migrated_row = connection.execute(
                    text(
                        "SELECT enabled, alert_option "
                        "FROM guardian_alert_settings "
                        "WHERE guardian_hash = 'guardian-a' "
                        "AND patient_hash = 'patient-a'"
                    )
                ).first()
                self.assertEqual(migrated_row[0], 0)
                self.assertEqual(migrated_row[1], "disable")
        finally:
            legacy_engine.dispose()


if __name__ == "__main__":
    unittest.main()
