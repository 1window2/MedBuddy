# 파일명: test_medication_care.py
# 역할: 약 버전·필요시 복용·사용자 복용 보고의 권한과 기존 일정 호환성을 검증한다.

from datetime import timedelta
import json
from types import SimpleNamespace
from uuid import uuid4

from fastapi import HTTPException
import pytest
from sqlalchemy.orm import Session

from controls.check_saved_medication_control import CheckSavedMedication
from controls.check_schedule_control import CheckSchedule
from controls.check_prescription_change_control import CheckPrescriptionChange
from controls.manage_account_control import ManageAccount
from controls.manage_medication_care_control import ManageMedicationCare
from controls.sync_dose_control import SyncDose
from core.application_clock import application_now, application_today
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.caregiver_alert_outbox_entity import _CaregiverAlertOutbox
from entities.medication_care_entity import _MedicationCareAudit, _MedicationCareOperation
from entities.medication_completion_entity import _MedicationCompletion
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import _UserAccount, utc_now
from schemas.dose_sync import DoseSyncRequest
from schemas.medication import SavedMedicationCreate
from schemas.medication_care import DoseHistoryUpdate, RegimenChangeRequest
from services.medication_course_policy import MedicationCoursePolicy
from services.medication_dosing_mode import medication_dosing_mode, resolve_dosing_mode
from support.db import seed_account, seed_medication


# 함수이름: principal
# 함수역할: 외부 인증 없이 테스트용 검증 주체를 만든다.
# 매개변수: owner: 소유자. 반환값: 주체.
def principal(owner: str = "patient-a") -> AuthenticatedPrincipal:
    return AuthenticatedPrincipal(subject=owner, issuer="test", user_hash=owner)


# 함수이름: change
# 함수역할: 중복되지 않는 기본 변경 요청을 만든다.
# 매개변수: values: 요청 덮어쓰기. 반환값: 검증된 요청.
def change(**values: object) -> RegimenChangeRequest:
    return RegimenChangeRequest(**{
        "action": "edit", "effective_date": application_today(), "operation_id": uuid4(),
        "changes": {"dosage_per_time": "0.5 tablet"}, **values,
    })


# 함수이름: report
# 함수역할: 테스트 실제 복용 시각 또는 선택 상태의 기록 요청을 만든다.
# 매개변수: values: 요청 덮어쓰기. 반환값: 검증된 요청.
def report(**values: object) -> DoseHistoryUpdate:
    data = {"status": "taken", "operation_id": uuid4(), **values}
    if data["status"] == "taken":
        data.setdefault("actual_taken_at", application_now() - timedelta(seconds=1))
    return DoseHistoryUpdate(**data)


# 함수이름: medication
# 함수역할: 최근 이력과 미래 변경을 검증할 충분한 기간의 약을 만든다.
# 매개변수: db: 세션, values: 약 속성. 반환값: 약.
def medication(db: Session, **values: object) -> _SavedMedication:
    return seed_medication(db, **{
        "prescription_date": application_today() - timedelta(days=10), "total_days": "90",
        "daily_frequency": "1", "schedule_slot_keys": '["morning"]', **values,
    })


# 함수이름: test_edit_creates_version_preserves_history_and_replays
# 함수역할: 수정이 기존 기록·처방 주기를 유지하고 동일 작업 재전송은 행을 늘리지 않는지 확인한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_edit_creates_version_preserves_history_and_replays(fk_db: Session) -> None:
    old = medication(fk_db)
    control = ManageMedicationCare(fk_db)
    yesterday = application_today() - timedelta(days=1)
    control.update_history(principal(), old.id, yesterday, "morning", report())
    request = change()
    result = control.change_medication(principal(), old.id, request)
    assert result["id"] != old.id and result["revision"] == 1
    assert control.change_medication(principal(), old.id, request) == result
    assert fk_db.query(_SavedMedication).count() == 2
    new = fk_db.get(_SavedMedication, result["id"])
    assert new.dosage_per_time == "0.5 tablet"
    assert new.prescription_date == old.prescription_date
    assert old.stopped_on == application_today() and old.superseded_by_id == new.id
    rows = control.history(principal(), yesterday, application_today())["items"]
    assert next(row for row in rows if row["medication_id"] == old.id)["status"] == "taken"
    ids = [int(row["medication_id"]) for row in CheckSchedule(fk_db).requestTodayMedicationSchedule("patient-a")["data"]]
    assert ids == [new.id]


