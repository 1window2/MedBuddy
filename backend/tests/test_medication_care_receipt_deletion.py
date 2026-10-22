"""개별 약 삭제와 자동 정리에서 건강정보 제거 및 재전송 차단을 검증한다."""

from datetime import timedelta
from uuid import uuid4

from fastapi import HTTPException
import pytest

from controls.check_saved_medication_control import CheckSavedMedication
from controls.manage_account_control import ManageAccount
from controls.manage_medication_care_control import ManageMedicationCare
from core.application_clock import application_today
from entities.medication_care_entity import _MedicationCareAudit, _MedicationCareOperation
from entities.medication_completion_entity import _MedicationCompletion
from entities.saved_medication_entity import _SavedMedication
from services.saved_medication_retention import SavedMedicationRetentionPolicy
from test_medication_care import change, medication, principal, report


def assert_status(code, operation):
    with pytest.raises(HTTPException) as error:
        operation()
    assert error.value.status_code == code


@pytest.mark.parametrize("as_needed", [False, True])
def test_deleted_dose_receipt_has_no_health_payload_and_never_recreates_record(fk_db, as_needed):
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


@pytest.mark.parametrize("delete_original", [False, True])
@pytest.mark.parametrize("legacy", [False, True])
def test_replacement_receipt_is_invalidated_by_deleting_either_medication(fk_db, delete_original, legacy):
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


def test_stop_receipt_is_invalidated(fk_db):
    med_id = medication(fk_db).id
    request = change(action="stop", changes={})
    care = ManageMedicationCare(fk_db)
    care.change_medication(principal(), med_id, request)
    CheckSavedMedication(fk_db).requestDelete(med_id, "patient-a")
    assert_status(410, lambda: care.change_medication(principal(), med_id, request))


@pytest.mark.parametrize("legacy", [False, True])
def test_delete_keeps_unrelated_medication_and_other_account_receipts(fk_db, legacy):
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


@pytest.mark.parametrize("payload", ["invalid-json", "[]", '{"unknown":"health-data"}'])
def test_unattributable_legacy_receipts_are_redacted_not_deleted(fk_db, payload):
    med_id = medication(fk_db).id
    fk_db.add(_MedicationCareOperation(patient_hash="patient-a", operation_id=str(uuid4()),
        request_hash="a" * 64, response_json=payload))
    fk_db.commit()
    CheckSavedMedication(fk_db).requestDelete(med_id, "patient-a")
    receipt = fk_db.query(_MedicationCareOperation).one()
    assert receipt.response_redacted and receipt.response_json == "{}"


@pytest.mark.parametrize("scoped", [False, True])
def test_retention_redacts_receipts_in_the_same_transaction_and_rollback_restores_them(fk_db, scoped):
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


@pytest.mark.parametrize("delete_account", [False, True])
def test_account_purge_removes_redacted_tombstones_as_well(fk_db, delete_account):
    med_id = medication(fk_db).id
    care = ManageMedicationCare(fk_db)
    care.update_history(principal(), med_id, application_today(), "morning", report())
    CheckSavedMedication(fk_db).requestDelete(med_id, "patient-a")
    assert fk_db.query(_MedicationCareOperation).count() == 1
    ManageAccount(fk_db)._purge_user_data("patient-a", delete_account=delete_account)
    fk_db.commit()
    assert fk_db.query(_MedicationCareOperation).count() == 0


def test_failed_medication_delete_rolls_back_receipt_redaction(fk_db, monkeypatch):
    med_id = medication(fk_db).id
    care = ManageMedicationCare(fk_db)
    request = report()
    response = care.update_history(principal(), med_id, application_today(), "morning", request)
    control = CheckSavedMedication(fk_db)

    def fail(_medication):
        raise RuntimeError("synthetic-delete-failure")

    monkeypatch.setattr(control, "_delete_medication_completions", fail)
    assert_status(500, lambda: control.requestDelete(med_id, "patient-a"))
    assert care.update_history(principal(), med_id, application_today(), "morning", request) == response
    assert not fk_db.query(_MedicationCareOperation).one().response_redacted


def test_retention_redacts_multiple_legacy_receipts_without_reloading_old_payloads(fk_db):
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
