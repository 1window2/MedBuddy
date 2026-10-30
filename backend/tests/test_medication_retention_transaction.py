"""만료 약 정리와 신규 저장의 원자성 및 계정 삭제와의 직렬화를 검증한다."""

from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
import os
from threading import Event
from uuid import uuid4

from fastapi import HTTPException
import pytest
from sqlalchemy import create_engine, event, text
from sqlalchemy.schema import CreateSchema, DropSchema

from controls.check_saved_medication_control import CheckSavedMedication
from controls.manage_account_control import AccountDeletionPendingError, ManageAccount
from core.account_database_lock import lock_account_operations
from core.application_clock import application_today
from core.config import settings
from core.database import Base, engine as application_engine
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import _UserAccount, utc_now
from schemas.medication import SavedMedicationCreate
from services.saved_medication_retention import SavedMedicationRetentionPolicy
from support.db import _register_all_entities, make_engine, make_session_factory, seed_account
from test_medication_care import medication


def save_request(**overrides):
    return SavedMedicationCreate(**{
        "patient_hash": "patient-a", "item_name": "new-test-medication", "efficacy": "",
        "use_method": "", "warning_message": "", "daily_frequency": "1", "total_days": "7",
        "prescription_date": application_today(), "schedule_slot_keys": ["morning"], **overrides,
    })


def seed_expired(db):
    return medication(db, prescription_date=application_today() - timedelta(days=10), total_days="1").id


def control_with_retention(db):
    control = CheckSavedMedication(db)
    control.retention_policy = SavedMedicationRetentionPolicy(retention_days_after_end=1)
    return control


def test_cleanup_and_save_commit_once_and_keep_the_callers_transaction(fk_db, monkeypatch):
    expired_id = seed_expired(fk_db)
    fk_db.rollback()
    lock_account_operations(fk_db, ["patient-a"])
    transaction = fk_db.get_transaction()
    commits = []
    event.listen(fk_db, "after_commit", lambda db: commits.append(True))
    control = control_with_retention(fk_db)
    original = control.retention_policy.cleanup_expired_medications

    def cleanup(*args, **kwargs):
        assert kwargs["commit"] is False
        count = original(*args, **kwargs)
        assert count == 1 and fk_db.get_transaction() is transaction and not commits
        return count

    monkeypatch.setattr(control.retention_policy, "cleanup_expired_medications", cleanup)
    response = control.saveMedicationDetail(save_request())
    assert response["success"] and len(commits) == 1
    assert fk_db.get(_SavedMedication, expired_id) is None
    assert fk_db.query(_SavedMedication).count() == 1


@pytest.mark.parametrize("failure", ["limit", "insert"])
def test_failed_save_restores_retention_deletions(fk_db, monkeypatch, failure):
    expired_id = seed_expired(fk_db)
    active_id = medication(fk_db, item_name="active-test").id
    control = control_with_retention(fk_db)
    if failure == "limit":
        monkeypatch.setattr(settings, "SAVED_MEDICATION_MAX_PER_ACCOUNT", 1)
    else:
        def fail_commit():
            raise RuntimeError("synthetic-insert-failure")
        monkeypatch.setattr(fk_db, "commit", fail_commit)
    with pytest.raises(HTTPException) as error:
        control.saveMedicationDetail(save_request())
    assert error.value.status_code == (409 if failure == "limit" else 500)
    assert {row.id for row in fk_db.query(_SavedMedication)} == {expired_id, active_id}


def test_retention_frees_space_before_the_limit_check(fk_db, monkeypatch):
    seed_expired(fk_db)
    monkeypatch.setattr(settings, "SAVED_MEDICATION_MAX_PER_ACCOUNT", 1)
    assert control_with_retention(fk_db).saveMedicationDetail(save_request())["success"]
    assert fk_db.query(_SavedMedication).count() == 1


def test_duplicate_save_still_commits_cleanup_without_an_intermediate_commit(fk_db):
    seed_account(fk_db, "patient-a")
    request = save_request()
    duplicate_id = CheckSavedMedication(fk_db).saveMedicationDetail(request)["id"]
    expired_id = seed_expired(fk_db)
    commits = []
    event.listen(fk_db, "after_commit", lambda db: commits.append(True))
    result = control_with_retention(fk_db).saveMedicationDetail(request)
    assert result["duplicate"] and result["id"] == duplicate_id and len(commits) == 1
    assert fk_db.get(_SavedMedication, expired_id) is None