# 함수이름: test_stop_today_preserves_taken_and_blocks_new_doses
# 함수역할: 아침 복용 후 당일 중단이 남은 일정을 없애되 아침 기록과 정정을 보존하는지 확인한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_stop_today_preserves_taken_and_blocks_new_doses(fk_db: Session) -> None:
    med = medication(fk_db, daily_frequency="2", schedule_slot_keys='["morning","evening"]')
    control = ManageMedicationCare(fk_db)
    today = application_today()
    first = control.update_history(principal(), med.id, today, "morning", report())
    result = control.change_medication(principal(), med.id, change(action="stop", changes={}))
    assert result["id"] == med.id and med.stopped_on == today
    assert CheckSchedule(fk_db).requestTodayMedicationSchedule("patient-a")["data"] == []
    assert CheckSchedule(fk_db).requestMedicationScheduleWindow("patient-a")["data"] == []
    rows = control.history(principal(), today, today)["items"]
    assert len(rows) == 1 and rows[0]["status"] == "taken"
    corrected = control.update_history(principal(), med.id, today, "morning", report(expected_revision=first["revision"], reason="time corrected"))
    assert corrected["revision"] == 2
    with pytest.raises(HTTPException) as error:
        control.update_history(principal(), med.id, today, "evening", report())
    assert error.value.status_code == 422


# 함수이름: test_stop_materializes_legacy_completion
# 함수역할: 행 단위로만 저장된 이전 앱 완료 기록도 중단 후 이력에서 유지한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_stop_materializes_legacy_completion(fk_db: Session) -> None:
    med = medication(fk_db, medication_status=True, medication_status_date=application_today())
    care = ManageMedicationCare(fk_db)
    care.change_medication(principal(), med.id, change(action="stop", changes={}))
    rows = care.history(principal(), application_today(), application_today())["items"]
    assert len(rows) == 1 and rows[0]["status"] == "taken"
    assert rows[0]["actual_taken_at"] is None


# 함수이름: test_stop_rejects_future_records
# 함수역할: 오늘 기록을 허용하는 중단 예외가 미래의 저장 기록까지 덮지 못하는지 확인한다.
# 매개변수: fk_db: 격리 세션, offset: 적용일 차이, legacy: 이전 전체 완료 형식. 반환값: 없음.
@pytest.mark.parametrize("offset", [0, 1])
@pytest.mark.parametrize("legacy", [False, True])
def test_stop_rejects_future_records(fk_db: Session, offset: int, legacy: bool) -> None:
    tomorrow = application_today() + timedelta(days=1)
    med = medication(fk_db, medication_status=legacy, medication_status_date=tomorrow if legacy else None)
    if not legacy:
        fk_db.add(_MedicationCompletion(
            patient_hash="patient-a", saved_medication_id=med.id,
            schedule_date=tomorrow, slot_key="morning", completed=True,
        ))
        fk_db.commit()
    with pytest.raises(HTTPException) as error:
        ManageMedicationCare(fk_db).change_medication(
            principal(), med.id,
            change(action="stop", changes={}, effective_date=application_today() + timedelta(days=offset)),
        )
    assert error.value.status_code == 409
    fk_db.refresh(med)
    assert med.stopped_on is None and med.regimen_revision == 0


