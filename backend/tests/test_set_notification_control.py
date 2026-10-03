# File Name: test_set_notification_control.py
# Role: Regression coverage for patient medication alarms, read-only defaults, input validation,
#   and legacy schema upgrades.

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

from controls.set_notification_control import SetNotification  # noqa: E402
from entities.user_setting_entity import _UserSetting  # noqa: E402
from core.database import Base  # noqa: E402
from entities.medication_alarm_entity import (  # noqa: E402
    _MedicationAlarm,
    ensure_medication_alarm_schema,
)


# Class Name: SetNotificationTest
# Role: Database-backed alarm tests covering each medication slot and persisted enable/disable
#   transitions.
# Responsibilities:
# - Returns four disabled default slots at 08:00, 12:00, 18:00, and 22:00 without persisting a
#   read-only request.
# - Rejects invalid alarm slots, hours, and minutes with HTTP 400.
# - Adds missing alarm columns, deduplicates legacy rows, and initializes the remaining row to a
#   disabled 08:00 alarm.
# Attributes:
# - engine (Engine): Isolated in-memory SQLite engine.
# - db (Session): SQLAlchemy session holding only this test's database state.
# - control (SetNotification): Use-case control under test, isolated from production state.
class SetNotificationTest(unittest.TestCase):
    # Function Name: test_unsaved_slots_follow_patient_defaults
    # Description: Updated defaults apply to unsaved slots, without writes or cross-account leakage.
    # Parameters: None.
    # Returns: None; assertions cover all slots and subsequent default changes.
    def test_unsaved_slots_follow_patient_defaults(self) -> None:
        setting = _UserSetting(
            user_hash="patient-a", default_morning_time="07:15",
            default_lunch_time="13:25", default_evening_time="19:35",
            default_bedtime="23:45",
        )
        self.db.add(setting)
        self.db.commit()
        alarms = self.control.requestMedicationAlarm("patient-a")["data"]
        self.assertEqual([(a["hour"], a["minute"]) for a in alarms],
                         [(7, 15), (13, 25), (19, 35), (23, 45)])
        self.assertTrue(all(not a["is_enabled"] for a in alarms))
        self.assertEqual(self.db.query(_MedicationAlarm).count(), 0)
        self.assertEqual(self.control.requestAlarmToggle("patient-b", "morning")["data"]["hour"], 8)
        setting.default_morning_time = "06:50"
        self.db.commit()
        alarm = self.control.requestAlarmToggle("patient-a", "morning")["data"]
        self.assertEqual((alarm["hour"], alarm["minute"]), (6, 50))

    # Function Name: test_default_changes_preserve_explicit_alarms
    # Description: Neither enabled nor disabled saved times are overwritten by defaults.
    # Parameters: None.
    # Returns: None; assertions also cover disabling a previously unsaved slot.
    def test_default_changes_preserve_explicit_alarms(self) -> None:
        self.db.add(_UserSetting(user_hash="patient-a", default_morning_time="07:15",
                                 default_lunch_time="13:25", default_evening_time="19:35"))
        self.db.commit()
        self.control.saveNotificationSetting("patient-a", "morning", 9, 40)
        self.control.saveNotificationSetting("patient-a", "lunch", 14, 10)
        self.control.disableAlarmSetting("patient-a", "lunch")
        alarms = self.control.requestMedicationAlarm("patient-a")["data"]
        self.assertEqual((alarms[0]["hour"], alarms[0]["minute"], alarms[0]["is_enabled"]), (9, 40, True))
        self.assertEqual((alarms[1]["hour"], alarms[1]["minute"], alarms[1]["is_enabled"]), (14, 10, False))
        disabled = self.control.disableAlarmSetting("patient-a", "evening")["data"]
        self.assertEqual((disabled["hour"], disabled["minute"], disabled["is_enabled"]), (19, 35, False))

    # Function Name: setUp
    # Description:
    # - Creates an isolated medication-alarm database, upgrades its schema, and prepares the
    #   notification control.
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
        ensure_medication_alarm_schema(self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.control = SetNotification(self.db)

    # Function Name: tearDown
    # Description:
    # - Closes the alarm-test session and disposes its database engine.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # Function Name: test_default_settings_return_every_schedule_slot
    # Description:
    # - Returns four disabled default slots at 08:00, 12:00, 18:00, and 22:00 without
    #   persisting a read-only request.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_default_settings_return_every_schedule_slot(self) -> None:
        response = self.control.requestMedicationAlarm("patient-a")

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

    # Function Name: test_set_and_disable_alarm_setting_are_persisted
    # Description:
    # - Persists an enabled patient-scoped morning alarm and retains its 09:30 time when
    #   later disabled.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_set_and_disable_alarm_setting_are_persisted(self) -> None:
        save_response = self.control.saveNotificationSetting(
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

        disable_response = self.control.disableAlarmSetting(
            "patient-a",
            "morning",
        )

        self.assertTrue(disable_response["success"])
        self.assertFalse(disable_response["data"]["is_enabled"])
        self.assertEqual(disable_response["data"]["hour"], 9)
        self.assertEqual(disable_response["data"]["minute"], 30)
        self.db.refresh(row)
        self.assertFalse(row.enabled)

    # Function Name: test_invalid_alarm_slot_and_time_are_rejected
    # Description:
    # - Rejects invalid alarm slots, hours, and minutes with HTTP 400.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_invalid_alarm_slot_and_time_are_rejected(self) -> None:
        with self.assertRaises(HTTPException) as slot_context:
            self.control.saveNotificationSetting("patient-a", "midnight", 8, 0)
        self.assertEqual(slot_context.exception.status_code, 400)

        with self.assertRaises(HTTPException) as hour_context:
            self.control.saveNotificationSetting("patient-a", "morning", 24, 0)
        self.assertEqual(hour_context.exception.status_code, 400)

        with self.assertRaises(HTTPException) as minute_context:
            self.control.saveNotificationSetting("patient-a", "morning", 8, 60)
        self.assertEqual(minute_context.exception.status_code, 400)

    # Function Name: test_schema_upgrade_adds_missing_columns_and_deduplicates_rows
    # Description:
    # - Adds missing alarm columns, deduplicates legacy rows, and initializes the remaining
    #   row to a disabled 08:00 alarm.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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
