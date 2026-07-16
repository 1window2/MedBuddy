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
#   - item_seq: Canonical public product identifier shared by MFDS datasets.
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

    item_seq: str = ""
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

    def getMedicationDetail(self) -> dict[str, object]:
        return self.model_dump(by_alias=True)

    def getVoiceGuideText(self, language: str = "ko") -> str:
        normalized_language = (language or "").strip().lower()
        labels = (
            ("Medication", "How to take", "Warning")
            if normalized_language == "en"
            else ("약 이름", "복용 방법", "주의사항")
        )
        values = (self.item_name, self.usage_method, self.warning)
        return "\n".join(
            f"{label}: {value.strip()}"
            for label, value in zip(labels, values, strict=True)
            if value and value.strip()
        )


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
