# File Name: sync_drug_catalog.py
# Role: Synchronizes Korean public medication APIs into the shared catalog.

import argparse
import asyncio
from collections.abc import Awaitable, Callable
from contextlib import contextmanager
from dataclasses import asdict
import json
import logging
import math
from pathlib import Path
import re
import sys
from typing import Any, Iterator
from uuid import uuid4

from sqlalchemy import or_, text
from sqlalchemy.orm import Session

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from boundaries.public_drug_api_boundary import (
    PublicDrugLargeAPI,
    PublicDrugSmallAPI,
    _PublicDrugTransport,
)
from boundaries.pill_identification_boundary import MFDSPillAPI
from core.database import SessionLocal
from entities import medication_detail_entity  # noqa: F401
from entities.medication_detail_entity import _DrugApprovalInfo, _DrugBasicInfo
from entities.pill_identification_entity import (
    PillCatalogDownloadReport,
    PillCatalogReconciliationReport,
    PillCatalogSnapshot,
    PillIdentificationReference,
)
from repositories.pill_identification_catalog_repository import (
    PillIdentificationCatalogRepository,
)

logger = logging.getLogger(__name__)

_CATALOG_SYNC_ADVISORY_LOCK_ID = 0x4D45444255444459


class CatalogSyncAlreadyRunningError(RuntimeError):
    """Raised when another PostgreSQL catalog synchronization owns the lock."""


class CatalogSyncIncompleteError(RuntimeError):
    """Raised when an upstream catalog response would publish partial data."""


_CATALOG_VOLUME_GUARD_MINIMUM_BASELINE = 10
_CATALOG_VOLUME_GUARD_RETENTION_RATIO = 0.80


def _configure_logging() -> None:
    """Configures catalog logs without exposing credential-bearing request URLs."""

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)


@contextmanager
def _exclusive_catalog_sync_lock(db: Session) -> Iterator[None]:
    """Serializes the complete catalog job across PostgreSQL-backed workers."""

    bind = db.get_bind()
    if bind.dialect.name != "postgresql":
        yield
        return

    connect = getattr(bind, "connect", None)
    if not callable(connect):
        raise RuntimeError("Catalog synchronization requires an engine-bound session.")

    with connect() as lock_connection:
        acquired = lock_connection.execute(
            text("SELECT pg_try_advisory_lock(:lock_id)"),
            {"lock_id": _CATALOG_SYNC_ADVISORY_LOCK_ID},
        ).scalar_one()
        if not acquired:
            raise CatalogSyncAlreadyRunningError(
                "Another drug catalog synchronization is already running."
            )
        try:
            yield
        finally:
            released = lock_connection.execute(
                text("SELECT pg_advisory_unlock(:lock_id)"),
                {"lock_id": _CATALOG_SYNC_ADVISORY_LOCK_ID},
            ).scalar_one()
            if not released:
                logger.error("PostgreSQL catalog synchronization lock was not owned.")


