# File Name: check_medication_detail_control.py
# Role: Control class for requesting medication detail information.

import json
import logging
import re
from typing import Any

import httpx
import redis.asyncio as redis
from google import genai
from sqlalchemy import or_
from sqlalchemy.orm import Session

from core.config import settings
from entities.medication_detail_entity import (
    MedicationDetail,
    _DrugApprovalInfo,
    _DrugBasicInfo,
)
from schemas.medication import MedicationResponse

logger = logging.getLogger(__name__)


# Class Name: _MedicationTextNormalizer
# Role: Internal helper for medication search keyword normalization.
# Responsibilities:
#   - Normalize OCR or UI-provided medication text.
#   - Strip dosage and dosage-form suffixes from search keywords.
class _MedicationTextNormalizer:
    _DOSAGE_PATTERN = re.compile(
        r"\d{1,10}(?:\.\d{1,5})?\s{0,5}(?:mg|g|ml)",
        flags=re.IGNORECASE,
    )

    # Function Name: normalize_raw_text
    # Description:
    # - Collapses raw OCR text into a single searchable line.
    # Parameters:
    # - raw_text: Raw medication text from the frontend.
    # Returns:
    # - Whitespace-normalized text.
    def normalize_raw_text(self, raw_text: str) -> str:
        return " ".join(raw_text.replace("\n", " ").split()).strip()

    # Function Name: build_search_keyword
    # Description:
    # - Builds the drug search keyword currently expected by public drug data.
    # Parameters:
    # - raw_text: Normalized or raw medication text.
    # Returns:
    # - Search keyword for local DB and public drug APIs.
    def build_search_keyword(self, raw_text: str) -> str:
        normalized_text = self.normalize_raw_text(raw_text)
        parts = self._DOSAGE_PATTERN.split(normalized_text)
        keyword = parts[0] if parts else normalized_text
        return keyword.replace("정", "").replace("캡슐", "").strip()


# Class Name: _MedicationDetailCache
# Role: Internal Redis cache boundary for medication detail lookup.
# Responsibilities:
#   - Read cached MedicationDetail lists.
#   - Save MedicationDetail lists without failing the main use case on Redis errors.
# Attributes:
#   - redis_client: Async Redis client used as optional cache storage.
class _MedicationDetailCache:
    CACHE_TTL_SECONDS = 604800

    def __init__(self, redis_client: redis.Redis | None = None) -> None:
        self.redis_client = redis_client or redis.from_url(
            settings.REDIS_URL,
            decode_responses=True,
        )

    # Function Name: get
    # Description:
    # - Attempts to load MedicationDetail values from Redis.
    # - Cache failures are treated as misses to preserve service availability.
    # Parameters:
    # - drug_name: Search keyword used as cache key suffix.
    # Returns:
    # - Cached MedicationDetail list, or None when missing/unavailable.
    async def get(self, drug_name: str) -> list[MedicationDetail] | None:
        try:
            cached_data = await self.redis_client.get(self._cache_key(drug_name))
            if not cached_data:
                return None

            logger.info("[Redis] cache hit for '%s'.", drug_name)
            cached_items = json.loads(cached_data)
            if not isinstance(cached_items, list):
                return None

            return [
                MedicationDetail(
                    **{
                        **item,
                        "source": f"[Cache] {item.get('source', '')}",
                    }
                )
                for item in cached_items
                if isinstance(item, dict)
            ]
        except Exception as exc:
            logger.warning("Redis lookup failed; proceeding without cache: %s", exc)
            return None

    # Function Name: set
    # Description:
    # - Stores MedicationDetail values in Redis.
    # - Cache failures are logged but do not fail the use case.
    # Parameters:
    # - drug_name: Search keyword used as cache key suffix.
    # - medication_details: MedicationDetail list to cache.
    # Returns:
    # - None.
    async def set(
        self,
        drug_name: str,
        medication_details: list[MedicationDetail],
    ) -> None:
        if not medication_details:
            return

        try:
            payload = [
                detail.model_dump(by_alias=True)
                for detail in medication_details
            ]
            await self.redis_client.setex(
                self._cache_key(drug_name),
                self.CACHE_TTL_SECONDS,
                json.dumps(payload, ensure_ascii=False),
            )
            logger.info("[Redis] cached medication detail for '%s'.", drug_name)
        except Exception as exc:
            logger.error("Redis save failed: %s", exc)

    def _cache_key(self, drug_name: str) -> str:
        return f"drug_info:{drug_name}"


