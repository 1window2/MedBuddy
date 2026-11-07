# 파일명: test_delayed_action_regressions.py
# 역할: 삭제·재연동·토큰 재등록 뒤 지연된 요청이 새 리소스를 변경하지 못하도록 검증한다.

from pathlib import Path
from sqlite3 import Cursor
from typing import Any
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException
from sqlalchemy import event
from sqlalchemy.engine import Connection, ExecutionContext
from sqlalchemy.orm import Session, sessionmaker

from controls.check_saved_medication_control import CheckSavedMedication
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.manage_linked_chat_control import ManageLinkedChat
from controls.manage_push_token_control import ManagePushToken
from controls.process_chat_notifications_control import ProcessChatNotifications
from controls.sync_dose_control import SyncDose
from core.application_clock import application_today
from entities.chat_message_entity import _ChatMessage
from entities.chat_notification_job_entity import ChatNotificationJob
from entities.device_push_token_entity import _DevicePushToken
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.saved_medication_entity import _SavedMedication
from schemas.dose_sync import DoseSyncRequest
from services.push_recipient_resolver import PushRecipientResolver
from support.db import make_engine, make_session_factory, seed_account, seed_medication


# 함수이름: test_deleted_medication_request_cannot_target_new_medication
# 함수역할:
# - 삭제된 약품의 늦은 삭제·완료 요청은 오류로 끝나고 새 약품의 존재와 미복용 상태를 보존하는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# - action: str; 오래된 삭제 또는 완료 요청.
# 반환값:
# - None.
@pytest.mark.parametrize("action", ["delete", "complete"])
def test_deleted_medication_request_cannot_target_new_medication(fk_db: Session, action: str) -> None:
    old = seed_medication(fk_db, daily_frequency="1", schedule_slot_keys='["morning"]')
    old_id = old.id
    CheckSavedMedication(fk_db).requestDelete(old_id, "patient-a")
    new = seed_medication(fk_db, item_name="new-tablet", daily_frequency="1", schedule_slot_keys='["morning"]')
    new_id = new.id

    with pytest.raises(HTTPException) as error:
        if action == "delete":
            CheckSavedMedication(fk_db).requestDelete(old_id, "patient-a")
        else:
            SyncDose(fk_db).apply("patient-a", DoseSyncRequest(
                operation_id="delayed_old_dose", schedule_date=application_today(),
                slot_key="morning", medication_ids=[old_id], completed=True,
            ))
    assert error.value.status_code in {404, 409}
    fk_db.rollback()
    assert fk_db.get(_SavedMedication, new_id) is not None
    assert not fk_db.get(_SavedMedication, new_id).medication_status


# 함수이름: seed_link
# 함수역할:
# - 환자·보호자 계정과 활성 연동을 저장한다.
# 매개변수:
# - db: Session; 격리 계정·채팅 세션.
# 반환값:
# - int; 생성된 연동 ID.
def seed_link(db: Session) -> int:
    seed_account(db, "patient-a", "caregiver-a")
    link = _PatientCaregiverLink(patient_hash="patient-a", caregiver_hash="caregiver-a", linked=True)
    db.add(link)
    db.commit()
    return link.id


# 함수이름: send
# 함수역할:
# - 주어진 요청 키와 본문으로 환자 메시지를 저장한다.
# 매개변수:
# - db: Session; 격리 계정·채팅 세션.
# - link_id: int; 환자·보호자 연동 ID.
# - key: str; 메시지 요청 ID와 본문.
# 반환값:
# - int; 저장된 메시지 ID.
def send(db: Session, link_id: int, key: str) -> int:
    return ManageLinkedChat(db).send_message(
        link_id=link_id, sender_hash="patient-a", client_message_id=key, body=key,
    ).message.message_id


# 함수이름: relink
# 함수역할:
# - 연동을 해제한 뒤 다시 등록하여 기존 연동 ID가 유지되는지 확인한다.
# 매개변수:
# - db: Session; 격리 계정·채팅 세션.
# - link_id: int; 환자·보호자 연동 ID.
# 반환값:
# - None.
def relink(db: Session, link_id: int) -> None:
    control = LinkPatientCaregiver(db)
    control.requestUnlink(link_id, "patient-a")
    code = control.generatePatientHash("patient-a")["data"]["patient_code"]
    assert control.requestPatientCaregiverLink("caregiver-a", code)["data"]["id"] == link_id


