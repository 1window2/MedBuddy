# 파일명: sync_drug_catalog.py
# 역할: 국내 공공 의약품 API 데이터를 로컬 SQLite 카탈로그로 동기화한다.

import argparse
import asyncio
from collections.abc import Awaitable, Callable
import json
import logging
import math
from pathlib import Path
import re
import sys
from typing import Any

from sqlalchemy.orm import Session

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from controls.check_medication_detail_control import _PublicDrugDataPortal
from core.database import Base, SessionLocal, engine
from entities import medication_detail_entity  # noqa: F401
from entities.medication_detail_entity import _DrugApprovalInfo, _DrugBasicInfo

logger = logging.getLogger(__name__)


# 클래스명: _DrugCatalogStore
# 역할: 로컬 의약품 카탈로그 동기화를 위한 내부 저장소 helper이다.
# 주요 책임:
#   - Upsert e약은요 and approval API records into SQLite.
#   - Preserve raw API payloads for traceability.
#   - Keep table-specific normalization in one sync-only helper.
# 속성:
#   - db: 저장 작업에 사용하는 SQLAlchemy 세션
class _DrugCatalogStore:
    _WHITESPACE_PATTERN = re.compile(r"\s+")

    def __init__(self, db: Session) -> None:
        self.db = db

    # 함수명: upsert_basic_items
    # 함수역할:
    # - Inserts or updates e약은요 records from public API payloads.
    # 매개변수:
    # - items: 공공 API에서 받은 원본 item dictionary 목록
    # 반환값:
    # - Number of rows processed.
    def upsert_basic_items(self, items: list[dict[str, Any]]) -> int:
        processed_count = 0
        batch_targets_by_seq: dict[str, _DrugBasicInfo] = {}
        batch_targets_by_name: dict[str, _DrugBasicInfo] = {}

        for item in items:
            item_name = self._read_text(item, "itemName")
            if not item_name:
                continue

            item_seq = self._read_text(item, "itemSeq")
            normalized_item_name = self.normalize_name(item_name)
            target_item = self._resolve_basic_target(
                item_seq=item_seq,
                normalized_item_name=normalized_item_name,
                batch_targets_by_seq=batch_targets_by_seq,
                batch_targets_by_name=batch_targets_by_name,
            )
            is_new_item = target_item is None
            target_item = target_item or _DrugBasicInfo()

            target_item.item_seq = item_seq or None
            target_item.item_name = item_name
            target_item.normalized_item_name = normalized_item_name
            target_item.entp_name = self._read_text(item, "entpName") or None
            target_item.efficacy = self._read_text(item, "efcyQesitm") or None
            target_item.use_method = self._read_text(item, "useMethodQesitm") or None
            target_item.warning_message = (
                self._read_text(item, "atpnWarnQesitm") or None
            )
            target_item.interaction = self._read_text(item, "intrcQesitm") or None
            target_item.side_effect = self._read_text(item, "seQesitm") or None
            target_item.deposit_method = (
                self._read_text(item, "depositMethodQesitm") or None
            )
            target_item.raw_json = self._dump_raw_json(item)

            if is_new_item:
                self.db.add(target_item)

            if item_seq:
                batch_targets_by_seq[item_seq] = target_item
            batch_targets_by_name[normalized_item_name] = target_item
            processed_count += 1

        self.db.commit()
        return processed_count

    # 함수명: upsert_approval_items
    # 함수역할:
    # - Inserts or updates detailed approval records from public API payloads.
    # 매개변수:
    # - items: 공공 API에서 받은 원본 item dictionary 목록
    # 반환값:
    # - Number of rows processed.
    def upsert_approval_items(self, items: list[dict[str, Any]]) -> int:
        processed_count = 0
        batch_targets_by_seq: dict[str, _DrugApprovalInfo] = {}
        batch_targets_by_name: dict[str, _DrugApprovalInfo] = {}

        for item in items:
            item_name = self._read_first_text(item, ["ITEM_NAME", "item_name"])
            if not item_name:
                continue

            item_seq = self._read_first_text(
                item,
                ["ITEM_SEQ", "itemSeq", "PRDLST_STDR_CODE", "prdlst_Stdr_code"],
            )
            normalized_item_name = self.normalize_name(item_name)
            target_item = self._resolve_approval_target(
                item_seq=item_seq,
                normalized_item_name=normalized_item_name,
                batch_targets_by_seq=batch_targets_by_seq,
                batch_targets_by_name=batch_targets_by_name,
            )
            is_new_item = target_item is None
            target_item = target_item or _DrugApprovalInfo()

            target_item.item_seq = item_seq or None
            target_item.item_name = item_name
            target_item.normalized_item_name = normalized_item_name
            target_item.entp_name = self._read_first_text(
                item,
                ["ENTP_NAME", "entp_name"],
            ) or None
            target_item.main_ingredient = self._read_first_text(
                item,
                ["MAIN_ITEM_INGR", "ITEM_INGR_NAME", "main_item_ingr"],
            ) or None
            target_item.efficacy_doc = self._read_first_text(
                item,
                ["EE_DOC_DATA", "efcyQesitm"],
            ) or None
            target_item.use_method_doc = self._read_first_text(
                item,
                ["UD_DOC_DATA", "useMethodQesitm"],
            ) or None
            target_item.warning_doc = self._read_first_text(
                item,
                ["NB_DOC_DATA", "atpnWarnQesitm"],
            ) or None
            target_item.raw_json = self._dump_raw_json(item)

            if is_new_item:
                self.db.add(target_item)

            if item_seq:
                batch_targets_by_seq[item_seq] = target_item
            batch_targets_by_name[normalized_item_name] = target_item
            processed_count += 1

        self.db.commit()
        return processed_count

    # 함수명: count_basic
    # 함수역할:
    # - Counts locally stored e약은요 rows.
    # 반환값:
    # - Row count.
    def count_basic(self) -> int:
        return self.db.query(_DrugBasicInfo).count()

    # 함수명: count_approval
    # 함수역할:
    # - Counts locally stored approval detail rows.
    # 반환값:
    # - Row count.
    def count_approval(self) -> int:
        return self.db.query(_DrugApprovalInfo).count()

    # 함수명: normalize_name
    # 함수역할:
    # - 안정적인 로컬 조회를 위해 약품명을 정규화한다.
    # 매개변수:
    # - name: 원본 약품명
    # 반환값:
    # - Normalized lowercase name without whitespace.
    @classmethod
    def normalize_name(cls, name: str) -> str:
        return cls._WHITESPACE_PATTERN.sub("", name).strip().lower()

    def _resolve_basic_target(
        self,
        item_seq: str,
        normalized_item_name: str,
        batch_targets_by_seq: dict[str, _DrugBasicInfo],
        batch_targets_by_name: dict[str, _DrugBasicInfo],
    ) -> _DrugBasicInfo | None:
        if item_seq and item_seq in batch_targets_by_seq:
            return batch_targets_by_seq[item_seq]
        if normalized_item_name in batch_targets_by_name:
            return batch_targets_by_name[normalized_item_name]

        if item_seq:
            existing_item = (
                self.db.query(_DrugBasicInfo)
                .filter(_DrugBasicInfo.item_seq == item_seq)
                .first()
            )
            if existing_item is not None:
                return existing_item

        return (
            self.db.query(_DrugBasicInfo)
            .filter(_DrugBasicInfo.normalized_item_name == normalized_item_name)
            .first()
        )

    def _resolve_approval_target(
        self,
        item_seq: str,
        normalized_item_name: str,
        batch_targets_by_seq: dict[str, _DrugApprovalInfo],
        batch_targets_by_name: dict[str, _DrugApprovalInfo],
    ) -> _DrugApprovalInfo | None:
        if item_seq and item_seq in batch_targets_by_seq:
            return batch_targets_by_seq[item_seq]
        if normalized_item_name in batch_targets_by_name:
            return batch_targets_by_name[normalized_item_name]

        if item_seq:
            existing_item = (
                self.db.query(_DrugApprovalInfo)
                .filter(_DrugApprovalInfo.item_seq == item_seq)
                .first()
            )
            if existing_item is not None:
                return existing_item

        return (
            self.db.query(_DrugApprovalInfo)
            .filter(_DrugApprovalInfo.normalized_item_name == normalized_item_name)
            .first()
        )

    def _read_text(self, item: dict[str, Any], key: str) -> str:
        value = item.get(key)
        if value is None:
            lowered_key = key.lower()
            for existing_key, existing_value in item.items():
                if str(existing_key).lower() == lowered_key:
                    value = existing_value
                    break

        if value is None:
            return ""
        return str(value).strip()

    def _read_first_text(self, item: dict[str, Any], keys: list[str]) -> str:
        for key in keys:
            value = self._read_text(item, key)
            if value:
                return value
        return ""

    def _dump_raw_json(self, item: dict[str, Any]) -> str:
        return json.dumps(item, ensure_ascii=False, separators=(",", ":"))


