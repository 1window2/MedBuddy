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


# 함수이름: test_dose_queued_with_a_removed_link_is_still_recorded
# 함수역할: 연동이 해제된 뒤 도착한 채팅 연동 복용 요청을 거부하지 않고 채팅 없이 일반 복용 기록으로 저장하는지 검증한다.
# 매개변수: fixture: 격리 DB와 약 식별자. 반환값: 없음; 불일치 시 단언 실패.
def test_dose_queued_with_a_removed_link_is_still_recorded(fixture):
    db, med_id = fixture
    events, message = SyncDose(db).apply("offline-patient", operation(med_id, link_id=987654))
    assert message is None
    assert db.query(_ChatMessage).count() == 0
    assert db.query(_DoseSyncOperation).count() == 1
    assert db.query(_MedicationCompletion).count() == 1
    schedule = CheckSchedule(db).requestTodayMedicationSchedule("offline-patient")["data"]
    assert schedule[0]["slot_statuses"]["morning"] is True


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
            sync_dose=SyncDose(db),
        ))
    assert error.value.status_code == 403
    assert db.query(_DoseSyncOperation).count() == 0


# 함수이름: test_route_accepts_a_linked_dose_and_broadcasts_its_chat_receipt
# 함수역할: 채팅 연동 복용 요청이 API에서 200으로 끝나고 저장된 복용 메시지를 실시간 연결에 한 번 전달하는지 검증한다.
#   일일 채팅 한도를 한 번 확인하고, 완료 알림을 예약한 뒤에는 요청 세션의 트랜잭션을 끝내는지도 확인한다.
# 매개변수: 없음. 반환값: 없음; 불일치 시 단언 실패.
def test_route_accepts_a_linked_dose_and_broadcasts_its_chat_receipt():
    import asyncio
    from types import SimpleNamespace
    from unittest.mock import AsyncMock
    from fastapi import BackgroundTasks
    from sqlalchemy.pool import StaticPool
    from api import router as medication_router
    from api.router import sync_dose_operation
    from controls.authorization_control import AuthorizationControl
    from entities.authenticated_principal_entity import AuthenticatedPrincipal
    from services.chat_connection_manager import ChatConnectionManager
    # The route runs its database work on a worker thread, so share one connection.
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False},
                           poolclass=StaticPool)
    Base.metadata.create_all(engine)
    try:
        with Session(engine) as db:
            db.add(_UserAccount(user_hash="offline-patient"))
            db.add(_UserAccount(user_hash="other-patient"))
            med = _SavedMedication(patient_hash="offline-patient", item_name="offline fixture",
                created_date=application_today()-timedelta(days=3), total_days="30",
                daily_frequency="1", dosage_per_time="1", schedule_slot_keys='["morning"]')
            db.add(med)
            db.commit()
            links = LinkPatientCaregiver(db)
            code = links.generatePatientHash("offline-patient")["data"]["patient_code"]
            link_id = links.requestPatientCaregiverLink("other-patient", code)["data"]["id"]
            manager = ChatConnectionManager()
            manager.broadcast = AsyncMock()
            request = SimpleNamespace(
                app=SimpleNamespace(state=SimpleNamespace(chat_connection_manager=manager)),
            )
            quota = AsyncMock()
            background_tasks = BackgroundTasks()
            with patch.object(medication_router, "enforce_chat_daily_quota", quota):
                response = asyncio.run(sync_dose_operation(
                    payload=operation(med.id, link_id=link_id), request=request,
                    background_tasks=background_tasks, patient_hash=None,
                    principal=AuthenticatedPrincipal(
                        subject="patient", issuer="test", user_hash="offline-patient"),
                    authorization=AuthorizationControl(db), check_schedule=CheckSchedule(db),
                    sync_dose=SyncDose(db),
                ))
            quota.assert_awaited_once()
            assert quota.await_args.kwargs["user_hash"] == "offline-patient"
            assert len(background_tasks.tasks) == 1
            assert not db.in_transaction()
            assert response["success"] is True
            assert response["operation_id"] == "offline_dose_0001"
            assert response["data"][0]["slot_statuses"]["morning"] is True
            manager.broadcast.assert_awaited_once()
            assert manager.broadcast.await_args.kwargs["link_id"] == link_id
            assert db.query(_ChatMessage).count() == 1
            assert db.query(_DoseSyncOperation).count() == 1
    finally:
        engine.dispose()


