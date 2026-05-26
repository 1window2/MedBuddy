# File Name: saved_medication_service.py
# Role: Coordinates saved medication CRUD use cases.

from fastapi import HTTPException

from models.db_models import SavedMedication
from repositories.saved_medication_repository import SavedMedicationRepository
from schemas.medication import SavedMedicationCreate


# Class Name: CheckSavedMedication
# Role: Control class for saved medication persistence workflows.
# Responsibilities:
#   - Save medication snapshots.
#   - List saved medications.
#   - Delete saved medications with not-found handling.
# Attributes:
#   - repository: SavedMedicationRepository used for persistence operations.
class CheckSavedMedication:
    def __init__(self, repository: SavedMedicationRepository) -> None:
        self.repository = repository

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
            db_medication = self.repository.create(medication)
            return {
                "success": True,
                "message": f"'{db_medication.item_name}'이(가) 약통에 저장되었습니다.",
                "id": db_medication.id,
            }
        except Exception as exc:
            self.repository.rollback()
            raise HTTPException(status_code=500, detail=f"저장 실패: {exc}") from exc

    # Function Name: request_saved_medication_info
    # Description:
    # - Reads all saved medications.
    # Returns:
    # - API-compatible list response dictionary.
    def request_saved_medication_info(self) -> dict[str, object]:
        saved_medications = self.repository.list_all()
        return {
            "success": True,
            "message": "약통 목록 조회 성공",
            "data": [
                self._to_response_dict(medication)
                for medication in saved_medications
            ],
        }

    # Function Name: _to_response_dict
    # Description:
    # - Converts a SavedMedication ORM entity into a JSON-serializable API DTO.
    # Parameters:
    # - medication: SavedMedication entity from persistence layer.
    # Returns:
    # - JSON-compatible saved medication dictionary.
    def _to_response_dict(self, medication: SavedMedication) -> dict[str, object]:
        return {
            "id": medication.id,
            "item_name": medication.item_name,
            "efficacy": medication.efficacy,
            "use_method": medication.use_method,
            "warning_message": medication.warning_message,
            "ai_guide": medication.ai_guide,
        }

    # Function Name: request_delete
    # Description:
    # - Deletes a saved medication by id.
    # Parameters:
    # - medication_id: Saved medication primary key.
    # Returns:
    # - API-compatible success response dictionary.
    def request_delete(self, medication_id: int) -> dict[str, object]:
        try:
            medication = self._get_existing_medication(medication_id)
            self.repository.delete(medication)
            return {"success": True, "message": "약통에서 삭제되었습니다."}
        except HTTPException:
            raise
        except Exception as exc:
            self.repository.rollback()
            raise HTTPException(status_code=500, detail=f"삭제 실패: {exc}") from exc

    # Function Name: _get_existing_medication
    # Description:
    # - Finds an existing saved medication or raises a 404 error.
    # Parameters:
    # - medication_id: Saved medication primary key.
    # Returns:
    # - Existing SavedMedication entity.
    def _get_existing_medication(self, medication_id: int) -> SavedMedication:
        medication = self.repository.get_by_id(medication_id)
        if medication is None:
            raise HTTPException(status_code=404, detail="약을 찾을 수 없습니다.")
        return medication
