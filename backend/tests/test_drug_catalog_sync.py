# File Name: test_drug_catalog_sync.py
# Role: Regression coverage for atomic drug-catalog synchronization, completeness guards, and
#   PostgreSQL writer locks.
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


# Class Name: DrugCatalogSyncTest
# Role: Database-backed catalog synchronization tests covering full refreshes, partial inputs,
#   and rollback preservation.
# Responsibilities:
# - Requires HTTP client loggers to suppress informational URLs that may contain API
#   credentials.
# - Prunes upstream-removed records after a complete refresh while retaining derived AI fields
#   on surviving basic and approval rows.
# - Requires the PostgreSQL advisory lock to be acquired and released across the catalog job.
# Attributes:
# - engine (Engine): Isolated in-memory SQLite engine.
# - db (Session): SQLAlchemy session holding only this test's database state.
# - store (_DrugCatalogStore): Database catalog store used for synchronization assertions.
class DrugCatalogSyncTest(unittest.TestCase):
    # Function Name: setUp
    # Description:
    # - Creates an isolated catalog database and store for synchronization tests.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

    # Function Name: tearDown
    # Description:
    # - Closes the catalog session and disposes its database engine.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # Function Name: test_logging_suppresses_credential_bearing_http_client_urls
    # Description:
    # - Requires HTTP client loggers to suppress informational URLs that may contain API
    #   credentials.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

    # Function Name: test_basic_sync_keeps_same_name_rows_with_distinct_item_seq
    # Description:
    # - Preserves distinct basic-drug records and efficacy text when product names match but
    #   item codes differ.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

    # Function Name: test_approval_sync_keeps_same_name_rows_with_distinct_item_seq
    # Description:
    # - Preserves distinct approval records and document text when product names match but
    #   item codes differ.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

    # Function Name: test_complete_seed_requires_every_shared_catalog
    # Description:
    # - Reports a complete seed only when all shared catalogs have been populated.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

    # Function Name: test_pill_sync_replaces_shared_reference_catalog
    # Description:
    # - Publishes the replacement pill catalog and records a publishable reconciliation
    #   report with the actual persisted count.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_pill_sync_replaces_shared_reference_catalog(self) -> None:
        # Class Name: _PillCatalogAPI
        # Role: Pill API double supplying one complete reference entry for a successful
        #   refresh.
        # Responsibilities:
        # - Returns one PILL-1 reference for successful catalog reconciliation.
        class _PillCatalogAPI:
            # Function Name: requestCatalog
            # Description:
            # - Returns one PILL-1 reference for successful catalog reconciliation.
            # Parameters:
            # - None.
            # Returns:
            # - list[PillCatalogEntry]: Configured replacement pill entries; empty
            #   or delayed in the corresponding failure scenarios.
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
        self.assertIsNotNone(sync_job.last_pill_reconciliation_report)
        assert sync_job.last_pill_reconciliation_report is not None
        self.assertTrue(sync_job.last_pill_reconciliation_report.is_publishable)
        self.assertEqual(
            sync_job.last_pill_reconciliation_report.persisted_rows,
            1,
        )
        self.assertEqual(
            self.db.query(PillIdentificationReference).one().item_seq,
            "PILL-1",
        )

    # Function Name: test_single_dataset_sync_commits_its_transaction
    # Description:
    # - Commits exactly once after a successful single-dataset refresh.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_single_dataset_sync_commits_its_transaction(self) -> None:
        # Class Name: _BasicAPI
        # Role: Basic-drug API double supplying one complete page for single-dataset
        #   commit checks.
        # Responsibilities:
        # - Returns one basic-drug record and an upstream total of one.
        class _BasicAPI:
            # Function Name: fetchPage
            # Description:
            # - Returns one basic-drug record and an upstream total of one.
            # Parameters:
            # - _page_no (int): One-based public-catalog page number requested.
            #   Unused by this double.
            # - _page_size (int): Requested maximum records per catalog page. Unused
            #   by this double.
            # Returns:
            # - tuple[list[dict[str, object]], int]: Configured catalog page and its
            #   advertised total, including intentionally incomplete test pages.
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

    # Function Name: test_pill_sync_rejects_catalog_below_kpic_product_floor
    # Description:
    # - Rejects a pill catalog below the KPIC product floor without persisting rows or
    #   publishing a reconciliation report.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_pill_sync_rejects_catalog_below_kpic_product_floor(self) -> None:
        # Class Name: _BelowFloorPillCatalogAPI
        # Role: Pill API double whose one-row result is below its advertised product
        #   floor.
        # Responsibilities:
        # - Returns the undersized pill dataset used to trigger identifier-set
        #   reconciliation failure.
        # Attributes:
        # - minimum_catalog_rows (int): Minimum catalog size advertised to the refresh
        #   completeness guard.
        class _BelowFloorPillCatalogAPI:
            minimum_catalog_rows = 2

            # Function Name: requestCatalog
            # Description:
            # - Returns the undersized pill dataset used to trigger identifier-set
            #   reconciliation failure.
            # Parameters:
            # - None.
            # Returns:
            # - list[PillCatalogEntry]: Configured replacement pill entries; empty
            #   or delayed in the corresponding failure scenarios.
            async def requestCatalog(self) -> list[PillCatalogEntry]:
                return [PillCatalogEntry(item_seq="PILL-1", item_name="pill")]

        sync_job = DrugCatalogSyncJob(
            store=self.store,
            public_drug_small_api=object(),  # type: ignore[arg-type]
            public_drug_large_api=object(),  # type: ignore[arg-type]
            pill_catalog_api=_BelowFloorPillCatalogAPI(),  # type: ignore[arg-type]
            page_size=100,
        )

        with self.assertRaisesRegex(
            CatalogSyncIncompleteError,
            "identifier-set reconciliation",
        ):
            asyncio.run(sync_job.sync_pill_identification())

        self.assertEqual(self.db.query(PillIdentificationReference).count(), 0)
        self.assertIsNone(sync_job.last_pill_reconciliation_report)

    # Function Name: test_all_sync_rolls_back_earlier_datasets_after_late_failure
    # Description:
    # - Rolls back earlier basic and approval replacements and pruning when the later pill
    #   refresh fails.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

        # Class Name: _BasicAPI
        # Role: Basic-drug API double supplying changed name and efficacy data before a
        #   later dataset failure.
        # Responsibilities:
        # - Returns replacement basic-drug metadata with a complete one-record total.
        class _BasicAPI:
            # Function Name: fetchPage
            # Description:
            # - Returns replacement basic-drug metadata with a complete one-record
            #   total.
            # Parameters:
            # - _page_no (int): One-based public-catalog page number requested.
            #   Unused by this double.
            # - _page_size (int): Requested maximum records per catalog page. Unused
            #   by this double.
            # Returns:
            # - tuple[list[dict[str, object]], int]: Configured catalog page and its
            #   advertised total, including intentionally incomplete test pages.
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

        # Class Name: _ApprovalAPI
        # Role: Approval API double supplying changed document data before a later
        #   dataset failure.
        # Responsibilities:
        # - Returns replacement approval metadata with a complete one-record total.
        class _ApprovalAPI:
            # Function Name: fetchPage
            # Description:
            # - Returns replacement approval metadata with a complete one-record
            #   total.
            # Parameters:
            # - _page_no (int): One-based public-catalog page number requested.
            #   Unused by this double.
            # - _page_size (int): Requested maximum records per catalog page. Unused
            #   by this double.
            # Returns:
            # - tuple[list[dict[str, object]], int]: Configured catalog page and its
            #   advertised total, including intentionally incomplete test pages.
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

        # Class Name: _FailingPillAPI
        # Role: Pill API double that fails after other catalog datasets have been
        #   updated.
        # Responsibilities:
        # - Raises a pill-catalog availability error to trigger the shared transaction
        #   rollback.
        class _FailingPillAPI:
            # Function Name: requestCatalog
            # Description:
            # - Raises a pill-catalog availability error to trigger the shared
            #   transaction rollback.
            # Parameters:
            # - None.
            # Returns:
            # - No normal result; raises the configured failure described above.
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

    # Function Name: test_all_sync_commits_every_dataset_once
    # Description:
    # - Commits all three successfully synchronized datasets in one transaction with one row
    #   per catalog.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_all_sync_commits_every_dataset_once(self) -> None:
        # Class Name: _BasicAPI
        # Role: Basic-drug API double supplying the successful all-dataset transaction's
        #   basic record.
        # Responsibilities:
        # - Returns one basic record and its matching total for the atomic refresh.
        class _BasicAPI:
            # Function Name: fetchPage
            # Description:
            # - Returns one basic record and its matching total for the atomic
            #   refresh.
            # Parameters:
            # - _page_no (int): One-based public-catalog page number requested.
            #   Unused by this double.
            # - _page_size (int): Requested maximum records per catalog page. Unused
            #   by this double.
            # Returns:
            # - tuple[list[dict[str, object]], int]: Configured catalog page and its
            #   advertised total, including intentionally incomplete test pages.
            async def fetchPage(
                self,
                _page_no: int,
                _page_size: int,
            ) -> tuple[list[dict[str, object]], int]:
                return ([{"itemSeq": "BASIC-1", "itemName": "basic tablet"}], 1)

        # Class Name: _ApprovalAPI
        # Role: Approval API double supplying the successful all-dataset transaction's
        #   approval record.
        # Responsibilities:
        # - Returns one approval record and its matching total for the atomic refresh.
        class _ApprovalAPI:
            # Function Name: fetchPage
            # Description:
            # - Returns one approval record and its matching total for the atomic
            #   refresh.
            # Parameters:
            # - _page_no (int): One-based public-catalog page number requested.
            #   Unused by this double.
            # - _page_size (int): Requested maximum records per catalog page. Unused
            #   by this double.
            # Returns:
            # - tuple[list[dict[str, object]], int]: Configured catalog page and its
            #   advertised total, including intentionally incomplete test pages.
            async def fetchPage(
                self,
                _page_no: int,
                _page_size: int,
            ) -> tuple[list[dict[str, object]], int]:
                return (
                    [{"ITEM_SEQ": "APPROVAL-1", "ITEM_NAME": "approval tablet"}],
                    1,
                )

        # Class Name: _PillAPI
        # Role: Pill API double supplying the successful all-dataset transaction's pill
        #   reference.
        # Responsibilities:
        # - Returns the PILL-1 entry used by the successful shared catalog transaction.
        class _PillAPI:
            # Function Name: requestCatalog
            # Description:
            # - Returns the PILL-1 entry used by the successful shared catalog
            #   transaction.
            # Parameters:
            # - None.
            # Returns:
            # - list[PillCatalogEntry]: Configured replacement pill entries; empty
            #   or delayed in the corresponding failure scenarios.
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

    # Function Name: test_complete_sync_prunes_basic_and_approval_rows_removed_upstream
    # Description:
    # - Prunes upstream-removed records after a complete refresh while retaining derived AI
    #   fields on surviving basic and approval rows.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

        # Class Name: _BasicAPI
        # Role: Basic API double containing only the surviving product for full-refresh
        #   pruning.
        # Responsibilities:
        # - Returns the retained basic product with its updated name and a total of one.
        class _BasicAPI:
            # Function Name: fetchPage
            # Description:
            # - Returns the retained basic product with its updated name and a total
            #   of one.
            # Parameters:
            # - _page_no (int): One-based public-catalog page number requested.
            #   Unused by this double.
            # - _page_size (int): Requested maximum records per catalog page. Unused
            #   by this double.
            # Returns:
            # - tuple[list[dict[str, object]], int]: Configured catalog page and its
            #   advertised total, including intentionally incomplete test pages.
            async def fetchPage(
                self,
                _page_no: int,
                _page_size: int,
            ) -> tuple[list[dict[str, object]], int]:
                return (
                    [{"itemSeq": "BASIC-KEEP", "itemName": "current basic"}],
                    1,
                )

        # Class Name: _ApprovalAPI
        # Role: Approval API double containing only the surviving product for
        #   full-refresh pruning.
        # Responsibilities:
        # - Returns the retained approval product with its updated name and a total of
        #   one.
        class _ApprovalAPI:
            # Function Name: fetchPage
            # Description:
            # - Returns the retained approval product with its updated name and a
            #   total of one.
            # Parameters:
            # - _page_no (int): One-based public-catalog page number requested.
            #   Unused by this double.
            # - _page_size (int): Requested maximum records per catalog page. Unused
            #   by this double.
            # Returns:
            # - tuple[list[dict[str, object]], int]: Configured catalog page and its
            #   advertised total, including intentionally incomplete test pages.
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

    # Function Name: test_page_limited_sync_does_not_prune_unvisited_rows
    # Description:
    # - Keeps unvisited catalog rows when a configured page limit stops synchronization
    #   early.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

        # Class Name: _BasicAPI
        # Role: Basic API double advertising two records while returning the visited
        #   page's single record.
        # Responsibilities:
        # - Returns the visited product with a larger upstream total to exercise
        #   page-limited preservation.
        class _BasicAPI:
            # Function Name: fetchPage
            # Description:
            # - Returns the visited product with a larger upstream total to exercise
            #   page-limited preservation.
            # Parameters:
            # - _page_no (int): One-based public-catalog page number requested.
            #   Unused by this double.
            # - _page_size (int): Requested maximum records per catalog page. Unused
            #   by this double.
            # Returns:
            # - tuple[list[dict[str, object]], int]: Configured catalog page and its
            #   advertised total, including intentionally incomplete test pages.
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

    # Function Name: test_basic_sync_rolls_back_premature_empty_page
    # Description:
    # - Rejects an empty page before the advertised total is reached and rolls back all
    #   partial basic-drug writes.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_basic_sync_rolls_back_premature_empty_page(self) -> None:
        # Class Name: _TruncatedBasicAPI
        # Role: Basic API double that stops producing rows before its advertised total
        #   is reached.
        # Responsibilities:
        # - Returns one record on page one and an empty later page while continuing to
        #   advertise two records.
        class _TruncatedBasicAPI:
            # Function Name: fetchPage
            # Description:
            # - Returns one record on page one and an empty later page while
            #   continuing to advertise two records.
            # Parameters:
            # - page_no (int): One-based public-catalog page number requested.
            # - _page_size (int): Requested maximum records per catalog page. Unused
            #   by this double.
            # Returns:
            # - tuple[list[dict[str, object]], int]: Configured catalog page and its
            #   advertised total, including intentionally incomplete test pages.
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

    # Function Name: test_full_sync_rejects_internally_consistent_mass_pruning
    # Description:
    # - Rejects a seemingly complete refresh that would prune most existing basic records
    #   and preserves all ten rows.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

        # Class Name: _PartialBasicAPI
        # Role: Basic API double reporting a self-consistent but suspiciously small
        #   replacement dataset.
        # Responsibilities:
        # - Returns one surviving basic product to trigger the mass-pruning guard.
        class _PartialBasicAPI:
            # Function Name: fetchPage
            # Description:
            # - Returns one surviving basic product to trigger the mass-pruning
            #   guard.
            # Parameters:
            # - _page_no (int): One-based public-catalog page number requested.
            #   Unused by this double.
            # - _page_size (int): Requested maximum records per catalog page. Unused
            #   by this double.
            # Returns:
            # - tuple[list[dict[str, object]], int]: Configured catalog page and its
            #   advertised total, including intentionally incomplete test pages.
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

    # Function Name: test_pill_sync_rejects_internally_consistent_mass_replacement
    # Description:
    # - Rejects a drastic pill-catalog replacement and preserves all ten previous product
    #   identifiers.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

        # Class Name: _PartialPillCatalogAPI
        # Role: Pill API double providing a drastic one-row replacement for an
        #   established catalog.
        # Responsibilities:
        # - Returns one new pill reference to exercise the mass-replacement guard.
        class _PartialPillCatalogAPI:
            # Function Name: requestCatalog
            # Description:
            # - Returns one new pill reference to exercise the mass-replacement
            #   guard.
            # Parameters:
            # - None.
            # Returns:
            # - list[PillCatalogEntry]: Configured replacement pill entries; empty
            #   or delayed in the corresponding failure scenarios.
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

    # Function Name: test_pill_sync_rejects_empty_catalog_without_deleting_existing_rows
    # Description:
    # - Rejects an empty pill refresh without removing the existing reference row.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

        # Class Name: _EmptyPillCatalogAPI
        # Role: Pill API double that produces an empty replacement catalog.
        # Responsibilities:
        # - Returns no pill entries to exercise the empty-catalog publication guard.
        class _EmptyPillCatalogAPI:
            # Function Name: requestCatalog
            # Description:
            # - Returns no pill entries to exercise the empty-catalog publication
            #   guard.
            # Parameters:
            # - None.
            # Returns:
            # - list[PillCatalogEntry]: Configured replacement pill entries; empty
            #   or delayed in the corresponding failure scenarios.
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

    # Function Name: test_failed_pill_sync_restores_previous_catalog
    # Description:
    # - Restores the previous pill catalog when duplicate identifiers cause a database
    #   integrity failure.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_failed_pill_sync_restores_previous_catalog(self) -> None:
        self.db.add(
            PillIdentificationReference(
                item_seq="EXISTING",
                item_name="existing tablet",
            )
        )
        self.db.commit()

        # Class Name: _DuplicatePillCatalogAPI
        # Role: Pill API double that supplies conflicting records with one duplicate
        #   product identifier.
        # Responsibilities:
        # - Returns two differently named entries sharing the same code to force an
        #   integrity error.
        class _DuplicatePillCatalogAPI:
            # Function Name: requestCatalog
            # Description:
            # - Returns two differently named entries sharing the same code to force
            #   an integrity error.
            # Parameters:
            # - None.
            # Returns:
            # - list[PillCatalogEntry]: Configured replacement pill entries; empty
            #   or delayed in the corresponding failure scenarios.
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

    # Function Name: test_postgresql_catalog_lock_rejects_overlapping_job
    # Description:
    # - Rejects an overlapping PostgreSQL catalog job after one failed advisory-lock
    #   attempt.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

    # Function Name: test_postgresql_catalog_lock_is_released_after_job
    # Description:
    # - Requires the PostgreSQL advisory lock to be acquired and released across the catalog
    #   job.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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
