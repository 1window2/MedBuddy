# 파일명: test_caregiver_setting_lifecycle_race.py
# 역할: 보호자 설정 저장과 환자의 삭제·연동 해제가 겹쳐도 설정이 다시 남지 않는지 검증한다.

from concurrent.futures import ThreadPoolExecutor
from threading import Event

import pytest
from fastapi import HTTPException

import controls.set_caregiver_notification_control as notification_module
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.manage_account_control import ManageAccount
from controls.set_caregiver_notification_control import SetCaregiverNotification
from core.account_database_lock import lock_account_operations
from entities.caregiver_notification_entity import _CaregiverNotification
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from support.db import make_engine, make_session_factory, seed_account


# 함수이름: test_patient_cleanup_does_not_leave_a_late_caregiver_setting
# 함수역할:
# - 설정 저장 중 시작한 환자 삭제·연동 해제가 저장을 기다린 뒤 설정과 활성 연동을 모두 제거하는지 확인한다.
# 매개변수:
# - tmp_path: Path; 테스트 전용 임시 디렉터리.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# - action: str; 환자 삭제(delete) 또는 연동 해제(unlink).
# 반환값:
# - None.
@pytest.mark.parametrize("action", ["delete", "unlink"])
def test_patient_cleanup_does_not_leave_a_late_caregiver_setting(tmp_path, monkeypatch, action):
    engine = make_engine(tmp_path)
    sessions = make_session_factory(engine)
    cleanup_started = Event()
    cleanup_finished = Event()
    cleanup = None
    try:
        with ThreadPoolExecutor(max_workers=1) as workers:
            with sessions() as db:
                seed_account(db, "patient-a", "caregiver-a")
                links = LinkPatientCaregiver(db)
                code = links.generatePatientHash("patient-a")["data"]["patient_code"]
                link_id = links.requestPatientCaregiverLink("caregiver-a", code)["data"]["id"]
                db.rollback()
                control = SetCaregiverNotification(db)
                find_setting = control._find_setting

                # 함수이름: cleanup_patient
                # 함수역할:
                # - 별도 세션에서 환자 삭제 또는 연동 해제를 실행하고 경합 시작·완료 신호를 보낸다.
                # 매개변수:
                # - 없음.
                # 반환값:
                # - None.
                def cleanup_patient():
                    with sessions() as deleting:
                        cleanup_started.set()
                        if action == "delete":
                            lock_account_operations(deleting, ["patient-a"])
                            ManageAccount(deleting)._prepare_firebase_account_deletion("patient-a")
                        else:
                            LinkPatientCaregiver(deleting).requestUnlink(link_id, "patient-a")
                    cleanup_finished.set()

                # 함수이름: find_after_cleanup_starts
                # 함수역할:
                # - 정리 작업을 시작해 잠금 경합을 만든 뒤 원래 보호자 설정 조회를 실행한다.
                # 매개변수:
                # - caregiver_hash: str; 설정을 저장하는 보호자 식별자.
                # - patient_hash: str; 정리 대상 환자 식별자.
                # 반환값:
                # - 기존 조회 함수가 반환하는 설정 행 또는 None.
                def find_after_cleanup_starts(caregiver_hash, patient_hash):
                    nonlocal cleanup
                    cleanup = workers.submit(cleanup_patient)
                    assert cleanup_started.wait(timeout=2)
                    # 올바른 잠금이면 정리가 저장을 기다린다. 잠금이 없으면 이 사이 정리가 완료된다.
                    cleanup_finished.wait(timeout=1)
                    return find_setting(caregiver_hash, patient_hash)

                monkeypatch.setattr(control, "_find_setting", find_after_cleanup_starts)
                response = control.saveCaregiverNotificationSetting(
                    "caregiver-a", "patient-a", enabled=True,
                )
                assert response["success"]
            assert cleanup is not None
            cleanup.result(timeout=5)

        with sessions() as verify:
            assert verify.query(_CaregiverNotification).count() == 0
            assert verify.query(_PatientCaregiverLink).filter_by(linked=True).count() == 0
    finally:
        engine.dispose()


