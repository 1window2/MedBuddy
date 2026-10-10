# File Name: local_medication_catalog.py
# Role: Looks up local medication catalogs with isolated worker reads and approval-summary enrichment.

import asyncio
import json
import logging
import re
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import or_, text
from sqlalchemy.engine import Connection
from sqlalchemy.orm import Session, sessionmaker

from boundaries.medication_summary_boundary import (
    MISSING_DETAIL_TEXT,
    MedicationSummaryGenerator,
)
from boundaries.public_drug_api_boundary import (
    read_public_image_url,
    read_public_item_name,
    read_public_item_sequence,
)
from entities.medication_detail_entity import (
    MedicationDetail,
    _DrugApprovalInfo,
    _DrugBasicInfo,
)
from services.medication_name_matching import MedicationNameMatcher

logger = logging.getLogger(__name__)

# Text the summary generator has returned for a field it could not summarize.
# It is never stored as a summary, and a row that already holds it is summarized again.
SUMMARY_FAILURE_PLACEHOLDER = "요약 실패"

# A stored summary is partial when the AI left a field out although the source document of that
# field has text. It is served for this long after it was written and then requested again on
# the next lookup, so one catalog row causes at most one such AI request per period. A naive
# updated_at is read as UTC; the period is longer than any time-zone offset, so a database
# clock in another zone only shifts the retry and cannot make it repeat.
PARTIAL_SUMMARY_RETRY_AFTER = timedelta(hours=24)


