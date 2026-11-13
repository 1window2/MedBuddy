# 파일명: test_medication_retention_transaction.py
# 역할: 만료 약품 정리·신규 저장의 원자성과 계정 삭제 경합의 잠금 보장을 검증한다.

"""만료 약 정리와 신규 저장의 원자성 및 계정 삭제와의 직렬화를 검증한다."""

from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
import os
from pathlib import Path
from threading import Event
from typing import Any, NoReturn
from uuid import uuid4

from fastapi import HTTPException
import pytest
from sqlalchemy import create_engine, event, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session
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


# 함수이름: save_request
# 함수역할:
# - 오늘 시작하는 7일 아침 약품 저장 요청에 지정 필드를 덮어쓴다.
# 매개변수:
# - overrides: dict; 저장 요청에 덮어쓸 약품 필드.
# 반환값:
# - SavedMedicationCreate; 합성 저장 요청.
def save_request(**overrides: Any) -> SavedMedicationCreate:
    return SavedMedicationCreate(**{
        "patient_hash": "patient-a", "item_name": "new-test-medication", "efficacy": "",
        "use_method": "", "warning_message": "", "daily_frequency": "1", "total_days": "7",
        "prescription_date": application_today(), "schedule_slot_keys": ["morning"], **overrides,
    })


# 함수이름: seed_expired
# 함수역할:
# - 열흘 전 시작해 하루만 복용하는 만료 약품을 저장한다.
# 매개변수:
# - db: Session; 격리 약품 저장 세션.
# 반환값:
# - int; 만료 약품 ID.
def seed_expired(db: Session) -> int:
    return medication(db, prescription_date=application_today() - timedelta(days=10), total_days="1").id


# 함수이름: control_with_retention
# 함수역할:
# - 복용 종료 하루 뒤 정리하는 정책을 약품 저장 컨트롤에 주입한다.
# 매개변수:
# - db: Session; 격리 약품 저장 세션.
# 반환값:
# - CheckSavedMedication; 짧은 보존 기간이 설정된 컨트롤.
def control_with_retention(db: Session) -> CheckSavedMedication:
    control = CheckSavedMedication(db)
    control.retention_policy = SavedMedicationRetentionPolicy(retention_days_after_end=1)
    return control


# 함수이름: test_cleanup_and_save_commit_once_and_keep_the_callers_transaction
# 함수역할:
# - 정리는 호출자 트랜잭션을 유지하며 중간 커밋 없이 신규 저장과 함께 한 번만 커밋되는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
def test_cleanup_and_save_commit_once_and_keep_the_callers_transaction(fk_db: Session, monkeypatch: pytest.MonkeyPatch) -> None:
    expired_id = seed_expired(fk_db)
    fk_db.rollback()
    lock_account_operations(fk_db, ["patient-a"])
    transaction = fk_db.get_transaction()
    commits = []
    event.listen(fk_db, "after_commit", lambda db: commits.append(True))
    control = control_with_retention(fk_db)
    original = control.retention_policy.cleanup_expired_medications

    # 함수이름: cleanup
    # 함수역할:
    # - commit=False로 정리되는지, 원래 트랜잭션과 미커밋 상태를 유지하는지 확인한다.
    # 매개변수:
    # - args: tuple; 원래 보존 기간 정리에 전달할 위치 인수.
    # - kwargs: dict; commit=False 등 정리 옵션.
    # 반환값:
    # - int; 삭제한 만료 약품 수.
    def cleanup(*args: Session | str | date | None, **kwargs: bool) -> int:
        assert kwargs["commit"] is False
        count = original(*args, **kwargs)
        assert count == 1 and fk_db.get_transaction() is transaction and not commits
        return count

    monkeypatch.setattr(control.retention_policy, "cleanup_expired_medications", cleanup)
    response = control.saveMedicationDetail(save_request())
    assert response["success"] and len(commits) == 1
    assert fk_db.get(_SavedMedication, expired_id) is None
    assert fk_db.query(_SavedMedication).count() == 1


# 함수이름: test_failed_save_restores_retention_deletions
# 함수역할:
# - 저장 개수 제한·커밋 실패는 만료 약품 정리도 롤백하여 기존 약품을 보존하는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# - failure: str; 개수 제한(limit) 또는 커밋(insert) 실패.
# 반환값:
# - None.
@pytest.mark.parametrize("failure", ["limit", "insert"])
def test_failed_save_restores_retention_deletions(fk_db: Session, monkeypatch: pytest.MonkeyPatch, failure: str) -> None:
    expired_id = seed_expired(fk_db)
    active_id = medication(fk_db, item_name="active-test").id
    control = control_with_retention(fk_db)
    if failure == "limit":
        monkeypatch.setattr(settings, "SAVED_MEDICATION_MAX_PER_ACCOUNT", 1)
    else:
        # 함수이름: fail_commit
        # 함수역할:
        # - 신규 저장 커밋에 실패를 주입하여 선행 만료 정리의 롤백을 검사한다.
        # 매개변수:
        # - 없음.
        # 반환값:
        # - 반환하지 않음; RuntimeError 발생.
        def fail_commit() -> NoReturn:
            raise RuntimeError("synthetic-insert-failure")
        monkeypatch.setattr(fk_db, "commit", fail_commit)
    with pytest.raises(HTTPException) as error:
        control.saveMedicationDetail(save_request())
    assert error.value.status_code == (409 if failure == "limit" else 500)
    assert {row.id for row in fk_db.query(_SavedMedication)} == {expired_id, active_id}


