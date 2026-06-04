# File Name: medication_detail_entity.py
# Role: Entity/DTO for medication detail information.

from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


# Class Name: MedicationDetail
# Role: Represents medication detail information shown to the user.
# Responsibilities:
#   - Carry efficacy, usage, warning, source, and optional guide text.
# Attributes:
#   - item_name: Public medication item name.
#   - efficacy: Medication efficacy summary.
#   - usage_method: Medication use method summary.
#   - warning: Medication warning summary.
#   - source: Data source label.
#   - ai_guide: Optional AI-generated patient guide.
class MedicationDetail(BaseModel):
    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)

    item_name: str
    efficacy: str
    usage_method: str = Field(alias="use_method")
    warning: str = Field(alias="warning_message")
    precaution: str = ""
    interaction: str = ""
    side_effect: str = ""
    storage_method: str = ""
    source: str = "e약은요"
    ai_guide: Optional[str] = None

    # Function Name: saveMedicationDetail
    # Description:
    # - Placeholder for the class diagram operation. Persistence is currently
    #   coordinated by CheckSavedMedication to keep database access in a control class.
    # Returns:
    # - None.
    def saveMedicationDetail(self) -> None:
        raise NotImplementedError("Medication detail saving is handled by CheckSavedMedication.")

    # Function Name: checkMedicationDetail
    # Description:
    # - Placeholder for the class diagram operation. Detail lookup is currently
    #   coordinated by CheckMedicationDetail.
    # Returns:
    # - Current MedicationDetail instance.
    def checkMedicationDetail(self) -> "MedicationDetail":
        return self

    # Function Name: get_medication_detail
    # Description:
    # - Returns this MedicationDetail instance for control code that follows
    #   the class diagram operation name.
    # Returns:
    # - Current MedicationDetail instance.
    def get_medication_detail(self) -> "MedicationDetail":
        return self

    # Function Name: getMedicationDetail
    # Description:
    # - Class diagram compatible wrapper for get_medication_detail.
    # Returns:
    # - Current MedicationDetail instance.
    def getMedicationDetail(self) -> "MedicationDetail":
        return self.get_medication_detail()

    # Function Name: get_voice_guide_text
    # Description:
    # - Builds text that can be handed to a TTS boundary when voice guidance is implemented.
    # Returns:
    # - Voice guide source text.
    def get_voice_guide_text(self) -> str:
        return "\n".join(
            item
            for item in [
                self.item_name,
                self.efficacy,
                self.usage_method,
                self.warning,
                self.ai_guide or "",
            ]
            if item.strip()
        )

    # Function Name: getVoiceGuideText
    # Description:
    # - Class diagram compatible wrapper for get_voice_guide_text.
    # Returns:
    # - Voice guide source text.
    def getVoiceGuideText(self) -> str:
        return self.get_voice_guide_text()
