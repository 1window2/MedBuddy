# 파일명: test_link_registration_deletion_race.py
# 역할: 연동 등록의 잠금 전환 중 계정 삭제가 완료되는 경합을 재현한다.

import pytest
from fastapi import HTTPException

import controls.link_patient_caregiver_control as link_module
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.manage_account_control import ManageAccount
from entities.patient_caregiver_link_entity import _PatientCaregiverLink, _PatientLinkCode
from entities.user_account_entity import _UserAccount
from support.db import make_engine, make_session_factory, seed_account


@pytest.mark.parametrize("identity_deleted", [False, True])
def test_registration_rechecks_deleted_caregiver_after_lock_handoff(
    tmp_path, monkeypatch, identity_deleted,
):
    engine = make_engine(tmp_path)
    sessions = make_session_factory(engine)
    real_lock = link_module.lock_account_operations
    deleted_subjects = []

    class IdentityBoundary:
        def deleteIdentity(self, subject):
            deleted_subjects.append(subject)

    try:
        with sessions() as db:
            seed_account(db, "patient-a", "caregiver-a")
            code = LinkPatientCaregiver(db).generatePatientHash("patient-a")["data"]["patient_code"]
            db.rollback()
            # 요청 시작 때의 정상 계정을 읽은 뒤, 두 계정 잠금 직전에 별도 세션으로 삭제한다.
            assert ManageAccount(db).ensureAccount("caregiver-a") == "caregiver-a"

            def delete_before_lock(session, participants):
                assert not session.in_transaction()
                with sessions() as deleting:
                    real_lock(deleting, ["caregiver-a"])
                    control = ManageAccount(deleting, identity_deletion_boundary=IdentityBoundary())
                    if identity_deleted:
                        control.deleteAccountData("caregiver-a", external_subject="caregiver-subject")
                    else:
                        control._prepare_firebase_account_deletion("caregiver-a")
                real_lock(session, participants)

            monkeypatch.setattr(link_module, "lock_account_operations", delete_before_lock)
            with pytest.raises(HTTPException) as error:
                LinkPatientCaregiver(db).requestPatientCaregiverLink("caregiver-a", code)

            assert error.value.status_code == 410
            assert not db.in_transaction()

        with sessions() as verify:
            assert verify.query(_PatientCaregiverLink).count() == 0
            link_code = verify.query(_PatientLinkCode).filter_by(patient_code=code).one()
            assert not link_code.used
            assert link_code.caregiver_hash is None
            account = verify.get(_UserAccount, "caregiver-a")
            assert account.deletion_requested_at is not None
            assert (account.identity_deleted_at is not None) == identity_deleted
            assert deleted_subjects == (["caregiver-subject"] if identity_deleted else [])
    finally:
        engine.dispose()