# 함수이름: test_retention_frees_space_before_the_limit_check
# 함수역할:
# - 저장 한도 검사 전에 만료 약품을 정리하여 새 약품 공간을 확보하는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
def test_retention_frees_space_before_the_limit_check(fk_db: Session, monkeypatch: pytest.MonkeyPatch) -> None:
    seed_expired(fk_db)
    monkeypatch.setattr(settings, "SAVED_MEDICATION_MAX_PER_ACCOUNT", 1)
    assert control_with_retention(fk_db).saveMedicationDetail(save_request())["success"]
    assert fk_db.query(_SavedMedication).count() == 1


# 함수이름: test_duplicate_save_still_commits_cleanup_without_an_intermediate_commit
# 함수역할:
# - 중복 저장 응답도 만료 정리를 한 번 커밋하고 기존 약품 ID를 유지하는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# 반환값:
# - None.
def test_duplicate_save_still_commits_cleanup_without_an_intermediate_commit(fk_db: Session) -> None:
    seed_account(fk_db, "patient-a")
    request = save_request()
    duplicate_id = CheckSavedMedication(fk_db).saveMedicationDetail(request)["id"]
    expired_id = seed_expired(fk_db)
    commits = []
    event.listen(fk_db, "after_commit", lambda db: commits.append(True))
    result = control_with_retention(fk_db).saveMedicationDetail(request)
    assert result["duplicate"] and result["id"] == duplicate_id and len(commits) == 1
    assert fk_db.get(_SavedMedication, expired_id) is None


# 함수이름: transaction_engine
# 함수역할:
# - SQLite 파일 또는 명시적으로 허용된 PostgreSQL의 고유 스키마를 제공하고 종료 후 정리한다.
# 매개변수:
# - request: pytest.FixtureRequest; sqlite 또는 postgresql 매개변수.
# - tmp_path: Path; 테스트 전용 임시 디렉터리.
# 반환값:
# - Iterator[Engine]; PostgreSQL 사용 조건이 없으면 pytest.skip.
@pytest.fixture(params=["sqlite", "postgresql"])
def transaction_engine(request: pytest.FixtureRequest, tmp_path: Path) -> Iterator[Engine]:
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


# 함수이름: test_account_deletion_waits_until_cleanup_and_save_commit
# 함수역할:
# - 약품 정리·저장이 계정 잠금을 유지하면 계정 삭제는 저장 커밋까지 기다린 뒤 모든 약품을 제거하는지 확인한다.
# 매개변수:
# - transaction_engine: Engine; 격리 SQLite 또는 명시적으로 허용한 PostgreSQL 스키마.
# 반환값:
# - None.
def test_account_deletion_waits_until_cleanup_and_save_commit(transaction_engine: Engine) -> None:
    factory = make_session_factory(transaction_engine)
    with factory() as db:
        seed_expired(db)
    cleaned, resume, deletion_started, deletion_locked, save_returned = (Event() for _ in range(5))

    # 함수이름: save
    # 함수역할:
    # - 계정 잠금 안에서 정리·저장을 실행하고 저장 반환 완료를 다른 스레드에 알린다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - dict; 약품 저장 응답.
    def save() -> dict[str, object]:
        with factory() as db:
            lock_account_operations(db, ["patient-a"])
            ManageAccount(db).ensureAccount("patient-a")
            control = control_with_retention(db)
            original = control.retention_policy.cleanup_expired_medications

            # 함수이름: cleanup
            # 함수역할:
            # - 실제 만료 정리 후 신호를 보내고 테스트가 허용할 때까지 저장을 대기시킨다.
            # 매개변수:
            # - args: tuple; 원래 보존 기간 정리에 전달할 위치 인수.
            # - kwargs: dict; commit=False 등 정리 옵션.
            # 반환값:
            # - int; 정리된 약품 수.
            def cleanup(*args: Session | str | date | None, **kwargs: bool) -> int:
                count = original(*args, **kwargs)
                cleaned.set()
                assert resume.wait(10)
                return count

            control.retention_policy.cleanup_expired_medications = cleanup
            result = control.saveMedicationDetail(save_request())
            save_returned.set()
            return result

    # 함수이름: delete
    # 함수역할:
    # - 저장 작업의 계정 잠금 해제를 기다리고 반환 완료 후 삭제 표시와 데이터 제거를 커밋한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - None.
    def delete() -> None:
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


# 함수이름: test_save_cannot_resurrect_data_when_account_deletion_wins
# 함수역할:
# - 계정 삭제가 잠금을 먼저 획득하면 후속 저장은 삭제 대기 오류로 거부되어 약품이 되살아나지 않는지 확인한다.
# 매개변수:
# - transaction_engine: Engine; 격리 SQLite 또는 명시적으로 허용한 PostgreSQL 스키마.
# 반환값:
# - None.
def test_save_cannot_resurrect_data_when_account_deletion_wins(transaction_engine: Engine) -> None:
    factory = make_session_factory(transaction_engine)
    with factory() as db:
        seed_expired(db)
    deleting, resume, saving, saved = (Event() for _ in range(4))

    # 함수이름: delete
    # 함수역할:
    # - 계정 잠금 안에서 삭제 상태와 데이터 제거를 준비한 뒤 허용 신호가 오면 커밋한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - None.
    def delete() -> None:
        with factory() as db:
            lock_account_operations(db, ["patient-a"])
            db.get(_UserAccount, "patient-a").deletion_requested_at = utc_now()
            ManageAccount(db)._purge_user_data("patient-a", delete_account=False)
            deleting.set()
            assert resume.wait(10)
            db.commit()

    # 함수이름: save
    # 함수역할:
    # - 계정 삭제 뒤 잠금을 넘겨받아 유효 계정을 확인하고 저장을 시도한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - dict; 정상 저장 응답. 삭제 완료 시 AccountDeletionPendingError 발생.
    def save() -> dict[str, object]:
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