# Class Name: _PublicDrugDataPortal
# Role: Internal boundary for public medication data APIs.
# Responsibilities:
#   - Query e약은요 as the primary public data source.
#   - Query drug approval information as fallback.
# Attributes:
#   - timeout_seconds: HTTP timeout value for public API requests.
class _PublicDrugDataPortal:
    def __init__(self, timeout_seconds: float = 15.0) -> None:
        self.timeout_seconds = timeout_seconds

    # Function Name: search_basic_drug_info
    # Description:
    # - Searches the e약은요 API by item name.
    # Parameters:
    # - drug_name: Search keyword.
    # Returns:
    # - Raw API item list. Empty list on no result or non-200 response.
    async def search_basic_drug_info(
        self,
        drug_name: str,
    ) -> list[dict[str, Any]]:
        params = {
            "serviceKey": settings.PUBLIC_DATA_API_KEY,
            "itemName": drug_name,
            "type": "json",
            "numOfRows": 3,
        }

        try:
            items, _ = await self._request_items(
                settings.BASIC_DRUG_API_BASE_URL,
                params,
            )
            return items
        except Exception as exc:
            logger.warning("Basic public drug API lookup failed: %s", exc)
            return []

    # Function Name: search_advanced_drug_info
    # Description:
    # - Searches the advanced drug approval API by item name.
    # Parameters:
    # - drug_name: Search keyword.
    # Returns:
    # - Raw API item list.
    async def search_advanced_drug_info(
        self,
        drug_name: str,
    ) -> list[dict[str, Any]]:
        params = {
            "serviceKey": settings.PUBLIC_DATA_API_KEY,
            "item_name": drug_name,
            "type": "json",
            "numOfRows": 1,
        }

        items, _ = await self._request_items(
            settings.ADVANCED_DRUG_API_BASE_URL,
            params,
        )
        return items

    # Function Name: fetch_basic_drug_info_page
    # Description:
    # - Fetches one unfiltered page from the e약은요 API for local DB sync.
    # Parameters:
    # - page_no: Page number to fetch.
    # - num_of_rows: Number of rows per page.
    # Returns:
    # - Tuple of raw item list and totalCount.
    async def fetch_basic_drug_info_page(
        self,
        page_no: int,
        num_of_rows: int,
    ) -> tuple[list[dict[str, Any]], int]:
        params = {
            "serviceKey": settings.PUBLIC_DATA_API_KEY,
            "pageNo": page_no,
            "numOfRows": num_of_rows,
            "type": "json",
        }
        return await self._request_items(settings.BASIC_DRUG_API_BASE_URL, params)

    # Function Name: fetch_approval_drug_info_page
    # Description:
    # - Fetches one unfiltered page from the approval detail API for local DB sync.
    # Parameters:
    # - page_no: Page number to fetch.
    # - num_of_rows: Number of rows per page.
    # Returns:
    # - Tuple of raw item list and totalCount.
    async def fetch_approval_drug_info_page(
        self,
        page_no: int,
        num_of_rows: int,
    ) -> tuple[list[dict[str, Any]], int]:
        params = {
            "serviceKey": settings.PUBLIC_DATA_API_KEY,
            "pageNo": page_no,
            "numOfRows": num_of_rows,
            "type": "json",
        }
        return await self._request_items(settings.ADVANCED_DRUG_API_BASE_URL, params)

    async def _request_items(
        self,
        url: str,
        params: dict[str, object],
    ) -> tuple[list[dict[str, Any]], int]:
        async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
            response = await client.get(url, params=params)

        if response.status_code != 200:
            raise RuntimeError("공공데이터 API 서버와 통신할 수 없습니다.")

        data = response.json()
        body = self._extract_body(data)
        return self._normalize_items(body.get("items")), self._safe_int(
            body.get("totalCount")
        )

    def _extract_body(self, data: dict[str, Any]) -> dict[str, Any]:
        body = data.get("body")
        if isinstance(body, dict):
            return body

        response = data.get("response")
        if isinstance(response, dict) and isinstance(response.get("body"), dict):
            return response["body"]

        return {}

    def _normalize_items(self, raw_items: Any) -> list[dict[str, Any]]:
        if raw_items is None:
            return []
        if isinstance(raw_items, list):
            return [item for item in raw_items if isinstance(item, dict)]
        if isinstance(raw_items, dict):
            nested_item = raw_items.get("item")
            if nested_item is not None:
                return self._normalize_items(nested_item)

            nested_items = raw_items.get("items")
            if nested_items is not None:
                return self._normalize_items(nested_items)

            return [raw_items]
        return []

    def _safe_int(self, value: Any) -> int:
        try:
            return int(value)
        except (TypeError, ValueError):
            return 0