# 함수이름: test_change_rejects_stale_request_and_historical_rewrite
# 함수역할: 이미 수정한 버전과 과거 날짜를 덮어쓰지 못하는지 확인한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_change_rejects_stale_request_and_historical_rewrite(fk_db: Session) -> None:
    med = medication(fk_db)
    care = ManageMedicationCare(fk_db)
    with pytest.raises(HTTPException) as error:
        care.change_medication(principal(), med.id, change(effective_date=application_today() - timedelta(days=1)))
    assert error.value.status_code == 422
    care.change_medication(principal(), med.id, change())
    with pytest.raises(HTTPException) as error:
        care.change_medication(principal(), med.id, change())
    assert error.value.status_code == 409
    assert fk_db.query(_SavedMedication).count() == 2


# 함수이름: test_edit_after_taken_requires_later_date
# 함수역할: 당일 기록이 있는 약의 수정·교체는 다음 날 적용하도록 충돌을 반환한다.
# 매개변수: fk_db: 격리 세션, action: 변경 종류. 반환값: 없음.
@pytest.mark.parametrize("action", ["edit", "replace"])
def test_edit_after_taken_requires_later_date(fk_db: Session, action: str) -> None:
    med = medication(fk_db)
    care = ManageMedicationCare(fk_db)
    care.update_history(principal(), med.id, application_today(), "morning", report())
    with pytest.raises(HTTPException) as error:
        care.change_medication(principal(), med.id, change(action=action))
    assert error.value.status_code == 409
    result = care.change_medication(principal(), med.id, change(action=action, effective_date=application_today() + timedelta(days=1)))
    assert result["id"] != med.id
    window = CheckSchedule(fk_db).requestMedicationScheduleWindow("patient-a")["data"]
    old = next(item for item in window if int(item["medication_id"]) == med.id)
    assert old["course_end_date"] == application_today().isoformat()
    assert int(old["total_days"]) == 11


# 함수이름: test_replacement_different_drug_clears_old_product_metadata
# 함수역할: 다른 약 이름에 이전 약품 이미지와 AI 안내를 재사용하지 않는지 확인한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_replacement_different_drug_clears_old_product_metadata(fk_db: Session) -> None:
    med = medication(fk_db, item_seq="old-product", ai_guide="old advice")
    result = ManageMedicationCare(fk_db).change_medication(principal(), med.id, change(action="replace", changes={"item_name": "different medicine"}))
    new = fk_db.get(_SavedMedication, result["id"])
    assert new.item_seq is None and new.ai_guide is None and new.efficacy == ""


# 함수이름: test_prn_detection
# 함수역할: 한국어·영어 필요시 지시만 정기 일정에서 분리하는지 확인한다.
# 매개변수: direction: 처방 지시. 반환값: 없음.
@pytest.mark.parametrize("direction", ["필요시 1정", "필요 시", "통증 있을 때", "PRN", "p.r.n.", "as needed", "if needed"])
def test_prn_detection(direction: str) -> None:
    assert resolve_dosing_mode("scheduled", direction) == "as_needed"
    assert resolve_dosing_mode("scheduled", "1일 3회") == "scheduled"


# 함수이름: test_scheduled_dose_with_extra_prn_dose_stays_scheduled
# 함수역할: 정기 복용약의 1회량에 붙은 추가 복용 안내 때문에 일정이 사라지지 않는지 확인한다.
# 매개변수: frequency, dosage, slots: 처방 지시와 선택 시간대, expected: 기대 모드. 반환값: 없음.
@pytest.mark.parametrize(("frequency", "dosage", "slots", "expected"), [
    ("1일 3회", "1정 (통증 시 2정)", [], "scheduled"),
    ("1일 2회 아침 저녁", "1정, 필요시 1정 추가", [], "scheduled"),
    ("3 times daily", "1 tablet, may repeat if needed", [], "scheduled"),
    ("", "1정(필요시)", ["morning", "evening"], "scheduled"),
    ("", "1정(필요시)", [], "as_needed"),
    ("1일 3회 필요시", "1정", ["morning"], "as_needed"),
    ("통증 시", "1정", [], "as_needed"),
])
def test_scheduled_dose_with_extra_prn_dose_stays_scheduled(
    frequency: str, dosage: str, slots: list[str], expected: str,
) -> None:
    assert resolve_dosing_mode("scheduled", frequency, dosage, has_slots=bool(slots)) == expected
    row = SimpleNamespace(dosing_mode="scheduled", daily_frequency=frequency, dosage_per_time=dosage,
                          schedule_slot_keys=json.dumps(slots))
    assert medication_dosing_mode(row) == expected


