# 파일명: test_request_schema_validation.py
# 역할: 비정상적으로 크거나 범위를 벗어난 API 요청이 경계에서 거절되는지 검증한다.

import unittest
from datetime import date, timedelta

from pydantic import ValidationError

from core.application_clock import application_today
from schemas.medication import (
    MedicationAlarmUpdate,
    MedicationRequest,
    PatientCodeRegister,
    SavedMedicationCreate,
    UserSettingUpdate,
)
from schemas.prescription_change import (
    PrescriptionChangeMedication,
    PrescriptionChangeRequest,
)


class RequestSchemaValidationTest(unittest.TestCase):
    def test_patient_code_is_normalized_before_validation(self) -> None:
        request = PatientCodeRegister(
            caregiver_hash="caregiver-a",
            patient_code=" abcd1234 ",
        )

        self.assertEqual(request.patient_code, "ABCD1234")

    def test_invalid_patient_code_and_alarm_time_are_rejected(self) -> None:
        with self.assertRaises(ValidationError):
            PatientCodeRegister(
                caregiver_hash="caregiver-a",
                patient_code="ABC-123",
            )

        with self.assertRaises(ValidationError):
            MedicationAlarmUpdate(hour=24, minute=0)

        with self.assertRaises(ValidationError):
            MedicationAlarmUpdate(hour=8, minute=60)

    def test_invalid_user_setting_values_are_rejected_at_request_boundary(
        self,
    ) -> None:
        with self.assertRaises(ValidationError):
            UserSettingUpdate(
                font_size=30,
                reading_speed=1.0,
                language="ko",
            )

        with self.assertRaises(ValidationError):
            UserSettingUpdate(
                font_size=16,
                reading_speed=1.0,
                language="jp",
            )

    def test_oversized_medication_text_is_rejected(self) -> None:
        with self.assertRaises(ValidationError):
            MedicationRequest(extracted_text="a" * 20_001)

        with self.assertRaises(ValidationError):
            SavedMedicationCreate(
                item_name="a" * 501,
                efficacy="",
                use_method="",
                warning_message="",
            )

    def test_prescription_date_outside_supported_range_is_rejected(self) -> None:
        common_fields = {
            "item_name": "테스트정",
            "efficacy": "",
            "use_method": "",
            "warning_message": "",
        }

        with self.assertRaises(ValidationError):
            SavedMedicationCreate(
                prescription_date=date(1999, 12, 31),
                **common_fields,
            )

        with self.assertRaises(ValidationError):
            SavedMedicationCreate(
                prescription_date=application_today() + timedelta(days=366),
                **common_fields,
            )

        valid_request = SavedMedicationCreate(
            prescription_date=application_today() + timedelta(days=365),
            **common_fields,
        )
        self.assertEqual(
            valid_request.prescription_date,
            application_today() + timedelta(days=365),
        )

    def test_prescription_change_payload_limits_each_medication(self) -> None:
        with self.assertRaises(ValidationError):
            PrescriptionChangeRequest(
                medications=[
                    PrescriptionChangeMedication(item_name="a" * 501),
                ]
            )


if __name__ == "__main__":
    unittest.main()
