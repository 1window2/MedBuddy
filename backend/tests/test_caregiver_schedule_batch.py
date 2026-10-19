# 파일명: test_caregiver_schedule_batch.py
# 역할: 보호자 일괄 조회의 조회 수와 기존 일정 응답 호환성을 검사한다.

from datetime import timedelta
from typing import Any
from uuid import UUID

import pytest
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

from controls.check_caregiver_monitoring_control import CheckCaregiverMonitoring
from controls.check_today_medication_info_control import CheckTodayMedicationInfo
from core.application_clock import application_today
from core.database import Base
from entities.medication_completion_entity import _MedicationCompletion
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import _UserAccount
from services.as_needed_caregiver_events import as_needed_taken_event_key


# 함수이름: test_batch_preserves_schedules_with_bounded_queries
# 함수역할: 환자 수·400명 경계에 따른 쿼리 수와 완료 기록·필드 투영을 검증한다.
# 매개변수: count: 합성 환자 수. 반환값: 없음, 불일치 시 assertion.
@pytest.mark.parametrize("count", [1, 5, 20, 401])
def test_batch_preserves_schedules_with_bounded_queries(count: int) -> None:
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    selects = []

    # 함수이름: record
    # 함수역할: SELECT만 집계해 숨은 지연 조회를 탐지한다.
    # 매개변수: SQLAlchemy 실행 event 인자. 반환값: 없음.
    def record(conn: Any, cursor: Any, statement: str, parameters: Any, context: Any, executemany: bool) -> None:
        if statement.lstrip().upper().startswith("SELECT"):
            selects.append(statement)

    event.listen(engine, "before_cursor_execute", record)
    try:
        with sessionmaker(bind=engine)() as db:
            today = application_today()
            expected_prn_keys = {}
            db.add(_UserAccount(user_hash="caregiver"))
            for index in range(count):
                owner = f"patient-{index}"
                db.add(_UserAccount(user_hash=owner))
                db.add(_PatientCaregiverLink(
                    patient_hash=owner, caregiver_hash="caregiver", linked=True,
                ))
                medication = _SavedMedication(
                    patient_hash=owner, item_name=f"tablet-{index}",
                    prescription_date=today, total_days="7", daily_frequency="2",
                    schedule_slot_keys='["morning", "evening"]',
                    dosage_per_time="1", efficacy="effect", use_method="use",
                    warning_message="warning", interaction="unused detail",
                    medication_status=True, medication_status_date=today,
                )
                db.add(medication)
                db.flush()
                db.add(_MedicationCompletion(
                    patient_hash=owner, saved_medication_id=medication.id,
                    schedule_date=today, slot_key="evening", completed=False,
                ))
                prn = _SavedMedication(
                    patient_hash=owner, item_name="as-needed", dosing_mode="as_needed",
                    prescription_date=today, total_days="7", daily_frequency="PRN",
                )
                db.add(prn)
                db.flush()
                record_slot = f"as_needed:{UUID(int=index + 1)}"
                db.add(_MedicationCompletion(
                    patient_hash=owner, saved_medication_id=prn.id,
                    schedule_date=today, slot_key=record_slot, completed=True, report_status="taken",
                ))
                expected_prn_keys[owner] = [as_needed_taken_event_key(owner, prn.id, today, record_slot)]
                db.add(_SavedMedication(
                    patient_hash=owner, item_name="expired",
                    prescription_date=today - timedelta(days=10), total_days="1",
                ))
            db.add(_UserAccount(user_hash="unlinked"))
            db.add(_SavedMedication(patient_hash="unlinked", item_name="private"))
            db.commit()
            expected = {
                f"patient-{index}": CheckTodayMedicationInfo(db).requestTodayMedicationInfo(
                    f"patient-{index}"
                )["data"]
                for index in range(count)
            }
            db.expunge_all()
            selects.clear()
            result = CheckCaregiverMonitoring(db).requestMonitoringSnapshot(
                "caregiver", include_all_schedules=True,
            )
            assert len(selects) == 3 + 2 * ((count + 399) // 400)
            assert {
                row["patient_hash"]: row["as_needed_taken_event_keys"]
                for row in result["data"]["patients"]
            } == expected_prn_keys
            assert all(row["as_needed_schedule_date"] == today.isoformat() for row in result["data"]["patients"])
            assert not any("saved_medications.interaction" in sql for sql in selects)
            assert not any("saved_medications.ai_guide" in sql for sql in selects)
            actual = {
                row["patient_hash"]: row["today_medication_info"]
                for row in result["data"]["patients"]
            }
            assert actual == expected
            assert all(item["completed_dose_count"] == 1 for item in actual.values())
            selects.clear()
            assert CheckTodayMedicationInfo(db).requestTodayMedicationInfoForPatients([]) == {}
            assert selects == []
    finally:
        engine.dispose()
