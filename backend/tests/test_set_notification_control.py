# File Name: test_set_notification_control.py
# Role: Regression coverage for patient medication alarms, read-only defaults, input validation,
#   and legacy schema upgrades.

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.set_notification_control import SetNotification  # noqa: E402
from entities.user_setting_entity import _UserSetting  # noqa: E402
from core.database import Base  # noqa: E402
from entities.medication_alarm_entity import (  # noqa: E402
    _MedicationAlarm,
    default_alarm_time,
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

        # A time changed in the same save is kept with the disabled alarm.
        retimed = self.control.disableAlarmSetting("patient-a", "morning", 7, 15)["data"]
        self.assertFalse(retimed["is_enabled"])
        self.assertEqual((retimed["hour"], retimed["minute"]), (7, 15))
        self.db.refresh(row)
        self.assertEqual((row.hour, row.minute, row.enabled), (7, 15, False))
        # A slot without a stored row takes the chosen time as well.
        created = self.control.disableAlarmSetting("patient-a", "lunch", 11, 40)["data"]
        self.assertFalse(created["is_enabled"])
        self.assertEqual((created["hour"], created["minute"]), (11, 40))
        with self.assertRaises(HTTPException) as invalid:
            self.control.disableAlarmSetting("patient-a", "morning", 24, 0)
        self.assertEqual(invalid.exception.status_code, 400)

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

    # Function Name: test_default_alarm_time_prefers_a_valid_patient_default
    # Description:
    # - The shared default-time helper returns the patient's "HH:MM" default for the slot
    #   and falls back to the product default hour when the preference row, the field or a
    #   valid time is missing.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_default_alarm_time_prefers_a_valid_patient_default(self) -> None:
        cases = [
            ("morning", None, (8, 0)),
            ("morning", SimpleNamespace(default_morning_time="07:30"), (7, 30)),
            ("lunch", SimpleNamespace(default_lunch_time="13:05"), (13, 5)),
            ("evening", SimpleNamespace(default_evening_time="00:00"), (0, 0)),
            ("bedtime", SimpleNamespace(default_bedtime="23:59"), (23, 59)),
            ("bedtime", SimpleNamespace(default_morning_time="07:30"), (22, 0)),
            ("lunch", SimpleNamespace(default_lunch_time=None), (12, 0)),
            ("lunch", SimpleNamespace(default_lunch_time=""), (12, 0)),
            ("evening", SimpleNamespace(default_evening_time="24:00"), (18, 0)),
            ("evening", SimpleNamespace(default_evening_time="18:60"), (18, 0)),
            ("evening", SimpleNamespace(default_evening_time="-1:30"), (18, 0)),
            ("evening", SimpleNamespace(default_evening_time="evening"), (18, 0)),
            ("evening", SimpleNamespace(default_evening_time="18:30:00"), (18, 0)),
            ("midnight", SimpleNamespace(default_morning_time="07:30"), (8, 0)),
        ]

        for slot_key, user_setting, expected in cases:
            with self.subTest(slot_key=slot_key, user_setting=user_setting):
                self.assertEqual(default_alarm_time(slot_key, user_setting), expected)

    # Function Name: test_invalid_patient_default_falls_back_to_product_default
    # Description:
    # - A stored default that matches the request pattern but is not a time of day ("99:99")
    #   is not shown as an alarm time; the slot shows the product default instead.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_invalid_patient_default_falls_back_to_product_default(self) -> None:
        self.db.add(_UserSetting(user_hash="patient-a", default_morning_time="99:99"))
        self.db.commit()

        alarm = self.control.requestAlarmToggle("patient-a", "morning")["data"]
        disabled = self.control.disableAlarmSetting("patient-a", "morning")["data"]

        self.assertEqual((alarm["hour"], alarm["minute"]), (8, 0))
        self.assertEqual((disabled["hour"], disabled["minute"]), (8, 0))

    # Function Name: _miss_first_lookup
    # Description:
    # - Replaces the control's alarm lookup so the first call reports no row, as when
    #   another request creates the row at the same moment, and later calls read the
    #   database.
    # Parameters:
    # - None.
    # Returns:
    # - Patcher for SetNotification._find_setting on the control under test.
    def _miss_first_lookup(self):
        find_setting = self.control._find_setting
        lookups: list[tuple[str, str]] = []

        # Function Name: lookup
        # Description:
        # - Returns None for the first lookup and the stored alarm afterwards.
        # Parameters:
        # - patient_hash (str): Patient owner of the alarm.
        # - slot_key (str): Medication schedule slot.
        # Returns:
        # - None on the first call, otherwise the stored alarm row.
        def lookup(patient_hash: str, slot_key: str) -> _MedicationAlarm | None:
            lookups.append((patient_hash, slot_key))
            if len(lookups) == 1:
                return None
            return find_setting(patient_hash, slot_key)

        return patch.object(self.control, "_find_setting", side_effect=lookup)

    # Function Name: test_save_conflict_updates_the_concurrently_created_alarm
    # Description:
    # - When the insert of a new alarm hits the patient/slot unique constraint, the control
    #   rolls back and applies the requested enabled time to the existing row.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_save_conflict_updates_the_concurrently_created_alarm(self) -> None:
        self.db.add(
            _MedicationAlarm(
                patient_hash="patient-a",
                slot_key="morning",
                hour=6,
                minute=0,
                enabled=False,
            )
        )
        self.db.commit()

        with self._miss_first_lookup() as lookup:
            response = self.control.saveNotificationSetting("patient-a", "morning", 9, 15)

        self.assertEqual(lookup.call_count, 2)
        self.assertTrue(response["success"])
        self.assertEqual(
            (
                response["data"]["hour"],
                response["data"]["minute"],
                response["data"]["is_enabled"],
            ),
            (9, 15, True),
        )
        row = self.db.query(_MedicationAlarm).one()
        self.assertEqual((row.hour, row.minute, row.enabled), (9, 15, True))

    # Function Name: test_disable_conflict_disables_the_concurrently_created_alarm
    # Description:
    # - When the insert of a disabled default alarm hits the unique constraint, the control
    #   rolls back and disables the existing row, keeping the time the patient chose.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_disable_conflict_disables_the_concurrently_created_alarm(self) -> None:
        self.db.add(
            _MedicationAlarm(
                patient_hash="patient-a",
                slot_key="morning",
                hour=9,
                minute=15,
                enabled=True,
            )
        )
        self.db.commit()

        with self._miss_first_lookup() as lookup:
            response = self.control.disableAlarmSetting("patient-a", "morning")

        self.assertEqual(lookup.call_count, 2)
        self.assertTrue(response["success"])
        self.assertEqual(
            (
                response["data"]["hour"],
                response["data"]["minute"],
                response["data"]["is_enabled"],
            ),
            (9, 15, False),
        )
        row = self.db.query(_MedicationAlarm).one()
        self.assertEqual((row.hour, row.minute, row.enabled), (9, 15, False))


if __name__ == "__main__":
    unittest.main()