# 함수이름: test_prn_save_and_legacy_never_schedule_or_missed
# 함수역할: 새 저장과 이전 앱의 필요시 지시가 모든 일정·미기록 알림에서 제외되는지 확인한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_prn_save_and_legacy_never_schedule_or_missed(fk_db: Session) -> None:
    seed_account(fk_db, "patient-a")
    saved = CheckSavedMedication(fk_db)
    dto = SavedMedicationCreate(patient_hash="patient-a", item_name="PRN tablet", efficacy="", use_method="", warning_message="", daily_frequency="필요시 1회", total_days="30")
    result = saved.saveMedicationDetail(dto)
    assert saved.saveMedicationDetail(dto)["duplicate"] is True
    assert fk_db.get(_SavedMedication, result["id"]).dosing_mode == "as_needed"
    legacy = medication(fk_db, daily_frequency="PRN", dosing_mode="scheduled")
    schedule = CheckSchedule(fk_db)
    assert schedule.requestTodayMedicationSchedule("patient-a")["data"] == []
    assert schedule.requestTodayMedicationSchedulesForPatients(["patient-a"])["patient-a"] == []
    assert schedule.requestMedicationScheduleWindow("patient-a")["data"] == []
    assert not schedule.isMedicationSlotIncomplete(patient_hash="patient-a", schedule_date=application_today(), slot_key="morning")
    with pytest.raises(HTTPException):
        schedule.updateMedicationStatus(legacy.id, True, "patient-a", "morning")


# 함수이름: test_history_prn_recording_eligibility_at_range_end
# 함수역할: 조회 종료일의 시작·만료·중단 경계를 적용하고 기록 불가 약도 조회 목록에 보존한다.
# 매개변수: fk_db: 격리 세션, end_offset: 오늘 기준 조회 종료일, 나머지 값: 종료일 기준 약 경계. 반환값: 없음.
@pytest.mark.parametrize("end_offset", [-7, 0], ids=["historical", "today"])
@pytest.mark.parametrize("start_offset,total_days,effective_offset,stop_offset,expected", [
    pytest.param(-10, "90", None, None, True, id="active"),
    pytest.param(1, "90", None, None, False, id="future-prescription"),
    pytest.param(-10, "90", 1, None, False, id="future-effective-date"),
    pytest.param(-10, "10", None, None, False, id="expired"),
    pytest.param(-10, "90", None, 0, False, id="stop-on-end"),
    pytest.param(-10, "90", None, -1, False, id="already-stopped"),
    pytest.param(0, "1", None, None, True, id="starts-on-end"),
    pytest.param(-10, "11", None, None, True, id="expires-on-end"),
    pytest.param(-10, "90", None, 1, True, id="stops-after-end"),
    pytest.param(-10, "", None, None, True, id="open-ended"),
])
def test_history_prn_recording_eligibility_at_range_end(
    fk_db: Session, end_offset: int, start_offset: int, total_days: str,
    effective_offset: int | None, stop_offset: int | None, expected: bool,
) -> None:
    end = application_today() + timedelta(days=end_offset)
    med = medication(
        fk_db, dosing_mode="as_needed", prescription_date=end + timedelta(days=start_offset),
        total_days=total_days,
        regimen_effective_from=end + timedelta(days=effective_offset) if effective_offset is not None else None,
        stopped_on=end + timedelta(days=stop_offset) if stop_offset is not None else None,
    )
    care = ManageMedicationCare(fk_db)
    result = care.history(principal(), end - timedelta(days=3), end)
    assert result["medications"] == [{
        **care.saved._to_response_dict(med), "can_record_as_needed": expected,
    }]
    assert result["medications"][0]["can_record_as_needed"] is expected
    assert result["items"] == []


