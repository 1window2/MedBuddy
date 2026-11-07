# 파일명: test_medication_care_receipt_deletion.py
# 역할: 약품 삭제·보존 기간 정리 시 영수증 건강정보 제거와 멱등 재시도 차단을 검증한다.

"""개별 약 삭제와 자동 정리에서 건강정보 제거 및 재전송 차단을 검증한다."""

from collections.abc import Callable
from datetime import timedelta
from typing import Any, NoReturn
from uuid import uuid4

from fastapi import HTTPException
import pytest
from sqlalchemy.orm import Session

from controls.check_saved_medication_control import CheckSavedMedication
from controls.manage_account_control import ManageAccount
from controls.manage_medication_care_control import ManageMedicationCare
from core.application_clock import application_today
from entities.medication_care_entity import _MedicationCareAudit, _MedicationCareOperation
from entities.medication_completion_entity import _MedicationCompletion
from entities.saved_medication_entity import _SavedMedication
from services.saved_medication_retention import SavedMedicationRetentionPolicy
from test_medication_care import change, medication, principal, report


# 함수이름: assert_status
# 함수역할:
# - 작업이 HTTPException으로 실패하며 지정 상태 코드를 갖는지 확인한다.
# 매개변수:
# - code: int; 예상 HTTP 오류 상태.
# - operation: Callable; 실패해야 할 재시도·삭제 작업.
# 반환값:
# - None.
def assert_status(code: int, operation: Callable[[], Any]) -> None:
    with pytest.raises(HTTPException) as error:
        operation()
    assert error.value.status_code == code


# 함수이름: test_deleted_dose_receipt_has_no_health_payload_and_never_recreates_record
# 함수역할:
# - 약품 삭제 시 영수증의 건강정보를 지우되 멱등 키는 보존하여 과거 요청이 복용을 재생성하거나 새 약품을 변경하지 못하는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# - as_needed: bool; 필요시 복용 또는 정기 복용 선택.
# 반환값:
# - None.
@pytest.mark.parametrize("as_needed", [False, True])
def test_deleted_dose_receipt_has_no_health_payload_and_never_recreates_record(fk_db: Session, as_needed: bool) -> None:
    med = medication(fk_db, dosing_mode="as_needed" if as_needed else "scheduled", item_name="private-test-name")
    med_id = med.id
    slot = f"as_needed:{uuid4()}" if as_needed else "morning"
    request = report(reason="private-test-reason")
    care = ManageMedicationCare(fk_db)
    response = care.update_history(principal(), med_id, application_today(), slot, request)
    receipt = fk_db.query(_MedicationCareOperation).one()
    original_hash = receipt.request_hash
    assert receipt.medication_id == med_id
    assert "private-test-name" in receipt.response_json
    assert "private-test-reason" in receipt.response_json
    assert care.update_history(principal(), med_id, application_today(), slot, request) == response

    CheckSavedMedication(fk_db).requestDelete(med_id, "patient-a")
    fk_db.refresh(receipt)
    assert receipt.response_json == "{}" and receipt.response_redacted
    assert receipt.medication_id is None and receipt.replacement_medication_id is None
    assert receipt.request_hash == original_hash and receipt.operation_id == str(request.operation_id)
    assert fk_db.query(_MedicationCompletion).count() == 0
    assert fk_db.query(_MedicationCareAudit).count() == 0
    assert_status(410, lambda: care.update_history(principal(), med_id, application_today(), slot, request))
    assert_status(409, lambda: care.update_history(principal(), med_id, application_today(), slot,
        report(operation_id=request.operation_id, reason="different")))
    assert_status(404, lambda: care.update_history(principal(), med_id, application_today(), slot, report()))
    new_id = medication(fk_db, item_name="new-test-medication").id
    assert new_id != med_id
    assert_status(409, lambda: care.update_history(principal(), new_id, application_today(), "morning", request))
    assert care.update_history(principal(), new_id, application_today(), "morning", report())["success"]
    assert fk_db.query(_MedicationCompletion).count() == 1


