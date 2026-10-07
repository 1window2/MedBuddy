# 파일명: test_prescription_registration_flow.py
# 역할: 검토한 처방 정보가 복약함·오늘 일정에 같은 내용으로 저장되는지 격리 DB에서 검증한다.

from collections.abc import Iterator
from datetime import timedelta
from itertools import combinations

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from controls.check_saved_medication_control import CheckSavedMedication
from controls.check_schedule_control import CheckSchedule
from core.application_clock import application_today
from core.database import Base
from entities.saved_medication_entity import _SavedMedication
from schemas.medication import SavedMedicationCreate

SLOT_SETS = [
    list(slots)
    for count in range(1, 5)
    for slots in combinations(["morning", "lunch", "evening", "bedtime"], count)
]


# 함수이름: db
# 함수역할: 실제 사용자 데이터와 분리된 메모리 DB를 만들고 시험 후 폐기한다.
# 매개변수: 없음. 반환값: 시험용 세션을 제공하는 제너레이터.
@pytest.fixture
def db() -> Iterator[Session]:
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session
    engine.dispose()


# 함수이름: test_reviewed_course_reaches_pillbox_and_today
# 함수역할: 15개 시간대 조합과 5개 기간 경계에서 저장·중복 재시도·환자 격리·오늘 일정 반영을 확인한다.
# 매개변수: db 격리 세션, slots 선택 시간대, offset 시작일 차이, days 기간, active 오늘 포함 여부.
# 반환값: 없음; 저장 정보나 조회 결과가 다르면 단언 실패.
@pytest.mark.parametrize("slots", SLOT_SETS)
@pytest.mark.parametrize(
    "offset,days,active",
    [(0, 1, True), (-6, 7, True), (-7, 7, False), (1, 7, False), (-1, 0, True)],
)
def test_reviewed_course_reaches_pillbox_and_today(
    db: Session,
    slots: list[str],
    offset: int,
    days: int,
    active: bool,
) -> None:
    start = application_today() + timedelta(days=offset)
    medication = SavedMedicationCreate(
        patient_hash="registration-patient",
        item_name="검토한 시험약",
        item_seq="audit-product",
        efficacy="",
        use_method="",
        warning_message="",
        dosage_per_time="0.5정",
        daily_frequency=f"{len(slots)}회",
        total_days=str(days),
        schedule_slot_keys=slots,
        prescription_date=start,
        prescription_batch_id="registration_batch_0001",
    )
    saved = CheckSavedMedication(db)
    first = saved.saveMedicationDetail(medication)
    retry = saved.saveMedicationDetail(medication)
    assert first["success"] and retry["duplicate"]
    assert first["id"] == retry["id"]
    assert db.query(_SavedMedication).count() == 1
    rows = saved.requestSavedMedicationInfo("registration-patient")["data"]
    assert len(rows) == 1
    assert rows[0]["prescription_date"] == start.isoformat()
    assert rows[0]["dosage_per_time"] == "0.5정"
    assert rows[0]["schedule_slot_keys"] == slots
    assert saved.requestSavedMedicationInfo("another-patient")["data"] == []
    schedule = CheckSchedule(db)
    schedules = schedule.requestTodayMedicationSchedule("registration-patient")["data"]
    assert len(schedules) == int(active)
    if active:
        assert schedules[0]["slot_statuses"] == dict.fromkeys(slots, False)
        assert schedules[0]["dosage_per_time"] == "0.5정"
    assert schedule.requestTodayMedicationSchedule("another-patient")["data"] == []


# 함수이름: test_new_registration_does_not_inherit_existing_completion
# 함수역할: 이미 복용한 약이 있어도 새로 등록한 처방은 미복용 상태로 시작하는지 확인한다.
# 매개변수: db 격리 세션. 반환값: 없음; 기존 또는 새 약의 상태가 다르면 단언 실패.
def test_new_registration_does_not_inherit_existing_completion(db: Session) -> None:
    saved = CheckSavedMedication(db)
    schedule = CheckSchedule(db)
    common = dict(
        patient_hash="registration-patient",
        item_name="같은 이름 시험약",
        efficacy="",
        use_method="",
        warning_message="",
        total_days="7",
        daily_frequency="1",
        prescription_date=application_today(),
        schedule_slot_keys=["bedtime"],
    )
    first = saved.saveMedicationDetail(
        SavedMedicationCreate(**common, prescription_batch_id="registration_batch_0001")
    )
    schedule.updateMedicationStatus(
        int(first["id"]), True, "registration-patient", slot_key="bedtime"
    )
    second = saved.saveMedicationDetail(
        SavedMedicationCreate(**common, prescription_batch_id="registration_batch_0002")
    )
    rows = schedule.requestTodayMedicationSchedule("registration-patient")["data"]
    by_id = {str(row["medication_id"]): row for row in rows}
    assert by_id[str(first["id"])]["slot_statuses"] == {"bedtime": True}
    assert by_id[str(second["id"])]["slot_statuses"] == {"bedtime": False}