# Class Name: _DrugCatalogStore
# Role: Internal persistence helper for shared drug catalog synchronization.
# Responsibilities:
#   - Upsert e약은요 and approval API records into the shared database.
#   - Preserve raw API payloads for traceability.
#   - Keep table-specific normalization in one sync-only helper.
# Attributes:
#   - db: SQLAlchemy Session used for persistence operations.
class _DrugCatalogStore:
    _WHITESPACE_PATTERN = re.compile(r"\s+")

    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: upsert_basic_items
    # Description:
    # - Inserts or updates e약은요 records from public API payloads.
    # Parameters:
    # - items: Raw public API item dictionaries.
    # Returns:
    # - Number of rows processed.
    def upsert_basic_items(
        self,
        items: list[dict[str, Any]],
        *,
        commit: bool = True,
        sync_token: str | None = None,
    ) -> int:
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
            target_item.catalog_sync_token = sync_token

            if is_new_item:
                self.db.add(target_item)

            if item_seq:
                batch_targets_by_seq[item_seq] = target_item
            batch_targets_by_name[normalized_item_name] = target_item
            processed_count += 1

        if commit:
            self.db.commit()
        else:
            self.db.flush()
        return processed_count

    # Function Name: upsert_approval_items
    # Description:
    # - Inserts or updates detailed approval records from public API payloads.
    # Parameters:
    # - items: Raw public API item dictionaries.
    # Returns:
    # - Number of rows processed.
    def upsert_approval_items(
        self,
        items: list[dict[str, Any]],
        *,
        commit: bool = True,
        sync_token: str | None = None,
    ) -> int:
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
            target_item.catalog_sync_token = sync_token

            if is_new_item:
                self.db.add(target_item)

            if item_seq:
                batch_targets_by_seq[item_seq] = target_item
            batch_targets_by_name[normalized_item_name] = target_item
            processed_count += 1

        if commit:
            self.db.commit()
        else:
            self.db.flush()
        return processed_count

    # Function Name: prune_basic_items_not_seen
    # Description:
    # - Deletes basic-catalog rows that were not observed during a successful
    #   complete refresh identified by sync_token.
    # - Participates in the caller's transaction so a later dataset failure
    #   restores the previously published catalog.
    # Parameters:
    # - sync_token: Unique marker assigned to every row observed by this refresh.
    # - commit: Whether this method owns the transaction commit.
    # Returns:
    # - Number of obsolete rows deleted.
    def prune_basic_items_not_seen(
        self,
        sync_token: str,
        *,
        commit: bool = True,
    ) -> int:
        deleted_count = (
            self.db.query(_DrugBasicInfo)
            .filter(
                or_(
                    _DrugBasicInfo.catalog_sync_token.is_(None),
                    _DrugBasicInfo.catalog_sync_token != sync_token,
                )
            )
            .delete(synchronize_session=False)
        )
        if commit:
            self.db.commit()
        else:
            self.db.flush()
        return deleted_count

    # Function Name: prune_approval_items_not_seen
    # Description:
    # - Deletes approval-catalog rows that were not observed during a successful
    #   complete refresh identified by sync_token.
    # - Participates in the caller's transaction so a later dataset failure
    #   restores the previously published catalog.
    # Parameters:
    # - sync_token: Unique marker assigned to every row observed by this refresh.
    # - commit: Whether this method owns the transaction commit.
    # Returns:
    # - Number of obsolete rows deleted.
    def prune_approval_items_not_seen(
        self,
        sync_token: str,
        *,
        commit: bool = True,
    ) -> int:
        deleted_count = (
            self.db.query(_DrugApprovalInfo)
            .filter(
                or_(
                    _DrugApprovalInfo.catalog_sync_token.is_(None),
                    _DrugApprovalInfo.catalog_sync_token != sync_token,
                )
            )
            .delete(synchronize_session=False)
        )
        if commit:
            self.db.commit()
        else:
            self.db.flush()
        return deleted_count

    # Function Name: count_basic
    # Description:
    # - Counts locally stored e약은요 rows.
    # Returns:
    # - Row count.
    def count_basic(self) -> int:
        return self.db.query(_DrugBasicInfo).count()

    def count_basic_seen(self, sync_token: str) -> int:
        return (
            self.db.query(_DrugBasicInfo)
            .filter(_DrugBasicInfo.catalog_sync_token == sync_token)
            .count()
        )

    # Function Name: count_approval
    # Description:
    # - Counts locally stored approval detail rows.
    # Returns:
    # - Row count.
    def count_approval(self) -> int:
        return self.db.query(_DrugApprovalInfo).count()

    def count_approval_seen(self, sync_token: str) -> int:
        return (
            self.db.query(_DrugApprovalInfo)
            .filter(_DrugApprovalInfo.catalog_sync_token == sync_token)
            .count()
        )

    def count_pill_identification(self) -> int:
        return self.db.query(PillIdentificationReference).count()

    def has_complete_seed(self) -> bool:
        return all(
            count > 0
            for count in (
                self.count_basic(),
                self.count_approval(),
                self.count_pill_identification(),
            )
        )

    # Function Name: normalize_name
    # Description:
    # - Normalizes medication names for stable local lookup.
    # Parameters:
    # - name: Raw medication name.
    # Returns:
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
        if not item_seq and normalized_item_name in batch_targets_by_name:
            return batch_targets_by_name[normalized_item_name]

        if item_seq:
            existing_item = (
                self.db.query(_DrugBasicInfo)
                .filter(_DrugBasicInfo.item_seq == item_seq)
                .first()
            )
            if existing_item is not None:
                return existing_item

        if not item_seq:
            return (
                self.db.query(_DrugBasicInfo)
                .filter(_DrugBasicInfo.normalized_item_name == normalized_item_name)
                .first()
            )
        return None

    def _resolve_approval_target(
        self,
        item_seq: str,
        normalized_item_name: str,
        batch_targets_by_seq: dict[str, _DrugApprovalInfo],
        batch_targets_by_name: dict[str, _DrugApprovalInfo],
    ) -> _DrugApprovalInfo | None:
        if item_seq and item_seq in batch_targets_by_seq:
            return batch_targets_by_seq[item_seq]
        if not item_seq and normalized_item_name in batch_targets_by_name:
            return batch_targets_by_name[normalized_item_name]

        if item_seq:
            existing_item = (
                self.db.query(_DrugApprovalInfo)
                .filter(_DrugApprovalInfo.item_seq == item_seq)
                .first()
            )
            if existing_item is not None:
                return existing_item

        if not item_seq:
            return (
                self.db.query(_DrugApprovalInfo)
                .filter(_DrugApprovalInfo.normalized_item_name == normalized_item_name)
                .first()
            )
        return None

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


