# File Name: check_medication_detail_control.py
# Role: Control class for requesting medication detail information.

import json
import logging
import re
from typing import Any

import httpx
import redis.asyncio as redis
from google import genai

from core.config import settings
from entities.medication_detail_entity import MedicationDetail
from schemas.medication import MedicationResponse

logger = logging.getLogger(__name__)


# Class Name: CheckMedicationDetail
# Role: Coordinates medication keyword normalization and detail lookup.
# Responsibilities:
#   - Validate and normalize user-provided medication text.
#   - Check Redis cache before public data lookup.
#   - Query e약은요 first and the drug approval API as fallback.
#   - Generate patient-facing guidance through Gemini.
#   - Build the API response DTO.
# Attributes:
#   - ai_client: Gemini client used for medication guidance generation.
#   - redis_client: Async Redis client used as an optional cache.
#   - model_name: Gemini model name.
class CheckMedicationDetail:
    MAX_KEYWORD_LENGTH = 100
    CACHE_TTL_SECONDS = 604800
    _DOSAGE_PATTERN = re.compile(
        r"\d{1,10}(?:\.\d{1,5})?\s{0,5}(?:mg|g|ml)",
        flags=re.IGNORECASE,
    )

    def __init__(
        self,
        ai_client: genai.Client | None = None,
        redis_client: redis.Redis | None = None,
        model_name: str = "gemini-3.1-flash-lite",
        timeout_seconds: float = 15.0,
    ) -> None:
        self.ai_client = ai_client or genai.Client(api_key=settings.GEMINI_API_KEY)
        self.redis_client = redis_client or redis.from_url(
            settings.REDIS_URL,
            decode_responses=True,
        )
        self.model_name = model_name
        self.timeout_seconds = timeout_seconds

    # Function Name: request_medication_detail
    # Description:
    # - Normalizes medication text and fetches detailed drug information.
    # Parameters:
    # - raw_text: Raw medication text supplied by the frontend.
    # Returns:
    # - MedicationResponse with success flag and MedicationDetail list.
    async def request_medication_detail(self, raw_text: str) -> MedicationResponse:
        normalized_text = self._normalize_raw_text(raw_text)
        self._validate_lookup_text(normalized_text)

        search_keyword = self._build_search_keyword(normalized_text)
        if not search_keyword:
            raise ValueError("Extracted medication text is empty.")

        medication_details = await self._fetch_drug_info(search_keyword)
        if not medication_details:
            return MedicationResponse(
                success=False,
                message=f"No medication information found for '{search_keyword}'.",
                data=[],
            )

        return MedicationResponse(
            success=True,
            message="Medication information lookup succeeded.",
            data=medication_details,
        )

    # Function Name: requestMedicationDetail
    # Description:
    # - Class diagram compatible wrapper for request_medication_detail.
    # Parameters:
    # - raw_text: Raw medication text supplied by the frontend.
    # Returns:
    # - MedicationResponse with success flag and MedicationDetail list.
    async def requestMedicationDetail(self, raw_text: str) -> MedicationResponse:
        return await self.request_medication_detail(raw_text)

    # Function Name: _validate_lookup_text
    # Description:
    # - Validates normalized medication text before dosage suffix stripping.
    # Parameters:
    # - text: Normalized medication lookup text.
    # Returns:
    # - None.
    def _validate_lookup_text(self, text: str) -> None:
        if not text:
            raise ValueError("Extracted medication text is empty.")
        if len(text) > self.MAX_KEYWORD_LENGTH:
            raise ValueError("Medication lookup text is too long.")

    # Function Name: _normalize_raw_text
    # Description:
    # - Collapses raw OCR text into a single searchable line.
    # Parameters:
    # - raw_text: Raw text extracted from prescription or medication candidates.
    # Returns:
    # - Whitespace-normalized text.
    def _normalize_raw_text(self, raw_text: str) -> str:
        return " ".join(raw_text.replace("\n", " ").split()).strip()

    # Function Name: _build_search_keyword
    # Description:
    # - Builds the drug search keyword currently expected by public drug data.
    # Parameters:
    # - raw_text: Raw medication text from frontend.
    # Returns:
    # - Search keyword for public drug APIs.
    def _build_search_keyword(self, raw_text: str) -> str:
        normalized_text = self._normalize_raw_text(raw_text)
        parts = self._DOSAGE_PATTERN.split(normalized_text)
        keyword = parts[0] if parts else normalized_text
        return keyword.replace("정", "").replace("캡슐", "").strip()

    # Function Name: _fetch_drug_info
    # Description:
    # - Fetches enriched drug information for a normalized medication name.
    # Parameters:
    # - drug_name: Normalized medication search keyword.
    # Returns:
    # - List of MedicationDetail DTOs. Empty list when no public data exists.
    async def _fetch_drug_info(self, drug_name: str) -> list[MedicationDetail]:
        cached_drugs = await self._get_cached_medication_detail(drug_name)
        if cached_drugs is not None:
            return cached_drugs

        medication_details = await self._fetch_uncached_drug_info(drug_name)
        await self._save_cached_medication_detail(drug_name, medication_details)
        return medication_details

    # Function Name: _fetch_uncached_drug_info
    # Description:
    # - Runs the public API and AI pipeline after cache miss.
    # Parameters:
    # - drug_name: Normalized medication search keyword.
    # Returns:
    # - List of MedicationDetail DTOs.
    async def _fetch_uncached_drug_info(
        self,
        drug_name: str,
    ) -> list[MedicationDetail]:
        basic_items = await self._search_basic_drug_info(drug_name)
        if basic_items:
            logger.info(
                "[Basic API] '%s' search succeeded (%s items)",
                drug_name,
                len(basic_items),
            )
            return await self._build_basic_drug_infos(basic_items)

        logger.info(
            "[Basic API] no result. Trying Advanced API fallback: '%s'",
            drug_name,
        )
        advanced_items = await self._search_advanced_drug_info(drug_name)
        if not advanced_items:
            logger.warning(
                "[%s] no drug information found in public drug databases.",
                drug_name,
            )
            return []

        advanced_drug = await self._summarize_advanced_item(
            drug_name,
            advanced_items[0],
        )
        return [advanced_drug]

    # Function Name: _search_basic_drug_info
    # Description:
    # - Searches the easy public drug API by item name.
    # Parameters:
    # - drug_name: Search keyword.
    # Returns:
    # - Raw API item list. Empty list on no result or non-200 response.
    async def _search_basic_drug_info(self, drug_name: str) -> list[dict[str, Any]]:
        params = {
            "serviceKey": settings.PUBLIC_DATA_API_KEY,
            "itemName": drug_name,
            "type": "json",
            "numOfRows": 3,
        }

        async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
            response = await client.get(settings.BASIC_DRUG_API_BASE_URL, params=params)

        if response.status_code != 200:
            return []

        data = response.json()
        return data.get("body", {}).get("items") or []

    # Function Name: _search_advanced_drug_info
    # Description:
    # - Searches the advanced drug approval API by item name.
    # Parameters:
    # - drug_name: Search keyword.
    # Returns:
    # - Raw API item list.
    async def _search_advanced_drug_info(
        self,
        drug_name: str,
    ) -> list[dict[str, Any]]:
        params = {
            "serviceKey": settings.PUBLIC_DATA_API_KEY,
            "item_name": drug_name,
            "type": "json",
            "numOfRows": 1,
        }

        async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
            response = await client.get(
                settings.ADVANCED_DRUG_API_BASE_URL,
                params=params,
            )

        if response.status_code != 200:
            raise RuntimeError("공공데이터 API 서버와 통신할 수 없습니다.")

        data = response.json()
        return data.get("body", {}).get("items") or []

    # Function Name: _build_basic_drug_infos
    # Description:
    # - Converts Basic API items into MedicationDetail DTOs and adds AI guide text.
    # Parameters:
    # - basic_items: Raw Basic API items.
    # Returns:
    # - List of MedicationDetail DTOs.
    async def _build_basic_drug_infos(
        self,
        basic_items: list[dict[str, Any]],
    ) -> list[MedicationDetail]:
        medication_details = [
            MedicationDetail(
                item_name=item.get("itemName", "정보 없음"),
                efficacy=item.get("efcyQesitm", "정보 없음"),
                usage_method=item.get("useMethodQesitm", "정보 없음"),
                warning=item.get("atpnWarnQesitm", "정보 없음"),
                source="Basic (e약은요)",
            )
            for item in basic_items
        ]

        enriched_details = []
        for medication_detail in medication_details:
            logger.info(
                "[Gemini] generating basic patient guide for '%s'.",
                medication_detail.item_name,
            )
            enriched_details.append(
                await self._add_basic_guide(medication_detail)
            )

        return enriched_details

    # Function Name: _add_basic_guide
    # Description:
    # - Adds an AI guide to a MedicationDetail built from the basic public API.
    # - On Gemini failure, keeps the medication result and inserts a fallback message.
    # Parameters:
    # - medication_detail: MedicationDetail that needs an ai_guide.
    # Returns:
    # - MedicationDetail with ai_guide populated.
    async def _add_basic_guide(
        self,
        medication_detail: MedicationDetail,
    ) -> MedicationDetail:
        if medication_detail.ai_guide:
            return medication_detail

        raw_data = (
            f"효능: {medication_detail.efficacy}\n"
            f"사용법: {medication_detail.usage_method}\n"
            f"주의사항: {medication_detail.warning}"
        )
        prompt = f"""
        당신은 환자가 이해하기 쉬운 복약 정보를 제공하는 AI 약사입니다.
        다음 식약처 약품 설명서를 일반 사용자가 이해할 수 있도록 정리해 주세요.
        {raw_data}

        작성 규칙:
        1. 핵심 효능과 복용법을 1~2줄로 요약합니다.
        2. 주의해야 할 부작용 또는 복약 주의사항을 명확히 안내합니다.
        3. 전문성을 유지하되 부드러운 조언 말투를 사용합니다.
        """

        try:
            ai_response = await self.ai_client.aio.models.generate_content(
                model=self.model_name,
                contents=prompt,
            )
            return medication_detail.model_copy(
                update={"ai_guide": ai_response.text}
            )
        except Exception as exc:
            logger.error("Gemini API call failed: %s", exc)
            return medication_detail.model_copy(
                update={"ai_guide": "AI 요약을 불러오는 중 일시적인 오류가 발생했습니다."}
            )

    # Function Name: _summarize_advanced_item
    # Description:
    # - Converts advanced approval API raw documents into patient-facing MedicationDetail.
    # Parameters:
    # - drug_name: Original search keyword.
    # - advanced_item: Raw item from the advanced public API.
    # Returns:
    # - MedicationDetail generated from Gemini summary output.
    async def _summarize_advanced_item(
        self,
        drug_name: str,
        advanced_item: dict[str, Any],
    ) -> MedicationDetail:
        actual_item_name = advanced_item.get("ITEM_NAME", drug_name)
        raw_efficacy = str(advanced_item.get("EE_DOC_DATA", "정보 없음"))[:2000]
        raw_usage = str(advanced_item.get("UD_DOC_DATA", "정보 없음"))[:2000]
        raw_warning = str(advanced_item.get("NB_DOC_DATA", "정보 없음"))[:2000]

        prompt = f"""
        당신은 복약 정보를 환자에게 설명하는 AI 약사입니다.
        아래는 식약처 허가 정보 원문입니다.
        일반 환자가 이해하기 쉽게 각 항목을 2~3문장 이내로 명확하게 요약해 주세요.
        반드시 아래 4가지 키를 가진 JSON 형식으로만 응답해 주세요.

        {{
            "efficacy": "요약된 효능",
            "use_method": "요약된 용법",
            "warning_message": "요약된 주의사항",
            "ai_guide": "전문성을 유지하되 부드러운 조언 말투로 작성한 전체 복약 가이드 2줄 요약"
        }}

        [원문 데이터]
        - 효능: {raw_efficacy}
        - 용법: {raw_usage}
        - 주의: {raw_warning}
        """

        logger.info(
            "[Gemini] requesting advanced approval summary for '%s'.",
            actual_item_name,
        )

        try:
            ai_response = await self.ai_client.aio.models.generate_content(
                model=self.model_name,
                contents=prompt,
                config={"response_mime_type": "application/json"},
            )
            summary_data = json.loads(ai_response.text)
        except Exception as exc:
            logger.error("Gemini AI summary failed: %s", exc)
            raise RuntimeError("AI 요약 처리 중 오류가 발생했습니다.") from exc

        return MedicationDetail(
            item_name=actual_item_name,
            efficacy=summary_data.get("efficacy", "요약 실패"),
            usage_method=summary_data.get("use_method", "요약 실패"),
            warning=summary_data.get("warning_message", "요약 실패"),
            source="Advanced (허가정보) + AI 요약",
            ai_guide=summary_data.get("ai_guide", "요약 실패"),
        )

    # Function Name: _get_cached_medication_detail
    # Description:
    # - Attempts to load a MedicationDetail list from Redis.
    # - Cache failures are treated as misses to preserve service availability.
    # Parameters:
    # - drug_name: Search keyword used as cache key suffix.
    # Returns:
    # - Cached MedicationDetail list, or None when missing/unavailable.
    async def _get_cached_medication_detail(
        self,
        drug_name: str,
    ) -> list[MedicationDetail] | None:
        cache_key = self._cache_key(drug_name)
        try:
            cached_data = await self.redis_client.get(cache_key)
            if not cached_data:
                return None

            logger.info(
                "[Redis Cache Hit] '%s' information loaded from cache.",
                drug_name,
            )
            items = json.loads(cached_data)
            return [
                MedicationDetail(
                    **{
                        **item,
                        "source": f"[Cache] {item.get('source', '')}",
                    }
                )
                for item in items
            ]
        except Exception as exc:
            logger.warning("Redis lookup failed; proceeding without cache: %s", exc)
            return None

    # Function Name: _save_cached_medication_detail
    # Description:
    # - Stores a MedicationDetail list in Redis.
    # - Cache failures are logged but do not fail the use case.
    # Parameters:
    # - drug_name: Search keyword used as cache key suffix.
    # - medication_details: MedicationDetail list to cache.
    # Returns:
    # - None.
    async def _save_cached_medication_detail(
        self,
        drug_name: str,
        medication_details: list[MedicationDetail],
    ) -> None:
        if not medication_details:
            return

        cache_key = self._cache_key(drug_name)
        try:
            payload = [
                detail.model_dump(by_alias=True)
                for detail in medication_details
            ]
            await self.redis_client.setex(
                cache_key,
                self.CACHE_TTL_SECONDS,
                json.dumps(payload, ensure_ascii=False),
            )
            logger.info("[Redis Cache Saved] '%s' information cached.", drug_name)
        except Exception as exc:
            logger.error("Redis save failed: %s", exc)

    # Function Name: _cache_key
    # Description:
    # - Builds the Redis cache key for a medication search keyword.
    # Parameters:
    # - drug_name: Search keyword.
    # Returns:
    # - Redis key string.
    def _cache_key(self, drug_name: str) -> str:
        return f"drug_info:{drug_name}"