# 함수이름: test_delayed_message_delete_after_relink_cannot_erase_new_message
# 함수역할:
# - 재연동 후 오래된 메시지 삭제 요청은 404로 거부하여 새 메시지를 지우지 않는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# 반환값:
# - None.
def test_delayed_message_delete_after_relink_cannot_erase_new_message(fk_db: Session) -> None:
    link_id = seed_link(fk_db)
    old_id = send(fk_db, link_id, "before_unlink")
    relink(fk_db, link_id)
    new_id = send(fk_db, link_id, "after_relink")
    with pytest.raises(HTTPException) as error:
        ManageLinkedChat(fk_db).delete_messages(
            link_id=link_id, user_hash="patient-a", message_ids=[old_id], scope="everyone",
        )
    assert error.value.status_code == 404
    assert fk_db.get(_ChatMessage, new_id).body == "after_relink"


# 함수이름: test_old_chat_worker_cannot_finish_replacement_message
# 함수역할:
# - 해제 전 알림 작업의 늦은 완료가 재연동 후 새 메시지 작업을 완료 처리하지 않는지 확인한다.
# 매개변수:
# - fk_session_factory: sessionmaker; 격리 데이터베이스의 세션을 생성한다.
# 반환값:
# - None.
def test_old_chat_worker_cannot_finish_replacement_message(fk_session_factory: sessionmaker[Session]) -> None:
    processor = ProcessChatNotifications(fk_session_factory, lambda: None, AsyncMock(), AsyncMock())
    with fk_session_factory() as db:
        link_id = seed_link(db)
        send(db, link_id, "before_unlink")
        old_claim = processor.claim()
        assert old_claim is not None
        relink(db, link_id)
        new_id = send(db, link_id, "after_relink")
        new_claim = processor.claim()
        assert new_claim is not None
        processor.finish(old_claim, "completed")
        assert db.get(ChatNotificationJob, new_id).status == "processing"


# 함수이름: test_late_push_rejection_preserves_new_registration
# 함수역할:
# - 푸시 실패 응답이 늦게 도착해도 그 사이 이전·갱신된 토큰 등록은 비활성화하지 않는지 확인한다.
# 매개변수:
# - tmp_path: Path; 테스트 전용 임시 디렉터리.
# - registration: str; 다른 소유자·동일 소유자·왕복 이전 재등록 조건.
# 반환값:
# - None.
@pytest.mark.parametrize("registration", ["other_owner", "same_owner", "round_trip"])
def test_late_push_rejection_preserves_new_registration(tmp_path: Path, registration: str) -> None:
    engine = make_engine(tmp_path)
    factory = make_session_factory(engine)
    token = "synthetic-delayed-response-token-12345"
    try:
        with factory() as db:
            seed_account(db, "patient-a", "patient-b")
            ManagePushToken(db).registerPushToken("patient-a", token, "android")
            resolver = PushRecipientResolver(db)
            assert resolver.resolve("patient-a").tokens == (token,)
            db.rollback()
            with factory() as other:
                control = ManagePushToken(other)
                if registration in {"other_owner", "round_trip"}:
                    control.registerPushToken("patient-b", token, "android")
                if registration in {"same_owner", "round_trip"}:
                    control.registerPushToken("patient-a", token, "android")
            resolver.disable_invalid((token,))
        with factory() as observer:
            row = observer.query(_DevicePushToken).one()
            assert row.enabled
            assert row.user_hash == ("patient-b" if registration == "other_owner" else "patient-a")
    finally:
        engine.dispose()


