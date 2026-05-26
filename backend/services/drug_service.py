# File Name: drug_service.py
# Role: Coordinates cache lookup, public API fallback, and AI medication guidance.

import logging
from typing import Optional

from schemas.medication import MedicationDetail
from services.drug_cache_service import DrugCacheService
from services.drug_guide_service import DrugGuideService
from services.public_drug_api_client import PublicDrugApiClient

logger = logging.getLogger(__name__)


# Class Name: DrugService
# Role: Control class for medication detail enrichment.
# Responsibilities:
#   - Check Redis cache before external lookup.
#   - Query the basic public drug API first.
#   - Fallback to the advanced approval API when basic data is missing.
#   - Add patient-friendly AI guidance.
#   - Cache successful lookup results.
# Attributes:
#   - cache_service: DrugCacheService used for Redis operations.
#   - public_api_client: PublicDrugApiClient used for public API calls.
#   - guide_service: DrugGuideService used for Gemini summaries.
class DrugService:
    def __init__(
        self,
        cache_service: Optional[DrugCacheService] = None,
        public_api_client: Optional[PublicDrugApiClient] = None,
        guide_service: Optional[DrugGuideService] = None,
    ) -> None:
        self.cache_service = cache_service or DrugCacheService()
        self.public_api_client = public_api_client or PublicDrugApiClient()
        self.guide_service = guide_service or DrugGuideService()

    # Function Name: fetch_drug_info
    # Description:
    # - Fetches enriched drug information for a normalized medication name.
    # - Preserves the previous Basic API -> Advanced API -> Gemini -> Redis flow.
    # Parameters:
    # - drug_name: Normalized medication search keyword.
    # Returns:
    # - List of MedicationDetail DTOs. Empty list when no public data exists.
    async def fetch_drug_info(self, drug_name: str) -> list[MedicationDetail]:
        cached_drugs = await self.cache_service.get(drug_name)
        if cached_drugs is not None:
            return cached_drugs

        drug_infos = await self._fetch_uncached_drug_info(drug_name)
        await self.cache_service.set(drug_name, drug_infos)
        return drug_infos

    # Function Name: _fetch_uncached_drug_info
    # Description:
    # - Runs the public API and AI pipeline after cache miss.
    # Parameters:
    # - drug_name: Normalized medication search keyword.
    # Returns:
    # - List of MedicationDetail DTOs.
    async def _fetch_uncached_drug_info(self, drug_name: str) -> list[MedicationDetail]:
        basic_items = await self.public_api_client.search_basic(drug_name)
        if basic_items:
            logger.info("[Basic API] '%s' 검색 성공 (%s건)", drug_name, len(basic_items))
            return await self._build_basic_drug_infos(basic_items)

        logger.info("[Basic API] 결과 없음. Advanced API로 Fallback 시도: '%s'", drug_name)
        advanced_items = await self.public_api_client.search_advanced(drug_name)
        if not advanced_items:
            logger.warning("[%s] 식약처 DB에 등록되지 않은 약품입니다.", drug_name)
            return []

        advanced_drug = await self.guide_service.summarize_advanced_item(
            drug_name,
            advanced_items[0],
        )
        return [advanced_drug]

    # Function Name: _build_basic_drug_infos
    # Description:
    # - Converts Basic API items into MedicationDetail DTOs and adds AI guide text.
    # Parameters:
    # - basic_items: Raw Basic API items.
    # Returns:
    # - List of MedicationDetail DTOs.
    async def _build_basic_drug_infos(
        self,
        basic_items: list[dict],
    ) -> list[MedicationDetail]:
        medication_details = [
            MedicationDetail(
                item_name=item.get("itemName", "정보 없음"),
                efficacy=item.get("efcyQesitm", "정보 없음"),
                use_method=item.get("useMethodQesitm", "정보 없음"),
                warning_message=item.get("atpnWarnQesitm", "정보 없음"),
                source="Basic (e약은요)",
            )
            for item in basic_items
        ]

        enriched_details = []
        for medication_detail in medication_details:
            logger.info(
                "[Gemini] '%s' Basic API 데이터 기반 환자 안내문 생성 중...",
                medication_detail.item_name,
            )
            enriched_details.append(
                await self.guide_service.add_basic_guide(medication_detail)
            )

        return enriched_details
