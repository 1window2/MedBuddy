# 파일명: test_prescription_change_schedule.py
# 역할: 복약 일정의 표기 차이는 무시하고 실제 수치·단위·지시 변경은 보존하는지 검증한다.

from datetime import date
from unittest.mock import Mock

import pytest
from sqlalchemy.orm import Session

from controls.check_prescription_change_control import CheckPrescriptionChange
from entities.saved_medication_entity import _SavedMedication
from repositories.saved_medication_repository import SavedMedicationRepository
from schemas.prescription_change import (
    PrescriptionChangeMedication,
    PrescriptionChangeRequest,
)


@pytest.fixture
def control() -> CheckPrescriptionChange:
    # 실제 저장소나 외부 서비스에 연결하지 않고 비교 로직만 실행한다.
    return CheckPrescriptionChange(
        Mock(spec=Session),
        medication_repository=Mock(spec=SavedMedicationRepository),
    )


@pytest.mark.parametrize(
    ("field_name", "previous_value", "current_value"),
    [
        ("daily_frequency", "2", "2회"),
        ("daily_frequency", "2회", "2"),
        ("daily_frequency", "2", "1일 2회"),
        ("daily_frequency", "1일 2회", "2"),
        ("daily_frequency", "2회", "1일 2회"),
        ("daily_frequency", " 2 ", "\t1일 2 회\n"),
        ("total_days", "7", "7일"),
        ("total_days", "7일", "7"),
        ("total_days", "7일", " 7 일 "),
        # Bare quantities are read with the schedule's own rules.
        ("total_days", "7", "7일분"),
        ("total_days", "7", "1주"),
        ("total_days", "7일", "7 days"),
        ("total_days", "30일", "1개월"),
        ("daily_frequency", "3회", "하루 3회"),
        ("daily_frequency", "3", "3 times"),
        ("dosage_per_time", "5 mg", "5MG"),
    ],
)
def test_equivalent_schedule_labels_are_unchanged(
    control: CheckPrescriptionChange,
    field_name: str,
    previous_value: str,
    current_value: str,
) -> None:
    previous = _SavedMedication(item_name="소론도정(프레드니솔론)")
    current = PrescriptionChangeMedication(item_name=previous.item_name)
    setattr(previous, field_name, previous_value)
    setattr(current, field_name, current_value)

    changes, unchanged_count = control._compare_medications([previous], [current])

    assert changes == []
    assert unchanged_count == 1


@pytest.mark.parametrize(
    ("field_name", "previous_value", "current_value"),
    [
        ("daily_frequency", "2", "3회"),
        ("daily_frequency", "1일 2회", "1일 3회"),
        ("daily_frequency", "2회", "주 2회"),
        ("daily_frequency", "2회", "2일 2회"),
        ("daily_frequency", "2회", "1일 2회 식후 30분"),
        ("daily_frequency", "1일 2회 식전", "1일 2회 식후"),
        ("daily_frequency", "2회", "필요시 2회"),
        ("daily_frequency", "2", "2일"),
        ("daily_frequency", "2", "2~3회"),
        # Counts above the schedule's four slots are still compared as written.
        ("daily_frequency", "1일 4회", "1일 6회"),
        ("daily_frequency", "6회", "8"),
        ("daily_frequency", "2", "1일2"),
        ("daily_frequency", "", "2회"),
        ("daily_frequency", "2회", ""),
        ("total_days", "7", "8일"),
        ("total_days", "7일", "7주"),
        ("total_days", "7", "7일 필요시"),
        ("total_days", "7", "7회"),
        ("total_days", "7", "7~14일"),
        ("total_days", "", "7일"),
        ("total_days", "7일", ""),
        ("dosage_per_time", "1", "1정"),
        ("dosage_per_time", "5mg", "5ml"),
        ("dosage_per_time", "1정", "1캡슐"),
        ("dosage_per_time", "10mg", "1mg"),
        ("dosage_per_time", "", "1정"),
    ],
)
def test_meaningful_schedule_changes_preserve_original_values(
    control: CheckPrescriptionChange,
    field_name: str,
    previous_value: str,
    current_value: str,
) -> None:
    previous = _SavedMedication(item_name="소론도정(프레드니솔론)")
    current = PrescriptionChangeMedication(item_name=previous.item_name)
    setattr(previous, field_name, previous_value)
    setattr(current, field_name, current_value)

    changes, unchanged_count = control._compare_medications([previous], [current])

    assert unchanged_count == 0
    assert len(changes) == 1
    change = changes[0]
    assert change.change_type == "schedule_changed"
    assert change.changed_fields == [field_name]
    assert getattr(change.previous, field_name) == previous_value
    assert getattr(change.current, field_name) == current_value


@pytest.mark.parametrize("current_dosage", ["1정", "0.5정"])
def test_response_reports_only_meaningful_changes(
    control: CheckPrescriptionChange,
    current_dosage: str,
) -> None:
    # 화면에서 확인한 횟수 오탐을 이전 처방 선택부터 응답 집계까지 재현한다.
    previous = _SavedMedication(
        item_name="소론도정(프레드니솔론)",
        prescription_date=date(2026, 10, 4),
        dosage_per_time="1정",
        daily_frequency="2",
        total_days="7",
    )
    control.medication_repository.list_recent_by_patient.return_value = [previous]
    current = PrescriptionChangeMedication(
        item_name=previous.item_name,
        dosage_per_time=current_dosage,
        daily_frequency="2회",
        total_days="7일",
    )

    response = control.request_prescription_change(
        PrescriptionChangeRequest(
            patient_hash="schedule-test-patient",
            prescription_date=date(2026, 10, 6),
            medications=[current],
        )
    )

    assert response.has_previous_prescription
    assert response.comparison_status == "comparable"
    assert response.previous_prescription_date == previous.prescription_date
    assert response.summary.added_count == 0
    assert response.summary.missing_count == 0
    if current_dosage == "1정":
        assert response.summary.unchanged_count == 1
        assert response.summary.schedule_changed_count == 0
        assert response.changes == []
    else:
        assert response.summary.unchanged_count == 0
        assert response.summary.schedule_changed_count == 1
        assert len(response.changes) == 1
        change = response.changes[0]
        assert change.changed_fields == ["dosage_per_time"]
        assert change.previous.daily_frequency == "2"
        assert change.current.daily_frequency == "2회"
        assert change.previous.total_days == "7"
        assert change.current.total_days == "7일"
    control.db.query.assert_not_called()
