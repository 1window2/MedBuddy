# File Name: saved_medication_enrichment.py
# Role: Best-effort, identity-checked detail enrichment after a committed medication save.

import asyncio
import contextvars
import json
import logging
import re
from dataclasses import dataclass
from typing import Any

from fastapi import BackgroundTasks
from sqlalchemy.orm import Session, sessionmaker

from boundaries.medication_summary_boundary import FAILED_SUMMARY_TEXT, MISSING_DETAIL_TEXT
from boundaries.public_drug_api_boundary import read_public_item_sequence
from controls.check_catalog_medication_detail_control import (
    CATALOG_ITEM_SEQ_PATTERN,
    CheckCatalogMedicationDetail,
)
from core.account_database_lock import lock_account_operations
from core.database import isolated_worker_session_policy
from core.request_database_work import drain_database_work
from entities.medication_detail_entity import MedicationDetail, _DrugApprovalInfo
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import _UserAccount
from services.catalog_document_text import read_catalog_document
from schemas.medication import _MAX_DETAIL_TEXT_LENGTH

logger = logging.getLogger(__name__)
DETAIL_FIELDS = {
    "efficacy": "efficacy", "use_method": "usage_method", "warning_message": "warning",
    "interaction": "interaction", "side_effect": "side_effect", "storage_method": "storage_method",
}
_PROTECTED_FIELDS = (
    "item_name", "regimen_revision", "dosage_per_time", "daily_frequency", "total_days",
    "schedule_slot_keys", "dosing_mode", "prescription_date", "prescription_batch_id",
    "regimen_effective_from", "created_date",
)
ENRICHMENT_TIMEOUT_SECONDS = 40.0
MAX_CONCURRENT_ENRICHMENTS = 2
MAX_PENDING_ENRICHMENTS = 32


def _missing(value: str | None) -> bool:
    return (value or "").strip() in {"", MISSING_DETAIL_TEXT, FAILED_SUMMARY_TEXT}


@dataclass(frozen=True)
class EnrichmentTarget:
    owner: str
    medication_id: int
    item_seq: str
    protected: dict[str, Any]
    missing: dict[str, str | None]


def _target(db: Session, target: EnrichmentTarget) -> _SavedMedication | None:
    account = db.get(_UserAccount, target.owner)
    if account is None or account.deletion_requested_at or account.identity_deleted_at:
        return None
    row = db.query(_SavedMedication).filter_by(
        id=target.medication_id, patient_hash=target.owner, item_seq=target.item_seq,
        stopped_on=None, superseded_by_id=None, **target.protected,
    ).first()
    return row


def _preflight(factory: sessionmaker, target: EnrichmentTarget) -> tuple[bool, MedicationDetail | None]:
    with factory() as db:
        if _target(db, target) is None:
            return False, None
        return True, CheckCatalogMedicationDetail(db).get_detail(target.item_seq)


def _merge(values: dict[str, str], detail: MedicationDetail | None, item_seq: str) -> None:
    if detail is None or detail.item_seq != item_seq:
        return
    for field, attribute in DETAIL_FIELDS.items():
        text = read_catalog_document(getattr(detail, attribute))
        if not _missing(text) and len(text) <= _MAX_DETAIL_TEXT_LENGTH:
            values.setdefault(field, text)


def _one_exact(items: list, item_seq: str, identity) -> Any | None:
    matches = [item for item in items if identity(item) == item_seq]
    return matches[0] if len(matches) == 1 else None


async def fetch_public_details(target: EnrichmentTarget, values: dict[str, str]) -> None:
    # Reuse the app-owned clients, but never its request session or name-ranking pipeline.
    # The existing public adapters expose name search, not exact-ID detail methods.
    from api.dependencies import get_check_medication_detail, get_medication_detail_cache

    cache = await get_medication_detail_cache()
    name = target.protected["item_name"]
    cached = _one_exact(await cache.get(name) or [], target.item_seq, lambda item: item.item_seq)
    _merge(values, cached, target.item_seq)
    if target.missing.keys() <= values.keys():
        return
    control = get_check_medication_detail(db=None, medication_cache=cache)
    try:
        items = await control.public_drug_small_api.searchMedication(name)
        basic = _one_exact(items, target.item_seq, read_public_item_sequence)
        if basic is not None:
            details = await control._build_basic_drug_infos([basic])
            _merge(values, details[0], target.item_seq)
            if target.missing.keys() <= values.keys():
                return
    except Exception as exc:
        logger.info("Basic enrichment unavailable: %s", type(exc).__name__)
    items = await control.public_drug_large_api.searchMedication(name)
    approval = _one_exact(items, target.item_seq, read_public_item_sequence)
    if approval is None:
        return
    # Persist readable authoritative text even when the optional summary fails/times out.
    raw = _DrugApprovalInfo(
        item_seq=target.item_seq, item_name=name, raw_json=json.dumps(approval),
    )
    raw_detail = CheckCatalogMedicationDetail(None)._approval_detail(raw)
    try:
        summary = await control._summarize_advanced_item(name, approval)
        _merge(values, summary, target.item_seq)
    finally:
        _merge(values, raw_detail, target.item_seq)
    # Do not replace a name-keyed multi-product cache with one filtered product.


