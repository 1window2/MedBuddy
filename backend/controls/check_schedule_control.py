# File Name: check_schedule_control.py
# Role: Control class mapped from CheckSchedule in class diagram integrated v5.

import logging
from datetime import date

from fastapi import HTTPException
from sqlalchemy.orm import Session

from boundaries.medication_completion_event_boundary import (
    MedicationCompletionEventBoundary,
)
from core.application_clock import application_today
from entities.medication_completion_entity import (
    MedicationCompletion,
    _MedicationCompletion,
    utc_now,
)
from entities.medication_schedule_entity import (
    MedicationSchedule,
    decode_medication_schedule_slot_keys,
    medication_schedule_slot_keys_for_frequency,
)
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH, normalize_patient_hash
from entities.saved_medication_entity import _SavedMedication
from services.medication_course_policy import MedicationCoursePolicy
from services.saved_medication_retention import SavedMedicationRetentionPolicy

logger = logging.getLogger(__name__)


# Class Name: CheckSchedule
# Role: Requests and updates medication schedules.
# Responsibilities:
#   - Read today's medication schedule for one patient scope.
#   - Persist a medication completion status for one saved medication row.
# Attributes:
#   - db: SQLAlchemy session used for schedule persistence operations.
class CheckSchedule:
    def __init__(
        self,
        db: Session,
        course_policy: MedicationCoursePolicy | None = None,
        completion_event_boundary: MedicationCompletionEventBoundary | None = None,
    ) -> None:
        self.db = db
        self.course_policy = course_policy or MedicationCoursePolicy()
        self.retention_policy = SavedMedicationRetentionPolicy(self.course_policy)
        self.completion_event_boundary = completion_event_boundary

    # Function Name: requestTodayMedicationSchedule
    # Description:
    # - Reads active medication schedules for today's date.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope schedule lookup.
    # Returns:
    # - API-compatible schedule list response dictionary.
    def requestTodayMedicationSchedule(
        self,
        patient_hash: str | None = None,
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        today = application_today()
        medications = (
            self.db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == normalized_patient_hash)
            .order_by(_SavedMedication.id.asc())
            .all()
        )
        active_medications = [
            medication
            for medication in medications
            if self._is_active_today(medication, today)
        ]
        completion_rows_by_medication_id = self._completion_rows_by_medication_id(
            active_medications,
            normalized_patient_hash,
            today,
        )
        active_schedules = [
            self._to_schedule_dict(
                medication,
                today,
                completion_rows_by_medication_id.get(int(medication.id), []),
            )
            for medication in active_medications
        ]
        return {
            "success": True,
            "message": "Today medication schedule lookup succeeded.",
            "data": active_schedules,
        }

    # Function Name: updateMedicationStatus
    # Description:
    # - Persists the medication completion status for one saved medication row.
    # Parameters:
    # - medication_id: Saved medication primary key.
    # - medication_status: New medication completion status.
    # - patient_hash: Patient ownership key used to scope update.
    # - slot_key: Optional time-slot key. Empty means all schedule slots.
    # Returns:
    # - API-compatible status update response dictionary.
    def updateMedicationStatus(
        self,
        medication_id: int,
        medication_status: bool,
        patient_hash: str | None = None,
        slot_key: str | None = None,
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        medication = self._get_existing_medication(
            medication_id,
            normalized_patient_hash,
        )
        today = application_today()
        slot_keys = self._slot_keys_for_medication(medication)
        target_slot_keys = self._slot_keys_for_update(slot_key, slot_keys)
        previous_slot_completion_states = self._slot_completion_states_for_patient(
            normalized_patient_hash,
            today,
            target_slot_keys,
        )

        try:
            if (slot_key or "").strip() and self._is_legacy_completed_on(
                medication,
                today,
            ):
                self._materialize_missing_completion_slots(
                    medication,
                    normalized_patient_hash,
                    today,
                    self._slot_statuses_for_medication(medication, today),
                )
                self.db.flush()
            for target_slot_key in target_slot_keys:
                self._upsert_completion(
                    medication,
                    normalized_patient_hash,
                    today,
                    target_slot_key,
                    medication_status,
                )
            self.db.flush()
            slot_statuses = self._slot_statuses_for_medication(medication, today)
            medication.medication_status = self._all_slots_completed(slot_statuses)
            medication.medication_status_date = today
            self.db.commit()
            self.db.refresh(medication)
        except Exception as exc:
            self.db.rollback()
            logger.error(
                "Medication completion status update failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Medication status could not be updated.",
            ) from exc

        current_slot_completion_states = self._slot_completion_states_for_patient(
            normalized_patient_hash,
            today,
            target_slot_keys,
        )
        self._dispatch_new_slot_completion_events(
            patient_hash=normalized_patient_hash,
            target_slot_keys=target_slot_keys,
            previous_slot_completion_states=previous_slot_completion_states,
            current_slot_completion_states=current_slot_completion_states,
        )
        return {
            "success": True,
            "message": "Medication status was updated.",
            "data": self._to_schedule_dict(medication, today),
        }

    # 함수명: _dispatch_new_slot_completion_events
    # 역할:
    # - 해당 시간대의 모든 약이 미완료에서 완료로 바뀐 경우만 후속 처리기에 전달한다.
    # - 알림 장애가 환자의 복약 체크 저장을 되돌리지 않도록 예외를 격리한다.
    # 매개변수:
    # - patient_hash: 환자 소유권 hash
    # - target_slot_keys: 이번 요청에서 변경한 시간대 목록
    # - previous_slot_completion_states: 변경 전 시간대별 전체 완료 상태
    # - current_slot_completion_states: 변경 후 시간대별 전체 완료 상태
    # 반환값:
    # - 없음
    def _dispatch_new_slot_completion_events(
        self,
        *,
        patient_hash: str,
        target_slot_keys: list[str],
        previous_slot_completion_states: dict[str, bool],
        current_slot_completion_states: dict[str, bool],
    ) -> None:
        if self.completion_event_boundary is None:
            return
        for target_slot_key in target_slot_keys:
            was_completed = previous_slot_completion_states.get(
                target_slot_key,
                False,
            )
            is_completed = current_slot_completion_states.get(
                target_slot_key,
                False,
            )
            if was_completed or not is_completed:
                continue
            try:
                self.completion_event_boundary.notifySlotCompleted(
                    patient_hash=patient_hash,
                    slot_key=target_slot_key,
                )
            except Exception as exc:
                logger.warning(
                    "Caregiver push dispatch failed after medication commit: %s",
                    type(exc).__name__,
                )

    # 함수명: _slot_completion_states_for_patient
    # 역할:
    # - 환자의 오늘 활성 약을 기준으로 각 시간대가 모두 완료되었는지 계산한다.
    # - 대상 약이 하나도 없는 시간대는 완료로 간주하지 않는다.
    # 매개변수:
    # - patient_hash: 환자 소유권 hash
    # - schedule_date: 완료 상태를 확인할 날짜
    # - slot_keys: 확인할 복약 시간대 목록
    # 반환값:
    # - 시간대 키별 전체 완료 여부
    def _slot_completion_states_for_patient(
        self,
        patient_hash: str,
        schedule_date: date,
        slot_keys: list[str],
    ) -> dict[str, bool]:
        medications = (
            self.db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == patient_hash)
            .order_by(_SavedMedication.id.asc())
            .all()
        )
        active_medications = [
            medication
            for medication in medications
            if self._is_active_today(medication, schedule_date)
        ]
        completion_rows_by_medication_id = self._completion_rows_by_medication_id(
            active_medications,
            patient_hash,
            schedule_date,
        )
        medication_slot_keys = {
            int(medication.id): self._slot_keys_for_medication(medication)
            for medication in active_medications
            if medication.id is not None
        }

        completion_states: dict[str, bool] = {}
        for current_slot_key in slot_keys:
            slot_medications = [
                medication
                for medication in active_medications
                if medication.id is not None
                and current_slot_key
                in medication_slot_keys.get(int(medication.id), [])
            ]
            completion_states[current_slot_key] = bool(slot_medications) and all(
                self._slot_statuses_for_medication(
                    medication,
                    schedule_date,
                    completion_rows_by_medication_id.get(int(medication.id), []),
                ).get(current_slot_key, False)
                for medication in slot_medications
            )
        return completion_states

    # Function Name: _get_existing_medication
    # Description:
    # - Finds an existing saved medication in a patient scope or raises 404.
    # Parameters:
    # - medication_id: Saved medication primary key.
    # - patient_hash: Patient ownership key used to scope lookup.
    # Returns:
    # - Existing saved medication row.
    def _get_existing_medication(
        self,
        medication_id: int,
        patient_hash: str,
    ) -> _SavedMedication:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        medication = (
            self.db.query(_SavedMedication)
            .filter(
                _SavedMedication.id == medication_id,
                _SavedMedication.patient_hash == normalized_patient_hash,
            )
            .first()
        )
        if medication is None:
            raise HTTPException(
                status_code=404,
                detail="Medication schedule was not found.",
            )
        return medication

    # Function Name: _to_schedule_dict
    # Description:
    # - Converts a saved medication row into a JSON-compatible schedule DTO.
    # Parameters:
    # - medication: Saved medication row.
    # Returns:
    # - JSON-compatible medication schedule dictionary.
    def _to_schedule_dict(
        self,
        medication: _SavedMedication,
        schedule_date: date | None = None,
        completion_rows: list[_MedicationCompletion] | None = None,
    ) -> dict[str, object]:
        target_date = schedule_date or application_today()
        schedule = self._to_schedule(
            medication,
            target_date,
            completion_rows,
        )
        return {
            "medication_id": schedule.medication_id,
            "drug_name": schedule.medication_name,
            "dosage_per_time": schedule.dosage,
            "daily_frequency": schedule.intake_time,
            "medication_status": schedule.medcation_status,
            "slot_statuses": schedule.slot_statuses,
            "completed_slot_keys": schedule.completed_slot_keys,
            "schedule_slot_keys": schedule.schedule_slot_keys,
            "schedule_date": target_date.isoformat(),
            "patient_hash": schedule.patient_id,
            "patient_id": schedule.patient_id,
            "total_days": schedule.medication_time,
            "efficacy": medication.efficacy,
            "use_method": medication.use_method,
            "warning_message": medication.warning_message,
            "image_url": medication.image_url,
            "created_date": (
                medication.created_date.isoformat()
                if medication.created_date is not None
                else ""
            ),
            "prescription_date": schedule.created_date.isoformat(),
        }

    # Function Name: _to_schedule
    # Description:
    # - Converts a saved medication row into the MedicationSchedule entity.
    # Parameters:
    # - medication: Saved medication row.
    # Returns:
    # - MedicationSchedule entity.
    def _to_schedule(
        self,
        medication: _SavedMedication,
        schedule_date: date | None = None,
        completion_rows: list[_MedicationCompletion] | None = None,
    ) -> MedicationSchedule:
        target_date = schedule_date or application_today()
        slot_statuses = self._slot_statuses_for_medication(
            medication,
            target_date,
            completion_rows,
        )
        is_completed_today = self._all_slots_completed(slot_statuses)
        return MedicationSchedule(
            created_date=self.course_policy.read_start_date(
                medication,
                target_date,
            ),
            medication_id=str(medication.id),
            medication_name=medication.item_name or "",
            dosage=medication.dosage_per_time or "",
            intake_time=medication.daily_frequency or "",
            medcation_status=is_completed_today,
            patient_id=medication.patient_hash or DEFAULT_PATIENT_HASH,
            medication_time=medication.total_days or "",
            slot_statuses=slot_statuses,
            completed_slot_keys=[
                key for key, completed in slot_statuses.items() if completed
            ],
            schedule_slot_keys=self._slot_keys_for_medication(medication),
        )

    # Function Name: _slot_keys_for_medication
    # Description:
    # - Derives the active time slots from the daily frequency label.
    # Parameters:
    # - medication: Saved medication row.
    # Returns:
    # - Ordered slot keys used by backend and Flutter schedule UI.
    def _slot_keys_for_medication(self, medication: _SavedMedication) -> list[str]:
        confirmed_slot_keys = decode_medication_schedule_slot_keys(
            medication.schedule_slot_keys
        )
        if confirmed_slot_keys:
            return confirmed_slot_keys
        frequency_count = self.course_policy.read_frequency_count(
            medication.daily_frequency
        )
        return medication_schedule_slot_keys_for_frequency(frequency_count)

    # Function Name: _slot_keys_for_update
    # Description:
    # - Resolves a requested slot key, or all slots for legacy row-level updates.
    # Parameters:
    # - slot_key: Optional requested slot key.
    # - valid_slot_keys: Slots allowed for the medication schedule.
    # Returns:
    # - Slot keys that should be updated.
    def _slot_keys_for_update(
        self,
        slot_key: str | None,
        valid_slot_keys: list[str],
    ) -> list[str]:
        normalized_slot_key = (slot_key or "").strip().lower()
        if not normalized_slot_key:
            return valid_slot_keys
        if normalized_slot_key not in valid_slot_keys:
            raise HTTPException(
                status_code=400,
                detail="Requested slot is not part of this medication schedule.",
            )
        return [normalized_slot_key]

    # Function Name: _slot_statuses_for_medication
    # Description:
    # - Reads per-slot completion state with legacy row-level status fallback.
    # Parameters:
    # - medication: Saved medication row.
    # - schedule_date: Date used for completion lookup.
    # Returns:
    # - Slot completion map keyed by slot name.
    def _slot_statuses_for_medication(
        self,
        medication: _SavedMedication,
        schedule_date: date,
        completion_rows: list[_MedicationCompletion] | None = None,
    ) -> dict[str, bool]:
        patient_hash = normalize_patient_hash(
            medication.patient_hash or DEFAULT_PATIENT_HASH
        )
        slot_statuses = {
            slot_key: self._is_legacy_completed_on(medication, schedule_date)
            for slot_key in self._slot_keys_for_medication(medication)
        }
        completions = completion_rows
        if completions is None:
            completions = (
                self.db.query(_MedicationCompletion)
                .filter(
                    _MedicationCompletion.saved_medication_id == medication.id,
                    _MedicationCompletion.patient_hash == patient_hash,
                    _MedicationCompletion.schedule_date == schedule_date,
                )
                .all()
            )
        if completions:
            for completion in completions:
                if completion.slot_key in slot_statuses:
                    slot_statuses[completion.slot_key] = bool(completion.completed)
        return slot_statuses

    # Function Name: _completion_rows_by_medication_id
    # Description:
    # - Batch-loads completion rows for active schedules to avoid one query per
    #   medication during today's schedule lookup.
    # Parameters:
    # - medications: Active saved medication rows for the requested date.
    # - patient_hash: Normalized patient ownership key.
    # - schedule_date: Date used for completion lookup.
    # Returns:
    # - Completion rows grouped by saved medication id.
    def _completion_rows_by_medication_id(
        self,
        medications: list[_SavedMedication],
        patient_hash: str,
        schedule_date: date,
    ) -> dict[int, list[_MedicationCompletion]]:
        medication_ids = [
            int(medication.id)
            for medication in medications
            if medication.id is not None
        ]
        if not medication_ids:
            return {}

        completion_rows = (
            self.db.query(_MedicationCompletion)
            .filter(
                _MedicationCompletion.saved_medication_id.in_(medication_ids),
                _MedicationCompletion.patient_hash == patient_hash,
                _MedicationCompletion.schedule_date == schedule_date,
            )
            .all()
        )
        grouped_rows: dict[int, list[_MedicationCompletion]] = {}
        for completion in completion_rows:
            grouped_rows.setdefault(int(completion.saved_medication_id), []).append(
                completion
            )
        return grouped_rows

    # Function Name: _materialize_missing_completion_slots
    # Description:
    # - Creates explicit completion rows for slots still represented only by
    #   legacy row-level status.
    # Parameters:
    # - medication: Saved medication row.
    # - patient_hash: Normalized patient ownership key.
    # - schedule_date: Date of the schedule slots.
    # - slot_statuses: Effective slot statuses before the requested update.
    # Returns:
    # - None.
    def _materialize_missing_completion_slots(
        self,
        medication: _SavedMedication,
        patient_hash: str,
        schedule_date: date,
        slot_statuses: dict[str, bool],
    ) -> None:
        existing_slot_keys = {
            completion.slot_key
            for completion in (
                self.db.query(_MedicationCompletion)
                .filter(
                    _MedicationCompletion.saved_medication_id == medication.id,
                    _MedicationCompletion.patient_hash == patient_hash,
                    _MedicationCompletion.schedule_date == schedule_date,
                )
                .all()
            )
        }
        for current_slot_key, completed in slot_statuses.items():
            if current_slot_key in existing_slot_keys:
                continue
            self.db.add(
                MedicationCompletion(
                    patient_hash=patient_hash,
                    medicine_name=medication.item_name or "",
                    time_slot=current_slot_key,
                    completed=completed,
                    completed_at=utc_now() if completed else None,
                ).insertMedicationCompletion(
                    saved_medication_id=int(medication.id),
                    schedule_date=schedule_date,
                )
            )

    # Function Name: _upsert_completion
    # Description:
    # - Inserts or updates one MedicationCompletion row for a schedule slot.
    # Parameters:
    # - medication: Saved medication row.
    # - patient_hash: Normalized patient ownership key.
    # - schedule_date: Date of the updated schedule slot.
    # - slot_key: Time-slot key to update.
    # - completed: New completion state.
    # Returns:
    # - None.
    def _upsert_completion(
        self,
        medication: _SavedMedication,
        patient_hash: str,
        schedule_date: date,
        slot_key: str,
        completed: bool,
    ) -> None:
        completion = (
            self.db.query(_MedicationCompletion)
            .filter(
                _MedicationCompletion.saved_medication_id == medication.id,
                _MedicationCompletion.patient_hash == patient_hash,
                _MedicationCompletion.schedule_date == schedule_date,
                _MedicationCompletion.slot_key == slot_key,
            )
            .first()
        )
        if completion is None:
            completion = MedicationCompletion(
                patient_hash=patient_hash,
                medicine_name=medication.item_name or "",
                time_slot=slot_key,
                completed=completed,
                completed_at=utc_now() if completed else None,
            ).insertMedicationCompletion(
                saved_medication_id=int(medication.id),
                schedule_date=schedule_date,
            )
            self.db.add(completion)

        completion.completed = completed
        completion.completed_at = utc_now() if completed else None

    # Function Name: _all_slots_completed
    # Description:
    # - Computes the row-level compatibility status from slot completion state.
    # Parameters:
    # - slot_statuses: Slot completion map.
    # Returns:
    # - True when every required slot is completed.
    def _all_slots_completed(self, slot_statuses: dict[str, bool]) -> bool:
        return bool(slot_statuses) and all(slot_statuses.values())

    # Function Name: _is_legacy_completed_on
    # Description:
    # - Checks whether the compatibility row-level status means completed on a date.
    # Parameters:
    # - medication: Saved medication row.
    # - schedule_date: Date used for compatibility fallback.
    # Returns:
    # - True when the legacy row marks every slot complete on the requested date.
    def _is_legacy_completed_on(
        self,
        medication: _SavedMedication,
        schedule_date: date,
    ) -> bool:
        status_date = self._read_status_date(medication.medication_status_date)
        return (
            bool(medication.medication_status)
            and status_date is not None
            and status_date == schedule_date
        )

    # Function Name: _is_active_today
    # Description:
    # - Checks whether a saved medication is active for today's schedule window.
    # Parameters:
    # - medication: Saved medication row.
    # - today: Date used for deterministic evaluation.
    # Returns:
    # - True when the medication should be shown in today's schedule.
    def _is_active_today(self, medication: _SavedMedication, today: date) -> bool:
        return self.course_policy.is_active_on(medication, today)

    # Function Name: _read_status_date
    # Description:
    # - Reads the per-dose completion date stored for a schedule slot.
    def _read_status_date(self, raw_date: object) -> date | None:
        if isinstance(raw_date, date):
            return raw_date
        if isinstance(raw_date, str) and raw_date.strip():
            try:
                return date.fromisoformat(raw_date.strip())
            except ValueError:
                return None
        return None
