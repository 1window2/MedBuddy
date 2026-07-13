# File Name: medication_detail_entity.py
# Role: Entity/DTO definitions for medication detail information.

from typing import Optional

from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import Column, DateTime, Integer, String, Text, func

from core.database import Base


# Class Name: MedicationDetail
# Role: Represents medication detail information shown to the user.
# Responsibilities:
#   - Carry efficacy, usage, warning, source, and optional guide text.
# Attributes:
#   - item_name: Public medication item name.
#   - efficacy: Medication efficacy summary.
#   - usage_method: Medication use method summary.
#   - warning: Medication warning summary.
#   - dosage_per_time: Optional dose per administration from prescription analysis.
#   - daily_frequency: Optional daily frequency from prescription analysis.
#   - total_days: Optional total medication days from prescription analysis.
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
    dosage_per_time: str = ""
    daily_frequency: str = ""
    total_days: str = ""
    image_url: str = ""
    source: str = "e약은요"
    ai_guide: Optional[str] = None

    # Function Name: saveMedicationDetail
    # Description:
    # - Placeholder for the class diagram operation. Persistence is currently
    #   coordinated by CheckSavedMedication to keep write access in a control class.
    # Returns:
    # - None.
    def saveMedicationDetail(self) -> None:
        raise NotImplementedError(
            "Medication detail saving is handled by CheckSavedMedication."
        )

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
                self.usage_method,
                self.dosage_per_time,
                self.daily_frequency,
                self.total_days,
                self.warning,
                self.efficacy,
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


# Class Name: _DrugBasicInfo
# Role: Internal SQLAlchemy entity for locally mirrored e약은요 records.
# Responsibilities:
#   - Store public medication records fetched from the e약은요 API.
#   - Preserve the raw API payload for traceability and refresh validation.
# Attributes:
#   - item_seq: Public API item sequence identifier.
#   - item_name: Original medication item name.
#   - normalized_item_name: Search-normalized medication name.
#   - raw_json: Original public API payload.
class _DrugBasicInfo(Base):
    __tablename__ = "drug_basic_infos"

    id = Column(Integer, primary_key=True, index=True)
    item_seq = Column(String, unique=True, index=True, nullable=True)
    item_name = Column(String, index=True, nullable=False)
    normalized_item_name = Column(String, index=True, nullable=False)
    entp_name = Column(String, nullable=True)
    efficacy = Column(Text, nullable=True)
    use_method = Column(Text, nullable=True)
    warning_message = Column(Text, nullable=True)
    interaction = Column(Text, nullable=True)
    side_effect = Column(Text, nullable=True)
    deposit_method = Column(Text, nullable=True)
    ai_guide = Column(Text, nullable=True)
    raw_json = Column(Text, nullable=False)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


# Class Name: _DrugApprovalInfo
# Role: Internal SQLAlchemy entity for locally mirrored detailed approval records.
# Responsibilities:
#   - Store raw approval documents fetched from the public approval API.
#   - Store generated patient-facing summaries after first use.
# Attributes:
#   - item_seq: Public item identifier or product standard code.
#   - item_name: Original medication item name.
#   - normalized_item_name: Search-normalized medication name.
#   - efficacy_doc: Raw approval efficacy document.
#   - use_method_doc: Raw approval usage document.
#   - warning_doc: Raw approval warning document.
class _DrugApprovalInfo(Base):
    __tablename__ = "drug_approval_infos"

    id = Column(Integer, primary_key=True, index=True)
    item_seq = Column(String, unique=True, index=True, nullable=True)
    item_name = Column(String, index=True, nullable=False)
    normalized_item_name = Column(String, index=True, nullable=False)
    entp_name = Column(String, nullable=True)
    main_ingredient = Column(Text, nullable=True)
    efficacy_doc = Column(Text, nullable=True)
    use_method_doc = Column(Text, nullable=True)
    warning_doc = Column(Text, nullable=True)
    summary_efficacy = Column(Text, nullable=True)
    summary_use_method = Column(Text, nullable=True)
    summary_warning_message = Column(Text, nullable=True)
    ai_guide = Column(Text, nullable=True)
    raw_json = Column(Text, nullable=False)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