# 함수이름: test_replacement_receipt_is_invalidated_by_deleting_either_medication
# 함수역할:
# - 기존·대체 약품 중 어느 쪽을 삭제해도 이전 형식 포함 변경 영수증이 비식별화되고 재시도는 410으로 거부되는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# - delete_original: bool; 변경 전 약품을 삭제할지 대체 약품을 삭제할지 선택.
# - legacy: bool; 약품 연결 필드가 없는 이전 영수증 형식 사용 여부.
# 반환값:
# - None.
@pytest.mark.parametrize("delete_original", [False, True])
@pytest.mark.parametrize("legacy", [False, True])
def test_replacement_receipt_is_invalidated_by_deleting_either_medication(fk_db: Session, delete_original: bool, legacy: bool) -> None:
    old_id = medication(fk_db).id
    request = change()
    care = ManageMedicationCare(fk_db)
    response = care.change_medication(principal(), old_id, request)
    receipt = fk_db.query(_MedicationCareOperation).one()
    assert receipt.medication_id == old_id and receipt.replacement_medication_id == response["id"]
    if legacy:
        receipt.medication_id = receipt.replacement_medication_id = None
        fk_db.commit()
    CheckSavedMedication(fk_db).requestDelete(old_id if delete_original else response["id"], "patient-a")
    assert_status(410, lambda: care.change_medication(principal(), old_id, request))
    assert fk_db.query(_MedicationCareOperation).one().response_json == "{}"
    assert fk_db.query(_SavedMedication).count() == 1


# 함수이름: test_stop_receipt_is_invalidated
# 함수역할:
# - 중단한 약품을 삭제한 뒤 중단 요청을 재시도하면 410으로 거부되는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# 반환값:
# - None.
def test_stop_receipt_is_invalidated(fk_db: Session) -> None:
    med_id = medication(fk_db).id
    request = change(action="stop", changes={})
    care = ManageMedicationCare(fk_db)
    care.change_medication(principal(), med_id, request)
    CheckSavedMedication(fk_db).requestDelete(med_id, "patient-a")
    assert_status(410, lambda: care.change_medication(principal(), med_id, request))


# 함수이름: test_delete_keeps_unrelated_medication_and_other_account_receipts
# 함수역할:
# - 권한 없는 삭제는 영수증을 바꾸지 않고 정상 삭제도 다른 약품·계정의 재시도 결과는 보존하는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# - legacy: bool; 약품 연결 필드가 없는 이전 영수증 형식 사용 여부.
# 반환값:
# - None.
@pytest.mark.parametrize("legacy", [False, True])
def test_delete_keeps_unrelated_medication_and_other_account_receipts(fk_db: Session, legacy: bool) -> None:
    ids = [medication(fk_db, item_name=f"test-{index}", patient_hash=owner).id
           for index, owner in enumerate(["patient-a", "patient-a", "patient-b"])]
    care = ManageMedicationCare(fk_db)
    requests = [report() for _ in ids]
    responses = [care.update_history(principal(owner), identifier, application_today(), "morning", request)
                 for identifier, owner, request in zip(ids, ["patient-a", "patient-a", "patient-b"], requests)]
    if legacy:
        for receipt in fk_db.query(_MedicationCareOperation).all():
            receipt.medication_id = None
        fk_db.commit()
    assert_status(404, lambda: CheckSavedMedication(fk_db).requestDelete(ids[0], "patient-b"))
    assert not any(receipt.response_redacted for receipt in fk_db.query(_MedicationCareOperation).all())
    CheckSavedMedication(fk_db).requestDelete(ids[0], "patient-a")
    assert care.update_history(principal(), ids[1], application_today(), "morning", requests[1]) == responses[1]
    assert care.update_history(principal("patient-b"), ids[2], application_today(), "morning", requests[2]) == responses[2]


# 함수이름: test_unattributable_legacy_receipts_are_redacted_not_deleted
# 함수역할:
# - 소유 약품을 복구할 수 없는 이전 영수증은 행을 삭제하지 않고 응답만 비식별화하는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# - payload: str; 약품 소유권을 복구할 수 없는 이전 응답 JSON.
# 반환값:
# - None.
@pytest.mark.parametrize("payload", ["invalid-json", "[]", '{"unknown":"health-data"}'])
def test_unattributable_legacy_receipts_are_redacted_not_deleted(fk_db: Session, payload: str) -> None:
    med_id = medication(fk_db).id
    fk_db.add(_MedicationCareOperation(patient_hash="patient-a", operation_id=str(uuid4()),
        request_hash="a" * 64, response_json=payload))
    fk_db.commit()
    CheckSavedMedication(fk_db).requestDelete(med_id, "patient-a")
    receipt = fk_db.query(_MedicationCareOperation).one()
    assert receipt.response_redacted and receipt.response_json == "{}"