# 함수이름: test_push_rejection_disables_only_the_observed_registration
# 함수역할:
# - 실제로 조회한 등록만 무효화하고 응답에 섞인 미조회 다른 계정 토큰은 보존하는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# 반환값:
# - None.
def test_push_rejection_disables_only_the_observed_registration(fk_db: Session) -> None:
    seed_account(fk_db, "patient-a", "patient-b")
    control = ManagePushToken(fk_db)
    control.registerPushToken("patient-a", "observed-token-1234567890", "android")
    control.registerPushToken("patient-b", "unobserved-token-1234567890", "android")
    resolver = PushRecipientResolver(fk_db)
    resolver.resolve("patient-a")
    fk_db.rollback()
    resolver.disable_invalid(("observed-token-1234567890", "unobserved-token-1234567890"))
    states = {row.user_hash: row.enabled for row in fk_db.query(_DevicePushToken)}
    assert states == {"patient-a": False, "patient-b": True}


# 함수이름: test_same_owner_reregistration_with_equal_persisted_timestamp_is_preserved
# 함수역할:
# - 재등록 전후 저장 시각이 같아도 등록 버전으로 새 등록을 구분해 보존하는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# 반환값:
# - None.
def test_same_owner_reregistration_with_equal_persisted_timestamp_is_preserved(fk_db: Session) -> None:
    seed_account(fk_db, "patient-a")
    token = "same-timestamp-registration-token-123"
    control = ManagePushToken(fk_db)
    control.registerPushToken("patient-a", token, "android")
    timestamp = fk_db.query(_DevicePushToken).one().updated_at
    resolver = PushRecipientResolver(fk_db)
    resolver.resolve("patient-a")
    fk_db.rollback()
    control.registerPushToken("patient-a", token, "android")
    # 시계 해상도나 DB 반올림으로 두 등록 시각이 같아지는 상황을 재현한다.
    fk_db.query(_DevicePushToken).update({"updated_at": timestamp})
    fk_db.commit()
    resolver.disable_invalid((token,))
    fk_db.expire_all()
    assert fk_db.query(_DevicePushToken).one().enabled


# 함수이름: test_push_cleanup_rechecks_registration_in_the_update
# 함수역할:
# - 조회 후 UPDATE 직전에 토큰이 갱신되면 원자적 갱신 조건으로 비활성화를 막는지 확인한다.
# 매개변수:
# - tmp_path: Path; 테스트 전용 임시 디렉터리.
# 반환값:
# - None.
def test_push_cleanup_rechecks_registration_in_the_update(tmp_path: Path) -> None:
    engine = make_engine(tmp_path)
    factory = make_session_factory(engine)
    token = "atomic-cleanup-registration-token-123"
    renewed = False
    try:
        with factory() as db:
            seed_account(db, "patient-a")
            ManagePushToken(db).registerPushToken("patient-a", token, "android")
            resolver = PushRecipientResolver(db)
            resolver.resolve("patient-a")
            db.rollback()

            # 함수이름: renew_before_update
            # 함수역할:
            # - 최초 토큰 비활성화 UPDATE 직전에 별도 세션에서 재등록을 완료해 경합을 만든다.
            # 매개변수:
            # - connection: Connection; SQL 실행 연결(사용하지 않음).
            # - cursor: Cursor; SQL 커서(사용하지 않음).
            # - statement: str; 토큰 비활성화 UPDATE인지 검사할 SQL.
            # - parameters: object; SQL 인수(사용하지 않음).
            # - context: ExecutionContext; 실행 문맥(사용하지 않음).
            # - executemany: bool; 다중 실행 여부(사용하지 않음).
            # 반환값:
            # - None.
            def renew_before_update(
                connection: Connection, cursor: Cursor, statement: str,
                parameters: tuple[Any, ...] | list[tuple[Any, ...]], context: ExecutionContext, executemany: bool,
            ) -> None:
                nonlocal renewed
                if not renewed and statement.startswith("UPDATE device_push_tokens SET enabled="):
                    renewed = True
                    with factory() as registration_db:
                        ManagePushToken(registration_db).registerPushToken("patient-a", token, "android")

            event.listen(engine, "before_cursor_execute", renew_before_update)
            try:
                resolver.disable_invalid((token,))
            finally:
                event.remove(engine, "before_cursor_execute", renew_before_update)
        assert renewed
        with factory() as observer:
            assert observer.query(_DevicePushToken).one().enabled
    finally:
        engine.dispose()
