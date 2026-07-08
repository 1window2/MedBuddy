import json
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

from controls.input_prescription_control import InputPrescription  # noqa: E402
from core.database import Base  # noqa: E402
from entities.medication_detail_entity import _DrugApprovalInfo, _DrugBasicInfo  # noqa: E402


class InputPrescriptionMedicationNameVerificationTest(unittest.TestCase):
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
        self.control = InputPrescription(client=object(), db=self.db)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def test_corrects_hangul_ocr_vowel_variant_from_local_catalog(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ud3ec\ub8e8\ucf54\ud504\uc815"
        self._save_basic_drug(canonical_name)

        medication_schedule, verification = self.control._to_verified_medication_schedule(
            self._medication_item(ocr_name)
        )
        payload = self.control._to_prescription_medication_payload(
            medication_schedule,
            verification,
            "2026-07-08",
        )

        self.assertEqual(payload["drug_name"], canonical_name)
        self.assertEqual(payload["raw_drug_name"], ocr_name)
        self.assertEqual(payload["name_correction_source"], "local_catalog_ocr_vowel_variant")
        self.assertGreaterEqual(payload["name_confidence"], 0.9)

    def test_keeps_unverified_name_when_catalog_has_no_safe_match(self) -> None:
        ocr_name = "\ud3ec\ub8e8\ucf54\ud504\uc815"

        medication_schedule, verification = self.control._to_verified_medication_schedule(
            self._medication_item(ocr_name)
        )
        payload = self.control._to_prescription_medication_payload(
            medication_schedule,
            verification,
            "2026-07-08",
        )

        self.assertEqual(payload["drug_name"], ocr_name)
        self.assertEqual(payload["raw_drug_name"], ocr_name)
        self.assertEqual(payload["name_correction_source"], "unverified")
        self.assertEqual(payload["name_confidence"], 0.0)

    def test_uses_approval_catalog_when_basic_catalog_misses(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ud3ec\ub8e8\ucf54\ud504\uc815"
        self._save_approval_drug(canonical_name)

        medication_schedule, verification = self.control._to_verified_medication_schedule(
            self._medication_item(ocr_name)
        )

        self.assertEqual(medication_schedule.medication_name, canonical_name)
        self.assertEqual(verification.source, "local_catalog_ocr_vowel_variant")

    def _save_basic_drug(self, item_name: str) -> None:
        self.db.add(
            _DrugBasicInfo(
                item_seq=f"basic-{item_name}",
                item_name=item_name,
                normalized_item_name=self._normalize_name(item_name),
                raw_json=json.dumps({"itemName": item_name}, ensure_ascii=False),
            )
        )
        self.db.commit()

    def _save_approval_drug(self, item_name: str) -> None:
        self.db.add(
            _DrugApprovalInfo(
                item_seq=f"approval-{item_name}",
                item_name=item_name,
                normalized_item_name=self._normalize_name(item_name),
                raw_json=json.dumps({"ITEM_NAME": item_name}, ensure_ascii=False),
            )
        )
        self.db.commit()

    def _medication_item(self, drug_name: str) -> dict[str, str]:
        return {
            "drug_name": drug_name,
            "dosage_per_time": "1",
            "daily_frequency": "3",
            "total_days": "5",
        }

    def _normalize_name(self, item_name: str) -> str:
        return "".join(item_name.split()).lower()


if __name__ == "__main__":
    unittest.main()
