# File Name: check_saved_medication_control.py
# Role: Control class for saved medication persistence workflows.

from fastapi import HTTPException
from sqlalchemy.orm import Session

from entities.patient_hash_entity import DEFAULT_PATIENT_HASH, normalize_patient_hash
from entities.saved_medication_entity import _SavedMedication
from schemas.medication import SavedMedicationCreate


# Class Name: CheckSavedMedication
# Role: Coordinates saved medication CRUD use cases.
# Responsibilities:
#   - Save medication snapshots.
#   - List saved medications for the requested patient hash.
#   - Delete saved medications with not-found handling.
# Attributes:
#   - db: SQLAlchemy session used for persistence operations.
class CheckSavedMedication:
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: save_medication_detail
    # Description:
    # - Persists a selected medication as a saved medication snapshot.
    # Parameters:
    # - medication: Validated saved medication DTO.
    # Returns:
    # - API-compatible success response dictionary.
    def save_medication_detail(
        self,
        medication: SavedMedicationCreate,
    ) -> dict[str, object]:
        try:
            patient_hash = normalize_patient_hash(medication.patient_hash)
            db_medication = _SavedMedication(
                patient_hash=patient_hash,
                item_name=medication.item_name,
                efficacy=medication.efficacy,
                use_method=medication.use_method,
                warning_message=medication.warning_message,
                dosage_per_time=medication.dosage_per_time,
                daily_frequency=medication.daily_frequency,
                total_days=medication.total_days,
                ai_guide=medication.ai_guide,
            )
            self.db.add(db_medication)
            self.db.commit()
            self.db.refresh(db_medication)
            return {
                "success": True,
                "message": f"'{db_medication.item_name}' saved to pillbox.",
                "id": db_medication.id,
            }
        except Exception as exc:
            self.db.rollback()
            raise HTTPException(status_code=500, detail=f"Save failed: {exc}") from exc

    # Function Name: saveMedicationDetail
    # Description:
    # - Class diagram compatible wrapper for save_medication_detail.
    # Parameters:
    # - medication: Validated saved medication DTO.
    # Returns:
    # - API-compatible success response dictionary.
    def saveMedicationDetail(
        self,
        medication: SavedMedicationCreate,
    ) -> dict[str, object]:
        return self.save_medication_detail(medication)

    # Function Name: request_saved_medication_info
    # Description:
    # - Reads saved medications owned by one patient hash.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope saved medication lookup.
    # Returns:
    # - API-compatible list response dictionary.
    def request_saved_medication_info(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        saved_medications = (
            self.db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == normalized_patient_hash)
            .all()
        )
        return {
            "success": True,
            "message": "Saved medication lookup succeeded.",
            "data": [
                self._to_response_dict(medication)
                for medication in saved_medications
            ],
        }

    # Function Name: requestSavedMedicationInfo
    # Description:
    # - Class diagram compatible wrapper for request_saved_medication_info.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope saved medication lookup.
    # Returns:
    # - API-compatible list response dictionary.
    def requestSavedMedicationInfo(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_saved_medication_info(patient_hash)

    # Function Name: request_delete
    # Description:
    # - Deletes a saved medication by id.
    # Parameters:
    # - medication_id: Saved medication primary key.
    # - patient_hash: Patient ownership key used to scope deletion.
    # Returns:
    # - API-compatible success response dictionary.
    def request_delete(
        self,
        medication_id: int,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        try:
            medication = self._get_existing_medication(medication_id, patient_hash)
            self.db.delete(medication)
            self.db.commit()
            return {"success": True, "message": "Medication was deleted from pillbox."}
        except HTTPException:
            raise
        except Exception as exc:
            self.db.rollback()
            raise HTTPException(status_code=500, detail=f"Delete failed: {exc}") from exc

    # Function Name: requestDelete
    # Description:
    # - Class diagram compatible wrapper for request_delete.
    # Parameters:
    # - medication_id: Saved medication primary key.
    # - patient_hash: Patient ownership key used to scope deletion.
    # Returns:
    # - API-compatible delete success dictionary.
    def requestDelete(
        self,
        medication_id: int,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_delete(medication_id, patient_hash)

    # Function Name: _to_response_dict
    # Description:
    # - Converts a SavedMedication ORM entity into a JSON-serializable API DTO.
    # Parameters:
    # - medication: SavedMedication entity from persistence layer.
    # Returns:
    # - JSON-compatible saved medication dictionary.
    def _to_response_dict(self, medication: _SavedMedication) -> dict[str, object]:
        return {
            "id": medication.id,
            "patient_hash": medication.patient_hash,
            "item_name": medication.item_name,
            "efficacy": medication.efficacy,
            "use_method": medication.use_method,
            "warning_message": medication.warning_message,
            "dosage_per_time": medication.dosage_per_time,
            "daily_frequency": medication.daily_frequency,
            "total_days": medication.total_days,
            "ai_guide": medication.ai_guide,
        }

    # Function Name: _get_existing_medication
    # Description:
    # - Finds an existing saved medication or raises a 404 error.
    # Parameters:
    # - medication_id: Saved medication primary key.
    # - patient_hash: Patient ownership key used to scope lookup.
    # Returns:
    # - Existing _SavedMedication row.
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
            raise HTTPException(status_code=404, detail="Medication was not found.")
        return medication
