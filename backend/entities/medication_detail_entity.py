# File Name: medication_detail_entity.py
# Role: Defines medication detail fields, API aliases and localized voice-guide text extraction.

import re
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import Column, DateTime, Integer, String, Text, func

from core.database import Base

_CATALOG_NAME_WHITESPACE = re.compile(r"\s+")


# Function Name: normalize_catalog_item_name
# Description:
# - Builds the catalog key stored in normalized_item_name: all whitespace removed and lowercased.
# - The catalog sync writes this key and the local lookups read the indexed column with it, so
#   every writer and reader must use this one rule.
# Parameters:
# - name (str): Medication name before catalog-key normalization.
# Returns:
# - Normalized catalog name; an empty string when the name has only whitespace.
def normalize_catalog_item_name(name: str) -> str:
    return _CATALOG_NAME_WHITESPACE.sub("", name).strip().lower()


# 클래스명: MedicationDetail
# 역할: 공공 약품 정보와 처방·요약 정보를 API 응답 모델로 표현한다.
# 주요 책임: use_method와 warning_message 별칭을 유지하고 선택적인 제조사·상호작용·이미지·AI 안내를 함께 전달한다.
# 속성: item_seq와 item_name은 품목, manufacturer는 제조사, efficacy·usage_method·warning 등은 약품 설명, dosage_per_time·daily_frequency·total_days는 복약 표기, image_url·source·ai_guide는 표시 보조 정보이다.
class MedicationDetail(BaseModel):
    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)

    item_seq: str = ""
    item_name: str
    manufacturer: str = ""
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

    # Function Name: getMedicationDetail
    # Description:
    # - Serializes medication details using the API compatibility aliases.
    # Parameters:
    # - None.
    # Returns:
    # - Aliased medication detail dictionary.
    def getMedicationDetail(self) -> dict[str, object]:
        return self.model_dump(by_alias=True)

    # Function Name: getVoiceGuideText
    # Description:
    # - Joins nonblank medication name, usage and warning fields with Korean or English speech labels.
    # Parameters:
    # - language (str): Requested Korean or English content language.
    # Returns:
    # - Newline-separated voice-guide text; empty when all source fields are blank.
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
# Role:
# - Internal SQLAlchemy entity for locally mirrored e약은요 records.
# Responsibilities:
# - Store public medication records fetched from the e약은요 API.
# - Preserve the raw API payload for traceability and refresh validation.
# Attributes:
# - item_seq (String): Public API item sequence identifier.
# - item_name (String): Original medication item name.
# - normalized_item_name (String): Search-normalized medication name.
# - raw_json (Text): Original public API payload.
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
    catalog_sync_token = Column(String(36), index=True, nullable=True)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


# Class Name: _DrugApprovalInfo
# Role:
# - Internal SQLAlchemy entity for locally mirrored detailed approval records.
# Responsibilities:
# - Store raw approval documents fetched from the public approval API.
# - Store generated patient-facing summaries after first use.
# Attributes:
# - item_seq (String): Public item identifier or product standard code.
# - item_name (String): Original medication item name.
# - normalized_item_name (String): Search-normalized medication name.
# - efficacy_doc (Text): Raw approval efficacy document.
# - use_method_doc (Text): Raw approval usage document.
# - warning_doc (Text): Raw approval warning document.
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
    catalog_sync_token = Column(String(36), index=True, nullable=True)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


# Field lengths of a searched product. The cache columns, the chat attachment schema
# (schemas.chat.ChatMedicationReference) and the cache writer share them, so every cached
# product can be attached and every attachment fits the cache.
SEARCHED_MEDICATION_ITEM_SEQ_MAX_LENGTH = 64
SEARCHED_MEDICATION_NAME_MAX_LENGTH = 300
SEARCHED_MEDICATION_MANUFACTURER_MAX_LENGTH = 200


# Class Name: MedicationSearchCacheRecord
# Role:
# - Public product details that the medication search returned, kept briefly so a searched
#   medication attached to a chat message is shown from server data, not from the sender's app.
# Responsibilities:
# - Keep only public catalogue fields keyed by item number; never the searching account.
# Attributes:
# - item_seq (String(64)): Public item number.
# - item_name (String(300)): Product name as returned by the search.
# - manufacturer (String(200)): Manufacturer as returned by the search.
# - image_url (String(2048)): Allowed public image address, or an empty string.
# - fetched_at (DateTime): When a search last returned the product (naive UTC).
class MedicationSearchCacheRecord(Base):
    """검색한 계정 정보 없이 공개 품목 정보만 24시간 재사용한다."""

    __tablename__ = "medication_search_cache"

    item_seq = Column(String(length=SEARCHED_MEDICATION_ITEM_SEQ_MAX_LENGTH), primary_key=True)
    item_name = Column(String(length=SEARCHED_MEDICATION_NAME_MAX_LENGTH), nullable=False)
    manufacturer = Column(
        String(length=SEARCHED_MEDICATION_MANUFACTURER_MAX_LENGTH), nullable=False, default="",
    )
    image_url = Column(String(length=2048), nullable=False, default="")
    fetched_at = Column(DateTime, nullable=False, index=True)