# 함수이름: test_history_recording_eligibility_uses_normalized_dosing_mode
# 함수역할: 정기 약은 기록 불가이며 이전 형식의 필요시 지시도 서버의 정규화 모드로 판정한다.
# 매개변수: fk_db: 격리 세션, mode: 저장 모드, frequency: 지시, expected: 기록 가능 여부. 반환값: 없음.
@pytest.mark.parametrize("mode,frequency,expected", [
    ("scheduled", "1", False), ("scheduled", "PRN", True), ("as_needed", "1", True),
])
def test_history_recording_eligibility_uses_normalized_dosing_mode(
    fk_db: Session, mode: str, frequency: str, expected: bool,
) -> None:
    medication(fk_db, dosing_mode=mode, daily_frequency=frequency)
    today = application_today()
    result = ManageMedicationCare(fk_db).history(principal(), today, today)
    assert result["medications"][0]["can_record_as_needed"] is expected


# 함수이름: test_history_recording_flag_leaves_regular_schedule_responses_unchanged
# 함수역할: 이력 전용 필드가 일반 약 응답과 정기 일정·알림 조회에 섞이거나 내용을 바꾸지 않는다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_history_recording_flag_leaves_regular_schedule_responses_unchanged(fk_db: Session) -> None:
    regular = medication(fk_db)
    prn = medication(fk_db, dosing_mode="as_needed")
    schedule = CheckSchedule(fk_db)
    today_before = schedule.requestTodayMedicationSchedule("patient-a")
    window_before = schedule.requestMedicationScheduleWindow("patient-a")
    care = ManageMedicationCare(fk_db)
    today = application_today()
    result = care.history(principal(), today, today)
    assert {row["id"]: row["can_record_as_needed"] for row in result["medications"]} == {
        regular.id: False, prn.id: True,
    }
    assert schedule.requestTodayMedicationSchedule("patient-a") == today_before
    assert schedule.requestMedicationScheduleWindow("patient-a") == window_before
    for response in (today_before, window_before):
        assert {int(row["medication_id"]) for row in response["data"]} == {regular.id}
        assert all("can_record_as_needed" not in row for row in response["data"])
    for med in (regular, prn):
        assert "can_record_as_needed" not in care.saved._to_response_dict(med)


# 함수이름: test_prn_multiple_administrations_and_independent_correction
# 함수역할: 같은 날 두 번의 필요시 복용을 독립 기록하고 하나만 수정하는지 검증한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_prn_multiple_administrations_and_independent_correction(fk_db: Session) -> None:
    med = medication(fk_db, dosing_mode="as_needed")
    care = ManageMedicationCare(fk_db)
    today = application_today()
    keys = [f"as_needed:{uuid4()}" for _ in range(2)]
    request = report()
    first = care.update_history(principal(), med.id, today, keys[0], request)
    assert care.update_history(principal(), med.id, today, keys[0], request) == first
    care.update_history(principal(), med.id, today, keys[1], report())
    care.update_history(principal(), med.id, today, keys[0], report(status="unrecorded", expected_revision=1, reason="duplicate corrected"))
    rows = care.history(principal(), today, today)["items"]
    assert len(rows) == 2
    assert {row["status"] for row in rows} == {"taken", "unrecorded"}
    assert fk_db.query(_MedicationCareAudit).count() == 3
    assert fk_db.query(_CaregiverAlertOutbox).count() == 2