# 함수이름: test_retention_redacts_receipts_in_the_same_transaction_and_rollback_restores_them
# 함수역할:
# - 보존 기간 정리의 약품 삭제와 영수증 비식별화가 같은 트랜잭션으로 롤백·커밋되는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# - scoped: bool; 특정 환자만 보존 기간 정리를 할지 지정한다.
# 반환값:
# - None.
@pytest.mark.parametrize("scoped", [False, True])
def test_retention_redacts_receipts_in_the_same_transaction_and_rollback_restores_them(fk_db: Session, scoped: bool) -> None:
    day = application_today() - timedelta(days=10)
    med_id = medication(fk_db, prescription_date=day, total_days="1").id
    care = ManageMedicationCare(fk_db)
    request = report(reason="retention-test-reason")
    response = care.update_history(principal(), med_id, day, "morning", request)
    policy = SavedMedicationRetentionPolicy(retention_days_after_end=1)
    assert policy.cleanup_expired_medications(fk_db, "patient-a" if scoped else None, commit=False) == 1
    fk_db.flush()
    assert fk_db.query(_MedicationCareOperation).one().response_redacted
    assert fk_db.query(_SavedMedication).count() == 0
    fk_db.rollback()
    assert care.update_history(principal(), med_id, day, "morning", request) == response
    assert policy.cleanup_expired_medications(fk_db, "patient-a" if scoped else None) == 1
    assert_status(410, lambda: care.update_history(principal(), med_id, day, "morning", request))


# 함수이름: test_account_purge_removes_redacted_tombstones_as_well
# 함수역할:
# - 계정 데이터 삭제는 비식별화된 멱등 영수증까지 제거하는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# - delete_account: bool; 사용자 행까지 삭제할지 지정한다.
# 반환값:
# - None.
@pytest.mark.parametrize("delete_account", [False, True])
def test_account_purge_removes_redacted_tombstones_as_well(fk_db: Session, delete_account: bool) -> None:
    med_id = medication(fk_db).id
    care = ManageMedicationCare(fk_db)
    care.update_history(principal(), med_id, application_today(), "morning", report())
    CheckSavedMedication(fk_db).requestDelete(med_id, "patient-a")
    assert fk_db.query(_MedicationCareOperation).count() == 1
    ManageAccount(fk_db)._purge_user_data("patient-a", delete_account=delete_account)
    fk_db.commit()
    assert fk_db.query(_MedicationCareOperation).count() == 0


# 함수이름: test_failed_medication_delete_rolls_back_receipt_redaction
# 함수역할:
# - 약품 삭제 중 실패하면 영수증 비식별화도 롤백되어 기존 재시도 응답이 유지되는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
def test_failed_medication_delete_rolls_back_receipt_redaction(fk_db: Session, monkeypatch: pytest.MonkeyPatch) -> None:
    med_id = medication(fk_db).id
    care = ManageMedicationCare(fk_db)
    request = report()
    response = care.update_history(principal(), med_id, application_today(), "morning", request)
    control = CheckSavedMedication(fk_db)

    # 함수이름: fail
    # 함수역할:
    # - 복용 기록 삭제 단계에 실패를 주입하여 전체 삭제 롤백을 재현한다.
    # 매개변수:
    # - _medication: _SavedMedication; 삭제 대상(오류 주입에 사용하지 않음).
    # 반환값:
    # - 반환하지 않음; RuntimeError 발생.
    def fail(_medication: _SavedMedication) -> NoReturn:
        raise RuntimeError("synthetic-delete-failure")

    monkeypatch.setattr(control, "_delete_medication_completions", fail)
    assert_status(500, lambda: control.requestDelete(med_id, "patient-a"))
    assert care.update_history(principal(), med_id, application_today(), "morning", request) == response
    assert not fk_db.query(_MedicationCareOperation).one().response_redacted


# 함수이름: test_retention_redacts_multiple_legacy_receipts_without_reloading_old_payloads
# 함수역할:
# - 여러 이전 영수증을 정리해도 비식별화된 응답을 오래된 세션 값으로 되살리지 않는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# 반환값:
# - None.
def test_retention_redacts_multiple_legacy_receipts_without_reloading_old_payloads(fk_db: Session) -> None:
    day = application_today() - timedelta(days=10)
    identifiers = [medication(fk_db, prescription_date=day, total_days="1", item_name=f"legacy-{i}").id
                   for i in range(2)]
    for identifier in identifiers:
        ManageMedicationCare(fk_db).update_history(principal(), identifier, day, "morning", report())
    for receipt in fk_db.query(_MedicationCareOperation):
        receipt.medication_id = None
    fk_db.commit()
    assert SavedMedicationRetentionPolicy(retention_days_after_end=1).cleanup_expired_medications(fk_db) == 2
    assert fk_db.query(_MedicationCareOperation).count() == 2
    assert all(receipt.response_redacted and receipt.response_json == "{}"
               for receipt in fk_db.query(_MedicationCareOperation))
