# File Name: test_set_notification_control.py
# Role: Verifies medication alarm persistence and scoping.

import sys
import unittest
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.patient_guardian_link_control import PatientGuardianLinkControl  # noqa: E402
from controls.set_notification_control import SetNotification  # noqa: E402
from core.database import Base  # noqa: E402
from entities.medication_alarm_entity import (  # noqa: E402
    _MedicationAlarm,
    ensure_medication_alarm_schema,
)


class SetNotificationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=self.engine)
        ensure_medication_alarm_schema(self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.control = SetNotification(self.db)
        self.link_control = PatientGuardianLinkControl(self.db)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def test_default_settings_return_every_schedule_slot(self) -> None:
        response = self.control.request_medication_alarm("patient-a")

        self.assertTrue(response["success"])
        self.assertEqual(
            [setting["slot_key"] for setting in response["data"]],
            ["morning", "lunch", "evening", "bedtime"],
        )
        self.assertEqual(
            [setting["hour"] for setting in response["data"]],
            [8, 12, 18, 22],
        )
        self.assertTrue(
            all(setting["is_enabled"] is False for setting in response["data"])
        )
        self.assertEqual(self.db.query(_MedicationAlarm).count(), 0)

    def test_set_and_disable_alarm_setting_are_persisted(self) -> None:
        save_response = self.control.set_medication_alarm(
            "patient-a",
            "morning",
            9,
            30,
        )

        self.assertTrue(save_response["success"])
        self.assertEqual(save_response["data"]["patient_hash"], "patient-a")
        self.assertEqual(save_response["data"]["slot_key"], "morning")
        self.assertEqual(save_response["data"]["hour"], 9)
        self.assertEqual(save_response["data"]["minute"], 30)
        self.assertTrue(save_response["data"]["is_enabled"])

        row = self.db.query(_MedicationAlarm).first()
        self.assertIsNotNone(row)
        self.assertEqual(row.patient_hash, "patient-a")
        self.assertEqual(row.slot_key, "morning")
        self.assertTrue(row.enabled)

        disable_response = self.control.disable_alarm_setting(
            "patient-a",
            "morning",
        )

        self.assertTrue(disable_response["success"])
        self.assertFalse(disable_response["data"]["is_enabled"])
        self.assertEqual(disable_response["data"]["hour"], 9)
        self.assertEqual(disable_response["data"]["minute"], 30)
        self.db.refresh(row)
        self.assertFalse(row.enabled)

    def test_invalid_alarm_slot_and_time_are_rejected(self) -> None:
        with self.assertRaises(HTTPException) as slot_context:
            self.control.set_medication_alarm("patient-a", "midnight", 8, 0)
        self.assertEqual(slot_context.exception.status_code, 400)

        with self.assertRaises(HTTPException) as hour_context:
            self.control.set_medication_alarm("patient-a", "morning", 24, 0)
        self.assertEqual(hour_context.exception.status_code, 400)

        with self.assertRaises(HTTPException) as minute_context:
            self.control.set_medication_alarm("patient-a", "morning", 8, 60)
        self.assertEqual(minute_context.exception.status_code, 400)

    def test_guardian_alarm_settings_resolve_linked_patient_scope(self) -> None:
        code_response = self.link_control.request_patient_code("patient-a")
        self.link_control.register_patient_code(
            "guardian-a",
            code_response["data"]["patient_code"],
        )

        response = self.control.set_medication_alarm(
            "patient-a",
            "lunch",
            13,
            15,
            user_hash="guardian-a",
            role="guardian",
        )

        self.assertTrue(response["success"])
        self.assertEqual(response["data"]["patient_hash"], "patient-a")
        self.assertEqual(response["data"]["slot_key"], "lunch")
        self.assertTrue(response["data"]["is_enabled"])

        guardian_list = self.control.request_medication_alarm(
            patient_hash="patient-a",
            user_hash="guardian-a",
            role="guardian",
        )
        lunch_setting = [
            setting
            for setting in guardian_list["data"]
            if setting["slot_key"] == "lunch"
        ][0]
        self.assertEqual(lunch_setting["hour"], 13)
        self.assertEqual(lunch_setting["minute"], 15)
        self.assertTrue(lunch_setting["is_enabled"])

    def test_schema_upgrade_adds_missing_columns_and_deduplicates_rows(
        self,
    ) -> None:
        legacy_engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        try:
            with legacy_engine.begin() as connection:
                connection.execute(
                    text(
                        "CREATE TABLE notification_settings ("
                        "id INTEGER PRIMARY KEY, "
                        "patient_hash VARCHAR, "
                        "slot_key VARCHAR"
                        ")"
                    )
                )
                connection.execute(
                    text(
                        "INSERT INTO notification_settings "
                        "(id, patient_hash, slot_key) "
                        "VALUES "
                        "(1, 'patient-a', 'morning'), "
                        "(2, 'patient-a', 'morning')"
                    )
                )

            ensure_medication_alarm_schema(legacy_engine)

            with legacy_engine.connect() as connection:
                columns = {
                    row[1]
                    for row in connection.execute(
                        text("PRAGMA table_info(notification_settings)")
                    )
                }
                self.assertIn("hour", columns)
                self.assertIn("minute", columns)
                self.assertIn("enabled", columns)
                row_count = connection.execute(
                    text("SELECT COUNT(*) FROM notification_settings")
                ).scalar_one()
                self.assertEqual(row_count, 1)
                migrated_row = connection.execute(
                    text(
                        "SELECT hour, minute, enabled "
                        "FROM notification_settings "
                        "WHERE patient_hash = 'patient-a' "
                        "AND slot_key = 'morning'"
                    )
                ).first()
                self.assertEqual(migrated_row[0], 8)
                self.assertEqual(migrated_row[1], 0)
                self.assertEqual(migrated_row[2], 0)
        finally:
            legacy_engine.dispose()


if __name__ == "__main__":
    unittest.main()
