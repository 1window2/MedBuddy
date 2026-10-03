# 파일명: test_check_prescription_change_control.py
# 역할: 처방 비교의 환자 범위, 비교 기간, 관련 처방 선택 및 약·복용법 변경 분류를 검증한다.

import sys
import unittest
from datetime import date, timedelta
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.check_prescription_change_control import (  # noqa: E402
    CheckPrescriptionChange,
)
from core.database import Base  # noqa: E402
from entities.saved_medication_entity import _SavedMedication  # noqa: E402
from schemas.prescription_change import (  # noqa: E402
    PrescriptionChangeMedication,
    PrescriptionChangeRequest,
)


# Class Name: CheckPrescriptionChangeTest
# Role: Database-backed prescription comparison tests covering related batches, change
#   categories, and patient isolation.
# Responsibilities:
# - Persists a previous medication snapshot with configurable patient, date, product identity,
#   dosing, and batch for comparison tests.
# - Keeps same-day prescription batches separate so a schedule change does not create a false
#   missing medication.
# Attributes:
# - engine (Engine): Isolated in-memory SQLite engine.
# - db (Session): SQLAlchemy session holding only this test's database state.
# - control (CheckPrescriptionChange): Use-case control under test, isolated from production
#   state.
# - previous_date (date): Fixed date for historical prescription snapshots.
# - current_date (date): Fixed date of the new prescription being compared.
class CheckPrescriptionChangeTest(unittest.TestCase):
    # 함수이름: setUp
    # 함수역할:
    # - 격리 SQLite DB와 처방 비교 control을 만들고 이전·현재 처방일을 고정한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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
        self.control = CheckPrescriptionChange(self.db)
        self.previous_date = date(2026, 7, 1)
        self.current_date = date(2026, 7, 15)

    # 함수이름: tearDown
    # 함수역할:
    # - 처방 비교 테스트의 세션과 데이터베이스 엔진을 닫는다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # Function Name: _save_previous
    # Description:
    # - Persists a previous medication snapshot with configurable patient, date, product
    #   identity, dosing, and batch for comparison tests.
    # Parameters:
    # - patient_hash (str): Patient owner identifying the medication or linked-data scope.
    # - prescription_date (date | None): Course start/prescription date; None uses the
    #   fixture's default.
    # - item_seq (str): Authoritative product code identifying the medication.
    # - item_name (str): Product name in the authoritative or saved medication record.
    # - efficacy (str): Medication effect text preserved in the saved snapshot.
    # - dosage_per_time (str): Amount taken in one medication dose.
    # - daily_frequency (str): Prescription dose-frequency label.
    # - total_days (str): Prescribed course-duration label, possibly unknown.
    # - prescription_batch_id (str | None): Analysis batch identity separating independently
    #   entered prescriptions.
    # Returns:
    # - None.
    def _save_previous(
        self,
        *,
        patient_hash: str = "patient-a",
        prescription_date: date | None = None,
        item_seq: str,
        item_name: str,
        efficacy: str = "효능",
        dosage_per_time: str = "1정",
        daily_frequency: str = "1일 3회",
        total_days: str = "7일",
        prescription_batch_id: str | None = None,
    ) -> None:
        saved_date = prescription_date or self.previous_date
        self.db.add(
            _SavedMedication(
                patient_hash=patient_hash,
                created_date=saved_date,
                prescription_date=saved_date,
                prescription_batch_id=prescription_batch_id,
                item_seq=item_seq,
                item_name=item_name,
                efficacy=efficacy,
                use_method="복용법",
                warning_message="주의사항",
                dosage_per_time=dosage_per_time,
                daily_frequency=daily_frequency,
                total_days=total_days,
            )
        )
        self.db.commit()

    # 함수이름: test_classifies_added_missing_and_schedule_changes
    # 함수역할:
    # - 처방 변경을 유지·추가·누락·복용법 변경으로 각각 분류하고 변경 필드가 용량과 횟수인지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_classifies_added_missing_and_schedule_changes(self) -> None:
        self._save_previous(item_seq="A-1", item_name="기존 유지약")
        self._save_previous(item_seq="B-1", item_name="일정 변경약")
        self._save_previous(item_seq="C-1", item_name="이전 처방 약")

        response = self.control.request_prescription_change(
            PrescriptionChangeRequest(
                patient_hash="patient-a",
                prescription_date=self.current_date,
                medications=[
                    PrescriptionChangeMedication(
                        item_seq="A-1",
                        item_name="기존 유지약",
                        dosage_per_time="1정",
                        daily_frequency="1일 3회",
                        total_days="7일",
                    ),
                    PrescriptionChangeMedication(
                        item_seq="B-1",
                        item_name="일정 변경약",
                        dosage_per_time="0.5정",
                        daily_frequency="1일 2회",
                        total_days="7일",
                    ),
                    PrescriptionChangeMedication(
                        item_seq="D-1",
                        item_name="새 처방 약",
                        dosage_per_time="1정",
                        daily_frequency="1일 1회",
                        total_days="3일",
                    ),
                ],
            )
        )

        self.assertTrue(response.has_previous_prescription)
        self.assertEqual(response.previous_prescription_date, self.previous_date)
        self.assertEqual(response.comparison_status, "comparable")
        self.assertEqual(response.summary.unchanged_count, 1)
        self.assertEqual(response.summary.added_count, 1)
        self.assertEqual(response.summary.missing_count, 1)
        self.assertEqual(response.summary.schedule_changed_count, 1)
        change_by_type = {change.change_type: change for change in response.changes}
        self.assertEqual(
            change_by_type["schedule_changed"].changed_fields,
            ["dosage_per_time", "daily_frequency"],
        )

    # 함수이름: test_uses_latest_prescription_before_current_date
    # 함수역할:
    # - 현재 처방일 이전의 가장 최근 관련 처방을 선택하고 동일 약에는 변경을 생성하지 않는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_uses_latest_prescription_before_current_date(self) -> None:
        self._save_previous(item_seq="OLD", item_name="오래된 약")
        recent_date = self.current_date - timedelta(days=2)
        self.db.add(
            _SavedMedication(
                patient_hash="patient-a",
                created_date=recent_date,
                prescription_date=recent_date,
                item_seq="RECENT",
                item_name="최근 약",
                dosage_per_time="1정",
                daily_frequency="1일 1회",
                total_days="5일",
            )
        )
        self.db.commit()

        response = self.control.request_prescription_change(
            PrescriptionChangeRequest(
                patient_hash="patient-a",
                prescription_date=self.current_date,
                medications=[
                    PrescriptionChangeMedication(
                        item_seq="RECENT",
                        item_name="최근 약",
                        dosage_per_time="1정",
                        daily_frequency="1일 1회",
                        total_days="5일",
                    )
                ],
            )
        )

        self.assertEqual(response.previous_prescription_date, recent_date)
        self.assertEqual(response.summary.unchanged_count, 1)
        self.assertEqual(response.changes, [])

    # Function Name: test_keeps_separate_prescription_batches_from_the_same_day
    # Description:
    # - Keeps same-day prescription batches separate so a schedule change does not create a
    #   false missing medication.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_keeps_separate_prescription_batches_from_the_same_day(self) -> None:
        same_day = self.current_date - timedelta(days=1)
        self._save_previous(
            prescription_date=same_day,
            prescription_batch_id="batch_cold_1234567890",
            item_seq="COLD-1",
            item_name="감기약",
            efficacy="기침과 가래를 완화합니다.",
        )
        self._save_previous(
            prescription_date=same_day,
            prescription_batch_id="batch_gi_123456789012",
            item_seq="GI-1",
            item_name="위장약",
            efficacy="위산 과다와 속쓰림을 완화합니다.",
        )

        response = self.control.request_prescription_change(
            PrescriptionChangeRequest(
                patient_hash="patient-a",
                prescription_date=self.current_date,
                medications=[
                    PrescriptionChangeMedication(
                        item_seq="COLD-1",
                        item_name="감기약",
                        efficacy="기침과 가래를 완화합니다.",
                    )
                ],
            )
        )

        self.assertTrue(response.has_previous_prescription)
        self.assertEqual(response.previous_prescription_date, same_day)
        self.assertEqual(response.summary.schedule_changed_count, 1)
        self.assertEqual(response.summary.missing_count, 0)

    # 함수이름: test_selects_older_related_prescription_over_latest_unrelated_one
    # 함수역할:
    # - 최신 처방이 무관하면 더 오래된 동일 약 처방을 비교 대상으로 선택하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_selects_older_related_prescription_over_latest_unrelated_one(
        self,
    ) -> None:
        self._save_previous(
            prescription_date=self.previous_date,
            item_seq="COLD-1",
            item_name="기존 감기약",
            efficacy="기침과 가래를 완화합니다.",
        )
        self._save_previous(
            prescription_date=self.current_date - timedelta(days=1),
            item_seq="GI-1",
            item_name="최근 위장약",
            efficacy="위산 과다와 속쓰림을 완화합니다.",
        )

        response = self.control.request_prescription_change(
            PrescriptionChangeRequest(
                patient_hash="patient-a",
                prescription_date=self.current_date,
                medications=[
                    PrescriptionChangeMedication(
                        item_seq="COLD-1",
                        item_name="기존 감기약",
                        efficacy="기침과 가래를 완화합니다.",
                    )
                ],
            )
        )

        self.assertTrue(response.has_previous_prescription)
        self.assertEqual(response.previous_prescription_date, self.previous_date)
        self.assertEqual(response.match_basis, "same_medication")

    # 함수이름: test_skips_comparison_when_recent_prescription_is_unrelated
    # 함수역할:
    # - 최근 처방이 무관하면 unrelated 상태와 빈 변경 목록으로 비교를 생략하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_skips_comparison_when_recent_prescription_is_unrelated(self) -> None:
        self._save_previous(
            item_seq="COLD-1",
            item_name="감기약",
            efficacy="기침과 가래, 콧물을 완화합니다.",
        )

        response = self.control.request_prescription_change(
            PrescriptionChangeRequest(
                patient_hash="patient-a",
                prescription_date=self.current_date,
                medications=[
                    PrescriptionChangeMedication(
                        item_seq="GI-1",
                        item_name="위장약",
                        efficacy="위산 과다와 속쓰림을 완화합니다.",
                    )
                ],
            )
        )

        self.assertFalse(response.has_previous_prescription)
        self.assertEqual(response.comparison_status, "unrelated")
        self.assertEqual(response.changes, [])

    # 함수이름: test_skips_prescription_older_than_comparison_window
    # 함수역할:
    # - 90일 비교 기간을 지난 처방은 expired로 표시하고 이전 비교 처방으로 인정하지 않는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_skips_prescription_older_than_comparison_window(self) -> None:
        self._save_previous(
            prescription_date=self.current_date - timedelta(days=91),
            item_seq="LONG-TERM-1",
            item_name="장기 복용약",
        )

        response = self.control.request_prescription_change(
            PrescriptionChangeRequest(
                patient_hash="patient-a",
                prescription_date=self.current_date,
                medications=[
                    PrescriptionChangeMedication(
                        item_seq="LONG-TERM-1",
                        item_name="장기 복용약",
                    )
                ],
            )
        )

        self.assertFalse(response.has_previous_prescription)
        self.assertEqual(response.comparison_status, "expired")
        self.assertEqual(response.comparison_window_days, 90)

    # 함수이름: test_compares_different_products_with_same_ingredient_name
    # 함수역할:
    # - 제품이 달라도 성분명이 같으면 same_ingredient 근거로 이전 처방을 비교하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_compares_different_products_with_same_ingredient_name(self) -> None:
        self._save_previous(
            item_seq="BRAND-A",
            item_name="브랜드A정(아세트아미노펜)",
        )

        response = self.control.request_prescription_change(
            PrescriptionChangeRequest(
                patient_hash="patient-a",
                prescription_date=self.current_date,
                medications=[
                    PrescriptionChangeMedication(
                        item_seq="BRAND-B",
                        item_name="브랜드B정(아세트아미노펜)",
                    )
                ],
            )
        )

        self.assertTrue(response.has_previous_prescription)
        self.assertEqual(response.match_basis, "same_ingredient")

    # 함수이름: test_does_not_compare_another_patients_medication
    # 함수역할:
    # - 다른 환자의 약은 이전 처방이나 변경 목록에 포함하지 않는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_does_not_compare_another_patients_medication(self) -> None:
        self._save_previous(
            patient_hash="patient-b",
            item_seq="OTHER",
            item_name="다른 환자 약",
        )

        response = self.control.request_prescription_change(
            PrescriptionChangeRequest(
                patient_hash="patient-a",
                prescription_date=self.current_date,
                medications=[
                    PrescriptionChangeMedication(
                        item_seq="CURRENT",
                        item_name="현재 약",
                    )
                ],
            )
        )

        self.assertFalse(response.has_previous_prescription)
        self.assertEqual(response.changes, [])


if __name__ == "__main__":
    unittest.main()
