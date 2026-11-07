# 파일명: test_link_registration_deletion_race.py
# 역할: 연동 등록의 잠금 전환 중 계정 삭제가 완료되는 경합을 재현한다.

from collections.abc import Iterable
from pathlib import Path

import pytest
from fastapi import HTTPException
from sqlalchemy.orm import Session

import controls.link_patient_caregiver_control as link_module
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.manage_account_control import ManageAccount
from entities.patient_caregiver_link_entity import _PatientCaregiverLink, _PatientLinkCode
from entities.user_account_entity import _UserAccount
from support.db import make_engine, make_session_factory, seed_account


# 함수이름: test_registration_rechecks_deleted_caregiver_after_lock_handoff
# 함수역할:
# - 연동 잠금 획득 전에 보호자 삭제가 완료되면 410으로 거부하고 연동 코드와 외부 신원 삭제 상태를 보존하는지 확인한다.
# 매개변수:
# - tmp_path: Path; 테스트 전용 임시 디렉터리.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# - identity_deleted: bool; 외부 신원까지 삭제할지, 삭제 요청 상태만 남길지 지정한다.
# 반환값:
# - None.
@pytest.mark.parametrize("identity_deleted", [False, True])
def test_registration_rechecks_deleted_caregiver_after_lock_handoff(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, identity_deleted: bool,
) -> None:
    engine = make_engine(tmp_path)
    sessions = make_session_factory(engine)
    real_lock = link_module.lock_account_operations
    deleted_subjects = []

    # 클래스명: IdentityBoundary
    # 역할: 외부 신원 삭제 요청을 메모리에 기록하는 대체 경계.
    # 주요 책임:
    # - 실제 신원 서비스 호출 없이 삭제 대상 subject를 수집한다.
    # 속성:
    # - 인스턴스 속성 없음; 바깥 deleted_subjects 목록을 사용한다.
    class IdentityBoundary:
        # 함수이름: deleteIdentity
        # 함수역할:
        # - 요청된 외부 신원 식별자를 공유 목록에 추가한다.
        # 매개변수:
        # - subject: str; 삭제 대상으로 전달된 외부 신원.
        # 반환값:
        # - None.
        def deleteIdentity(self, subject: str) -> None:
            deleted_subjects.append(subject)

    try:
        with sessions() as db:
            seed_account(db, "patient-a", "caregiver-a")
            code = LinkPatientCaregiver(db).generatePatientHash("patient-a")["data"]["patient_code"]
            db.rollback()
            # 요청 시작 때의 정상 계정을 읽은 뒤, 두 계정 잠금 직전에 별도 세션으로 삭제한다.
            assert ManageAccount(db).ensureAccount("caregiver-a") == "caregiver-a"

            # 함수이름: delete_before_lock
            # 함수역할:
            # - 별도 세션에서 보호자 삭제를 완료한 뒤 원래 연동 요청의 계정 잠금을 획득한다.
            # 매개변수:
            # - session: Session; 연동 등록 요청 세션.
            # - participants: Iterable[str]; 잠금 대상 계정 식별자.
            # 반환값:
            # - None.
            def delete_before_lock(session: Session, participants: Iterable[str]) -> None:
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
