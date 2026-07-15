import asyncio
import json
import os
import sys
import unittest
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from controls.check_medication_detail_control import _LocalMedicationCatalog  # noqa: E402
from entities.medication_detail_entity import (  # noqa: E402
    _DrugApprovalInfo,
    _DrugBasicInfo,
)


class MedicationDetailLocalCatalogTest(unittest.TestCase):
    def test_raw_approval_item_with_alternate_keys_is_normalized(self) -> None:
        catalog = _LocalMedicationCatalog(db=None, summary_generator=object())
        approval_item = _DrugApprovalInfo(
            item_seq="200000001",
            item_name="same-tablet",
            efficacy_doc="stored effect",
            use_method_doc="stored usage",
            warning_doc="stored warning",
            raw_json=json.dumps(
                {
                    "item_name": "same-tablet",
                    "efcyQesitm": "raw effect",
                    "useMethodQesitm": "raw usage",
                    "atpnWarnQesitm": "raw warning",
                    "itemImage": "https://example.com/pill.png",
                }
            ),
        )

        raw_item = catalog._load_raw_approval_item(approval_item)

        self.assertEqual(raw_item["ITEM_NAME"], "same-tablet")
        self.assertEqual(raw_item["ITEM_SEQ"], "200000001")
        self.assertEqual(raw_item["EE_DOC_DATA"], "raw effect")
        self.assertEqual(raw_item["UD_DOC_DATA"], "raw usage")
        self.assertEqual(raw_item["NB_DOC_DATA"], "raw warning")
        self.assertEqual(raw_item["ITEM_IMAGE"], "https://example.com/pill.png")

    def test_local_basic_detail_preserves_product_code(self) -> None:
        catalog = _LocalMedicationCatalog(db=None, summary_generator=object())
        basic_item = _DrugBasicInfo(
            item_seq="200000001",
            item_name="same-tablet",
            normalized_item_name="same-tablet",
            efficacy="effect",
            use_method="usage",
            warning_message="warning",
            raw_json="{}",
        )

        details = asyncio.run(catalog._build_basic_details([basic_item]))

        self.assertEqual(details[0].item_seq, "200000001")

    def test_cached_approval_detail_preserves_product_code(self) -> None:
        catalog = _LocalMedicationCatalog(db=None, summary_generator=object())
        approval_item = _DrugApprovalInfo(
            item_seq="200000001",
            item_name="same-tablet",
            normalized_item_name="same-tablet",
            summary_efficacy="effect",
            summary_use_method="usage",
            summary_warning_message="warning",
            raw_json="{}",
        )

        detail = catalog._build_cached_approval_summary(approval_item)

        self.assertIsNotNone(detail)
        self.assertEqual(detail.item_seq, "200000001")


if __name__ == "__main__":
    unittest.main()