# 함수이름: _run_dose_route
# 함수역할: 지정한 복약 완료 라우트 핸들러를 실제 Control과 요청 세션으로 직접 호출하고, 응답 뒤에 실행될 작업을 요청 세션이 열린 채로 실행한다.
# 매개변수: route: 호출할 라우트 이름, db: 요청 세션, medication_id: 약 식별자, link_id: 채팅 연동 식별자.
# 반환값: 라우트 응답 사전.
def _run_dose_route(route, db, medication_id, link_id):
    import asyncio
    from types import SimpleNamespace
    from unittest.mock import AsyncMock
    from fastapi import BackgroundTasks
    from api import chat_router, router as medication_router
    from controls.authorization_control import AuthorizationControl
    from controls.manage_linked_chat_control import ManageLinkedChat
    from entities.authenticated_principal_entity import AuthenticatedPrincipal
    from schemas.chat import ChatMedicationTaken
    from schemas.medication import MedicationStatusUpdate
    from services.chat_connection_manager import ChatConnectionManager

    manager = ChatConnectionManager()
    manager.broadcast = AsyncMock()
    request = SimpleNamespace(
        app=SimpleNamespace(state=SimpleNamespace(chat_connection_manager=manager)),
    )
    principal = AuthenticatedPrincipal(subject="patient", issuer="test", user_hash="patient-a")
    authorization = AuthorizationControl(db)
    background_tasks = BackgroundTasks()
    today = application_today()

    # 함수이름: exercise
    # 함수역할: 핸들러를 호출한 뒤 FastAPI가 응답 이후에 하듯 예약된 작업을 실행한다.
    # 매개변수: 없음. 반환값: 라우트 응답 사전.
    async def exercise():
        if route == "slot_status":
            response = medication_router.update_medication_slot_status(
                slot_key="morning", request=MedicationStatusUpdate(medication_status=True),
                background_tasks=background_tasks, patient_hash=None, principal=principal,
                authorization=authorization, check_schedule=CheckSchedule(db),
            )
        elif route == "medication_status":
            response = medication_router.update_medication_status(
                medication_id=medication_id,
                request=MedicationStatusUpdate(medication_status=True, slot_key="morning"),
                background_tasks=background_tasks, patient_hash=None, principal=principal,
                authorization=authorization, check_schedule=CheckSchedule(db),
            )
        elif route in ("dose_sync", "dose_sync_with_chat"):
            payload = DoseSyncRequest(
                operation_id="offline_dose_0001", schedule_date=today, slot_key="morning",
                medication_ids=[medication_id], completed=True,
                link_id=link_id if route == "dose_sync_with_chat" else None,
            )
            response = await medication_router.sync_dose_operation(
                payload=payload, request=request, background_tasks=background_tasks,
                patient_hash=None, principal=principal, authorization=authorization,
                check_schedule=CheckSchedule(db), sync_dose=SyncDose(db),
            )
        else:
            response = await chat_router.record_chat_medication_taken(
                link_id=link_id,
                payload=ChatMedicationTaken(
                    client_message_id="chat_dose_0001", schedule_date=today,
                    slot_key="morning", medication_ids=[medication_id],
                ),
                request=request, background_tasks=background_tasks, user_hash="patient-a",
                principal=principal, authorization=authorization, chat=ManageLinkedChat(db),
            )
        assert len(background_tasks.tasks) == 1
        await background_tasks()
        return response

    return asyncio.run(exercise())


# 함수이름: _seed_completion_push
# 함수역할: 환자의 아침 약 한 건과, 아침 복용 완료 알림을 켜고 푸시 토큰을 등록한 연동 보호자를 만든다.
# 매개변수: factory: 시험 DB의 세션 팩토리. 반환값: 연동 식별자와 약 식별자.
def _seed_completion_push(factory):
    from entities.caregiver_notification_entity import (
        CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
        _CaregiverNotification,
        encode_slot_settings,
    )
    from entities.device_push_token_entity import _DevicePushToken
    from entities.patient_caregiver_link_entity import _PatientCaregiverLink
    from support.db import seed_account, seed_medication

    with factory() as db:
        seed_account(db, "patient-a", "caregiver-a")
        link = _PatientCaregiverLink(
            patient_hash="patient-a", caregiver_hash="caregiver-a", linked=True)
        db.add_all([
            link,
            _CaregiverNotification(
                patient_hash="patient-a", caregiver_hash="caregiver-a", enabled=True,
                alert_option=CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
                slot_settings=encode_slot_settings({"morning": {
                    "notification_type": CAREGIVER_NOTIFICATION_MODE_DOSE_COMPLETED,
                    "deadline_hour": None, "deadline_minute": None,
                }}),
            ),
            _DevicePushToken(user_hash="caregiver-a", token="caregiver-completion-token-12345",
                             platform="android", enabled=True),
        ])
        db.commit()
        medication = seed_medication(
            db, patient_hash="patient-a", daily_frequency="1", schedule_slot_keys='["morning"]')
        return link.id, medication.id


