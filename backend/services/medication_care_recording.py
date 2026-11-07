# 파일명: medication_care_recording.py
# 역할: 기존 완료 API와 날짜별 정정 API의 복용 기록·감사 이력을 일관되게 저장한다.

from datetime import datetime
import json

from sqlalchemy.orm import Session

from entities.medication_care_entity import _MedicationCareAudit
from entities.medication_completion_entity import _MedicationCompletion
from entities.user_account_entity import as_naive_utc, utc_isoformat, utc_now


# Function Name: completion_snapshot
# Description: Converts legacy and current rows to the same JSON-compatible report, retaining unknown actual intake time.
# Parameters: row (_MedicationCompletion) is the persisted or in-memory completion record.
# Returns: Dict with dose identity, report status, UTC timestamps, reason and revision; legacy completed flags supply missing report status.
def completion_snapshot(row: _MedicationCompletion) -> dict[str, object]:
    return {
        "medication_id": row.saved_medication_id,
        "schedule_date": row.schedule_date.isoformat(),
        "slot_key": row.slot_key,
        "status": row.report_status or ("taken" if row.completed else "unrecorded"),
        "actual_taken_at": utc_isoformat(row.actual_taken_at),
        "recorded_at": utc_isoformat(row.recorded_at or row.completed_at),
        "reason": row.reason or "",
        "revision": row.revision or 0,
    }


# Function Name: apply_completion_report
# Description: Captures the prior state, applies the caller-validated report, increments revision and records before/after audit data in the same transaction.
# Parameters: db (Session), row (_MedicationCompletion) select the transaction/record; status (str), actual_taken_at (datetime | None), reason and source (str) describe the report;
#   audit_rows (list[dict] | None) receives mappings for bulk insertion instead of adding an ORM audit row immediately.
# Returns: None; never commits. The caller owns validation and commit/rollback.
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
        as_naive_utc(actual_taken_at) if actual_taken_at is not None else None
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
