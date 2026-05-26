# File Name: medication.py
# Role: Defines medication request and response DTOs.

from typing import Optional

from pydantic import BaseModel, Field


# Class Name: MedicationRequest
# Role: Request DTO for medication lookup.
# Attributes:
#   - extracted_text: Raw medication text extracted by the frontend or analysis flow.
class MedicationRequest(BaseModel):
    extracted_text: Optional[str] = None


# Class Name: MedicationDetail
# Role: API DTO for public medication information.
# Attributes:
#   - item_name: Public medication item name.
#   - efficacy: Medication efficacy summary.
#   - use_method: Medication use method summary.
#   - warning_message: Medication warning summary.
#   - source: Data source label.
#   - ai_guide: Optional AI-generated patient guide.
class MedicationDetail(BaseModel):
    item_name: str
    efficacy: str
    use_method: str
    warning_message: str
    source: str = "e약은요"
    ai_guide: Optional[str] = None


# Class Name: SavedMedicationCreate
# Role: Request DTO for saving a medication snapshot.
# Attributes:
#   - item_name: Medication item name.
#   - efficacy: Medication efficacy summary.
#   - use_method: Medication use method summary.
#   - warning_message: Medication warning summary.
#   - ai_guide: Optional AI-generated patient guide.
class SavedMedicationCreate(BaseModel):
    item_name: str
    efficacy: str
    use_method: str
    warning_message: str
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
