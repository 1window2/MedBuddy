import asyncio
import logging
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from sqlalchemy.exc import IntegrityError
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from core.database import Base  # noqa: E402
from entities.medication_detail_entity import _DrugApprovalInfo, _DrugBasicInfo  # noqa: E402
from entities.pill_identification_entity import (  # noqa: E402
    PillCatalogEntry,
    PillIdentificationReference,
)
from scripts.sync_drug_catalog import (  # noqa: E402
    CatalogSyncAlreadyRunningError,
    CatalogSyncIncompleteError,
    DrugCatalogSyncJob,
    _DrugCatalogStore,
    _configure_logging,
    _exclusive_catalog_sync_lock,
)


class DrugCatalogSyncTest(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.store = _DrugCatalogStore(self.db)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def test_logging_suppresses_credential_bearing_http_client_urls(self) -> None:
        httpx_logger = logging.getLogger("httpx")
        httpcore_logger = logging.getLogger("httpcore")
        previous_httpx_level = httpx_logger.level
        previous_httpcore_level = httpcore_logger.level
        try:
            httpx_logger.setLevel(logging.INFO)
            httpcore_logger.setLevel(logging.INFO)

            with patch("scripts.sync_drug_catalog.logging.basicConfig"):
                _configure_logging()

            self.assertEqual(httpx_logger.level, logging.WARNING)
            self.assertEqual(httpcore_logger.level, logging.WARNING)
        finally:
            httpx_logger.setLevel(previous_httpx_level)
            httpcore_logger.setLevel(previous_httpcore_level)

    def test_basic_sync_keeps_same_name_rows_with_distinct_item_seq(self) -> None:
        self.store.upsert_basic_items(
            [
                {
                    "itemSeq": "SEQ-A",
                    "itemName": "same-tablet",
                    "efcyQesitm": "effect-a",
                },
                {
                    "itemSeq": "SEQ-B",
                    "itemName": "same-tablet",
                    "efcyQesitm": "effect-b",
                },
            ]
        )

        rows = self.db.query(_DrugBasicInfo).order_by(_DrugBasicInfo.item_seq).all()

        self.assertEqual(len(rows), 2)
        self.assertEqual([row.item_seq for row in rows], ["SEQ-A", "SEQ-B"])
        self.assertEqual([row.efficacy for row in rows], ["effect-a", "effect-b"])

    def test_approval_sync_keeps_same_name_rows_with_distinct_item_seq(self) -> None:
        self.store.upsert_approval_items(
            [
                {
                    "ITEM_SEQ": "SEQ-A",
                    "ITEM_NAME": "same-tablet",
                    "EE_DOC_DATA": "effect-a",
                },
                {
                    "ITEM_SEQ": "SEQ-B",
                    "ITEM_NAME": "same-tablet",
                    "EE_DOC_DATA": "effect-b",
                },
            ]
        )

        rows = (
            self.db.query(_DrugApprovalInfo)
            .order_by(_DrugApprovalInfo.item_seq)
            .all()
        )

        self.assertEqual(len(rows), 2)
        self.assertEqual([row.item_seq for row in rows], ["SEQ-A", "SEQ-B"])
        self.assertEqual(
            [row.efficacy_doc for row in rows],
            ["effect-a", "effect-b"],
        )

    def test_complete_seed_requires_every_shared_catalog(self) -> None:
        self.assertFalse(self.store.has_complete_seed())
        self.db.add_all(
            [
                _DrugBasicInfo(
                    item_seq="BASIC-1",
                    item_name="basic",
                    normalized_item_name="basic",
                    raw_json="{}",
                ),
                _DrugApprovalInfo(
                    item_seq="APPROVAL-1",
                    item_name="approval",
                    normalized_item_name="approval",
                    raw_json="{}",
                ),
                PillIdentificationReference(
                    item_seq="PILL-1",
                    item_name="pill",
                ),
            ]
        )
        self.db.commit()

        self.assertTrue(self.store.has_complete_seed())

    def test_pill_sync_replaces_shared_reference_catalog(self) -> None:
        class _PillCatalogAPI:
            async def requestCatalog(self) -> list[PillCatalogEntry]:
                return [
                    PillCatalogEntry(
                        item_seq="PILL-1",
                        item_name="sample tablet",
                    )
                ]

        sync_job = DrugCatalogSyncJob(
            store=self.store,
            public_drug_small_api=object(),  # type: ignore[arg-type]
            public_drug_large_api=object(),  # type: ignore[arg-type]
            pill_catalog_api=_PillCatalogAPI(),  # type: ignore[arg-type]
            page_size=100,
        )

        synchronized_count = asyncio.run(sync_job.sync_pill_identification())

        self.assertEqual(synchronized_count, 1)
        self.assertEqual(
            self.db.query(PillIdentificationReference).one().item_seq,
            "PILL-1",
        )

    def test_single_dataset_sync_commits_its_transaction(self) -> None:
        class _BasicAPI:
            async def fetchPage(
                self,
                _page_no: int,
                _page_size: int,
            ) -> tuple[list[dict[str, object]], int]:
                return ([{"itemSeq": "BASIC-1", "itemName": "basic tablet"}], 1)

        sync_job = DrugCatalogSyncJob(
            store=self.store,
            public_drug_small_api=_BasicAPI(),  # type: ignore[arg-type]
            public_drug_large_api=object(),  # type: ignore[arg-type]
            pill_catalog_api=object(),  # type: ignore[arg-type]
            page_size=100,
        )

        with patch.object(self.db, "commit", wraps=self.db.commit) as commit:
            synchronized_count = asyncio.run(sync_job.sync_basic())

        self.assertEqual(synchronized_count, 1)
        commit.assert_called_once_with()

    def test_all_sync_rolls_back_earlier_datasets_after_late_failure(self) -> None:
        self.db.add_all(
            [
                _DrugBasicInfo(
                    item_seq="BASIC-1",
                    item_name="existing basic",
                    normalized_item_name="existingbasic",
                    efficacy="existing basic effect",
                    raw_json="{}",
                ),
                _DrugBasicInfo(
                    item_seq="BASIC-WITHDRAWN",
                    item_name="existing withdrawn basic",
                    normalized_item_name="existingwithdrawnbasic",
                    raw_json="{}",
                ),
                _DrugApprovalInfo(
                    item_seq="APPROVAL-1",
                    item_name="existing approval",
                    normalized_item_name="existingapproval",
                    efficacy_doc="existing approval effect",
                    raw_json="{}",
                ),
                _DrugApprovalInfo(
                    item_seq="APPROVAL-WITHDRAWN",
                    item_name="existing withdrawn approval",
                    normalized_item_name="existingwithdrawnapproval",
                    raw_json="{}",
                ),
                PillIdentificationReference(
                    item_seq="PILL-1",
                    item_name="existing pill",
                ),
            ]
        )
        self.db.commit()

        class _BasicAPI:
            async def fetchPage(
                self,
                _page_no: int,
                _page_size: int,
            ) -> tuple[list[dict[str, object]], int]:
                return (
                    [
                        {
                            "itemSeq": "BASIC-1",
                            "itemName": "replacement basic",
                            "efcyQesitm": "replacement basic effect",
                        }
                    ],
                    1,
                )

        class _ApprovalAPI:
            async def fetchPage(
                self,
                _page_no: int,
                _page_size: int,
            ) -> tuple[list[dict[str, object]], int]:
                return (
                    [
                        {
                            "ITEM_SEQ": "APPROVAL-1",
                            "ITEM_NAME": "replacement approval",
                            "EE_DOC_DATA": "replacement approval effect",
                        }
                    ],
                    1,
                )

        class _FailingPillAPI:
            async def requestCatalog(self) -> list[PillCatalogEntry]:
                raise RuntimeError("pill catalog unavailable")

        sync_job = DrugCatalogSyncJob(
            store=self.store,
            public_drug_small_api=_BasicAPI(),  # type: ignore[arg-type]
            public_drug_large_api=_ApprovalAPI(),  # type: ignore[arg-type]
            pill_catalog_api=_FailingPillAPI(),  # type: ignore[arg-type]
            page_size=100,
        )

        with self.assertRaisesRegex(RuntimeError, "pill catalog unavailable"):
            asyncio.run(sync_job.sync_all())

        self.db.expire_all()
        basic = (
            self.db.query(_DrugBasicInfo)
            .filter(_DrugBasicInfo.item_seq == "BASIC-1")
            .one()
        )
        approval = (
            self.db.query(_DrugApprovalInfo)
            .filter(_DrugApprovalInfo.item_seq == "APPROVAL-1")
            .one()
        )
        pill = self.db.query(PillIdentificationReference).one()
        self.assertEqual(basic.item_name, "existing basic")
        self.assertEqual(basic.efficacy, "existing basic effect")
        self.assertEqual(approval.item_name, "existing approval")
        self.assertEqual(approval.efficacy_doc, "existing approval effect")
        self.assertEqual(pill.item_name, "existing pill")
        self.assertEqual(
            {
                row.item_seq for row in self.db.query(_DrugBasicInfo).all()
            },
            {"BASIC-1", "BASIC-WITHDRAWN"},
        )
        self.assertEqual(
            {
                row.item_seq for row in self.db.query(_DrugApprovalInfo).all()
            },
            {"APPROVAL-1", "APPROVAL-WITHDRAWN"},
        )

    def test_all_sync_commits_every_dataset_once(self) -> None:
        class _BasicAPI:
            async def fetchPage(
                self,
                _page_no: int,
                _page_size: int,
            ) -> tuple[list[dict[str, object]], int]:
                return ([{"itemSeq": "BASIC-1", "itemName": "basic tablet"}], 1)

        class _ApprovalAPI:
            async def fetchPage(
                self,
                _page_no: int,
                _page_size: int,
            ) -> tuple[list[dict[str, object]], int]:
                return (
                    [{"ITEM_SEQ": "APPROVAL-1", "ITEM_NAME": "approval tablet"}],
                    1,
                )

        class _PillAPI:
            async def requestCatalog(self) -> list[PillCatalogEntry]:
                return [PillCatalogEntry(item_seq="PILL-1", item_name="pill")]

        sync_job = DrugCatalogSyncJob(
            store=self.store,
            public_drug_small_api=_BasicAPI(),  # type: ignore[arg-type]
            public_drug_large_api=_ApprovalAPI(),  # type: ignore[arg-type]
            pill_catalog_api=_PillAPI(),  # type: ignore[arg-type]
            page_size=100,
        )

        with patch.object(self.db, "commit", wraps=self.db.commit) as commit:
            synchronized_counts = asyncio.run(sync_job.sync_all())

        self.assertEqual(
            synchronized_counts,
            {"basic": 1, "approval": 1, "pill": 1},
        )
        commit.assert_called_once_with()
        self.assertEqual(self.db.query(_DrugBasicInfo).count(), 1)
        self.assertEqual(self.db.query(_DrugApprovalInfo).count(), 1)
        self.assertEqual(self.db.query(PillIdentificationReference).count(), 1)

    def test_complete_sync_prunes_basic_and_approval_rows_removed_upstream(
        self,
    ) -> None:
        self.db.add_all(
            [
                _DrugBasicInfo(
                    item_seq="BASIC-KEEP",
                    item_name="old basic",
                    normalized_item_name="oldbasic",
                    ai_guide="preserved guide",
                    raw_json="{}",
                ),
                _DrugBasicInfo(
                    item_seq="BASIC-WITHDRAWN",
                    item_name="withdrawn basic",
                    normalized_item_name="withdrawnbasic",
                    raw_json="{}",
                ),
                _DrugApprovalInfo(
                    item_seq="APPROVAL-KEEP",
                    item_name="old approval",
                    normalized_item_name="oldapproval",
                    summary_efficacy="preserved summary",
                    raw_json="{}",
                ),
                _DrugApprovalInfo(
                    item_seq="APPROVAL-WITHDRAWN",
                    item_name="withdrawn approval",
                    normalized_item_name="withdrawnapproval",
                    raw_json="{}",
                ),
            ]
        )
        self.db.commit()

        class _BasicAPI:
            async def fetchPage(
                self,
                _page_no: int,
                _page_size: int,
            ) -> tuple[list[dict[str, object]], int]:
                return (
                    [{"itemSeq": "BASIC-KEEP", "itemName": "current basic"}],
                    1,
                )

        class _ApprovalAPI:
            async def fetchPage(
                self,
                _page_no: int,
                _page_size: int,
            ) -> tuple[list[dict[str, object]], int]:
                return (
                    [
                        {
                            "ITEM_SEQ": "APPROVAL-KEEP",
                            "ITEM_NAME": "current approval",
                        }
                    ],
                    1,
                )

        sync_job = DrugCatalogSyncJob(
            store=self.store,
            public_drug_small_api=_BasicAPI(),  # type: ignore[arg-type]
            public_drug_large_api=_ApprovalAPI(),  # type: ignore[arg-type]
            pill_catalog_api=object(),  # type: ignore[arg-type]
            page_size=100,
        )

        asyncio.run(sync_job.sync_basic())
        asyncio.run(sync_job.sync_approval())

        basic = self.db.query(_DrugBasicInfo).one()
        approval = self.db.query(_DrugApprovalInfo).one()
        self.assertEqual(basic.item_seq, "BASIC-KEEP")
        self.assertEqual(basic.item_name, "current basic")
        self.assertEqual(basic.ai_guide, "preserved guide")
        self.assertIsNotNone(basic.catalog_sync_token)
        self.assertEqual(approval.item_seq, "APPROVAL-KEEP")
        self.assertEqual(approval.item_name, "current approval")
        self.assertEqual(approval.summary_efficacy, "preserved summary")
        self.assertIsNotNone(approval.catalog_sync_token)

    def test_page_limited_sync_does_not_prune_unvisited_rows(self) -> None:
        self.db.add(
            _DrugBasicInfo(
                item_seq="BASIC-UNVISITED",
                item_name="unvisited basic",
                normalized_item_name="unvisitedbasic",
                raw_json="{}",
            )
        )
        self.db.commit()

        class _BasicAPI:
            async def fetchPage(
                self,
                _page_no: int,
                _page_size: int,
            ) -> tuple[list[dict[str, object]], int]:
                return (
                    [{"itemSeq": "BASIC-VISITED", "itemName": "visited basic"}],
                    2,
                )

        sync_job = DrugCatalogSyncJob(
            store=self.store,
            public_drug_small_api=_BasicAPI(),  # type: ignore[arg-type]
            public_drug_large_api=object(),  # type: ignore[arg-type]
            pill_catalog_api=object(),  # type: ignore[arg-type]
            page_size=1,
            max_pages=1,
        )

        asyncio.run(sync_job.sync_basic())

        item_seqs = {
            row.item_seq for row in self.db.query(_DrugBasicInfo).all()
        }
        self.assertEqual(item_seqs, {"BASIC-UNVISITED", "BASIC-VISITED"})

    def test_basic_sync_rolls_back_premature_empty_page(self) -> None:
        class _TruncatedBasicAPI:
            async def fetchPage(
                self,
                page_no: int,
                _page_size: int,
            ) -> tuple[list[dict[str, object]], int]:
                if page_no == 1:
                    return ([{"itemSeq": "PARTIAL", "itemName": "partial"}], 2)
                return ([], 2)

        sync_job = DrugCatalogSyncJob(
            store=self.store,
            public_drug_small_api=_TruncatedBasicAPI(),  # type: ignore[arg-type]
            public_drug_large_api=object(),  # type: ignore[arg-type]
            pill_catalog_api=object(),  # type: ignore[arg-type]
            page_size=1,
            max_retries=0,
        )

        with self.assertRaises(CatalogSyncIncompleteError):
            asyncio.run(sync_job.sync_basic())

        self.assertEqual(self.db.query(_DrugBasicInfo).count(), 0)

    def test_full_sync_rejects_internally_consistent_mass_pruning(self) -> None:
        self.db.add_all(
            [
                _DrugBasicInfo(
                    item_seq=f"EXISTING-{index}",
                    item_name=f"existing tablet {index}",
                    normalized_item_name=f"existingtablet{index}",
                    raw_json="{}",
                )
                for index in range(10)
            ]
        )
        self.db.commit()

        class _PartialBasicAPI:
            async def fetchPage(
                self,
                _page_no: int,
                _page_size: int,
            ) -> tuple[list[dict[str, object]], int]:
                return (
                    [{"itemSeq": "EXISTING-0", "itemName": "current tablet"}],
                    1,
                )

        sync_job = DrugCatalogSyncJob(
            store=self.store,
            public_drug_small_api=_PartialBasicAPI(),  # type: ignore[arg-type]
            public_drug_large_api=object(),  # type: ignore[arg-type]
            pill_catalog_api=object(),  # type: ignore[arg-type]
            page_size=100,
        )

        with self.assertRaises(CatalogSyncIncompleteError):
            asyncio.run(sync_job.sync_basic())

        self.db.expire_all()
        self.assertEqual(self.db.query(_DrugBasicInfo).count(), 10)

    def test_pill_sync_rejects_internally_consistent_mass_replacement(
        self,
    ) -> None:
        self.db.add_all(
            [
                PillIdentificationReference(
                    item_seq=f"EXISTING-{index}",
                    item_name=f"existing tablet {index}",
                )
                for index in range(10)
            ]
        )
        self.db.commit()

        class _PartialPillCatalogAPI:
            async def requestCatalog(self) -> list[PillCatalogEntry]:
                return [
                    PillCatalogEntry(
                        item_seq="REPLACEMENT",
                        item_name="replacement tablet",
                    )
                ]

        sync_job = DrugCatalogSyncJob(
            store=self.store,
            public_drug_small_api=object(),  # type: ignore[arg-type]
            public_drug_large_api=object(),  # type: ignore[arg-type]
            pill_catalog_api=_PartialPillCatalogAPI(),  # type: ignore[arg-type]
            page_size=100,
        )

        with self.assertRaises(CatalogSyncIncompleteError):
            asyncio.run(sync_job.sync_pill_identification())

        self.db.expire_all()
        item_seqs = {
            row.item_seq
            for row in self.db.query(PillIdentificationReference).all()
        }
        self.assertEqual(
            item_seqs,
            {f"EXISTING-{index}" for index in range(10)},
        )

    def test_pill_sync_rejects_empty_catalog_without_deleting_existing_rows(
        self,
    ) -> None:
        self.db.add(
            PillIdentificationReference(
                item_seq="EXISTING",
                item_name="existing tablet",
            )
        )
        self.db.commit()

        class _EmptyPillCatalogAPI:
            async def requestCatalog(self) -> list[PillCatalogEntry]:
                return []

        sync_job = DrugCatalogSyncJob(
            store=self.store,
            public_drug_small_api=object(),  # type: ignore[arg-type]
            public_drug_large_api=object(),  # type: ignore[arg-type]
            pill_catalog_api=_EmptyPillCatalogAPI(),  # type: ignore[arg-type]
            page_size=100,
        )

        with self.assertRaises(CatalogSyncIncompleteError):
            asyncio.run(sync_job.sync_pill_identification())

        rows = self.db.query(PillIdentificationReference).all()
        self.assertEqual([row.item_seq for row in rows], ["EXISTING"])

    def test_failed_pill_sync_restores_previous_catalog(self) -> None:
        self.db.add(
            PillIdentificationReference(
                item_seq="EXISTING",
                item_name="existing tablet",
            )
        )
        self.db.commit()

        class _DuplicatePillCatalogAPI:
            async def requestCatalog(self) -> list[PillCatalogEntry]:
                return [
                    PillCatalogEntry(item_seq="DUPLICATE", item_name="first"),
                    PillCatalogEntry(item_seq="DUPLICATE", item_name="second"),
                ]

        sync_job = DrugCatalogSyncJob(
            store=self.store,
            public_drug_small_api=object(),  # type: ignore[arg-type]
            public_drug_large_api=object(),  # type: ignore[arg-type]
            pill_catalog_api=_DuplicatePillCatalogAPI(),  # type: ignore[arg-type]
            page_size=100,
        )

        with self.assertRaises(IntegrityError):
            asyncio.run(sync_job.sync_pill_identification())

        rows = self.db.query(PillIdentificationReference).all()
        self.assertEqual([row.item_seq for row in rows], ["EXISTING"])

    def test_postgresql_catalog_lock_rejects_overlapping_job(self) -> None:
        db = MagicMock()
        bind = MagicMock()
        bind.dialect.name = "postgresql"
        db.get_bind.return_value = bind
        lock_connection = bind.connect.return_value.__enter__.return_value
        lock_connection.execute.return_value.scalar_one.return_value = False

        with self.assertRaises(CatalogSyncAlreadyRunningError):
            with _exclusive_catalog_sync_lock(db):
                self.fail("contended catalog job must not start")

        lock_connection.execute.assert_called_once()

    def test_postgresql_catalog_lock_is_released_after_job(self) -> None:
        db = MagicMock()
        bind = MagicMock()
        bind.dialect.name = "postgresql"
        db.get_bind.return_value = bind
        lock_connection = bind.connect.return_value.__enter__.return_value
        lock_connection.execute.return_value.scalar_one.return_value = True

        with _exclusive_catalog_sync_lock(db):
            pass

        self.assertEqual(lock_connection.execute.call_count, 2)


if __name__ == "__main__":
    unittest.main()