# Class Name: _MedicationGuideGenerator
# Role: Internal AI boundary for patient-facing medication guide generation.
# Responsibilities:
#   - Add plain-language guide text to Basic API results.
#   - Summarize advanced approval documents into MedicationDetail fields.
# Attributes:
#   - ai_client: Gemini client used for medication guidance generation.
#   - model_name: Gemini model name.
class _MedicationGuideGenerator:
    def __init__(
        self,
        ai_client: genai.Client | None = None,
        model_name: str = "gemini-3.1-flash-lite",
    ) -> None:
        self.ai_client = ai_client or genai.Client(api_key=settings.GEMINI_API_KEY)
        self.model_name = model_name

    # Function Name: add_basic_guide
    # Description:
    # - Adds an AI guide to a MedicationDetail built from e약은요 data.
    # - On Gemini failure, keeps the medication result and inserts a fallback message.
    # Parameters:
    # - medication_detail: MedicationDetail that needs an ai_guide.
    # Returns:
    # - MedicationDetail with ai_guide populated.
    async def add_basic_guide(
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
        3. 전문성을 유지하되 부드러운 존댓말을 사용합니다.
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

    # Function Name: summarize_advanced_item
    # Description:
    # - Converts advanced approval API raw documents into patient-facing MedicationDetail.
    # Parameters:
    # - drug_name: Original search keyword.
    # - advanced_item: Raw item from the advanced public API or local approval DB.
    # Returns:
    # - MedicationDetail generated from Gemini summary output.
    async def summarize_advanced_item(
        self,
        drug_name: str,
        advanced_item: dict[str, Any],
    ) -> MedicationDetail:
        actual_item_name = str(advanced_item.get("ITEM_NAME") or drug_name)
        raw_efficacy = str(advanced_item.get("EE_DOC_DATA") or "정보 없음")[:2000]
        raw_usage = str(advanced_item.get("UD_DOC_DATA") or "정보 없음")[:2000]
        raw_warning = str(advanced_item.get("NB_DOC_DATA") or "정보 없음")[:2000]

        prompt = f"""
        당신은 복약 정보를 환자에게 설명하는 AI 약사입니다.
        아래는 식약처 허가 정보 원문입니다.
        일반 환자가 이해하기 쉽게 각 항목을 2~3문장 이내로 명확하게 요약해 주세요.
        반드시 아래 4가지 키를 가진 JSON 형식으로만 응답해 주세요.

        {{
            "efficacy": "요약된 효능",
            "use_method": "요약된 용법",
            "warning_message": "요약된 주의사항",
            "ai_guide": "전문성을 유지하되 부드러운 존댓말로 작성한 전체 복약 가이드 2줄 요약"
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


# Class Name: _LocalMedicationCatalog
# Role: Internal local SQLite lookup helper for mirrored public medication data.
# Responsibilities:
#   - Search locally mirrored e약은요 rows before approval rows.
#   - Convert local records into MedicationDetail DTOs.
#   - Persist AI summaries generated on first local DB use.
# Attributes:
#   - db: Optional SQLAlchemy session. None disables local DB lookup.
#   - guide_generator: AI guide generator for missing local summaries.
class _LocalMedicationCatalog:
    _WHITESPACE_PATTERN = re.compile(r"\s+")

    def __init__(
        self,
        db: Session | None,
        guide_generator: _MedicationGuideGenerator,
    ) -> None:
        self.db = db
        self.guide_generator = guide_generator

    # Function Name: fetch_drug_info
    # Description:
    # - Searches local e약은요 rows first, then local approval rows.
    # Parameters:
    # - drug_name: Normalized medication search keyword.
    # Returns:
    # - List of MedicationDetail DTOs, or an empty list when local DB has no match.
    async def fetch_drug_info(self, drug_name: str) -> list[MedicationDetail]:
        if self.db is None:
            return []

        basic_items = self._search_basic(drug_name)
        if basic_items:
            logger.info(
                "[Local DB] e약은요 lookup succeeded for '%s' (%s items).",
                drug_name,
                len(basic_items),
            )
            return await self._build_basic_details(basic_items)

        approval_items = self._search_approval(drug_name)
        if not approval_items:
            return []

        logger.info("[Local DB] approval lookup succeeded for '%s'.", drug_name)
        return [await self._build_approval_detail(drug_name, approval_items[0])]

    def _search_basic(self, drug_name: str, limit: int = 3) -> list[_DrugBasicInfo]:
        keyword = self._normalize_name(drug_name)
        if not keyword:
            return []

        exact_matches = (
            self.db.query(_DrugBasicInfo)
            .filter(_DrugBasicInfo.normalized_item_name == keyword)
            .limit(limit)
            .all()
        )
        if exact_matches:
            return exact_matches

        return (
            self.db.query(_DrugBasicInfo)
            .filter(
                or_(
                    _DrugBasicInfo.normalized_item_name.like(
                        self._like_pattern(keyword, suffix="%"),
                        escape="\\",
                    ),
                    _DrugBasicInfo.normalized_item_name.like(
                        self._like_pattern(keyword, prefix="%", suffix="%"),
                        escape="\\",
                    ),
                )
            )
            .limit(limit)
            .all()
        )

    def _search_approval(
        self,
        drug_name: str,
        limit: int = 1,
    ) -> list[_DrugApprovalInfo]:
        keyword = self._normalize_name(drug_name)
        if not keyword:
            return []

        exact_matches = (
            self.db.query(_DrugApprovalInfo)
            .filter(_DrugApprovalInfo.normalized_item_name == keyword)
            .limit(limit)
            .all()
        )
        if exact_matches:
            return exact_matches

        return (
            self.db.query(_DrugApprovalInfo)
            .filter(
                or_(
                    _DrugApprovalInfo.normalized_item_name.like(
                        self._like_pattern(keyword, suffix="%"),
                        escape="\\",
                    ),
                    _DrugApprovalInfo.normalized_item_name.like(
                        self._like_pattern(keyword, prefix="%", suffix="%"),
                        escape="\\",
                    ),
                )
            )
            .limit(limit)
            .all()
        )

    async def _build_basic_details(
        self,
        basic_items: list[_DrugBasicInfo],
    ) -> list[MedicationDetail]:
        enriched_details = []
        for item in basic_items:
            medication_detail = MedicationDetail(
                item_name=item.item_name,
                efficacy=item.efficacy or "정보 없음",
                usage_method=item.use_method or "정보 없음",
                warning=item.warning_message or "정보 없음",
                interaction=item.interaction or "",
                side_effect=item.side_effect or "",
                storage_method=item.deposit_method or "",
                source="Local DB (e약은요)",
                ai_guide=item.ai_guide,
            )
            if not medication_detail.ai_guide:
                medication_detail = await self.guide_generator.add_basic_guide(
                    medication_detail
                )
                self._save_basic_ai_guide(item, medication_detail.ai_guide)

            enriched_details.append(medication_detail)

        return enriched_details

    async def _build_approval_detail(
        self,
        drug_name: str,
        approval_item: _DrugApprovalInfo,
    ) -> MedicationDetail:
        cached_summary = self._build_cached_approval_summary(approval_item)
        if cached_summary is not None:
            return cached_summary

        raw_item = self._load_raw_approval_item(approval_item)
        medication_detail = await self.guide_generator.summarize_advanced_item(
            drug_name,
            raw_item,
        )
        medication_detail = medication_detail.model_copy(
            update={"source": "Local DB (허가정보) + AI 요약"}
        )
        self._save_approval_summary(approval_item, medication_detail)
        return medication_detail

    def _build_cached_approval_summary(
        self,
        approval_item: _DrugApprovalInfo,
    ) -> MedicationDetail | None:
        if not (
            approval_item.summary_efficacy
            and approval_item.summary_use_method
            and approval_item.summary_warning_message
        ):
            return None

        return MedicationDetail(
            item_name=approval_item.item_name,
            efficacy=approval_item.summary_efficacy,
            usage_method=approval_item.summary_use_method,
            warning=approval_item.summary_warning_message,
            source="Local DB (허가정보) + 저장된 AI 요약",
            ai_guide=approval_item.ai_guide,
        )

    def _load_raw_approval_item(
        self,
        approval_item: _DrugApprovalInfo,
    ) -> dict[str, Any]:
        try:
            raw_item = json.loads(approval_item.raw_json)
            if isinstance(raw_item, dict):
                normalized_item = self._normalize_raw_approval_item(
                    raw_item,
                    approval_item,
                )
                if normalized_item is not None:
                    return normalized_item
        except json.JSONDecodeError:
            logger.warning(
                "Local approval raw_json decode failed: item_name=%s",
                approval_item.item_name,
            )

        return self._approval_columns_to_raw_item(approval_item)

    def _normalize_raw_approval_item(
        self,
        raw_item: dict[str, Any],
        approval_item: _DrugApprovalInfo,
    ) -> dict[str, Any] | None:
        normalized_item = {
            "ITEM_NAME": self._read_first_raw_text(
                raw_item,
                ["ITEM_NAME", "itemName", "item_name"],
            )
            or approval_item.item_name,
            "EE_DOC_DATA": self._read_first_raw_text(
                raw_item,
                ["EE_DOC_DATA", "efcyQesitm"],
            )
            or approval_item.efficacy_doc,
            "UD_DOC_DATA": self._read_first_raw_text(
                raw_item,
                ["UD_DOC_DATA", "useMethodQesitm"],
            )
            or approval_item.use_method_doc,
            "NB_DOC_DATA": self._read_first_raw_text(
                raw_item,
                ["NB_DOC_DATA", "atpnWarnQesitm"],
            )
            or approval_item.warning_doc,
        }
        if any(
            normalized_item[key]
            for key in ("EE_DOC_DATA", "UD_DOC_DATA", "NB_DOC_DATA")
        ):
            return normalized_item
        return None

    def _approval_columns_to_raw_item(
        self,
        approval_item: _DrugApprovalInfo,
    ) -> dict[str, Any]:
        return {
            "ITEM_NAME": approval_item.item_name,
            "EE_DOC_DATA": approval_item.efficacy_doc or "정보 없음",
            "UD_DOC_DATA": approval_item.use_method_doc or "정보 없음",
            "NB_DOC_DATA": approval_item.warning_doc or "정보 없음",
        }

    def _read_first_raw_text(
        self,
        raw_item: dict[str, Any],
        keys: list[str],
    ) -> str:
        lowered_items = {
            str(existing_key).lower(): existing_value
            for existing_key, existing_value in raw_item.items()
        }
        for key in keys:
            value = raw_item.get(key)
            if value is None:
                value = lowered_items.get(key.lower())
            if value is not None and str(value).strip():
                return str(value).strip()
        return ""

    def _save_basic_ai_guide(
        self,
        basic_info: _DrugBasicInfo,
        ai_guide: str | None,
    ) -> None:
        if not ai_guide:
            return

        try:
            basic_info.ai_guide = ai_guide
            self.db.commit()
        except Exception as exc:
            self.db.rollback()
            logger.warning("Failed to persist local AI guide: %s", exc)

    def _save_approval_summary(
        self,
        approval_info: _DrugApprovalInfo,
        medication_detail: MedicationDetail,
    ) -> None:
        try:
            approval_info.summary_efficacy = medication_detail.efficacy
            approval_info.summary_use_method = medication_detail.usage_method
            approval_info.summary_warning_message = medication_detail.warning
            approval_info.ai_guide = medication_detail.ai_guide
            self.db.commit()
        except Exception as exc:
            self.db.rollback()
            logger.warning("Failed to persist local approval summary: %s", exc)

    @classmethod
    def _normalize_name(cls, name: str) -> str:
        return cls._WHITESPACE_PATTERN.sub("", name).strip().lower()

    def _like_pattern(
        self,
        keyword: str,
        prefix: str = "",
        suffix: str = "",
    ) -> str:
        escaped_keyword = (
            keyword.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        )
        return f"{prefix}{escaped_keyword}{suffix}"


# Class Name: CheckMedicationDetail
# Role: Coordinates medication keyword normalization and detail lookup.
# Responsibilities:
#   - Validate medication lookup text.
#   - Query the local medication catalog before Redis or runtime public APIs.
#   - Coordinate cache, public data fallback, and patient-facing guide generation.
#   - Build the API response DTO.
# Attributes:
#   - text_normalizer: Internal helper for search keyword generation.
#   - medication_cache: Internal cache helper.
#   - public_drug_data_portal: Internal public API boundary.
#   - guide_generator: Internal AI guide generator.
#   - local_medication_catalog: Internal local SQLite lookup helper.
class CheckMedicationDetail:
    MAX_KEYWORD_LENGTH = 100

    def __init__(
        self,
        db: Session | None = None,
        text_normalizer: _MedicationTextNormalizer | None = None,
        medication_cache: _MedicationDetailCache | None = None,
        public_drug_data_portal: _PublicDrugDataPortal | None = None,
        guide_generator: _MedicationGuideGenerator | None = None,
        local_medication_catalog: _LocalMedicationCatalog | None = None,
    ) -> None:
        self.text_normalizer = text_normalizer or _MedicationTextNormalizer()
        self.medication_cache = medication_cache or _MedicationDetailCache()
        self.public_drug_data_portal = (
            public_drug_data_portal or _PublicDrugDataPortal()
        )
        self.guide_generator = guide_generator or _MedicationGuideGenerator()
        self.local_medication_catalog = local_medication_catalog or _LocalMedicationCatalog(
            db=db,
            guide_generator=self.guide_generator,
        )

    # Function Name: request_medication_detail
    # Description:
    # - Normalizes medication text and fetches detailed drug information.
    # Parameters:
    # - raw_text: Raw medication text supplied by the frontend.
    # Returns:
    # - MedicationResponse with success flag and MedicationDetail list.
    async def request_medication_detail(self, raw_text: str) -> MedicationResponse:
        normalized_text = self.text_normalizer.normalize_raw_text(raw_text)
        self._validate_lookup_text(normalized_text)

        search_keyword = self.text_normalizer.build_search_keyword(normalized_text)
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

    def _validate_lookup_text(self, text: str) -> None:
        if not text:
            raise ValueError("Extracted medication text is empty.")
        if len(text) > self.MAX_KEYWORD_LENGTH:
            raise ValueError("Medication lookup text is too long.")

    async def _fetch_drug_info(self, drug_name: str) -> list[MedicationDetail]:
        local_drugs = await self.local_medication_catalog.fetch_drug_info(drug_name)
        if local_drugs:
            return local_drugs

        cached_drugs = await self.medication_cache.get(drug_name)
        if cached_drugs is not None:
            return cached_drugs

        medication_details = await self._fetch_public_drug_info(drug_name)
        await self.medication_cache.set(drug_name, medication_details)
        return medication_details

    async def _fetch_public_drug_info(
        self,
        drug_name: str,
    ) -> list[MedicationDetail]:
        basic_items = await self.public_drug_data_portal.search_basic_drug_info(
            drug_name
        )
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
        advanced_items = await self.public_drug_data_portal.search_advanced_drug_info(
            drug_name
        )
        if not advanced_items:
            logger.warning(
                "[%s] no drug information found in public drug databases.",
                drug_name,
            )
            return []

        advanced_drug = await self.guide_generator.summarize_advanced_item(
            drug_name,
            advanced_items[0],
        )
        return [advanced_drug]

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
                await self.guide_generator.add_basic_guide(medication_detail)
            )

        return enriched_details
