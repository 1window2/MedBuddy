# 파일명: test_medication_history_chat_share_locking.py
# 역할: 이력 공유와 연동 해제·계정 삭제의 잠금 순서 및 실패 시 원자성을 검증한다.

"""이력 공유와 연동 해제·계정 삭제가 같은 잠금 순서로 직렬화되는지 검증한다."""

from collections.abc import Iterable, Iterator
from datetime import date
from pathlib import Path
from threading import Event, Thread
from unittest.mock import Mock

import pytest
from fastapi import HTTPException
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session, sessionmaker

from controls import manage_linked_chat_control
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.manage_account_control import ManageAccount
from controls.manage_linked_chat_control import ChatSendResult, ManageLinkedChat
from controls.manage_medication_care_control import ManageMedicationCare
from core.account_database_lock import ACCOUNT_BUSY_DETAIL, lock_account_operations
from core.application_clock import application_today
from entities.chat_message_entity import _ChatMessage
from entities.chat_notification_job_entity import ChatNotificationJob
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.user_account_entity import _UserAccount, utc_now
from support.db import make_engine, make_session_factory, seed_account


# 함수이름: scene
# 함수역할:
# - 파일 데이터베이스에 활성 연동을 만들고 여러 세션에서 경합을 재현한 뒤 엔진을 정리한다.
# 매개변수:
# - tmp_path: Path; 테스트 전용 임시 디렉터리.
# 반환값:
# - Iterator[tuple]; 세션 팩터리와 연동 ID.
@pytest.fixture
def scene(tmp_path: Path) -> Iterator[tuple[sessionmaker[Session], int]]:
    engine = make_engine(tmp_path)
    factory = make_session_factory(engine)
    with factory() as db:
        seed_account(db, "patient-a", "caregiver-a")
        link = _PatientCaregiverLink(patient_hash="patient-a", caregiver_hash="caregiver-a", linked=True)
        db.add(link)
        db.commit()
        link_id = link.id
    try:
        yield factory, link_id
    finally:
        engine.dispose()


# 함수이름: send_history
# 함수역할:
# - 보호자가 당일 이력을 고정 요청 ID로 공유하도록 실제 저장 컨트롤을 호출한다.
# 매개변수:
# - db: Session; 공유 또는 철회 작업 세션.
# - link_id: int; 활성 연동 ID.
# 반환값:
# - 채팅 전송 결과; 계정·잠금 오류는 전파.
def send_history(db: Session, link_id: int) -> ChatSendResult:
    return ManageLinkedChat(db).send_message(
        link_id=link_id, sender_hash="caregiver-a", client_message_id="history_lock_001",
        body="복약 기록을 공유해요.", message_kind="medication_history_share",
        history_start_date=application_today(), history_end_date=application_today(),
    )


# 함수이름: revoke
# 함수역할:
# - 선택 계정의 연동 해제·전체 삭제 또는 삭제 요청 표시를 수행한다.
# 매개변수:
# - db: Session; 공유 또는 철회 작업 세션.
# - link_id: int; 활성 연동 ID.
# - actor: str; 환자 또는 보호자 식별자.
# - action: str; unlink·delete·tombstone 중 철회 방식.
# 반환값:
# - None.
def revoke(db: Session, link_id: int, actor: str, action: str) -> None:
    if action == "unlink":
        LinkPatientCaregiver(db).requestUnlink(link_id, actor)
    elif action == "delete":
        ManageAccount(db).deleteAccountData(actor)
    else:
        db.get(_UserAccount, actor).deletion_requested_at = utc_now()
        db.commit()


# 함수이름: test_revocation_after_preflight_is_rechecked_before_snapshot
# 함수역할:
# - 초기 조회 후 잠금 전 연동 해제·삭제가 완료되면 집계를 읽지 않고 404·410으로 거부하며 메시지·알림을 남기지 않는지 확인한다.
# 매개변수:
# - scene: tuple[sessionmaker, int]; 파일 DB 세션 팩터리와 연동 ID.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# - actor: str; 환자 또는 보호자 식별자.
# - action: str; unlink·delete·tombstone 중 철회 방식.
# 반환값:
# - None.
@pytest.mark.parametrize("actor", ["patient-a", "caregiver-a"])
@pytest.mark.parametrize("action", ["unlink", "delete", "tombstone"])
def test_revocation_after_preflight_is_rechecked_before_snapshot(scene: tuple[sessionmaker[Session], int], monkeypatch: pytest.MonkeyPatch, actor: str, action: str) -> None:
    """초기 연동 조회가 성공해도 잠금 전 해제·삭제가 완료되면 공유를 만들지 않는다."""
    factory, link_id = scene
    calls = []

    # 함수이름: lock_after_revocation
    # 함수역할:
    # - 정렬할 계정과 해제된 트랜잭션을 확인한 뒤 별도 세션에서 철회를 완료하고 원래 잠금을 획득한다.
    # 매개변수:
    # - db: Session; 공유 또는 철회 작업 세션.
    # - participants: Iterable[str]; 잠금 대상 양측 계정.
    # 반환값:
    # - None.
    def lock_after_revocation(db: Session, participants: Iterable[str]) -> None:
        assert not db.in_transaction()
        assert set(participants) == {"patient-a", "caregiver-a"}
        calls.append(participants)
        with factory() as other:
            lock_account_operations(other, [actor])
            revoke(other, link_id, actor, action)
        lock_account_operations(db, participants)

    lookup = Mock(side_effect=AssertionError("Revoked history must not be read"))
    monkeypatch.setattr(manage_linked_chat_control, "lock_account_operations", lock_after_revocation)
    monkeypatch.setattr(ManageMedicationCare, "history_share_context", lookup)
    with factory() as db:
        # 인증 단계에서 이미 가진 단일 계정 잠금도 재정렬 전에 반환해야 한다.
        lock_account_operations(db, ["caregiver-a"])
        with pytest.raises(HTTPException) as caught:
            send_history(db, link_id)
        assert caught.value.status_code == (404 if action == "unlink" else 410)
        assert len(calls) == 1 and not db.in_transaction()
        assert db.query(_ChatMessage).count() == 0
        assert db.query(ChatNotificationJob).count() == 0
    lookup.assert_not_called()


