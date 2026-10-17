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


def as_needed_taken_event_key(
    patient_hash: str, medication_id: int, schedule_date: date, record_slot_key: str,
) -> str:
    """시각·수정 버전과 무관한 복용 기록 식별자를 64자리 키로 만든다."""
    identity = f"as_needed:{patient_hash}:{medication_id}:{schedule_date.isoformat()}:{record_slot_key}"
    return hashlib.sha256(identity.encode("utf-8")).hexdigest()


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