# 함수이름: test_prn_slots_validated
# 함수역할: 필요시 UUID와 정기 시간대를 서로 바꾸어 쓰지 못하는지 확인한다.
# 매개변수: fk_db: 격리 세션, mode: 모드, slot: 잘못된 키. 반환값: 없음.
@pytest.mark.parametrize("mode,slot", [("as_needed", "as_needed"), ("as_needed", "as_needed:bad"), ("as_needed", "morning"), ("scheduled", f"as_needed:{uuid4()}")])
def test_prn_slots_validated(fk_db: Session, mode: str, slot: str) -> None:
    med = medication(fk_db, dosing_mode=mode)
    with pytest.raises(HTTPException) as error:
        ManageMedicationCare(fk_db).update_history(principal(), med.id, application_today(), slot, report())
    assert error.value.status_code == 422


# 함수이름: test_history_skipped_not_taken_and_legacy_completion_undo_coherent
# 함수역할: 미복용은 완료가 아니며 기존 완료·취소 API도 기록 상태와 감사 버전을 갱신한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_history_skipped_not_taken_and_legacy_completion_undo_coherent(fk_db: Session) -> None:
    med = medication(fk_db)
    care = ManageMedicationCare(fk_db)
    today = application_today()
    care.update_history(principal(), med.id, today, "morning", report(status="skipped", reason="doctor asked to hold"))
    schedule = CheckSchedule(fk_db)
    item = schedule.requestTodayMedicationSchedule("patient-a")["data"][0]
    assert item["medication_status"] is False and item["skipped_slot_keys"] == ["morning"]
    assert schedule.isMedicationSlotIncomplete(patient_hash="patient-a", schedule_date=today, slot_key="morning")
    assert not schedule.is_medication_slot_complete(patient_hash="patient-a", schedule_date=today, slot_key="morning")
    schedule.updateMedicationStatus(med.id, True, "patient-a", "morning")
    taken = care.history(principal(), today, today)["items"][0]
    assert taken["status"] == "taken" and taken["reason"] == ""
    assert taken["revision"] == 2 and taken["actual_taken_at"] is None
    schedule.updateMedicationStatus(med.id, False, "patient-a", "morning")
    undone = care.history(principal(), today, today)["items"][0]
    assert undone["status"] == "unrecorded" and undone["revision"] == 3
    assert undone["actual_taken_at"] is None and undone["recorded_at"] is not None
    assert fk_db.query(_MedicationCareAudit).count() == 3
    with pytest.raises(HTTPException) as error:
        care.update_history(principal(), med.id, today, "morning", report(expected_revision=1))
    assert error.value.status_code == 409


# 함수이름: test_actual_time_late_weekly_dose_and_past_no_alert
# 함수역할: 주 1회 약을 다음 날 먹은 보고는 원래 예정일에 저장하며 새 완료 알림을 만들지 않는다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_actual_time_late_weekly_dose_and_past_no_alert(fk_db: Session) -> None:
    yesterday = application_today() - timedelta(days=1)
    med = medication(fk_db, daily_frequency="주 1회", prescription_date=yesterday)
    care = ManageMedicationCare(fk_db)
    result = care.update_history(principal(), med.id, yesterday, "morning", report())
    assert result["schedule_date"] == yesterday.isoformat()
    assert result["actual_taken_at"] is not None and result["recorded_at"] is not None
    assert not MedicationCoursePolicy().is_due_on(med, application_today())
    assert fk_db.query(_CaregiverAlertOutbox).count() == 0
    row = fk_db.query(_MedicationCompletion).one()
    assert row.actual_taken_at != row.recorded_at


# 함수이름: test_history_taken_queues_completion_event_only_for_today
# 함수역할: 오늘 전체 완료는 기존 아웃박스를 사용하고 정정 재전송은 중복하지 않는다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_history_taken_queues_completion_event_only_for_today(fk_db: Session) -> None:
    med = medication(fk_db)
    care = ManageMedicationCare(fk_db)
    request = report()
    care.update_history(principal(), med.id, application_today(), "morning", request)
    care.update_history(principal(), med.id, application_today(), "morning", request)
    assert fk_db.query(_CaregiverAlertOutbox).count() == 1


