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

                def cleanup_patient():
                    with sessions() as deleting:
                        cleanup_started.set()
                        if action == "delete":
                            lock_account_operations(deleting, ["patient-a"])
                            ManageAccount(deleting)._prepare_firebase_account_deletion("patient-a")
                        else:
                            LinkPatientCaregiver(deleting).requestUnlink(link_id, "patient-a")
                    cleanup_finished.set()

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


def test_settings_response_does_not_reread_a_row_deleted_after_commit(fk_db, monkeypatch):
    seed_account(fk_db, "patient-a", "caregiver-a")
    links = LinkPatientCaregiver(fk_db)
    code = links.generatePatientHash("patient-a")["data"]["patient_code"]
    links.requestPatientCaregiverLink("caregiver-a", code)
    commit = fk_db.commit

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