# 함수이름: test_completion_push_is_sent_without_an_open_request_transaction
# 함수역할: 시간대 완료를 만든 모든 라우트에서 응답 본문을 만든 뒤 요청 세션의 트랜잭션이 끝나 있고,
#   응답 이후 보호자 푸시가 전송되는 시점에도 요청 세션이 연결을 잡고 있지 않은지 검증한다.
# 매개변수: tmp_path: 연결을 세션별로 분리할 파일 DB 위치, route: 검증할 라우트 이름.
# 반환값: 없음; 불일치 시 단언 실패.
@pytest.mark.parametrize("route", [
    "slot_status", "medication_status", "dose_sync", "dose_sync_with_chat", "chat_medication_taken",
])
def test_completion_push_is_sent_without_an_open_request_transaction(tmp_path, route):
    from unittest.mock import AsyncMock
    from fastapi.encoders import jsonable_encoder
    from api import chat_router, route_support, router as medication_router
    from support.db import make_engine, make_session_factory
    from support.fakes import RecordingPushBoundary

    engine = make_engine(tmp_path)
    factory = make_session_factory(engine)
    try:
        link_id, medication_id = _seed_completion_push(factory)

        with factory() as request_db:
            open_at_send: list[bool] = []
            push = RecordingPushBoundary(
                on_send=lambda _call: open_at_send.append(request_db.in_transaction()))
            with patch.object(route_support, "SessionLocal", factory), \
                 patch.object(route_support, "get_push_notification_boundary", return_value=push), \
                 patch.object(medication_router, "enforce_chat_daily_quota", AsyncMock()), \
                 patch.object(chat_router, "enforce_chat_daily_quota", AsyncMock()):
                response = _run_dose_route(route, request_db, medication_id, link_id)

            # 응답은 요청 세션을 다시 읽지 않고도 직렬화할 수 있는 값으로만 이루어져야 한다.
            jsonable_encoder(response)
            schedules = response["schedules"] if route == "chat_medication_taken" else response["data"]
            schedule = schedules[0] if isinstance(schedules, list) else schedules
            assert schedule["slot_statuses"]["morning"] is True
            assert not request_db.in_transaction()
            assert len(push.calls) == 1, push.calls
            assert push.calls[0]["data"]["type"] == "caregiver_slot_completed"
            assert open_at_send == [False]
    finally:
        engine.dispose()


# 함수이름: test_dose_sync_over_http_uses_one_request_session_released_before_the_push
# 함수역할: 실제 라우터와 의존성으로 복용 동기화를 요청해, 요청 하나가 세션 하나만 쓰고(동기화 Control과
#   일정 Control이 같은 세션을 공유), 응답 이후 푸시가 나가는 동안 그 세션이 트랜잭션 없이 열려 있다가
#   푸시가 끝난 뒤에 닫히는지 검증한다.
# 매개변수: tmp_path: 연결을 세션별로 분리할 파일 DB 위치. 반환값: 없음; 불일치 시 단언 실패.
def test_dose_sync_over_http_uses_one_request_session_released_before_the_push(tmp_path):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient
    from api import route_support
    from api.dependencies import get_authenticated_principal, get_registered_principal
    from api.router import router
    from core.database import get_db
    from entities.authenticated_principal_entity import AuthenticatedPrincipal
    from support.db import make_engine, make_session_factory
    from support.fakes import RecordingPushBoundary

    engine = make_engine(tmp_path)
    factory = make_session_factory(engine)
    try:
        _, medication_id = _seed_completion_push(factory)
        request_sessions = []
        timeline = []

        # 함수이름: request_db
        # 함수역할: get_db처럼 요청 세션을 제공하고, 세션을 연 시점과 닫는 시점을 기록한다.
        # 매개변수: 없음. 반환값: 요청 세션을 내주는 제너레이터.
        def request_db():
            db = factory()
            request_sessions.append(db)
            try:
                yield db
            finally:
                timeline.append("request session closed")
                db.close()

        # 함수이름: record_send
        # 함수역할: 푸시 전송 시점에 요청 세션이 트랜잭션을 잡고 있는지 기록한다.
        # 매개변수: _call: 기록된 푸시 요청. 반환값: 없음.
        def record_send(_call):
            timeline.append(
                "push sent with open transaction" if request_sessions[0].in_transaction()
                else "push sent")

        push = RecordingPushBoundary(on_send=record_send)
        app = FastAPI()
        app.include_router(router, prefix="/api/v1/medication")
        app.dependency_overrides[get_db] = request_db
        app.dependency_overrides[get_registered_principal] = lambda: None
        app.dependency_overrides[get_authenticated_principal] = lambda: AuthenticatedPrincipal(
            subject="patient", issuer="test", user_hash="patient-a")
        body = {
            "operation_id": "offline_dose_0001", "schedule_date": application_today().isoformat(),
            "slot_key": "morning", "medication_ids": [medication_id], "completed": True,
        }
        with patch.object(route_support, "SessionLocal", factory), \
             patch.object(route_support, "get_push_notification_boundary", return_value=push), \
             TestClient(app) as client:
            response = client.post("/api/v1/medication/schedule/completion-operations", json=body)

        assert response.status_code == 200, response.text
        assert response.json()["data"][0]["slot_statuses"]["morning"] is True
        assert len(request_sessions) == 1
        assert timeline == ["push sent", "request session closed"]
    finally:
        engine.dispose()


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
