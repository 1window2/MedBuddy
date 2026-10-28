# File Name: check_medication_detail_control.py
# Role: Coordinates medication-detail lookup and original-evidence validation across cohesive catalog, cache and public-service adapters.

import asyncio
import logging
from typing import Any, Literal

from sqlalchemy.orm import Session

from boundaries.medication_detail_cache_boundary import MedicationDetailCache
from boundaries.medication_summary_boundary import (
    MedicationSummaryGenerator,
    gather_summaries_keeping_successes,
    read_medication_detail_text,
)
from boundaries.public_drug_api_boundary import (
    PillImageAPI,
    PublicDrugLargeAPI,
    PublicDrugSmallAPI,
    read_public_image_url,
    read_public_item_name,
    read_public_item_sequence,
)
from entities.medication_detail_entity import MedicationDetail
from entities.medication_lookup_result import MedicationLookupResult
from schemas.medication import MedicationResponse
from services.local_medication_catalog import LocalMedicationCatalog
from services.medication_match_safety import can_auto_match, match_conflict
from services.medication_name_matching import MedicationNameMatcher, MedicationTextNormalizer

logger = logging.getLogger(__name__)


# 클래스명: CheckMedicationDetail
# 역할:
# - 약품명 후보를 정규화해 로컬·캐시·공공 API를 조회하고 부족한 이미지와 허가 요약을 보완한다.
# 주요 책임:
# - 검색어 길이와 이름 신뢰도를 검증하고 로컬·Redis·기본 API·허가 API 순서로 상세 정보를 보완한다.
# 속성:
# - text_normalizer (MedicationTextNormalizer): OCR 특성을 반영한 약품명 정규화·변형 생성기.
# - medication_cache (MedicationDetailCache): 약품 상세 결과를 보관하는 공유 Redis 캐시.
# - public_drug_small_api (PublicDrugSmallAPI): 기본 공공 약품 정보 API 경계.
# - public_drug_large_api (PublicDrugLargeAPI): 상세 약품 허가 문서 API 경계.
# - pill_image_api (PillImageAPI): 공공 약품 이미지 조회 API 경계.
# - summary_generator (MedicationSummaryGenerator): 상세 허가 문서의 AI 요약 생성기.
# - local_medication_catalog (LocalMedicationCatalog): 문서 요약 캐시를 포함한 로컬 기본·허가 정보 조회기.
class CheckMedicationDetail:
    MAX_KEYWORD_LENGTH = 100
    # 프런트엔드의 60초 제한 안에서 응답할 여유를 남기며 모드별로 시간을 늘리지 않는다.
    LOOKUP_TIMEOUT_SECONDS = 50.0

    # 함수이름: __init__
    # 함수역할:
    # - 이름 보정·유사도 비교, Redis 캐시, 공공 약품·이미지 API와 로컬 카탈로그를 연결한다.
    # 매개변수:
    # - db (Session | None): 현재 작업에 사용할 SQLAlchemy 세션.
    # - text_normalizer (MedicationTextNormalizer | None): OCR 특성을 반영한 약품명 정규화·변형 생성기.
    # - medication_cache (MedicationDetailCache | None): 약품 상세 결과를 보관하는 공유 Redis 캐시.
    # - public_drug_small_api (PublicDrugSmallAPI | None): 기본 공공 약품 정보 API 경계.
    # - public_drug_large_api (PublicDrugLargeAPI | None): 상세 약품 허가 문서 API 경계.
    # - pill_image_api (PillImageAPI | None): 공공 약품 이미지 조회 API 경계.
    # - summary_generator (MedicationSummaryGenerator | None): 상세 허가 문서의 AI 요약 생성기.
    # - local_medication_catalog (LocalMedicationCatalog | None): 문서 요약 캐시를 포함한 로컬 기본·허가 정보 조회기.
    # - name_matcher (MedicationNameMatcher | None): 약품명 유사도 점수 계산과 신뢰도 필터.
    # 반환값:
    # - 없음.
    def __init__(
        self,
        db: Session | None = None,
        text_normalizer: MedicationTextNormalizer | None = None,
        medication_cache: MedicationDetailCache | None = None,
        public_drug_small_api: PublicDrugSmallAPI | None = None,
        public_drug_large_api: PublicDrugLargeAPI | None = None,
        pill_image_api: PillImageAPI | None = None,
        summary_generator: MedicationSummaryGenerator | None = None,
        local_medication_catalog: LocalMedicationCatalog | None = None,
        name_matcher: MedicationNameMatcher | None = None,
    ) -> None:
        self.text_normalizer = text_normalizer or MedicationTextNormalizer()
        self.name_matcher = name_matcher or MedicationNameMatcher(
            self.text_normalizer
        )
        self.medication_cache = medication_cache or MedicationDetailCache()
        self.public_drug_small_api = public_drug_small_api or PublicDrugSmallAPI()
        self.public_drug_large_api = public_drug_large_api or PublicDrugLargeAPI()
        self.pill_image_api = pill_image_api or PillImageAPI()
        self.summary_generator = summary_generator or MedicationSummaryGenerator()
        self.local_medication_catalog = local_medication_catalog or LocalMedicationCatalog(
            db=db,
            summary_generator=self.summary_generator,
            name_matcher=self.name_matcher,
        )

    # Function Name: requestMedicationDetail
    # Description:
    # - Normalizes medication text and fetches detailed drug information.
    # Parameters:
    # - raw_text (str): Raw medication text supplied by the frontend.
    # - original_text (str | None): OCR evidence retained before an automatic name correction.
    # Returns:
    # - Exact product details, or confirmation-only candidates without automatic data.
    async def requestMedicationDetail(
        self, raw_text: str, *, original_text: str | None = None,
        search_mode: Literal['fast', 'balanced', 'thorough'] = 'balanced',
    ) -> MedicationResponse:
        if search_mode not in MedicationTextNormalizer.SEARCH_KEYWORD_LIMITS:
            raise ValueError("Invalid medication search mode.")
        normalized_text = self.text_normalizer.normalize_raw_text(raw_text)
        self._validate_lookup_text(normalized_text)
        reference = self.text_normalizer.normalize_raw_text(original_text or raw_text)
        self._validate_lookup_text(reference)

        # 기본 모드에서는 기존 한 인자 정규화기 대역과 호출 계약을 유지한다.
        search_keywords = self.text_normalizer.build_search_keywords(
            normalized_text,
            **({'search_mode': search_mode} if search_mode != 'balanced' else {}),
        )[:MedicationTextNormalizer.SEARCH_KEYWORD_LIMITS[search_mode]]
        if not search_keywords:
            raise ValueError("Extracted medication text is empty.")

        logger.info("Medication lookup generated %s candidate(s).", len(search_keywords))

        candidates_by_product: dict[str | tuple[str, str], MedicationDetail] = {}
        lookup_complete = True
        rejected = False
        exact: list[MedicationDetail] = []
        # 검색어는 순차 조회하며 시간 초과·공급자 오류는 빈 결과로 바꾸지 않는다.
        async with asyncio.timeout(self.LOOKUP_TIMEOUT_SECONDS):
            for search_keyword in search_keywords:
                found = await self._fetch_drug_info(search_keyword, reference=reference)
                lookup_complete = lookup_complete and found.is_complete
                safe = [item for item in found.details if not match_conflict(
                    reference, item.item_name, allow_unknown_strength=True,
                )]
                rejected = rejected or len(safe) != len(found.details)
                ranked = self.name_matcher.rank_candidates(
                    reference, safe, lambda item: item.item_name, limit=5,
                    allow_unknown_strength=True,
                )
                for item in ranked:
                    key = item.item_seq or (item.item_name, item.manufacturer)
                    existing = candidates_by_product.get(key)
                    if existing is None or (
                        can_auto_match(reference, item.item_name)
                        and not can_auto_match(reference, existing.item_name)
                    ):
                        candidates_by_product[key] = item
                exact = [item for item in candidates_by_product.values()
                         if can_auto_match(reference, item.item_name)]
                if len(exact) == 1 and lookup_complete:
                    break
                if candidates_by_product and search_mode != 'thorough':
                    break

        if not candidates_by_product:
            return MedicationResponse(
                success=False,
                message=f"No medication information found for '{search_keywords[0]}'.",
                data=[],
                review_reason='strength_or_form' if rejected else 'not_found',
            )

        # 최대 8회×5개만 누적한다. 표시 개수 제한이 다른 동일명 품목의 존재를 지우면 안 된다.
        if len(exact) == 1 and lookup_complete:
            medication_details = exact
        else:
            medication_details = self.name_matcher.rank_candidates(
                reference, list(candidates_by_product.values()),
                lambda item: item.item_name, limit=5,
                allow_unknown_strength=True,
            )
            return MedicationResponse(
                success=True, message="Confirm the product against the prescription.",
                data=[], candidates=medication_details, requires_confirmation=True,
                review_reason='ambiguous_product',
            )

        return MedicationResponse(
            success=True,
            message="Medication information lookup succeeded.",
            data=medication_details,
        )

    # Function Name: _validate_lookup_text
    # Description:
    # - Rejects blank medication queries and queries exceeding the 100-character lookup limit.
    # Parameters:
    # - text (str): Extracted medication query to validate before lookup.
    # Returns:
    # - None.
    def _validate_lookup_text(self, text: str) -> None:
        if not text:
            raise ValueError("Extracted medication text is empty.")
        if len(text) > self.MAX_KEYWORD_LENGTH:
            raise ValueError("Medication lookup text is too long.")

    # 함수이름: _fetch_drug_info
    # 함수역할:
    # - 로컬 조회를 우선하고 신뢰 가능한 캐시 후보를 확인한 뒤 공공 API 결과를 캐시에 저장한다.
    # 매개변수:
    # - drug_name (str): 검색 또는 직렬화할 약품명.
    # 반환값:
    # - 이미지가 보완된 약품 상세 목록과 후보 요약 완결 여부.
    async def _fetch_drug_info(self, drug_name: str, *, reference: str | None = None) -> MedicationLookupResult:
        reference = reference or drug_name
        local_result = await self.local_medication_catalog.fetch_drug_info(drug_name)
        local_drugs = self.name_matcher.rank_candidates(
            reference, local_result.details, lambda item: item.item_name, limit=5,
            allow_unknown_strength=True,
        )
        if local_drugs:
            return MedicationLookupResult(
                await self._enrich_missing_image_urls(local_drugs),
                is_complete=local_result.is_complete,
            )

        cache_name = drug_name if reference == drug_name else f'{reference}|{drug_name}'
        cached_drugs = await self.medication_cache.get(cache_name)
        if cached_drugs is not None:
            ranked_cached_drugs = self.name_matcher.rank_candidates(
                reference,
                cached_drugs,
                lambda item: item.item_name,
                limit=3,
                allow_unknown_strength=True,
            )
            if ranked_cached_drugs:
                return MedicationLookupResult(
                    await self._enrich_missing_image_urls(ranked_cached_drugs),
                    is_complete=local_result.is_complete,
                )

        public_result = await self._fetch_public_drug_info(drug_name, reference=reference)
        result = MedicationLookupResult(
            public_result.details,
            is_complete=local_result.is_complete and public_result.is_complete,
        )
        await self.medication_cache.set(cache_name, result)
        return result

    # 함수이름: _enrich_missing_image_urls
    # 함수역할:
    # - 기존 이미지는 유지하고 이미지가 없는 약품만 공공 이미지 API로 병렬 보완한다.
    # 매개변수:
    # - medication_details (list[MedicationDetail]): 누락 이미지를 보완할 약품 상세 객체 목록.
    # 반환값:
    # - 입력 순서를 유지한 약품 상세 목록.
    async def _enrich_missing_image_urls(
        self,
        medication_details: list[MedicationDetail],
    ) -> list[MedicationDetail]:
        # 함수이름: enrich_detail
        # 함수역할:
        # - 이미지가 없는 약품에 한해 품목 식별자·이름으로 이미지를 찾아 복사본에 추가한다.
        # 매개변수:
        # - medication_detail (MedicationDetail): 환자에게 표시할 약품 안내와 품목 정보.
        # 반환값:
        # - 이미지가 추가된 상세 복사본 또는 변경 없는 원본.
        async def enrich_detail(
            medication_detail: MedicationDetail,
        ) -> MedicationDetail:
            if medication_detail.image_url.strip():
                return medication_detail

            image_url = await self.pill_image_api.searchMedicationImage(
                medication_detail.item_name,
                medication_detail.item_seq,
            )
            if not image_url:
                return medication_detail

            return medication_detail.model_copy(
                update={"image_url": image_url}
            )

        return list(
            await asyncio.gather(
                *(enrich_detail(detail) for detail in medication_details),
            )
        )

    # 함수이름: _fetch_public_drug_info
    # 함수역할:
    # - 기본 API의 상위 후보를 우선 사용하고 없으면 허가 API 후보를 최대 세 개 요약한다.
    # 매개변수:
    # - drug_name (str): 검색 또는 직렬화할 약품명.
    # 반환값:
    # - 신뢰도 기준을 통과한 상세 목록과 후보 요약 완결 여부.
    async def _fetch_public_drug_info(
        self,
        drug_name: str,
        *, reference: str | None = None,
    ) -> MedicationLookupResult:
        basic_items = await self.public_drug_small_api.searchMedication(drug_name)
        basic_items = self.name_matcher.rank_candidates(
            reference or drug_name,
            basic_items,
            read_public_item_name,
            limit=3,
            allow_unknown_strength=True,
        )
        if basic_items:
            logger.info(
                "[Basic API] search succeeded (%s items)",
                len(basic_items),
            )
            basic_details = await self._build_basic_drug_infos(basic_items)
            return MedicationLookupResult(await self._enrich_missing_image_urls(basic_details))

        logger.info("[Basic API] no result. Trying Advanced API fallback.")
        advanced_items = await self.public_drug_large_api.searchMedication(drug_name)
        advanced_items = self.name_matcher.rank_candidates(
            reference or drug_name,
            advanced_items,
            read_public_item_name,
            limit=3,
            allow_unknown_strength=True,
        )
        if not advanced_items:
            logger.warning("No drug information found in public drug databases.")
            return MedicationLookupResult()

        exact = [item for item in advanced_items
                 if can_auto_match(reference or drug_name, read_public_item_name(item))]
        if len(exact) == 1:
            advanced_items = exact
        result = await gather_summaries_keeping_successes(
            self.summary_generator.summarize_advanced_item(drug_name, dict(item))
            for item in advanced_items
        )
        return MedicationLookupResult(
            await self._enrich_missing_image_urls(result.details),
            is_complete=result.is_complete,
        )

    # 함수이름: _build_basic_drug_infos
    # 함수역할:
    # - 기본 API 응답의 효능·복용법·주의사항과 이미지를 상세 엔티티로 변환한다.
    # 매개변수:
    # - basic_items (list[dict[str, Any]]): 공공 품목·안내 필드를 포함한 기본 약품 기록 목록.
    # 반환값:
    # - 응답 순서의 약품 상세 목록.
    async def _build_basic_drug_infos(
        self,
        basic_items: list[dict[str, Any]],
    ) -> list[MedicationDetail]:
        medication_details = [
            MedicationDetail(
                item_seq=read_public_item_sequence(item),
                item_name=read_medication_detail_text(item.get("itemName")),
                manufacturer=read_medication_detail_text(item.get("entpName")),
                efficacy=read_medication_detail_text(item.get("efcyQesitm")),
                usage_method=read_medication_detail_text(item.get("useMethodQesitm")),
                warning=read_medication_detail_text(item.get("atpnWarnQesitm")),
                interaction=read_medication_detail_text(item.get("intrcQesitm")),
                side_effect=read_medication_detail_text(item.get("seQesitm")),
                storage_method=read_medication_detail_text(item.get("depositMethodQesitm")),
                image_url=read_public_image_url(item),
                source="Basic (e약은요)",
            )
            for item in basic_items
        ]

        return medication_details