# 함수이름: test_settings_revalidate_after_account_lock_handoff
# 함수역할:
# - 잠금 획득 직전 계정 삭제·연동 해제가 끝나면 410 또는 404로 거부하고 설정이나 트랜잭션을 남기지 않는지 확인한다.
# 매개변수:
# - tmp_path: Path; 테스트 전용 임시 디렉터리.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# - action: str; 삭제할 계정 또는 unlink.
# - status: int; 계정 삭제는 410, 연동 해제는 404.
# 반환값:
# - None.
@pytest.mark.parametrize("action,status", [("patient-a", 410), ("caregiver-a", 410), ("unlink", 404)])
def test_settings_revalidate_after_account_lock_handoff(tmp_path, monkeypatch, action, status):
    engine = make_engine(tmp_path)
    sessions = make_session_factory(engine)
    try:
        with sessions() as db:
            seed_account(db, "patient-a", "caregiver-a")
            links = LinkPatientCaregiver(db)
            code = links.generatePatientHash("patient-a")["data"]["patient_code"]
            link_id = links.requestPatientCaregiverLink("caregiver-a", code)["data"]["id"]
            db.rollback()

            # 함수이름: cleanup_before_lock
            # 함수역할:
            # - 요청 트랜잭션이 해제된 상태에서 별도 세션으로 정리를 완료한 뒤 원래 계정 잠금을 획득한다.
            # 매개변수:
            # - session: Session; 설정 저장 요청의 세션.
            # - participants: Iterable[str]; 잠글 환자·보호자 식별자.
            # 반환값:
            # - None.
            def cleanup_before_lock(session, participants):
                assert not session.in_transaction()
                with sessions() as deleting:
                    if action == "unlink":
                        LinkPatientCaregiver(deleting).requestUnlink(link_id, "patient-a")
                    else:
                        lock_account_operations(deleting, [action])
                        ManageAccount(deleting)._prepare_firebase_account_deletion(action)
                lock_account_operations(session, participants)

            monkeypatch.setattr(notification_module, "lock_account_operations", cleanup_before_lock)
            with pytest.raises(HTTPException) as error:
                SetCaregiverNotification(db).saveCaregiverNotificationSetting(
                    "caregiver-a", "patient-a", enabled=True,
                )
            assert error.value.status_code == status
            assert not db.in_transaction()
        with sessions() as verify:
            assert verify.query(_CaregiverNotification).count() == 0
    finally:
        engine.dispose()


# 함수이름: test_settings_response_does_not_reread_a_row_deleted_after_commit
# 함수역할:
# - 커밋 직후 설정 행이 삭제되어도 응답은 저장 당시의 활성 설정을 사용하고 재조회 오류를 내지 않는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
def test_settings_response_does_not_reread_a_row_deleted_after_commit(fk_db, monkeypatch):
    seed_account(fk_db, "patient-a", "caregiver-a")
    links = LinkPatientCaregiver(fk_db)
    code = links.generatePatientHash("patient-a")["data"]["patient_code"]
    links.requestPatientCaregiverLink("caregiver-a", code)
    commit = fk_db.commit

    # 함수이름: commit_then_delete
    # 함수역할:
    # - 원래 커밋을 실행하고 설정 행이 세션에 있으면 즉시 삭제·커밋하여 응답 생성 전 삭제를 재현한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - None.
    def commit_then_delete():
        has_setting = any(isinstance(row, _CaregiverNotification) for row in fk_db.identity_map.values())
        commit()
        if has_setting:
            fk_db.query(_CaregiverNotification).delete(synchronize_session=False)
            commit()

    monkeypatch.setattr(fk_db, "commit", commit_then_delete)
    response = SetCaregiverNotification(fk_db).saveCaregiverNotificationSetting(
        "caregiver-a", "patient-a", enabled=True,
    )
    assert response["success"]
    assert response["data"]["is_enabled"]
    assert fk_db.query(_CaregiverNotification).count() == 0
