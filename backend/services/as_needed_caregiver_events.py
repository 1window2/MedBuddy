# 파일명: as_needed_caregiver_events.py
# 역할: 필요시 복용의 안정된 알림 식별자와 현재 유효 기록을 푸시·일괄 감시에 공유한다.

import hashlib
from datetime import date

from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from entities.caregiver_alert_outbox_entity import (
    CAREGIVER_ALERT_EVENT_AS_NEEDED_COMPLETED,
    _CaregiverAlertOutbox,
)
from entities.medication_completion_entity import _MedicationCompletion
from entities.saved_medication_entity import _SavedMedication


# 함수이름: as_needed_taken_event_key
# 함수역할: 수정 시각·버전에 의존하지 않는 필요시 복용 알림 식별자를 만든다.
# 매개변수: patient_hash (str)는 환자, medication_id (int)는 약, schedule_date (date)는 복용일, record_slot_key (str)는 기록 슬롯이다.
# 반환값: 네 식별 요소를 SHA-256으로 해시한 64자리 str.
def as_needed_taken_event_key(
    patient_hash: str, medication_id: int, schedule_date: date, record_slot_key: str,
) -> str:
    """시각·수정 버전과 무관한 복용 기록 식별자를 64자리 키로 만든다."""
    identity = f"as_needed:{patient_hash}:{medication_id}:{schedule_date.isoformat()}:{record_slot_key}"
    return hashlib.sha256(identity.encode("utf-8")).hexdigest()


# 함수이름: load_as_needed_taken_event_keys
# 함수역할: 삭제되지 않은 소유 약의 필요시 taken 기록을 한 번에 조회한다.
# 매개변수: db (Session)는 조회 세션, patient_hashes (list[str])는 환자 범위, schedule_date (date)는 대상 날짜다.
# 반환값: 환자별 정렬된 이벤트 키 목록. 기록이 없는 환자는 빈 목록이며 DB 오류는 전달한다.
def load_as_needed_taken_event_keys(
    db: Session, patient_hashes: list[str], schedule_date: date,
) -> dict[str, list[str]]:
    """연동 환자 전체의 해당 날짜 taken 기록만 한 쿼리로 읽고 삭제된 약은 제외한다."""
    result: dict[str, list[str]] = {owner: [] for owner in patient_hashes}
    if not patient_hashes:
        return result
    rows = db.query(
        _MedicationCompletion.patient_hash,
        _MedicationCompletion.saved_medication_id,
        _MedicationCompletion.slot_key,
    ).join(_SavedMedication, (
        (_SavedMedication.id == _MedicationCompletion.saved_medication_id)
        & (_SavedMedication.patient_hash == _MedicationCompletion.patient_hash)
    )).filter(
        _MedicationCompletion.patient_hash.in_(patient_hashes),
        _MedicationCompletion.schedule_date == schedule_date,
        _MedicationCompletion.slot_key.startswith("as_needed:", autoescape=True),
        _MedicationCompletion.completed.is_(True),
        or_(_MedicationCompletion.report_status == "taken", _MedicationCompletion.report_status.is_(None)),
    ).all()
    for row in rows:
        result[row.patient_hash].append(as_needed_taken_event_key(
            row.patient_hash, row.saved_medication_id, schedule_date, row.slot_key,
        ))
    return {owner: sorted(keys) for owner, keys in result.items()}


# 함수이름: queue_as_needed_taken_event
# 함수역할: 복용 저장 트랜잭션 안에서 고유 outbox 이벤트를 재사용하거나 savepoint로 삽입한다.
# 매개변수: db (Session)는 열린 트랜잭션, row (_MedicationCompletion)는 알림 대상 복용 기록이다.
# 반환값: 기존 또는 신규 이벤트 ID (int). 중복 삽입 경합은 재조회하고 다른 DB 오류는 전달하며 commit하지 않는다.
def queue_as_needed_taken_event(db: Session, row: _MedicationCompletion) -> int:
    """복용 저장 트랜잭션에 고유 이벤트를 추가하며 재전송·재체크는 기존 행을 유지한다."""
    key = as_needed_taken_event_key(
        row.patient_hash, row.saved_medication_id, row.schedule_date, row.slot_key,
    )
    existing = db.query(_CaregiverAlertOutbox).filter_by(event_key=key).first()
    if existing is not None:
        return int(existing.id)
    event = _CaregiverAlertOutbox(
        event_key=key, patient_hash=row.patient_hash, slot_key="as_needed",
        schedule_date=row.schedule_date, event_type=CAREGIVER_ALERT_EVENT_AS_NEEDED_COMPLETED,
    )
    try:
        with db.begin_nested():
            db.add(event)
            db.flush()
    except IntegrityError:
        event = db.query(_CaregiverAlertOutbox).filter_by(event_key=key).one()
    return int(event.id)
