# File Name: check_schedule_control.py
# Role: Control class mapped from the CheckSchedule box in ClassDiagram2.

from datetime import date, timedelta
import re

from fastapi import HTTPException
from sqlalchemy.orm import Session

from entities.medication_schedule_entity import MedicationSchedule
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH, normalize_patient_hash
from entities.saved_medication_entity import _SavedMedication

_TOTAL_DAYS_PATTERN = re.compile(r"\d+")

# Class Name: CheckSchedule
# Role: Requests and updates medication schedules.
# Responsibilities:
#   - Read today's medication schedule for one patient hash.
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
    # Returns:
    # - API-compatible schedule list response dictionary.
    def requestMedicationSchedule(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_today_medication_schedule(patient_hash)

    # Function Name: requestTodayMedicationSchedule
    # Description:
    # - Class diagram compatible wrapper for today's medication schedule lookup.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope schedule lookup.
    # Returns:
    # - API-compatible schedule list response dictionary.
    def requestTodayMedicationSchedule(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_today_medication_schedule(patient_hash)

    # Function Name: request_today_medication_schedule
    # Description:
    # - Reads active medication schedules for today's date.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope schedule lookup.
    # Returns:
    # - API-compatible schedule list response dictionary.
    def request_today_medication_schedule(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        today = date.today()
        medications = (
            self.db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == normalized_patient_hash)
            .order_by(_SavedMedication.id.asc())
            .all()
        )
        active_schedules = [
            self._to_schedule_dict(medication)
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
    # Returns:
    # - API-compatible status update response dictionary.
    def updateMedicationStatus(
        self,
        medication_id: int,
        medication_status: bool,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.update_medication_status(
            medication_id,
            medication_status,
            patient_hash,
        )

    # Function Name: update_medication_status
    # Description:
    # - Persists the medication completion status for one saved medication row.
    # Parameters:
    # - medication_id: Saved medication primary key.
    # - medication_status: New medication completion status.
    # - patient_hash: Patient ownership key used to scope update.
    # Returns:
    # - API-compatible status update response dictionary.
    def update_medication_status(
        self,
        medication_id: int,
        medication_status: bool,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        medication = self._get_existing_medication(medication_id, patient_hash)
        schedule = self._to_schedule(medication)
        schedule.saveMedicationStatus(medication_status)

        try:
            medication.medication_status = schedule.medcation_status
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
            "data": self._to_schedule_dict(medication),
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
    def _to_schedule_dict(self, medication: _SavedMedication) -> dict[str, object]:
        schedule = self._to_schedule(medication).getTodayMedicationSchedule()
        return {
            "medication_id": schedule.medication_id,
            "drug_name": schedule.medication_name,
            "dosage_per_time": schedule.dosage,
            "daily_frequency": schedule.intake_time,
            "medication_status": schedule.medcation_status,
            "patient_hash": schedule.patient_id,
            "patient_id": schedule.patient_id,
            "total_days": schedule.medication_time,
            "created_date": (
                schedule.created_date.isoformat()
                if schedule.created_date is not None
                else ""
            ),
        }

    # Function Name: _to_schedule
    # Description:
    # - Converts a saved medication row into the MedicationSchedule entity.
    # Parameters:
    # - medication: Saved medication row.
    # Returns:
    # - MedicationSchedule entity.
    def _to_schedule(self, medication: _SavedMedication) -> MedicationSchedule:
        return MedicationSchedule(
            created_date=self._read_created_date(
                medication.created_date,
                date.today(),
            ),
            medication_id=str(medication.id),
            medication_name=medication.item_name or "",
            dosage=medication.dosage_per_time or "",
            intake_time=medication.daily_frequency or "",
            medcation_status=bool(medication.medication_status),
            patient_id=medication.patient_hash or DEFAULT_PATIENT_HASH,
            medication_time=medication.total_days or "",
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
        start_date = self._read_created_date(medication.created_date, today)
        total_days = self._read_total_days(medication.total_days)
        if total_days <= 0:
            return start_date <= today

        end_date = start_date + timedelta(days=total_days - 1)
        return start_date <= today <= end_date

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
