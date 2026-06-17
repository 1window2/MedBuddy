# File Name: medication.py
# Role: Defines medication request and response DTOs.

from typing import Optional

from pydantic import BaseModel, Field

from entities.medication_detail_entity import MedicationDetail


# Class Name: MedicationRequest
# Role: Request DTO for medication lookup.
# Attributes:
#   - extracted_text: Raw medication text extracted by the frontend or analysis flow.
class MedicationRequest(BaseModel):
    extracted_text: Optional[str] = None


# Class Name: SavedMedicationCreate
# Role: Request DTO for saving a medication snapshot.
# Attributes:
#   - item_name: Medication item name.
#   - efficacy: Medication efficacy summary.
#   - use_method: Medication use method summary.
#   - warning_message: Medication warning summary.
#   - dosage_per_time: Optional dose per administration from prescription analysis.
#   - daily_frequency: Optional daily frequency from prescription analysis.
#   - total_days: Optional total medication days from prescription analysis.
#   - ai_guide: Optional AI-generated patient guide.
class SavedMedicationCreate(BaseModel):
    item_name: str
    efficacy: str
    use_method: str
    warning_message: str
    dosage_per_time: Optional[str] = None
    daily_frequency: Optional[str] = None
    total_days: Optional[str] = None
    ai_guide: Optional[str] = None


# Class Name: MedicationResponse
# Role: Response DTO for medication lookup results.
# Attributes:
#   - success: Whether lookup found data.
#   - message: User-facing result message.
#   - data: MedicationDetail result list.
class MedicationResponse(BaseModel):
    success: bool
    message: str
    data: list[MedicationDetail] = Field(default_factory=list)
