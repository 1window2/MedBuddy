# 파일명: test_request_schema_validation.py
# 역할: 요청 스키마의 코드 정규화, 범위·길이 제한 및 안전한 약 사진 URL을 검증한다.

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


# Class Name: RequestSchemaValidationTest
# Role: Request-boundary validation tests for link codes, preferences, medication text, images,
#   and prescription dates.
# Responsibilities:
# - Rejects untrusted medication image URLs while accepting an official MFDS HTTPS image.
class RequestSchemaValidationTest(unittest.TestCase):
    # 함수이름: test_patient_code_is_normalized_before_validation
    # 함수역할:
    # - 환자 연동 코드를 검증 전에 공백 제거·대문자로 정규화하여 ABCD1234로 보존하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_patient_code_is_normalized_before_validation(self) -> None:
        request = PatientCodeRegister(
            caregiver_hash="caregiver-a",
            patient_code=" abcd1234 ",
        )

        self.assertEqual(request.patient_code, "ABCD1234")

    # 함수이름: test_invalid_patient_code_and_alarm_time_are_rejected
    # 함수역할:
    # - 잘못된 연동 코드와 알람 시·분을 요청 검증 단계에서 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_invalid_user_setting_values_are_rejected_at_request_boundary
    # 함수역할:
    # - 유효 범위를 벗어난 사용자 설정을 control 호출 전 스키마에서 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_oversized_medication_text_is_rejected
    # 함수역할:
    # - 허용 길이를 초과한 약 텍스트 입력을 ValidationError로 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # Function Name: test_untrusted_medication_image_url_is_rejected
    # Description:
    # - Rejects untrusted medication image URLs while accepting an official MFDS HTTPS
    #   image.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_untrusted_medication_image_url_is_rejected(self) -> None:
        common_fields = {
            "item_name": "테스트정",
            "efficacy": "",
            "use_method": "",
            "warning_message": "",
        }

        for image_url in (
            "http://nedrug.mfds.go.kr/pill.jpg",
            "https://example.com/pill.jpg",
            "https://user:pass@nedrug.mfds.go.kr/pill.jpg",
            "https://nedrug.mfds.go.kr:8443/pill.jpg",
        ):
            with self.subTest(image_url=image_url):
                with self.assertRaises(ValidationError):
                    SavedMedicationCreate(image_url=image_url, **common_fields)

        request = SavedMedicationCreate(
            image_url="https://nedrug.mfds.go.kr/pill.jpg",
            **common_fields,
        )
        self.assertEqual(
            request.image_url,
            "https://nedrug.mfds.go.kr/pill.jpg",
        )

    # 함수이름: test_prescription_date_outside_supported_range_is_rejected
    # 함수역할:
    # - 지원 범위 밖 과거·미래 처방일은 거절하고 오늘부터 365일 뒤의 경계값은 허용하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_prescription_change_payload_limits_each_medication
    # 함수역할:
    # - 처방 변경 목록의 각 약 항목에도 길이 제한을 적용하여 과도한 값을 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_prescription_change_payload_limits_each_medication(self) -> None:
        with self.assertRaises(ValidationError):
            PrescriptionChangeRequest(
                medications=[
                    PrescriptionChangeMedication(item_name="a" * 501),
                ]
            )


if __name__ == "__main__":
    unittest.main()
