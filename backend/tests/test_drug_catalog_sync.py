import os
import sys
import unittest
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from core.database import Base  # noqa: E402
from entities.medication_detail_entity import _DrugApprovalInfo, _DrugBasicInfo  # noqa: E402
from scripts.sync_drug_catalog import _DrugCatalogStore  # noqa: E402


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


if __name__ == "__main__":
    unittest.main()
