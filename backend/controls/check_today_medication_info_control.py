# File Name: check_today_medication_info_control.py
# Role: Control class mapped from CheckTodayMedicationInfo in class diagram integrated v5.

from typing import Any

from sqlalchemy.orm import Session

from controls.check_schedule_control import CheckSchedule
from entities.patient_hash_entity import normalize_patient_hash


# Class Name: CheckTodayMedicationInfo
# Role: Builds today's medication summary from the schedule entity flow.
# Responsibilities:
#   - Read one patient's medication schedule through CheckSchedule.
#   - Reuse today's MedicationSchedule DTOs instead of creating a second schedule source.
#   - Return dose-level progress counts for MainUI/TodayMedicationUI summaries.
# Attributes:
#   - db: SQLAlchemy session used by delegated schedule control.
class CheckTodayMedicationInfo:
    def __init__(
        self,
        db: Session,
        check_schedule: CheckSchedule | None = None,
    ) -> None:
        self.db = db
        self.check_schedule = check_schedule or CheckSchedule(db)

    # Function Name: requestTodayMedicationInfo
    # Description:
    # - Reads today's schedule and converts it into medication/dose progress data.
    # Parameters:
    # - patient_hash: Patient ownership key used for the summary lookup.
    # Returns:
    # - API-compatible today medication summary response dictionary.
    def requestTodayMedicationInfo(
        self,
        patient_hash: str | None = None,
    ) -> dict[str, object]:
        resolved_patient_hash = normalize_patient_hash(patient_hash)
        schedule_response = self.check_schedule.requestTodayMedicationSchedule(
            resolved_patient_hash,
        )
        schedules = self._read_schedule_items(schedule_response.get("data"))
        total_dose_count = sum(self._dose_count(schedule) for schedule in schedules)
        completed_dose_count = sum(
            self._completed_dose_count(schedule) for schedule in schedules
        )

        return {
            "success": True,
            "message": "Today medication info lookup succeeded.",
            "data": {
                "patient_hash": resolved_patient_hash,
                "medication_count": len(schedules),
                "total_dose_count": total_dose_count,
                "completed_dose_count": completed_dose_count,
                "remaining_dose_count": max(
                    total_dose_count - completed_dose_count,
                    0,
                ),
                "progress_ratio": (
                    completed_dose_count / total_dose_count
                    if total_dose_count > 0
                    else 0.0
                ),
                "schedules": schedules,
            },
        }

    def _read_schedule_items(self, raw_items: object) -> list[dict[str, Any]]:
        if not isinstance(raw_items, list):
            return []
        return [item for item in raw_items if isinstance(item, dict)]

    def _dose_count(self, schedule: dict[str, Any]) -> int:
        slot_statuses = schedule.get("slot_statuses")
        if isinstance(slot_statuses, dict) and slot_statuses:
            return len(slot_statuses)
        return 1

    def _completed_dose_count(self, schedule: dict[str, Any]) -> int:
        slot_statuses = schedule.get("slot_statuses")
        if isinstance(slot_statuses, dict) and slot_statuses:
            return sum(1 for completed in slot_statuses.values() if bool(completed))
        return 1 if bool(schedule.get("medication_status")) else 0