# 함수이름: test_history_bounds_and_future_actual_time
# 함수역할: 오래된 날짜, 미래 범위, 과도한 조회 길이와 미래 시각을 거부한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_history_bounds_and_future_actual_time(fk_db: Session) -> None:
    med = medication(fk_db)
    care = ManageMedicationCare(fk_db)
    today = application_today()
    for start, end in [(today - timedelta(days=90), today - timedelta(days=90)), (today, today + timedelta(days=1)), (today - timedelta(days=31), today), (today, today - timedelta(days=1))]:
        with pytest.raises(HTTPException) as error:
            care.history(principal(), start, end)
        assert error.value.status_code == 422
    with pytest.raises(HTTPException) as error:
        care.update_history(principal(), med.id, today, "morning", report(actual_taken_at=application_now() + timedelta(minutes=2)))
    assert error.value.status_code == 422


# 함수이름: test_scope_and_revoked_caregiver
# 함수역할: 환자 격리, 보호자 읽기 전용, 연동 해제와 삭제 표식을 검증한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_scope_and_revoked_caregiver(fk_db: Session) -> None:
    med = medication(fk_db)
    seed_account(fk_db, "patient-b", "caregiver")
    link = _PatientCaregiverLink(patient_hash="patient-a", caregiver_hash="caregiver", linked=True)
    fk_db.add(link)
    fk_db.commit()
    care = ManageMedicationCare(fk_db)
    today = application_today()
    assert care.history(principal("caregiver"), today, today, "patient-a")["items"]
    for actor, requested in [("caregiver", "patient-a"), ("patient-b", "patient-a")]:
        with pytest.raises(HTTPException) as error:
            care.update_history(principal(actor), med.id, today, "morning", report(patient_hash=requested))
        assert error.value.status_code == 403
    with pytest.raises(HTTPException) as error:
        care.change_medication(principal("patient-b"), med.id, change())
    assert error.value.status_code == 404
    link.linked = False
    fk_db.commit()
    with pytest.raises(HTTPException) as error:
        care.history(principal("caregiver"), today, today, "patient-a")
    assert error.value.status_code == 403
    fk_db.get(_UserAccount, "patient-a").deletion_requested_at = utc_now()
    fk_db.commit()
    with pytest.raises(HTTPException) as error:
        care.change_medication(principal(), med.id, change())
    assert error.value.status_code == 410


# 함수이름: test_offline_completion_integrates_history_and_audit
# 함수역할: 기존 오프라인 요청이 날짜별 이력에 나타나고 재전송은 감사 기록을 늘리지 않는다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_offline_completion_integrates_history_and_audit(fk_db: Session) -> None:
    med = medication(fk_db)
    request = DoseSyncRequest(operation_id=str(uuid4()), schedule_date=application_today() - timedelta(days=1), slot_key="morning", medication_ids=[med.id], completed=True)
    SyncDose(fk_db).apply("patient-a", request)
    SyncDose(fk_db).apply("patient-a", request)
    result = ManageMedicationCare(fk_db).history(principal(), request.schedule_date, request.schedule_date)
    assert result["items"][0]["status"] == "taken"
    assert result["items"][0]["actual_taken_at"] is None
    assert fk_db.query(_MedicationCareAudit).count() == 1


# 함수이름: test_operation_reuse_and_account_cleanup
# 함수역할: 다른 내용의 작업 ID 재사용을 막고 삭제 시 영수증·감사 개인정보도 제거한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_operation_reuse_and_account_cleanup(fk_db: Session) -> None:
    med = medication(fk_db)
    care = ManageMedicationCare(fk_db)
    request = report()
    care.update_history(principal(), med.id, application_today(), "morning", request)
    with pytest.raises(HTTPException) as error:
        care.update_history(principal(), med.id, application_today(), "morning", report(status="skipped", operation_id=request.operation_id))
    assert error.value.status_code == 409
    export = ManageAccount(fk_db).exportAccountData("patient-a")["data"]
    assert len(export["medication_care_audits"]) == 1
    audit = fk_db.query(_MedicationCareAudit).one()
    assert json.loads(audit.after_json)["status"] == "taken"
    ManageAccount(fk_db)._purge_user_data("patient-a", delete_account=False)
    fk_db.commit()
    assert fk_db.query(_MedicationCareOperation).count() == 0
    assert fk_db.query(_MedicationCareAudit).count() == 0