# Class Name: DrugCatalogSyncJob
# Role: Control class for public drug API to shared DB synchronization.
# Responsibilities:
#   - Fetch paginated e약은요 records.
#   - Fetch paginated approval detail records.
#   - Upsert fetched records into the local catalog tables.
# Attributes:
#   - store: _DrugCatalogStore used for shared persistence.
#   - public_drug_small_api: eDrug API boundary used for basic catalog pages.
#   - public_drug_large_api: Approval API boundary used for complete catalog pages.
#   - page_size: Number of API rows fetched per request.
#   - start_page: First API page to request.
#   - max_pages: Optional page cap for smoke tests or partial syncs.
#   - max_retries: Number of retry attempts for transient public API failures.
#   - retry_delay_seconds: Delay between retry attempts.
class DrugCatalogSyncJob:
    def __init__(
        self,
        store: _DrugCatalogStore,
        public_drug_small_api: PublicDrugSmallAPI,
        public_drug_large_api: PublicDrugLargeAPI,
        pill_catalog_api: MFDSPillAPI,
        page_size: int,
        start_page: int = 1,
        max_pages: int | None = None,
        max_retries: int = 3,
        retry_delay_seconds: float = 3.0,
    ) -> None:
        self.store = store
        self.public_drug_small_api = public_drug_small_api
        self.public_drug_large_api = public_drug_large_api
        self.pill_catalog_api = pill_catalog_api
        self.page_size = page_size
        self.start_page = start_page
        self.max_pages = max_pages
        self.max_retries = max_retries
        self.retry_delay_seconds = retry_delay_seconds
        self.last_pill_reconciliation_report: (
            PillCatalogReconciliationReport | None
        ) = None

    # Function Name: sync_basic
    # Description:
    # - Synchronizes the full e약은요 API dataset into drug_basic_infos.
    # Returns:
    # - Number of rows processed.
    async def sync_basic(self, *, commit: bool = True) -> int:
        previous_count = self.store.count_basic()
        sync_token = str(uuid4()) if self._is_complete_dataset_sync else None
        try:
            processed = await self._sync_pages(
                dataset_name="e약은요",
                fetch_page=self.public_drug_small_api.fetchPage,
                upsert_items=lambda items: self.store.upsert_basic_items(
                    items,
                    commit=False,
                    sync_token=sync_token,
                ),
            )
            if processed == 0:
                raise CatalogSyncIncompleteError(
                    "The basic medication catalog returned no usable rows."
                )
            if sync_token is not None:
                self._validate_refresh_volume(
                    dataset_name="e약은요",
                    previous_count=previous_count,
                    refreshed_count=self.store.count_basic_seen(sync_token),
                )
                self.store.prune_basic_items_not_seen(sync_token, commit=False)
            if commit:
                self.store.db.commit()
            return processed
        except Exception:
            if commit:
                self.store.db.rollback()
            raise

    # Function Name: sync_approval
    # Description:
    # - Synchronizes the full approval detail API dataset into drug_approval_infos.
    # Returns:
    # - Number of rows processed.
    async def sync_approval(self, *, commit: bool = True) -> int:
        previous_count = self.store.count_approval()
        sync_token = str(uuid4()) if self._is_complete_dataset_sync else None
        try:
            processed = await self._sync_pages(
                dataset_name="허가정보",
                fetch_page=self.public_drug_large_api.fetchPage,
                upsert_items=lambda items: self.store.upsert_approval_items(
                    items,
                    commit=False,
                    sync_token=sync_token,
                ),
            )
            if processed == 0:
                raise CatalogSyncIncompleteError(
                    "The approval medication catalog returned no usable rows."
                )
            if sync_token is not None:
                self._validate_refresh_volume(
                    dataset_name="허가정보",
                    previous_count=previous_count,
                    refreshed_count=self.store.count_approval_seen(sync_token),
                )
                self.store.prune_approval_items_not_seen(sync_token, commit=False)
            if commit:
                self.store.db.commit()
            return processed
        except Exception:
            if commit:
                self.store.db.rollback()
            raise

    async def sync_pill_identification(self, *, commit: bool = True) -> int:
        previous_count = self.store.count_pill_identification()
        try:
            request_snapshot = getattr(
                self.pill_catalog_api,
                "requestCatalogSnapshot",
                None,
            )
            if callable(request_snapshot):
                snapshot = await request_snapshot()
                catalog = list(snapshot.entries)
            else:
                catalog = await self.pill_catalog_api.requestCatalog()
                snapshot = PillCatalogSnapshot(
                    entries=tuple(catalog),
                    report=PillCatalogDownloadReport(
                        advertised_rows=len(catalog),
                        fetched_rows=len(catalog),
                        valid_rows=len(catalog),
                        accepted_unique_rows=len(catalog),
                        rejected_rows=0,
                        duplicate_rows=0,
                        page_count=1,
                        response_bytes=0,
                    ),
                )
            if not catalog:
                raise CatalogSyncIncompleteError(
                    "The pill-identification catalog returned no rows."
                )
            repository = PillIdentificationCatalogRepository(self.store.db)
            repository.replace_all(
                catalog,
                commit=False,
            )
            expected_item_sequences = {entry.item_seq for entry in catalog}
            persisted_item_sequences = repository.list_item_sequences()
            missing_item_sequences = (
                expected_item_sequences - persisted_item_sequences
            )
            unexpected_item_sequences = (
                persisted_item_sequences - expected_item_sequences
            )
            reconciliation_report = PillCatalogReconciliationReport(
                source=snapshot.report,
                kpic_product_floor=getattr(
                    self.pill_catalog_api,
                    "minimum_catalog_rows",
                    len(catalog),
                ),
                persisted_rows=len(persisted_item_sequences),
                missing_persisted_rows=len(missing_item_sequences),
                unexpected_persisted_rows=len(unexpected_item_sequences),
            )
            if not reconciliation_report.is_publishable:
                raise CatalogSyncIncompleteError(
                    "The pill-identification catalog failed identifier-set "
                    "reconciliation."
                )
            self._validate_refresh_volume(
                dataset_name="알약 식별정보",
                previous_count=previous_count,
                refreshed_count=self.store.count_pill_identification(),
            )
            if commit:
                self.store.db.commit()
            self.last_pill_reconciliation_report = reconciliation_report
            logger.info(
                "pill catalog reconciliation: %s",
                json.dumps(asdict(reconciliation_report), separators=(",", ":")),
            )
            return len(catalog)
        except Exception:
            self.last_pill_reconciliation_report = None
            if commit:
                self.store.db.rollback()
            raise

    async def sync_all(self) -> dict[str, int]:
        """Synchronizes every catalog as one caller-owned transaction."""

        try:
            synchronized_counts = {
                "basic": await self.sync_basic(commit=False),
                "approval": await self.sync_approval(commit=False),
                "pill": await self.sync_pill_identification(commit=False),
            }
            self.store.db.commit()
            return synchronized_counts
        except Exception:
            self.store.db.rollback()
            raise

    @property
    def _is_complete_dataset_sync(self) -> bool:
        """Returns whether this job covers every page from the first page."""

        return self.start_page == 1 and self.max_pages is None

    # Function Name: _validate_refresh_volume
    # Description:
    # - Rejects a full refresh that would replace a populated catalog with a
    #   sharply smaller result, even when the upstream response is internally
    #   consistent and returns HTTP success.
    # Parameters:
    # - dataset_name: Human-readable catalog name for the error message.
    # - previous_count: Row count before the refresh transaction started.
    # - refreshed_count: Distinct rows observed in the candidate refresh.
    # Returns:
    # - None when the candidate volume is safe to publish.
    @staticmethod
    def _validate_refresh_volume(
        *,
        dataset_name: str,
        previous_count: int,
        refreshed_count: int,
    ) -> None:
        if previous_count < _CATALOG_VOLUME_GUARD_MINIMUM_BASELINE:
            return
        minimum_safe_count = math.ceil(
            previous_count * _CATALOG_VOLUME_GUARD_RETENTION_RATIO
        )
        if refreshed_count < minimum_safe_count:
            raise CatalogSyncIncompleteError(
                f"{dataset_name} refresh produced {refreshed_count} rows; "
                f"at least {minimum_safe_count} are required before replacing "
                f"the existing {previous_count}-row catalog."
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
                if total_pages is not None and page_no <= total_pages:
                    raise CatalogSyncIncompleteError(
                        f"{dataset_name} ended at page {page_no} before the "
                        f"reported final page {total_pages}."
                    )
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
        description="Synchronize public drug API datasets into shared catalog tables.",
    )
    parser.add_argument(
        "--dataset",
        choices=["basic", "approval", "pill", "all"],
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
    parser.add_argument(
        "--only-if-empty",
        action="store_true",
        help="Skip synchronization when every shared catalog already has rows.",
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
    _configure_logging()

    db = SessionLocal()
    transport = _PublicDrugTransport(timeout_seconds=60.0)
    try:
        store = _DrugCatalogStore(db)
        sync_job = DrugCatalogSyncJob(
            store=store,
            public_drug_small_api=PublicDrugSmallAPI(transport=transport),
            public_drug_large_api=PublicDrugLargeAPI(transport=transport),
            pill_catalog_api=MFDSPillAPI(),
            page_size=args.page_size,
            start_page=args.start_page,
            max_pages=args.max_pages,
            max_retries=args.max_retries,
            retry_delay_seconds=args.retry_delay_seconds,
        )

        with _exclusive_catalog_sync_lock(db):
            if args.only_if_empty and store.has_complete_seed():
                logger.info("Shared medication catalogs are already seeded; skipping sync.")
            elif args.dataset == "all":
                synchronized_counts = await sync_job.sync_all()
                logger.info(
                    "[e약은요] synchronized rows: %s",
                    synchronized_counts["basic"],
                )
                logger.info(
                    "[허가정보] synchronized rows: %s",
                    synchronized_counts["approval"],
                )
                logger.info(
                    "[알약 식별정보] synchronized rows: %s",
                    synchronized_counts["pill"],
                )
            elif args.dataset == "basic":
                basic_count = await sync_job.sync_basic()
                logger.info("[e약은요] synchronized rows: %s", basic_count)
            elif args.dataset == "approval":
                approval_count = await sync_job.sync_approval()
                logger.info("[허가정보] synchronized rows: %s", approval_count)
            elif args.dataset == "pill":
                pill_count = await sync_job.sync_pill_identification()
                logger.info("[알약 식별정보] synchronized rows: %s", pill_count)

            logger.info(
                "shared catalog counts: basic=%s, approval=%s, pill=%s",
                store.count_basic(),
                store.count_approval(),
                store.count_pill_identification(),
            )
    finally:
        await transport.close()
        db.close()


if __name__ == "__main__":
    asyncio.run(main())