# 함수이름: test_revocation_waits_for_snapshot_commit_then_removes_message
# 함수역할:
# - 공유가 잠금을 먼저 잡으면 철회 작업은 커밋까지 기다린 뒤 메시지와 알림을 함께 제거하는지 확인한다.
# 매개변수:
# - scene: tuple[sessionmaker, int]; 파일 DB 세션 팩터리와 연동 ID.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# - actor: str; 환자 또는 보호자 식별자.
# - action: str; unlink·delete·tombstone 중 철회 방식.
# 반환값:
# - None.
@pytest.mark.parametrize("actor", ["patient-a", "caregiver-a"])
@pytest.mark.parametrize("action", ["unlink", "delete"])
def test_revocation_waits_for_snapshot_commit_then_removes_message(scene: tuple[sessionmaker[Session], int], monkeypatch: pytest.MonkeyPatch, actor: str, action: str) -> None:
    """공유가 먼저 잠그면 해제·삭제가 커밋까지 기다린 뒤 메시지와 알림을 함께 제거한다."""
    factory, link_id = scene
    reading = Event()
    attempted = Event()
    acquired = Event()
    failures = []
    original = ManageMedicationCare.history_share_context

    # 함수이름: snapshot_while_locked
    # 함수역할:
    # - 철회 스레드가 잠금을 기다리는 동안 원래 이력 집계를 실행하여 공유 잠금의 유지를 확인한다.
    # 매개변수:
    # - args: tuple; 원래 이력 집계 함수에 전달할 인수.
    # 반환값:
    # - dict; 원래 함수가 생성한 이력 집계 문맥.
    def snapshot_while_locked(self, *args: str | date) -> dict[str, object]:
        reading.set()
        assert attempted.wait(3)
        assert not acquired.wait(0.1)
        return original(self, *args)

    # 함수이름: mutation
    # 함수역할:
    # - 집계 시작 신호 뒤 계정 잠금을 획득해 철회하고 작업 오류는 공유 목록에 기록한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - None.
    def mutation() -> None:
        try:
            assert reading.wait(3)
            with factory() as db:
                attempted.set()
                lock_account_operations(db, [actor])
                acquired.set()
                revoke(db, link_id, actor, action)
        except BaseException as exc:
            failures.append(exc)

    monkeypatch.setattr(ManageMedicationCare, "history_share_context", snapshot_while_locked)
    worker = Thread(target=mutation, daemon=True)
    worker.start()
    try:
        with factory() as db:
            sent = send_history(db, link_id)
            assert sent.created and sent.message.context_payload["history_context"]["taken_count"] == 0
    finally:
        worker.join(8)
    assert not worker.is_alive() and not failures and acquired.is_set()
    with factory() as db:
        assert db.query(_ChatMessage).count() == 0
        assert db.query(ChatNotificationJob).count() == 0


# 함수이름: test_lock_timeout_is_retryable_without_partial_snapshot
# 함수역할:
# - 잠금 시간 초과는 Retry-After가 있는 503으로 반환하고 미완료 트랜잭션·메시지는 남기지 않는지 확인한다.
# 매개변수:
# - scene: tuple[sessionmaker, int]; 파일 DB 세션 팩터리와 연동 ID.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
def test_lock_timeout_is_retryable_without_partial_snapshot(scene: tuple[sessionmaker[Session], int], monkeypatch: pytest.MonkeyPatch) -> None:
    factory, link_id = scene
    monkeypatch.setattr(manage_linked_chat_control, "lock_account_operations", Mock(
        side_effect=OperationalError("lock", {}, Exception("timeout")),
    ))
    with factory() as db:
        with pytest.raises(HTTPException) as caught:
            send_history(db, link_id)
        assert caught.value.status_code == 503
        assert caught.value.detail == ACCOUNT_BUSY_DETAIL
        assert caught.value.headers == {"Retry-After": "5"}
        assert not db.in_transaction()
        assert db.query(_ChatMessage).count() == 0