# 클래스명: LocalMedicationCatalog
# 역할:
# - 로컬 약품 카탈로그에서 이름이 일치하는 기본 정보와 허가 정보 요약을 조회한다.
# 주요 책임:
# - 기본·허가 카탈로그 후보의 이름 신뢰도를 비교하고 저장 요약을 재사용하거나 새 요약을 보관한다.
# 속성:
# - db (Session | None): 현재 작업에 사용할 SQLAlchemy 세션.
# - summary_generator (MedicationSummaryGenerator): 상세 허가 문서의 AI 요약 생성기.
# Note: File-backed catalog reads and conditional summary writes own Engine-bound worker sessions.
# Connection-local in-memory SQLite retains only the read fallback; its optional summary writes are skipped.
class LocalMedicationCatalog:
    _WHITESPACE_PATTERN = re.compile(r"\s+")
    _FUZZY_ANCHOR_LENGTH = 3
    _FUZZY_CANDIDATE_LIMIT = 30
    # The weekly catalog sync keeps row locks until its single commit; the optional summary
    # write gives up after this wait instead of holding a worker thread behind it.
    _SUMMARY_WRITE_LOCK_TIMEOUT_SQL = "SELECT set_config('lock_timeout', '2s', true)"

    # 함수이름: __init__
    # 함수역할:
    # - 약품 조회 세션, 이름 일치 판정기와 허가 문서 요약기를 연결한다.
    # 매개변수:
    # - db (Session | None): 현재 작업에 사용할 SQLAlchemy 세션.
    # - summary_generator (MedicationSummaryGenerator): 상세 허가 문서의 AI 요약 생성기.
    # - name_matcher (MedicationNameMatcher | None): 약품명 유사도 점수 계산과 신뢰도 필터.
    # 반환값:
    # - 없음.
    def __init__(
        self,
        db: Session | None,
        summary_generator: MedicationSummaryGenerator,
        name_matcher: MedicationNameMatcher | None = None,
    ) -> None:
        self.db = db
        self.summary_generator = summary_generator
        self.name_matcher = name_matcher or MedicationNameMatcher()
        # Workers retain the engine, never a borrowed request-session operation.
        bind = db.get_bind() if db is not None else None
        engine = bind.engine if isinstance(bind, Connection) else bind
        self._worker_session_factory = (
            sessionmaker(bind=engine) if engine is not None else None
        )
        self._uses_memory_sqlite = (
            engine is not None
            and engine.dialect.name == "sqlite"
            and engine.url.database in {None, "", ":memory:"}
        )

    # 함수이름: fetch_drug_info
    # 함수역할:
    # - 로컬 기본 정보를 우선 반환하고, 없으면 상위 허가 후보를 확인용으로 보존한다.
    # 매개변수:
    # - drug_name (str): 검색 또는 직렬화할 약품명.
    # 반환값:
    # - 약품 상세 목록; DB나 일치 결과가 없으면 빈 목록.
    async def fetch_drug_info(self, drug_name: str) -> list[MedicationDetail]:
        if self.db is None:
            return []

        basic_items, approval_items = await self._search_catalog(drug_name)
        if basic_items:
            logger.info(
                "[Local DB] e약은요 lookup succeeded (%s items).",
                len(basic_items),
            )
            return await self._build_basic_details(basic_items)

        if not approval_items:
            return []

        logger.info("[Local DB] approval lookup succeeded.")
        return list(await asyncio.gather(*(
            self._build_approval_detail(drug_name, item) for item in approval_items
        )))

    # 함수이름: _search_catalog
    # 함수역할:
    # - 로컬 카탈로그 조회를 이벤트 루프 밖의 독립 DB 세션에서 처리한다.
    # - 연결별 DB가 분리되는 인메모리 SQLite에서는 현재 테스트 세션을 사용한다.
    # 매개변수:
    # - drug_name (str): 검색 또는 직렬화할 약품명.
    # 반환값:
    # - 이름 신뢰도 기준을 통과한 기본 카탈로그 행과 허가 카탈로그 행의 쌍.
    async def _search_catalog(
        self,
        drug_name: str,
    ) -> tuple[list[_DrugBasicInfo], list[_DrugApprovalInfo]]:
        if self.db is None:
            return [], []
        if self._uses_memory_sqlite:
            basic_items = self._search_basic(drug_name)
            return basic_items, [] if basic_items else self._search_approval(drug_name)
        return await asyncio.to_thread(
            self._search_catalog_with_isolated_session,
            drug_name,
        )

    # 함수이름: _search_catalog_with_isolated_session
    # 함수역할:
    # - 작업 스레드 안에서 별도 세션을 만들고 기본·허가 카탈로그를 순서대로 조회한다.
    # 매개변수:
    # - drug_name (str): 검색 또는 직렬화할 약품명.
    # 반환값:
    # - 독립 세션에서 읽은 기본·허가 카탈로그 후보 목록의 쌍.
    def _search_catalog_with_isolated_session(
        self,
        drug_name: str,
    ) -> tuple[list[_DrugBasicInfo], list[_DrugApprovalInfo]]:
        if self._worker_session_factory is None:
            return [], []
        worker_db = self._worker_session_factory()
        try:
            worker = LocalMedicationCatalog(
                db=worker_db,
                summary_generator=self.summary_generator,
                name_matcher=self.name_matcher,
            )
            basic_items = worker._search_basic(drug_name)
            return basic_items, [] if basic_items else worker._search_approval(drug_name)
        finally:
            worker_db.close()

    # 함수이름: _search_basic
    # 함수역할:
    # - 로컬 e약은요 DB에서 완전 일치를 우선 조회하고 유사 후보를 점수화한다.
    # 매개변수:
    # - drug_name (str): OCR 보정 검색어
    # - limit (int): 반환할 최대 후보 수
    # 반환값:
    # - 이름 유사도 임계값을 통과한 e약은요 후보 목록
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

        candidates = (
            self.db.query(_DrugBasicInfo)
            .filter(self._build_fuzzy_filter(_DrugBasicInfo, keyword))
            .limit(self._FUZZY_CANDIDATE_LIMIT)
            .all()
        )
        return self.name_matcher.rank_candidates(
            drug_name,
            candidates,
            lambda item: item.item_name,
            limit,
        )

    # 함수이름: _search_approval
    # 함수역할:
    # - 로컬 허가정보 DB에서 완전 일치를 우선 조회하고 유사 후보를 점수화한다.
    # 매개변수:
    # - drug_name (str): OCR 보정 검색어
    # - limit (int): 반환할 최대 후보 수
    # 반환값:
    # - 이름 유사도 임계값을 통과한 허가정보 후보 목록
    def _search_approval(
        self,
        drug_name: str,
        limit: int = 3,
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

        candidates = (
            self.db.query(_DrugApprovalInfo)
            .filter(self._build_fuzzy_filter(_DrugApprovalInfo, keyword))
            .limit(self._FUZZY_CANDIDATE_LIMIT)
            .all()
        )
        return self.name_matcher.rank_candidates(
            drug_name,
            candidates,
            lambda item: item.item_name,
            limit,
        )

    # 함수이름: _build_fuzzy_filter
    # 함수역할:
    # - 전체 검색어와 부분 앵커 중 하나를 포함하는 로컬 DB 조회 조건을 만든다.
    # 매개변수:
    # - model (type[_DrugBasicInfo] | type[_DrugApprovalInfo]): 조회할 로컬 약품 SQLAlchemy 모델
    # - keyword (str): 공백을 제거한 검색어
    # 반환값:
    # - SQLAlchemy OR 검색 조건
    def _build_fuzzy_filter(
        self,
        model: type[_DrugBasicInfo] | type[_DrugApprovalInfo],
        keyword: str,
    ) -> Any:
        search_fragments = [keyword, *self._build_fuzzy_anchors(keyword)]
        return or_(
            *(
                model.normalized_item_name.like(
                    self._like_pattern(fragment, prefix="%", suffix="%"),
                    escape="\\",
                )
                for fragment in search_fragments
            )
        )

    # 함수이름: _build_fuzzy_anchors
    # 함수역할:
    # - 한두 글자 OCR 오류가 있어도 후보를 찾도록 검색어 앞·중간·뒤 조각을 만든다.
    # 매개변수:
    # - keyword (str): 공백을 제거한 검색어
    # 반환값:
    # - 중복이 제거된 세 글자 검색 조각 목록
    def _build_fuzzy_anchors(self, keyword: str) -> list[str]:
        if len(keyword) < self._FUZZY_ANCHOR_LENGTH + 2:
            return []

        anchor_length = self._FUZZY_ANCHOR_LENGTH
        middle_start = max(0, (len(keyword) - anchor_length) // 2)
        anchors = [
            keyword[:anchor_length],
            keyword[middle_start : middle_start + anchor_length],
            keyword[-anchor_length:],
        ]
        return list(dict.fromkeys(anchor for anchor in anchors if anchor))

    # Function Name: _build_basic_details
    # Description:
    # - Maps stored basic drug records to patient-facing details while preserving safety guidance and image provenance.
    # Parameters:
    # - basic_items (list[_DrugBasicInfo]): Basic drug records with public product and guidance fields.
    # Returns:
    # - MedicationDetail objects in the input record order.
    async def _build_basic_details(
        self,
        basic_items: list[_DrugBasicInfo],
    ) -> list[MedicationDetail]:
        enriched_details = []
        for item in basic_items:
            medication_detail = MedicationDetail(
                item_seq=item.item_seq or "",
                item_name=item.item_name,
                manufacturer=item.entp_name or "",
                efficacy=item.efficacy or "정보 없음",
                usage_method=item.use_method or "정보 없음",
                warning=item.warning_message or "정보 없음",
                interaction=item.interaction or "",
                side_effect=item.side_effect or "",
                storage_method=item.deposit_method or "",
                image_url=self._read_basic_image_url(item),
                source="Local DB (e약은요)",
            )

            enriched_details.append(medication_detail)

        return enriched_details

    # 함수이름: _build_approval_detail
    # 함수역할:
    # - 저장된 허가 요약을 재사용하거나 원문을 AI로 요약한 뒤 결과를 캐시에 저장한다.
    # - 원문이 있는데도 빠진 항목이 있는 저장 요약은 PARTIAL_SUMMARY_RETRY_AFTER가 지나면 다시 요약한다.
    #   다시 요약하지 못하면 저장된 요약을 그대로 돌려주고, 새 요약에서 빠진 항목은 저장된 문구를 유지한다.
    # 매개변수:
    # - drug_name (str): 검색 또는 직렬화할 약품명.
    # - approval_item (_DrugApprovalInfo): 원문 문서와 선택적 생성 요약을 가진 저장된 허가 정보 행.
    # 반환값:
    # - 로컬 허가 자료 출처를 표시한 약품 상세 정보.
    async def _build_approval_detail(
        self,
        drug_name: str,
        approval_item: _DrugApprovalInfo,
    ) -> MedicationDetail:
        cached_summary = self._build_cached_approval_summary(approval_item)
        raw_item = self._load_raw_approval_item(approval_item)
        if cached_summary is not None and not self._is_partial_summary_due_for_retry(
            approval_item, raw_item,
        ):
            return cached_summary

        try:
            medication_detail = await self.summary_generator.summarize_advanced_item(
                drug_name,
                raw_item,
            )
        except Exception as exc:
            if cached_summary is None:
                raise
            # The stored partial summary is still the best answer. Writing it back restarts
            # its retry period, so an AI outage is not asked again on every lookup.
            logger.warning(
                "Partial approval summary could not be completed; keeping the stored one: %s",
                type(exc).__name__,
            )
            await self._save_approval_summary(approval_item, cached_summary)
            return cached_summary
        updated_fields = {
            "source": "Local DB (허가정보) + AI 요약",
            "manufacturer": approval_item.entp_name or "",
        }
        if cached_summary is not None:
            # A field the new answer left out keeps the text the stored summary already had.
            updated_fields.update({
                field: getattr(cached_summary, field)
                for field in ("efficacy", "usage_method", "warning")
                if self._is_missing_text(getattr(medication_detail, field))
            })
        medication_detail = medication_detail.model_copy(update=updated_fields)
        await self._save_approval_summary(approval_item, medication_detail)
        return medication_detail

    # Function Name: _is_partial_summary_due_for_retry
    # Description:
    # - Tells whether a stored summary lacks a field whose source document has text and was
    #   written longer ago than PARTIAL_SUMMARY_RETRY_AFTER. A field whose source document is
    #   empty is complete without a summary and never causes a retry.
    # Parameters:
    # - approval_item (_DrugApprovalInfo): Stored approval record with its generated summary.
    # - raw_item (dict[str, Any]): Approval documents the summary is generated from.
    # Returns:
    # - True when the summary should be requested again on this lookup.
    def _is_partial_summary_due_for_retry(
        self,
        approval_item: _DrugApprovalInfo,
        raw_item: dict[str, Any],
    ) -> bool:
        is_partial = any(
            self._is_missing_text(summary_text)
            and not self._is_missing_text(raw_item.get(document_key))
            for summary_text, document_key in (
                (approval_item.summary_efficacy, "EE_DOC_DATA"),
                (approval_item.summary_use_method, "UD_DOC_DATA"),
                (approval_item.summary_warning_message, "NB_DOC_DATA"),
            )
        )
        if not is_partial:
            return False
        written_at = approval_item.updated_at
        if written_at is None:
            return True
        written_at = (
            written_at.replace(tzinfo=UTC)
            if written_at.tzinfo is None
            else written_at.astimezone(UTC)
        )
        return datetime.now(UTC) - written_at >= PARTIAL_SUMMARY_RETRY_AFTER

    # Function Name: _build_cached_approval_summary
    # Description:
    # - Reuses an approval summary only when efficacy, usage and warning fields are all populated.
    # - A field holding the failure placeholder counts as missing, so the row is summarized again.
    # Parameters:
    # - approval_item (_DrugApprovalInfo): Stored approval record with raw documents and optional generated summary.
    # Returns:
    # - MedicationDetail with stored guidance, or None when the summary is incomplete or failed.
    def _build_cached_approval_summary(
        self,
        approval_item: _DrugApprovalInfo,
    ) -> MedicationDetail | None:
        if not (
            self._is_usable_summary_text(approval_item.summary_efficacy)
            and self._is_usable_summary_text(approval_item.summary_use_method)
            and self._is_usable_summary_text(approval_item.summary_warning_message)
        ):
            return None

        return MedicationDetail(
            item_seq=approval_item.item_seq or "",
            item_name=approval_item.item_name,
            manufacturer=approval_item.entp_name or "",
            efficacy=approval_item.summary_efficacy,
            usage_method=approval_item.summary_use_method,
            warning=approval_item.summary_warning_message,
            image_url=read_public_image_url(
                self._load_raw_approval_item(approval_item)
            ),
            source="Local DB (허가정보) + 저장된 AI 요약",
            ai_guide=approval_item.ai_guide,
        )

    # Function Name: _load_raw_approval_item
    # Description:
    # - Decodes the stored approval payload and falls back to database columns when JSON or document fields are unusable.
    # Parameters:
    # - approval_item (_DrugApprovalInfo): Stored approval record with raw documents and optional generated summary.
    # Returns:
    # - Approval document dictionary suitable for summarization.
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
            logger.warning("Local approval raw_json decode failed.")

        return self._approval_columns_to_raw_item(approval_item)

    # Function Name: _normalize_raw_approval_item
    # Description:
    # - Harmonizes basic/approval API field aliases and fills missing identifiers or documents from the stored row.
    # Parameters:
    # - raw_item (dict[str, Any]): Original approval API payload used for field-alias lookup.
    # - approval_item (_DrugApprovalInfo): Stored approval record with raw documents and optional generated summary.
    # Returns:
    # - Canonical approval fields, or None if every guidance document is empty.
    def _normalize_raw_approval_item(
        self,
        raw_item: dict[str, Any],
        approval_item: _DrugApprovalInfo,
    ) -> dict[str, Any] | None:
        normalized_item = {
            "ITEM_SEQ": read_public_item_sequence(raw_item)
            or approval_item.item_seq
            or "",
            "ITEM_NAME": read_public_item_name(raw_item) or approval_item.item_name,
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
            "ITEM_IMAGE": read_public_image_url(raw_item),
        }
        if any(
            normalized_item[key]
            for key in ("EE_DOC_DATA", "UD_DOC_DATA", "NB_DOC_DATA")
        ):
            return normalized_item
        return None

    # Function Name: _approval_columns_to_raw_item
    # Description:
    # - Reconstructs an approval API-shaped payload from persisted document columns.
    # Parameters:
    # - approval_item (_DrugApprovalInfo): Stored approval record with raw documents and optional generated summary.
    # Returns:
    # - Product identifiers and efficacy, usage and warning documents with display fallbacks.
    def _approval_columns_to_raw_item(
        self,
        approval_item: _DrugApprovalInfo,
    ) -> dict[str, Any]:
        return {
            "ITEM_SEQ": approval_item.item_seq or "",
            "ITEM_NAME": approval_item.item_name,
            "EE_DOC_DATA": approval_item.efficacy_doc or "정보 없음",
            "UD_DOC_DATA": approval_item.use_method_doc or "정보 없음",
            "NB_DOC_DATA": approval_item.warning_doc or "정보 없음",
        }

    # Function Name: _read_first_raw_text
    # Description:
    # - Searches field aliases in order, including case-insensitive keys, and skips blank values.
    # Parameters:
    # - raw_item (dict[str, Any]): Original approval API payload used for field-alias lookup.
    # - keys (list[str]): Field aliases searched in priority order.
    # Returns:
    # - First nonblank trimmed field value, or an empty string.
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

    # Function Name: _read_basic_image_url
    # Description:
    # - Reads a public medication image from stored basic-catalog JSON.
    # Parameters:
    # - basic_info (_DrugBasicInfo): Stored basic public-drug record including its raw payload.
    # Returns:
    # - Accepted image URL, or an empty string for invalid JSON or absent images.
    def _read_basic_image_url(self, basic_info: _DrugBasicInfo) -> str:
        try:
            raw_item = json.loads(basic_info.raw_json)
        except json.JSONDecodeError:
            return ""

        if not isinstance(raw_item, dict):
            return ""

        return read_public_image_url(raw_item)

    # Function Name: _save_approval_summary
    # Description:
    # - Offloads optional summary caching using an immutable identity/document snapshot.
    # - Skips connection-local in-memory SQLite rather than commit the borrowed request transaction.
    # - Skips a summary with a blank or failed field, so it is generated again on the next lookup.
    # Parameters:
    # - approval_info (_DrugApprovalInfo): Stored approval record with raw documents and optional generated summary.
    # - medication_detail (MedicationDetail): Patient-facing medication guidance and product metadata.
    # Returns:
    # - None.
    async def _save_approval_summary(
        self,
        approval_info: _DrugApprovalInfo,
        medication_detail: MedicationDetail,
    ) -> None:
        if self._worker_session_factory is None or self._uses_memory_sqlite:
            return
        if not (
            self._is_usable_summary_text(medication_detail.efficacy)
            and self._is_usable_summary_text(medication_detail.usage_method)
            and self._is_usable_summary_text(medication_detail.warning)
        ):
            logger.warning("Local approval summary is incomplete; not persisted.")
            return

        approval_snapshot = {
            "id": approval_info.id,
            "item_seq": approval_info.item_seq,
            "item_name": approval_info.item_name,
            "entp_name": approval_info.entp_name,
            "efficacy_doc": approval_info.efficacy_doc,
            "use_method_doc": approval_info.use_method_doc,
            "warning_doc": approval_info.warning_doc,
            "raw_json": approval_info.raw_json,
        }
        summary_fields = {
            "summary_efficacy": medication_detail.efficacy,
            "summary_use_method": medication_detail.usage_method,
            "summary_warning_message": medication_detail.warning,
            "ai_guide": medication_detail.ai_guide,
        }
        await asyncio.to_thread(
            self._save_approval_summary_with_isolated_session,
            approval_snapshot,
            summary_fields,
        )

    # Function Name: _save_approval_summary_with_isolated_session
    # Description:
    # - Atomically caches guidance only if the same product and source documents still exist.
    # - Owns commit, rollback and closure entirely inside the worker; failures never replace generated guidance.
    # - On PostgreSQL the row-lock wait is bounded for this transaction; a timeout is one of the tolerated failures.
    # Parameters:
    # - approval_snapshot (dict[str, Any]): Approval identity and exact document fields used to generate the summary.
    # - summary_fields (dict[str, str | None]): Four generated guidance fields permitted for cache persistence.
    # Returns:
    # - None; deleted or refreshed catalog rows are deliberately not updated.
    def _save_approval_summary_with_isolated_session(
        self,
        approval_snapshot: dict[str, Any],
        summary_fields: dict[str, str | None],
    ) -> None:
        if self._worker_session_factory is None:
            return
        try:
            with self._worker_session_factory.begin() as worker_db:
                if worker_db.get_bind().dialect.name == "postgresql":
                    worker_db.execute(text(self._SUMMARY_WRITE_LOCK_TIMEOUT_SQL))
                worker_db.query(_DrugApprovalInfo).filter_by(
                    **approval_snapshot,
                ).update(summary_fields, synchronize_session=False)
        except Exception as exc:
            logger.warning(
                "Failed to persist local approval summary: %s",
                type(exc).__name__,
            )

    # Function Name: _is_usable_summary_text
    # Description:
    # - Tells a generated summary field apart from a blank one and from the failure placeholder.
    # Parameters:
    # - value (str | None): Stored or freshly generated summary field.
    # Returns:
    # - True when the field holds real guidance text.
    @staticmethod
    def _is_usable_summary_text(value: str | None) -> bool:
        summary_text = (value or "").strip()
        return bool(summary_text) and summary_text != SUMMARY_FAILURE_PLACEHOLDER

    # Function Name: _is_missing_text
    # Description:
    # - Recognizes a summary field or source document without content: blank, or the display
    #   text the summary generator writes for a field the AI left out.
    # Parameters:
    # - value (Any): Stored summary field or raw approval document.
    # Returns:
    # - True when the value carries no guidance text.
    @staticmethod
    def _is_missing_text(value: Any) -> bool:
        text_value = "" if value is None else str(value).strip()
        return not text_value or text_value == MISSING_DETAIL_TEXT

    # Function Name: _normalize_name
    # Description:
    # - Removes all whitespace and lowercases medication names for indexed local lookup.
    # Parameters:
    # - name (str): Medication name before catalog-key normalization.
    # Returns:
    # - Normalized catalog name.
    @classmethod
    def _normalize_name(cls, name: str) -> str:
        return cls._WHITESPACE_PATTERN.sub("", name).strip().lower()

    # Function Name: _like_pattern
    # Description:
    # - Escapes client wildcard characters before adding caller-selected SQL LIKE prefixes and suffixes.
    # Parameters:
    # - keyword (str): Literal medication-name fragment for a database search.
    # - prefix (str): Caller-selected SQL LIKE prefix wildcard.
    # - suffix (str): Caller-selected SQL LIKE suffix wildcard.
    # Returns:
    # - Escaped LIKE pattern for literal medication-name matching.
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
