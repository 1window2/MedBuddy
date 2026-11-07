# File Name: check_today_medication_info_control.py
# Role: Aggregates today's medication schedules into dose counts, completion progress and remaining doses.

from typing import Any

from sqlalchemy.orm import Session

from controls.check_schedule_control import CheckSchedule
from entities.patient_hash_entity import normalize_patient_hash


# Class Name: CheckTodayMedicationInfo
# Role:
# - Builds today's medication summary from the schedule entity flow.
# Responsibilities:
# - Read one patient's medication schedule through CheckSchedule.
# - Reuse today's MedicationSchedule DTOs instead of creating a second schedule source.
# - Return dose-level progress counts for MainUI/TodayMedicationUI summaries.
# Attributes:
# - db (Session): SQLAlchemy session used by delegated schedule control.
class CheckTodayMedicationInfo:
    # Function Name: __init__
    # Description:
    # - Binds today's summary to the shared schedule control and database session.
    # Parameters:
    # - db (Session): SQLAlchemy session for this unit of work.
    # - check_schedule (CheckSchedule | None): Control for medication courses and per-dose completion.
    # Returns:
    # - None.
    def __init__(
        self,
        db: Session,
        check_schedule: CheckSchedule | None = None,
    ) -> None:
        self.db = db
        self.check_schedule = check_schedule or CheckSchedule(db)

    # 함수이름: requestTodayMedicationInfo
    # 함수역할: 정규화한 환자의 오늘 일정을 조회하고 복용 진행률 요약을 구성한다.
    # 매개변수: patient_hash (str | None)는 조회할 환자 범위이다.
    # 반환값: dict[str, object] 일정·약품 수·복용 횟수 요약. 범위 검증과 조회 오류는 전파한다.
    def requestTodayMedicationInfo(
        self,
        patient_hash: str | None = None,
    ) -> dict[str, object]:
        resolved_patient_hash = normalize_patient_hash(patient_hash)
        schedule_response = self.check_schedule.requestTodayMedicationSchedule(
            resolved_patient_hash,
        )
        schedules = self._read_schedule_items(schedule_response.get("data"))
        return self._summarize(resolved_patient_hash, schedules)

    # 함수이름: requestTodayMedicationInfoForPatients
    # 함수역할: 여러 환자의 오늘 일정을 일괄 조회한 뒤 환자별 진행률을 계산한다.
    # 매개변수: patient_hashes (list[str])는 조회할 환자 식별자 목록이다.
    # 반환값: dict[str, dict[str, object]] 환자별 요약. 일괄 조회 오류는 전파한다.
    def requestTodayMedicationInfoForPatients(
        self, patient_hashes: list[str],
    ) -> dict[str, dict[str, object]]:
        schedules = self.check_schedule.requestTodayMedicationSchedulesForPatients(patient_hashes)
        return {owner: self._summarize(owner, items) for owner, items in schedules.items()}

    # 함수이름: _summarize
    # 함수역할: 전달받은 일정에서 전체·완료 복용 횟수와 남은 횟수, 진행률을 계산한다.
    # 매개변수: resolved_patient_hash (str)는 정규화된 환자 식별자, schedules (list[dict[str, Any]])는 해당 환자의 일정이다.
    # 반환값: dict[str, object] 요약 응답. 일정이 없으면 진행률은 0이고 남은 횟수는 음수가 되지 않는다.
    def _summarize(
        self, resolved_patient_hash: str, schedules: list[dict[str, Any]],
    ) -> dict[str, object]:
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

    # Function Name: _read_schedule_items
    # Description:
    # - Discards malformed schedule payloads while retaining dictionary entries.
    # Parameters:
    # - raw_items (object): Untrusted daily-schedule response data to filter.
    # Returns:
    # - Schedule dictionaries, or an empty list for non-list input.
    def _read_schedule_items(self, raw_items: object) -> list[dict[str, Any]]:
        if not isinstance(raw_items, list):
            return []
        return [item for item in raw_items if isinstance(item, dict)]

    # Function Name: _dose_count
    # Description:
    # - Counts explicit dose slots and treats a legacy schedule without slots as one dose.
    # Parameters:
    # - schedule (dict[str, Any]): Daily medication schedule including per-slot completion flags.
    # Returns:
    # - Number of planned doses represented by the schedule.
    def _dose_count(self, schedule: dict[str, Any]) -> int:
        slot_statuses = schedule.get("slot_statuses")
        if isinstance(slot_statuses, dict) and slot_statuses:
            return len(slot_statuses)
        return 1

    # Function Name: _completed_dose_count
    # Description:
    # - Counts completed dose slots, falling back to the legacy medication completion flag.
    # Parameters:
    # - schedule (dict[str, Any]): Daily medication schedule including per-slot completion flags.
    # Returns:
    # - Number of completed doses in the schedule.
    def _completed_dose_count(self, schedule: dict[str, Any]) -> int:
        slot_statuses = schedule.get("slot_statuses")
        if isinstance(slot_statuses, dict) and slot_statuses:
            return sum(1 for completed in slot_statuses.values() if bool(completed))
        return 1 if bool(schedule.get("medication_status")) else 0
