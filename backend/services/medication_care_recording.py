# 파일명: medication_care_recording.py
# 역할: 기존 완료 API와 날짜별 정정 API의 복용 기록·감사 이력을 일관되게 저장한다.

from datetime import UTC, datetime
import json

from sqlalchemy.orm import Session

from entities.medication_care_entity import _MedicationCareAudit
from entities.medication_completion_entity import _MedicationCompletion
from entities.user_account_entity import utc_now


# 함수이름: iso_utc
# 함수역할: DB의 UTC naive 시각을 명시적인 UTC ISO 문자열로 응답한다.
# 매개변수: value: DB 시각. 반환값: ISO 문자열 또는 None.
def iso_utc(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.replace(tzinfo=UTC).isoformat() if value.tzinfo is None else value.astimezone(UTC).isoformat()


# 함수이름: completion_snapshot
# 함수역할: 이전 완료 행도 같은 사용자 보고 형식으로 변환한다. 실제 복용 시각은 추측하지 않는다.
# 매개변수: row: 기록 행. 반환값: JSON 호환 상태 스냅샷.
def completion_snapshot(row: _MedicationCompletion) -> dict[str, object]:
    return {
        "medication_id": row.saved_medication_id,
        "schedule_date": row.schedule_date.isoformat(),
        "slot_key": row.slot_key,
        "status": row.report_status or ("taken" if row.completed else "unrecorded"),
        "actual_taken_at": iso_utc(row.actual_taken_at),
        "recorded_at": iso_utc(row.recorded_at or row.completed_at),
        "reason": row.reason or "",
        "revision": row.revision or 0,
    }


# 함수이름: apply_completion_report
# 함수역할: 상태 변경과 이전·이후 감사 스냅샷을 호출자의 트랜잭션에 추가한다.
# 매개변수: db: 세션, row: 기록, status: 상태, actual_taken_at: 실제 시각, reason: 이유, source: 경로.
# 반환값: 없음. 호출자가 commit/rollback한다.
def apply_completion_report(
    db: Session, row: _MedicationCompletion, *, status: str,
    actual_taken_at: datetime | None = None, reason: str = "", source: str = "history",
    audit_rows: list[dict[str, object]] | None = None,
) -> None:
    before = completion_snapshot(row)
    now = utc_now()
    row.report_status = status
    row.completed = status == "taken"
    row.completed_at = now if row.completed else None
    row.actual_taken_at = (
        actual_taken_at.replace(tzinfo=UTC).replace(tzinfo=None)
        if actual_taken_at is not None and actual_taken_at.tzinfo is None
        else actual_taken_at.astimezone(UTC).replace(tzinfo=None) if actual_taken_at else None
    )
    row.recorded_at = now
    row.reason = reason
    row.revision = (row.revision or 0) + 1
    audit = {
        "patient_hash": row.patient_hash, "medication_id": row.saved_medication_id,
        "kind": source, "before_json": json.dumps(before, ensure_ascii=False),
        "after_json": json.dumps(completion_snapshot(row), ensure_ascii=False), "recorded_at": now,
    }
    if audit_rows is None:
        db.add(_MedicationCareAudit(**audit))
    else:
        audit_rows.append(audit)