def _apply(factory: sessionmaker, target: EnrichmentTarget, values: dict[str, str]) -> None:
    with factory() as db:
        lock_account_operations(db, [target.owner])
        row = _target(db, target)
        if row is None:
            return
        updates = {
            field: values[field] for field, old_value in target.missing.items()
            if field in values and not _missing(values[field])
            and len(values[field]) <= _MAX_DETAIL_TEXT_LENGTH and getattr(row, field) == old_value
        }
        if updates:
            # Compare the original blank values as well as identity/revision. A user edit
            # wins even if another writer does not participate in account locking.
            db.query(_SavedMedication).filter_by(
                id=target.medication_id, patient_hash=target.owner, item_seq=target.item_seq,
                stopped_on=None, superseded_by_id=None, **target.protected,
                **{field: target.missing[field] for field in updates},
            ).update(updates, synchronize_session=False)
            db.commit()


class EnrichmentDispatcher:
    def __init__(self) -> None:
        self.jobs: dict[tuple, asyncio.Task] = {}
        self._gate = asyncio.Semaphore(MAX_CONCURRENT_ENRICHMENTS)

    async def dispatch(self, factory: sessionmaker, target: EnrichmentTarget) -> None:
        key = (factory.kw["bind"], target.owner, target.medication_id, target.item_seq,
               target.protected["regimen_revision"])
        if key in self.jobs or len(self.jobs) >= MAX_PENDING_ENRICHMENTS:
            return
        # BackgroundTasks must finish immediately so dependency teardown releases the
        # saving request's account lock. Do not inherit its database-admission context.
        task = asyncio.create_task(self._run(factory, target), context=contextvars.Context())
        self.jobs[key] = task
        task.add_done_callback(lambda completed: self.jobs.pop(key, None))

    async def _run(self, factory: sessionmaker, target: EnrichmentTarget) -> None:
        values: dict[str, str] = {}
        try:
            async with asyncio.timeout(ENRICHMENT_TIMEOUT_SECONDS):
                async with self._gate:
                    valid, detail = await drain_database_work(_preflight, factory, target)
                    if not valid:
                        return
                    _merge(values, detail, target.item_seq)
                    if not target.missing.keys() <= values.keys():
                        await fetch_public_details(target, values)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.info("Medication enrichment deferred: %s", type(exc).__name__)
        if values:
            try:
                await drain_database_work(_apply, factory, target, values)
            except Exception as exc:
                logger.warning("Medication enrichment write skipped: %s", type(exc).__name__)


_dispatchers: dict[asyncio.AbstractEventLoop, EnrichmentDispatcher] = {}


async def _dispatch(factory: sessionmaker, target: EnrichmentTarget) -> None:
    loop = asyncio.get_running_loop()
    # Usually one app loop; discard finished test/previous server-loop dispatchers.
    for previous in list(_dispatchers):
        if previous.is_closed() and not _dispatchers[previous].jobs:
            del _dispatchers[previous]
    dispatcher = _dispatchers.get(loop)
    if dispatcher is None:
        dispatcher = _dispatchers[loop] = EnrichmentDispatcher()
    await dispatcher.dispatch(factory, target)


def queue_saved_medication_enrichment(
    background_tasks: BackgroundTasks, db: Session, response: dict[str, object],
    owner: str, item_seq: str | None,
) -> None:
    if not (response.get("success") or response.get("duplicate")):
        return
    if not item_seq or re.fullmatch(CATALOG_ITEM_SEQ_PATTERN, item_seq) is None:
        return
    try:
        row = db.query(_SavedMedication).filter_by(
            id=response.get("id"), patient_hash=owner, item_seq=item_seq,
            stopped_on=None, superseded_by_id=None,
        ).first()
        if row is None:
            return
        missing = {field: getattr(row, field) for field in DETAIL_FIELDS if _missing(getattr(row, field))}
        if not missing:
            return
        target = EnrichmentTarget(
            owner, row.id, item_seq,
            {field: getattr(row, field) for field in _PROTECTED_FIELDS}, missing,
        )
        factory, _ = isolated_worker_session_policy(db)
        if factory is not None:
            background_tasks.add_task(_dispatch, factory, target)
    except Exception as exc:
        logger.warning("Medication enrichment could not be queued: %s", type(exc).__name__)
    finally:
        # Save/duplicate already committed; release its refresh/read transaction before
        # background work. The response consists solely of plain values at this point.
        try:
            db.rollback()
        except Exception as exc:
            logger.warning("Enrichment session release failed: %s", type(exc).__name__)
