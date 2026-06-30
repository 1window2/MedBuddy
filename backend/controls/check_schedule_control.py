# File Name: check_schedule_control.py
# Role: Control class mapped from the CheckSchedule box in ClassDiagram2.

from datetime import date, timedelta
import re

from fastapi import HTTPException
from sqlalchemy.orm import Session

from controls.patient_guardian_link_control import PatientGuardianLinkControl
from entities.medication_completion_entity import _MedicationCompletion, utc_now
from entities.medication_schedule_entity import MedicationSchedule
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH, normalize_patient_hash
from entities.saved_medication_entity import _SavedMedication
from services.saved_medication_retention import SavedMedicationRetentionPolicy

_TOTAL_DAYS_PATTERN = re.compile(r"\d+")
# "caregiver" is accepted only as a legacy API role alias.
_GUARDIAN_ROLES = {"guardian", "caregiver"}
_SLOT_KEYS = ("morning", "lunch", "evening", "bedtime")


# Class Name: CheckSchedule
# Role: Requests and updates medication schedules.
# Responsibilities:
#   - Read today's medication schedule for one patient or linked guardian scope.
#   - Persist a medication completion status for one saved medication row.
# Attributes:
#   - db: SQLAlchemy session used for schedule persistence operations.
class CheckSchedule:
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: requestMedicationSchedule
    # Description:
    # - Class diagram compatible wrapper for today's medication schedule lookup.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope schedule lookup.
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # Returns:
    # - API-compatible schedule list response dictionary.
    def requestMedicationSchedule(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        return self.request_today_medication_schedule(patient_hash, user_hash, role)

    # Function Name: requestTodayMedicationSchedule
    # Description:
    # - Class diagram compatible wrapper for today's medication schedule lookup.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope schedule lookup.
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # Returns:
    # - API-compatible schedule list response dictionary.
    def requestTodayMedicationSchedule(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        return self.request_today_medication_schedule(patient_hash, user_hash, role)

    # Function Name: request_today_medication_schedule
    # Description:
    # - Reads active medication schedules for today's date.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope schedule lookup.
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # Returns:
    # - API-compatible schedule list response dictionary.
    def request_today_medication_schedule(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        normalized_patient_hash = self._resolve_patient_hash(
            patient_hash,
            user_hash,
            role,
        )
        SavedMedicationRetentionPolicy().cleanup_expired_medications(
            self.db,
            normalized_patient_hash,
        )
        today = date.today()
        medications = (
            self.db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == normalized_patient_hash)
            .order_by(_SavedMedication.id.asc())
            .all()
        )
        active_schedules = [
            self._to_schedule_dict(medication, today)
            for medication in medications
            if self._is_active_today(medication, today)
        ]
        return {
            "success": True,
            "message": "Today medication schedule lookup succeeded.",
            "data": active_schedules,
        }

    # Function Name: updateMedicationStatus
    # Description:
    # - Class diagram compatible wrapper for medication status persistence.
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
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
        slot_key: str | None = None,
    ) -> dict[str, object]:
        return self.update_medication_status(
            medication_id,
            medication_status,
            patient_hash,
            user_hash,
            role,
            slot_key,
        )

    # Function Name: update_medication_status
    # Description:
    # - Persists the medication completion status for one saved medication row.
    # Parameters:
    # - medication_id: Saved medication primary key.
    # - medication_status: New medication completion status.
    # - patient_hash: Patient ownership key used to scope update.
    # - slot_key: Optional time-slot key. Empty means all schedule slots.
    # Returns:
    # - API-compatible status update response dictionary.
    def update_medication_status(
        self,
        medication_id: int,
        medication_status: bool,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
        slot_key: str | None = None,
    ) -> dict[str, object]:
        normalized_patient_hash = self._resolve_patient_hash(
            patient_hash,
            user_hash,
            role,
        )
        medication = self._get_existing_medication(
            medication_id,
            normalized_patient_hash,
        )
        today = date.today()
        slot_keys = self._slot_keys_for_medication(medication)
        target_slot_keys = self._slot_keys_for_update(slot_key, slot_keys)

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
            raise HTTPException(
                status_code=500,
                detail=f"Status update failed: {exc}",
            ) from exc

        return {
            "success": True,
            "message": "Medication status was updated.",
            "data": self._to_schedule_dict(medication, today),
        }

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
    ) -> dict[str, object]:
        target_date = schedule_date or date.today()
        schedule = self._to_schedule(
            medication,
            target_date,
        ).getTodayMedicationSchedule()
        return {
            "medication_id": schedule.medication_id,
            "drug_name": schedule.medication_name,
            "dosage_per_time": schedule.dosage,
            "daily_frequency": schedule.intake_time,
            "medication_status": schedule.medcation_status,
            "slot_statuses": schedule.slot_statuses,
            "completed_slot_keys": schedule.completed_slot_keys,
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

    # Function Name: resolvePatientHash
    # Description:
    # - Class diagram compatible wrapper for patient/guardian scope resolution.
    # Parameters:
    # - patient_hash: Direct patient hash for patient requests.
    # - user_hash: Requesting user hash for guardian requests.
    # - role: Requesting user role.
    # Returns:
    # - Patient hash authorized for this request.
    def resolvePatientHash(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> str:
        return self._resolve_patient_hash(patient_hash, user_hash, role)

    # 함수명: _resolve_patient_hash
    # 함수역할:
    # - 요청자 역할에 따라 직접 환자 해시 또는 보호자 연동 환자 해시를 계산한다.
    # 매개변수:
    # - patient_hash: 환자 해시 후보
    # - user_hash: 사용자 해시 후보
    # - role: 요청자 역할
    # 반환값:
    # - 권한 범위가 확인된 환자 해시
    def _resolve_patient_hash(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> str:
        normalized_role = (role or "patient").strip().lower()
        if normalized_role in _GUARDIAN_ROLES:
            return PatientGuardianLinkControl(self.db).get_linked_patient_hash(
                user_hash or patient_hash,
                patient_hash,
            )
        return normalize_patient_hash(user_hash or patient_hash)

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
    ) -> MedicationSchedule:
        target_date = schedule_date or date.today()
        slot_statuses = self._slot_statuses_for_medication(
            medication,
            target_date,
        )
        is_completed_today = self._all_slots_completed(slot_statuses)
        return MedicationSchedule(
            created_date=self._read_schedule_start_date(
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
        )

    # Function Name: _slot_keys_for_medication
    # Description:
    # - Derives the active time slots from the daily frequency label.
    # Parameters:
    # - medication: Saved medication row.
    # Returns:
    # - Ordered slot keys used by backend and Flutter schedule UI.
    def _slot_keys_for_medication(self, medication: _SavedMedication) -> list[str]:
        frequency_count = self._read_total_days(medication.daily_frequency)
        if frequency_count >= 4:
            return list(_SLOT_KEYS)
        if frequency_count == 3:
            return ["morning", "lunch", "evening"]
        if frequency_count == 2:
            return ["morning", "evening"]
        return ["morning"]

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
    ) -> dict[str, bool]:
        patient_hash = normalize_patient_hash(
            medication.patient_hash or DEFAULT_PATIENT_HASH
        )
        slot_statuses = {
            slot_key: self._is_legacy_completed_on(medication, schedule_date)
            for slot_key in self._slot_keys_for_medication(medication)
        }
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
                _MedicationCompletion(
                    saved_medication_id=medication.id,
                    patient_hash=patient_hash,
                    schedule_date=schedule_date,
                    slot_key=current_slot_key,
                    completed=completed,
                    completed_at=utc_now() if completed else None,
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
            completion = _MedicationCompletion(
                saved_medication_id=medication.id,
                patient_hash=patient_hash,
                schedule_date=schedule_date,
                slot_key=slot_key,
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
        start_date = self._read_schedule_start_date(medication, today)
        total_days = self._read_total_days(medication.total_days)
        if total_days <= 0:
            return start_date <= today

        end_date = start_date + timedelta(days=total_days - 1)
        return start_date <= today <= end_date

    # 함수명: _read_schedule_start_date
    # 함수역할:
    # - 오늘 복약 일정 계산에 사용할 시작일을 조제일자 우선으로 읽는다.
    # - 조제일자가 비어 있는 기존 데이터는 저장일을 대체값으로 사용한다.
    # 매개변수:
    # - medication: 저장된 복약 정보 row
    # - fallback_date: 날짜 정보가 없을 때 사용할 기준일
    # 반환값:
    # - 일정 계산에 사용할 시작 날짜
    def _read_schedule_start_date(
        self,
        medication: _SavedMedication,
        fallback_date: date,
    ) -> date:
        prescription_date = getattr(medication, "prescription_date", None)
        if prescription_date:
            return self._read_created_date(prescription_date, fallback_date)
        return self._read_created_date(medication.created_date, fallback_date)

    # Function Name: _read_created_date
    # Description:
    # - Reads a saved medication created date with a safe fallback.
    # Parameters:
    # - raw_date: Raw created_date value from SQLAlchemy.
    # - fallback_date: Date used when raw_date is empty or invalid.
    # Returns:
    # - Parsed date.
    def _read_created_date(
        self,
        raw_date: object,
        fallback_date: date,
    ) -> date:
        if isinstance(raw_date, date):
            return raw_date
        if isinstance(raw_date, str) and raw_date.strip():
            try:
                return date.fromisoformat(raw_date.strip())
            except ValueError:
                return fallback_date
        return fallback_date

    def _read_status_date(self, raw_date: object) -> date | None:
        if isinstance(raw_date, date):
            return raw_date
        if isinstance(raw_date, str) and raw_date.strip():
            try:
                return date.fromisoformat(raw_date.strip())
            except ValueError:
                return None
        return None

    # Function Name: _read_total_days
    # Description:
    # - Extracts a numeric medication duration from a schedule label.
    # Parameters:
    # - raw_total_days: Raw total_days value such as "7 days" or "7일".
    # Returns:
    # - Parsed duration in days, or 0 when unavailable.
    def _read_total_days(self, raw_total_days: str | None) -> int:
        if not raw_total_days:
            return 0
        match = _TOTAL_DAYS_PATTERN.search(raw_total_days)
        if match is None:
            return 0
        return int(match.group(0))
