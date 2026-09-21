# 파일명: test_dose_sync.py
# 역할: 오프라인 복약 재전송의 중복 방지, 계정·날짜 검증과 트랜잭션 롤백을 검증한다.
"""Offline retries, undo, ownership and midnight must not invent new doses."""
from datetime import timedelta
from unittest.mock import patch

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from controls.sync_dose_control import SyncDose
from controls.check_schedule_control import CheckSchedule
from core.application_clock import application_today
from core.database import Base
from entities.dose_sync_operation_entity import _DoseSyncOperation
from entities.medication_completion_entity import _MedicationCompletion
from entities.caregiver_alert_outbox_entity import _CaregiverAlertOutbox
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import _UserAccount
from schemas.dose_sync import DoseSyncRequest
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from entities.chat_message_entity import _ChatMessage


# 함수이름: fixture
# 함수역할: 격리된 메모리 DB에 두 계정과 아침 약을 만들고 테스트 종료 후 연결을 정리한다.
# 매개변수: 없음. 반환값: 테스트 세션과 약 식별자를 제공하는 제너레이터.
@pytest.fixture
def fixture():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        db.add(_UserAccount(user_hash="offline-patient"))
        db.add(_UserAccount(user_hash="other-patient"))
        med = _SavedMedication(patient_hash="offline-patient", item_name="offline fixture",
            created_date=application_today()-timedelta(days=3), total_days="30",
            daily_frequency="1", dosage_per_time="1", schedule_slot_keys='["morning"]')
        db.add(med)
        db.commit()
        yield db, med.id
    engine.dispose()


# 함수이름: operation
# 함수역할: 오늘 아침 복용 완료 요청을 만들고 사례별로 지정한 필드만 덮어쓴다.
# 매개변수: med_id: 약 식별자, changes: 변경할 요청 필드. 반환값: 동기화 요청.
def operation(med_id, **changes):
    return DoseSyncRequest(**dict(dict(operation_id="offline_dose_0001",
        schedule_date=application_today(), slot_key="morning", medication_ids=[med_id], completed=True), **changes))


# 함수이름: test_retry_after_undo_never_reapplies
# 함수역할: 취소 뒤 원래 완료 요청이 재전송되어도 취소를 유지하고 처리 이력·알림을 중복 생성하지 않는지 검증한다.
# 매개변수: fixture: 격리 DB와 약 식별자. 반환값: 없음; 불일치 시 단언 실패.
def test_retry_after_undo_never_reapplies(fixture):
    db, med_id = fixture
    control = SyncDose(db)
    first = operation(med_id)
    control.apply("offline-patient", first)
    control.apply("offline-patient", operation(med_id, operation_id="offline_undo_0002", completed=False))
    control.apply("offline-patient", first)
    assert db.query(_MedicationCompletion).one().completed is False
    assert db.query(_DoseSyncOperation).count() == 2
    assert db.query(_CaregiverAlertOutbox).count() == 1


# 함수이름: test_midnight_records_original_day_without_today_or_live_alert
# 함수역할: 전날 기록을 원래 날짜에 저장하고 오늘 일정과 실시간 보호자 알림에는 반영하지 않는지 검증한다.
# 매개변수: fixture: 격리 DB와 약 식별자. 반환값: 없음; 불일치 시 단언 실패.
def test_midnight_records_original_day_without_today_or_live_alert(fixture):
    db, med_id = fixture
    yesterday = application_today()-timedelta(days=1)
    SyncDose(db).apply("offline-patient", operation(med_id, schedule_date=yesterday))
    row = db.query(_MedicationCompletion).one()
    assert row.schedule_date == yesterday and row.completed
    assert db.query(_CaregiverAlertOutbox).count() == 0
    assert not CheckSchedule(db).requestTodayMedicationSchedule("offline-patient")["data"][0]["medication_status"]


# 함수이름: test_future_and_expired_dates_reject_without_receipt
# 함수역할: 미래 또는 복구 허용 기간 밖의 요청을 409로 거부하고 처리 이력과 복용 기록을 남기지 않는지 검증한다.
# 매개변수: fixture: 격리 DB와 약 식별자, days: 오늘 기준 날짜 차이. 반환값: 없음; 불일치 시 단언 실패.
@pytest.mark.parametrize("days", [1, -31])
def test_future_and_expired_dates_reject_without_receipt(fixture, days):
    db, med_id = fixture
    with pytest.raises(HTTPException) as error:
        SyncDose(db).apply("offline-patient", operation(med_id, schedule_date=application_today()+timedelta(days=days)))
    assert error.value.status_code == 409
    assert db.query(_DoseSyncOperation).count() == 0
    assert db.query(_MedicationCompletion).count() == 0


# 함수이름: test_wrong_owner_and_deleted_medication_reject
# 함수역할: 타인 소유 약과 존재하지 않는 약의 요청을 거부해 무효한 기록이 생기지 않는지 검증한다.
# 매개변수: fixture: 격리 DB와 약 식별자. 반환값: 없음; 불일치 시 단언 실패.
def test_wrong_owner_and_deleted_medication_reject(fixture):
    db, med_id = fixture
    with pytest.raises(HTTPException):
        SyncDose(db).apply("other-patient", operation(med_id))
    assert db.query(_DoseSyncOperation).count() == 0
    with pytest.raises(HTTPException):
        SyncDose(db).apply("offline-patient", operation(med_id+999))
    assert db.query(_MedicationCompletion).count() == 0


