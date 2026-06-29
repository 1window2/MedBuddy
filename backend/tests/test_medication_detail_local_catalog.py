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
from entities.medication_detail_entity import _DrugApprovalInfo  # noqa: E402


class MedicationDetailLocalCatalogTest(unittest.TestCase):
    def test_raw_approval_item_with_alternate_keys_is_normalized(self) -> None:
        catalog = _LocalMedicationCatalog(db=None, summary_generator=object())
        approval_item = _DrugApprovalInfo(
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
                }
            ),
        )

        raw_item = catalog._load_raw_approval_item(approval_item)

        self.assertEqual(raw_item["ITEM_NAME"], "same-tablet")
        self.assertEqual(raw_item["EE_DOC_DATA"], "raw effect")
        self.assertEqual(raw_item["UD_DOC_DATA"], "raw usage")
        self.assertEqual(raw_item["NB_DOC_DATA"], "raw warning")


if __name__ == "__main__":
    unittest.main()
