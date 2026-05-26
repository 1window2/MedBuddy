# File Name: saved_medication_repository.py
# Role: Encapsulates persistence operations for saved medications.

from typing import Optional

from sqlalchemy.orm import Session

from models.db_models import SavedMedication
from schemas.medication import SavedMedicationCreate


# Class Name: SavedMedicationRepository
# Role: Persistence adapter for the saved_medications table.
# Responsibilities:
#   - Create saved medication rows.
#   - Read saved medication rows.
#   - Delete saved medication rows.
# Attributes:
#   - db: SQLAlchemy Session used for persistence operations.
class SavedMedicationRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: create
    # Description:
    # - Converts a validated request DTO into a SavedMedication ORM entity.
    # - Persists and refreshes the entity.
    # Parameters:
    # - medication: Validated saved medication input DTO.
    # Returns:
    # - Persisted SavedMedication entity.
    def create(self, medication: SavedMedicationCreate) -> SavedMedication:
        db_medication = SavedMedication(
            item_name=medication.item_name,
            efficacy=medication.efficacy,
            use_method=medication.use_method,
            warning_message=medication.warning_message,
            ai_guide=medication.ai_guide,
        )
        self.db.add(db_medication)
        self.db.commit()
        self.db.refresh(db_medication)
        return db_medication

    # Function Name: list_all
    # Description:
    # - Reads every saved medication row.
    # Returns:
    # - List of SavedMedication entities.
    def list_all(self) -> list[SavedMedication]:
        return self.db.query(SavedMedication).all()

    # Function Name: get_by_id
    # Description:
    # - Finds a saved medication by primary key.
    # Parameters:
    # - medication_id: Saved medication primary key.
    # Returns:
    # - SavedMedication if found, otherwise None.
    def get_by_id(self, medication_id: int) -> Optional[SavedMedication]:
        return (
            self.db.query(SavedMedication)
            .filter(SavedMedication.id == medication_id)
            .first()
        )

    # Function Name: delete
    # Description:
    # - Deletes an existing SavedMedication entity.
    # Parameters:
    # - medication: Existing SavedMedication entity.
    # Returns:
    # - None.
    def delete(self, medication: SavedMedication) -> None:
        self.db.delete(medication)
        self.db.commit()

    # Function Name: rollback
    # Description:
    # - Rolls back the current transaction after persistence errors.
    # Returns:
    # - None.
    def rollback(self) -> None:
        self.db.rollback()