# 함수이름: test_receipt_payload_cannot_change
# 함수역할: 같은 요청 식별자로 완료 상태를 바꾸면 409로 거부하고 최초 기록을 유지하는지 검증한다.
# 매개변수: fixture: 격리 DB와 약 식별자. 반환값: 없음; 불일치 시 단언 실패.
def test_receipt_payload_cannot_change(fixture):
    db, med_id = fixture
    SyncDose(db).apply("offline-patient", operation(med_id))
    with pytest.raises(HTTPException) as error:
        SyncDose(db).apply("offline-patient", operation(med_id, completed=False))
    assert error.value.status_code == 409
    assert db.query(_MedicationCompletion).one().completed


# 함수이름: test_transaction_failure_rolls_back_receipt_and_dose
# 함수역할: DB 커밋 실패 시 처리 이력·복용 기록·보호자 알림이 모두 롤백되는지 검증한다.
# 매개변수: fixture: 격리 DB와 약 식별자. 반환값: 없음; 불일치 시 단언 실패.
def test_transaction_failure_rolls_back_receipt_and_dose(fixture):
    db, med_id = fixture
    with patch.object(db, "commit", side_effect=RuntimeError("disk failure")):
        with pytest.raises(RuntimeError):
            SyncDose(db).apply("offline-patient", operation(med_id))
    assert db.query(_DoseSyncOperation).count() == 0
    assert db.query(_MedicationCompletion).count() == 0
    assert db.query(_CaregiverAlertOutbox).count() == 0


# 함수이름: test_chat_and_historical_dose_share_one_idempotent_transaction
# 함수역할: 과거 복용 기록과 채팅이 한 번만 저장되고 메시지에도 원래 날짜가 유지되는지 검증한다.
# 매개변수: fixture: 격리 DB와 약 식별자. 반환값: 없음; 불일치 시 단언 실패.
def test_chat_and_historical_dose_share_one_idempotent_transaction(fixture):
    db, med_id = fixture
    links = LinkPatientCaregiver(db)
    code = links.generatePatientHash("offline-patient")["data"]["patient_code"]
    link_id = links.requestPatientCaregiverLink("other-patient", code)["data"]["id"]
    yesterday = application_today()-timedelta(days=1)
    request = operation(med_id, link_id=link_id, schedule_date=yesterday)
    events, message = SyncDose(db).apply("offline-patient", request)
    assert events == [] and message.created
    SyncDose(db).apply("offline-patient", request)
    assert db.query(_ChatMessage).count() == 1
    assert db.query(_DoseSyncOperation).count() == 1
    assert yesterday.isoformat() in db.query(_ChatMessage).one().body
    assert db.query(_ChatMessage).one().context_payload["schedule_context"]["schedule_date"] == yesterday.isoformat()


# 함수이름: test_chat_failure_rolls_back_the_dose_and_receipt
# 함수역할: 채팅 저장 실패 시 복용 기록과 처리 이력도 함께 취소되어 재시도가 가능한지 검증한다.
# 매개변수: fixture: 격리 DB와 약 식별자. 반환값: 없음; 불일치 시 단언 실패.
def test_chat_failure_rolls_back_the_dose_and_receipt(fixture):
    db, med_id = fixture
    links = LinkPatientCaregiver(db)
    code = links.generatePatientHash("offline-patient")["data"]["patient_code"]
    link_id = links.requestPatientCaregiverLink("other-patient", code)["data"]["id"]
    with patch("repositories.chat_message_repository.ChatMessageRepository.add", side_effect=RuntimeError("chat failure")):
        with pytest.raises(RuntimeError):
            SyncDose(db).apply("offline-patient", operation(med_id, link_id=link_id))
    assert db.query(_DoseSyncOperation).count() == 0
    assert db.query(_MedicationCompletion).count() == 0


# 함수이름: test_route_rejects_a_previous_accounts_queued_request
# 함수역할: 로그인 계정과 다른 계정의 대기 요청을 API에서 403으로 거부하고 처리 이력을 남기지 않는지 검증한다.
# 매개변수: fixture: 격리 DB와 약 식별자. 반환값: 없음; 불일치 시 단언 실패.
def test_route_rejects_a_previous_accounts_queued_request(fixture):
    import asyncio
    from fastapi import BackgroundTasks, Request
    from api.router import sync_dose_operation
    from controls.authorization_control import AuthorizationControl
    from entities.authenticated_principal_entity import AuthenticatedPrincipal
    db, med_id = fixture
    with pytest.raises(HTTPException) as error:
        asyncio.run(sync_dose_operation(
            payload=operation(med_id), request=Request({"type": "http"}),
            background_tasks=BackgroundTasks(), patient_hash="offline-patient",
            principal=AuthenticatedPrincipal(subject="other", issuer="test", user_hash="other-patient"),
            authorization=AuthorizationControl(db), check_schedule=CheckSchedule(db),
        ))
    assert error.value.status_code == 403
    assert db.query(_DoseSyncOperation).count() == 0


# 함수이름: test_migration_accepts_demo_metadata_initialization
# 함수역할: 데모 초기화로 테이블이 이미 있는 DB에서도 마이그레이션을 반복 실행할 수 있는지 검증한다.
# 매개변수: fixture: 테이블이 생성된 격리 DB와 약 식별자. 반환값: 없음; 실행 오류 시 실패.
def test_migration_accepts_demo_metadata_initialization(fixture):
    import importlib.util
    from pathlib import Path
    from alembic.migration import MigrationContext
    from alembic.operations import Operations
    db, _ = fixture
    path = Path(__file__).parents[1] / "migrations/versions/a6e2d903bc71_add_dose_sync_operations.py"
    spec = importlib.util.spec_from_file_location("dose_migration", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with db.bind.begin() as connection:
        with patch.object(module, "op", Operations(MigrationContext.configure(connection))):
            module.upgrade()
            module.upgrade()