# 함수이름: test_repeated_completion_keeps_reported_actual_time_until_undo
# 함수역할: 위젯·통합 완료의 중복 체크가 사용자가 정정한 실제 시각을 지우지 않는지 확인한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_repeated_completion_keeps_reported_actual_time_until_undo(fk_db: Session) -> None:
    med = medication(fk_db)
    care = ManageMedicationCare(fk_db)
    today = application_today()
    recorded = care.update_history(principal(), med.id, today, "morning", report(reason="late dose"))
    CheckSchedule(fk_db).updateMedicationStatus(med.id, True, "patient-a", "morning")
    current = care.history(principal(), today, today)["items"][0]
    assert current["actual_taken_at"] == recorded["actual_taken_at"]
    assert current["reason"] == "late dose"
    CheckSchedule(fk_db).updateMedicationStatus(med.id, False, "patient-a", "morning")
    assert care.history(principal(), today, today)["items"][0]["actual_taken_at"] is None


# 함수이름: test_repeated_legacy_completion_keeps_revision_and_audit
# 함수역할: 이전 앱의 같은 완료 재전송이 버전과 감사 이력을 늘려 이력 정정을 거짓 충돌시키지 않는지 확인한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_repeated_legacy_completion_keeps_revision_and_audit(fk_db: Session) -> None:
    med = medication(fk_db)
    care = ManageMedicationCare(fk_db)
    today = application_today()
    schedule = CheckSchedule(fk_db)
    schedule.updateMedicationStatus(med.id, True, "patient-a", "morning")
    first = care.history(principal(), today, today)["items"][0]
    audits = fk_db.query(_MedicationCareAudit).count()
    schedule.updateMedicationStatus(med.id, True, "patient-a", "morning")
    again = care.history(principal(), today, today)["items"][0]
    assert again["revision"] == first["revision"]
    assert fk_db.query(_MedicationCareAudit).count() == audits
    schedule.updateMedicationStatus(med.id, False, "patient-a", "morning")
    assert care.history(principal(), today, today)["items"][0]["revision"] == first["revision"] + 1


# 함수이름: test_version_copy_does_not_duplicate_prescription_comparison
# 함수역할: 약 변경 복사본이 기존 처방의 약 개수를 늘리는 비교 오류를 방지한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_version_copy_does_not_duplicate_prescription_comparison(fk_db: Session) -> None:
    med = medication(fk_db)
    ManageMedicationCare(fk_db).change_medication(principal(), med.id, change())
    _, candidates = CheckPrescriptionChange(fk_db)._load_candidate_prescriptions("patient-a", application_today())
    assert len(candidates) == 1 and len(candidates[0][1]) == 1
    assert candidates[0][1][0].id == med.id


# 함수이름: test_legacy_prn_deduplication_still_matches
# 함수역할: 이전 버전의 중복 키를 가진 필요시 약이 다시 등록되지 않는지 확인한다.
# 매개변수: fk_db: 격리 세션. 반환값: 없음.
def test_legacy_prn_deduplication_still_matches(fk_db: Session) -> None:
    seed_account(fk_db, "patient-a")
    control = CheckSavedMedication(fk_db)
    dto = SavedMedicationCreate(patient_hash="patient-a", item_name="legacy PRN", efficacy="", use_method="", warning_message="", daily_frequency="필요시", total_days="30")
    original = seed_medication(fk_db, item_name=dto.item_name, daily_frequency=dto.daily_frequency, total_days=dto.total_days, deduplication_key=control._build_deduplication_key(dto, include_dosing_mode=False))
    result = control.saveMedicationDetail(dto)
    assert result["duplicate"] is True and result["id"] == original.id