@pytest.fixture(params=["sqlite", "postgresql"])
def transaction_engine(request, tmp_path):
    if request.param == "sqlite":
        engine = make_engine(tmp_path)
        try:
            yield engine
        finally:
            engine.dispose()
        return
    if os.getenv("MEDBUDDY_RUN_POSTGRES_INTEGRATION") != "1" or application_engine.dialect.name != "postgresql":
        pytest.skip("requires the opt-in PostgreSQL integration database")
    # 명시적으로 지정한 테스트 DB에서도 고유 스키마만 만들고 지운다.
    schema = f"care_retention_test_{uuid4().hex}"
    with application_engine.begin() as connection:
        connection.execute(CreateSchema(schema))
    engine = create_engine(application_engine.url, connect_args={"options": f"-csearch_path={schema}"})
    try:
        _register_all_entities()
        Base.metadata.create_all(engine)
        yield engine
    finally:
        engine.dispose()
        with application_engine.begin() as connection:
            connection.execute(DropSchema(schema, cascade=True))


def test_account_deletion_waits_until_cleanup_and_save_commit(transaction_engine):
    factory = make_session_factory(transaction_engine)
    with factory() as db:
        seed_expired(db)
    cleaned, resume, deletion_started, deletion_locked, save_returned = (Event() for _ in range(5))

    def save():
        with factory() as db:
            lock_account_operations(db, ["patient-a"])
            ManageAccount(db).ensureAccount("patient-a")
            control = control_with_retention(db)
            original = control.retention_policy.cleanup_expired_medications

            def cleanup(*args, **kwargs):
                count = original(*args, **kwargs)
                cleaned.set()
                assert resume.wait(10)
                return count

            control.retention_policy.cleanup_expired_medications = cleanup
            result = control.saveMedicationDetail(save_request())
            save_returned.set()
            return result

    def delete():
        with factory() as db:
            deletion_started.set()
            lock_account_operations(db, ["patient-a"])
            deletion_locked.set()
            assert save_returned.wait(10)
            db.get(_UserAccount, "patient-a").deletion_requested_at = utc_now()
            ManageAccount(db)._purge_user_data("patient-a", delete_account=False)
            db.commit()

    with ThreadPoolExecutor(max_workers=2) as pool:
        save_future = pool.submit(save)
        try:
            assert cleaned.wait(10)
            if transaction_engine.dialect.name == "postgresql":
                with transaction_engine.begin() as connection:
                    assert not connection.execute(text(
                        "SELECT pg_try_advisory_xact_lock(hashtextextended(:owner, 0))"
                    ), {"owner": "patient-a"}).scalar_one()
            delete_future = pool.submit(delete)
            assert deletion_started.wait(10)
            assert not deletion_locked.wait(0.2)
        finally:
            resume.set()
        assert save_future.result(timeout=15)["success"]
        delete_future.result(timeout=15)
    with factory() as db:
        assert db.query(_SavedMedication).count() == 0
        assert db.get(_UserAccount, "patient-a").deletion_requested_at is not None


def test_save_cannot_resurrect_data_when_account_deletion_wins(transaction_engine):
    factory = make_session_factory(transaction_engine)
    with factory() as db:
        seed_expired(db)
    deleting, resume, saving, saved = (Event() for _ in range(4))

    def delete():
        with factory() as db:
            lock_account_operations(db, ["patient-a"])
            db.get(_UserAccount, "patient-a").deletion_requested_at = utc_now()
            ManageAccount(db)._purge_user_data("patient-a", delete_account=False)
            deleting.set()
            assert resume.wait(10)
            db.commit()

    def save():
        with factory() as db:
            saving.set()
            lock_account_operations(db, ["patient-a"])
            ManageAccount(db).ensureAccount("patient-a")
            result = control_with_retention(db).saveMedicationDetail(save_request())
            saved.set()
            return result

    with ThreadPoolExecutor(max_workers=2) as pool:
        delete_future = pool.submit(delete)
        try:
            assert deleting.wait(10)
            save_future = pool.submit(save)
            assert saving.wait(10)
            assert not saved.wait(0.2)
        finally:
            resume.set()
        delete_future.result(timeout=15)
        with pytest.raises(AccountDeletionPendingError):
            save_future.result(timeout=15)
    with factory() as db:
        assert db.query(_SavedMedication).count() == 0
