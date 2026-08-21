# 파일명: test_set_caregiver_notification_control.py
# 역할: 보호자 알림의 시간대별 저장과 연동 범위 제한을 검증한다.

import sys
import unittest
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.link_patient_caregiver_control import LinkPatientCaregiver  # noqa: E402
from controls.set_caregiver_notification_control import (  # noqa: E402
    SetCaregiverNotification,
)
from core.database import Base  # noqa: E402
from entities.caregiver_notification_entity import (  # noqa: E402
    _CaregiverNotification,
    ensure_caregiver_notification_schema,
)


class SetCaregiverNotificationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=self.engine)
        ensure_caregiver_notification_schema(self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.link_control = LinkPatientCaregiver(self.db)
        self.control = SetCaregiverNotification(self.db)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def _link_caregiver(self) -> None:
        code_response = self.link_control.generatePatientHash("patient-a")
        self.link_control.requestPatientCaregiverLink(
            "caregiver-a",
            code_response["data"]["patient_code"],
        )

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

    def test_invalid_alert_option_is_rejected(self) -> None:
        self._link_caregiver()

        with self.assertRaises(HTTPException) as context:
            self.control.saveCaregiverNotificationSetting(
                "caregiver-a",
                "patient-a",
                alert_option="later",
            )

        self.assertEqual(context.exception.status_code, 400)

    def test_string_enabled_value_is_parsed_without_truthiness_bug(self) -> None:
        self._link_caregiver()

        response = self.control.saveCaregiverNotificationSetting(
            "caregiver-a",
            "patient-a",
            enabled="false",  # type: ignore[arg-type]
        )

        self.assertFalse(response["data"]["is_enabled"])
        self.assertEqual(response["data"]["alert_option"], "disabled")

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
                        "(2, 'guardian-a', 'patient-a'), "
                        "(3, NULL, NULL)"
                    )
                )

            ensure_caregiver_notification_schema(legacy_engine)

            with legacy_engine.connect() as connection:
                columns = {
                    row[1]
                    for row in connection.execute(
                        text("PRAGMA table_info(guardian_alert_settings)")
                    )
                }
                self.assertIn("enabled", columns)
                self.assertIn("alert_option", columns)
                self.assertIn("deadline_hour", columns)
                self.assertIn("deadline_minute", columns)
                self.assertIn("slot_settings", columns)
                row_count = connection.execute(
                    text(
                        "SELECT COUNT(*) FROM guardian_alert_settings "
                        "WHERE guardian_hash = 'guardian-a' "
                        "AND patient_hash = 'patient-a'"
                    )
                ).scalar_one()
                self.assertEqual(row_count, 1)
                migrated_row = connection.execute(
                    text(
                        "SELECT enabled, alert_option, created_at, updated_at "
                        "FROM guardian_alert_settings "
                        "WHERE guardian_hash = 'guardian-a' "
                        "AND patient_hash = 'patient-a'"
                    )
                ).first()
                self.assertEqual(migrated_row[0], 0)
                self.assertEqual(migrated_row[1], "disabled")
                self.assertIsNotNone(migrated_row[2])
                self.assertIsNotNone(migrated_row[3])
        finally:
            legacy_engine.dispose()


if __name__ == "__main__":
    unittest.main()