# 클래스명: DrugCatalogSyncJob
# 역할: Control class for public drug API to local DB synchronization.
# 주요 책임:
#   - Fetch paginated e약은요 records.
#   - Fetch paginated approval detail records.
#   - Upsert fetched records into the local catalog tables.
# 속성:
#   - store: _DrugCatalogStore used for local persistence.
#   - public_drug_data_portal: API boundary used for pagination.
#   - page_size: Number of API rows fetched per request.
#   - start_page: First API page to request.
#   - max_pages: 스모크 테스트나 부분 동기화를 위한 선택적 최대 페이지 수
#   - max_retries: Number of retry attempts for transient public API failures.
#   - retry_delay_seconds: Delay between retry attempts.
class DrugCatalogSyncJob:
    def __init__(
        self,
        store: _DrugCatalogStore,
        public_drug_data_portal: _PublicDrugDataPortal,
        page_size: int,
        start_page: int = 1,
        max_pages: int | None = None,
        max_retries: int = 3,
        retry_delay_seconds: float = 3.0,
    ) -> None:
        self.store = store
        self.public_drug_data_portal = public_drug_data_portal
        self.page_size = page_size
        self.start_page = start_page
        self.max_pages = max_pages
        self.max_retries = max_retries
        self.retry_delay_seconds = retry_delay_seconds

    # 함수명: sync_basic
    # 함수역할:
    # - e약은요 API 전체 데이터를 drug_basic_infos 테이블로 동기화한다.
    # 반환값:
    # - Number of rows processed.
    async def sync_basic(self) -> int:
        return await self._sync_pages(
            dataset_name="e약은요",
            fetch_page=self.public_drug_data_portal.fetch_basic_drug_info_page,
            upsert_items=self.store.upsert_basic_items,
        )

    # 함수명: sync_approval
    # 함수역할:
    # - 의약품 허가 상세 API 전체 데이터를 drug_approval_infos 테이블로 동기화한다.
    # 반환값:
    # - Number of rows processed.
    async def sync_approval(self) -> int:
        return await self._sync_pages(
            dataset_name="허가정보",
            fetch_page=self.public_drug_data_portal.fetch_approval_drug_info_page,
            upsert_items=self.store.upsert_approval_items,
        )

    async def _sync_pages(
        self,
        dataset_name: str,
        fetch_page: Callable[[int, int], Awaitable[tuple[list[dict[str, Any]], int]]],
        upsert_items: Callable[[list[dict[str, Any]]], int],
    ) -> int:
        processed_total = 0
        page_no = self.start_page
        total_pages: int | None = None
        total_pages_resolved = False

        while True:
            items, total_count = await self._fetch_page_with_retry(
                dataset_name=dataset_name,
                page_no=page_no,
                fetch_page=fetch_page,
            )
            if not total_pages_resolved:
                total_pages = self._resolve_total_pages(total_count)
                total_pages_resolved = True
                logger.info(
                    "[%s] total_count=%s, page_size=%s, start_page=%s, total_pages=%s",
                    dataset_name,
                    total_count,
                    self.page_size,
                    self.start_page,
                    total_pages if total_pages is not None else "unknown",
                )

            if not items:
                logger.info("[%s] page %s returned no items. stopping.", dataset_name, page_no)
                break

            processed_count = upsert_items(items)
            processed_total += processed_count
            if processed_count == 0:
                logger.warning(
                    "[%s] page %s contained %s items, but no rows were persisted.",
                    dataset_name,
                    page_no,
                    len(items),
                )
            logger.info(
                "[%s] page %s/%s processed: %s rows",
                dataset_name,
                page_no,
                total_pages if total_pages is not None else "?",
                processed_count,
            )

            if total_pages is not None and page_no >= total_pages:
                break
            processed_pages = page_no - self.start_page + 1
            if self.max_pages is not None and processed_pages >= self.max_pages:
                logger.info("[%s] max_pages=%s reached.", dataset_name, self.max_pages)
                break
            page_no += 1

        return processed_total

    async def _fetch_page_with_retry(
        self,
        dataset_name: str,
        page_no: int,
        fetch_page: Callable[[int, int], Awaitable[tuple[list[dict[str, Any]], int]]],
    ) -> tuple[list[dict[str, Any]], int]:
        for attempt in range(1, self.max_retries + 2):
            try:
                return await fetch_page(page_no, self.page_size)
            except Exception:
                if attempt > self.max_retries:
                    raise
                logger.warning(
                    "[%s] page %s fetch failed. retrying %s/%s after %.1fs.",
                    dataset_name,
                    page_no,
                    attempt,
                    self.max_retries,
                    self.retry_delay_seconds,
                    exc_info=True,
                )
                await asyncio.sleep(self.retry_delay_seconds)

        return [], 0

    def _resolve_total_pages(self, total_count: int) -> int | None:
        if total_count <= 0:
            return None
        return max(1, math.ceil(total_count / self.page_size))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Synchronize public drug API datasets into local SQLite tables.",
    )
    parser.add_argument(
        "--dataset",
        choices=["basic", "approval", "all"],
        default="all",
        help="Dataset to synchronize.",
    )
    parser.add_argument(
        "--page-size",
        type=int,
        default=500,
        help="Rows fetched per public API request.",
    )
    parser.add_argument(
        "--start-page",
        type=int,
        default=1,
        help="First API page to request. Useful for resuming an interrupted sync.",
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        default=None,
        help="Optional page cap for partial sync or smoke tests.",
    )
    parser.add_argument(
        "--max-retries",
        type=int,
        default=3,
        help="Retry attempts per page for transient public API failures.",
    )
    parser.add_argument(
        "--retry-delay-seconds",
        type=float,
        default=3.0,
        help="Delay between retry attempts.",
    )
    args = parser.parse_args()
    if args.page_size <= 0:
        parser.error("--page-size must be greater than 0.")
    if args.start_page <= 0:
        parser.error("--start-page must be greater than 0.")
    if args.max_pages is not None and args.max_pages <= 0:
        parser.error("--max-pages must be greater than 0.")
    if args.max_retries < 0:
        parser.error("--max-retries must be greater than or equal to 0.")
    if args.retry_delay_seconds < 0:
        parser.error("--retry-delay-seconds must be greater than or equal to 0.")
    return args


async def main() -> None:
    args = parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )

    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        store = _DrugCatalogStore(db)
        sync_job = DrugCatalogSyncJob(
            store=store,
            public_drug_data_portal=_PublicDrugDataPortal(timeout_seconds=60.0),
            page_size=args.page_size,
            start_page=args.start_page,
            max_pages=args.max_pages,
            max_retries=args.max_retries,
            retry_delay_seconds=args.retry_delay_seconds,
        )

        if args.dataset in {"basic", "all"}:
            basic_count = await sync_job.sync_basic()
            logger.info("[e약은요] synchronized rows: %s", basic_count)

        if args.dataset in {"approval", "all"}:
            approval_count = await sync_job.sync_approval()
            logger.info("[허가정보] synchronized rows: %s", approval_count)

        logger.info(
            "local catalog counts: basic=%s, approval=%s",
            store.count_basic(),
            store.count_approval(),
        )
    finally:
        db.close()


if __name__ == "__main__":
    asyncio.run(main())
