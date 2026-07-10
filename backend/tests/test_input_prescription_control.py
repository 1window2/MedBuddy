import asyncio
import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from controls.input_prescription_control import (  # noqa: E402
    MAX_PRESCRIPTION_IMAGE_BYTES,
    PrescriptionAnalysisControl,
    _PrescriptionMedicationNameVerifier,
)
from core.database import Base  # noqa: E402
from entities.medication_detail_entity import _DrugApprovalInfo, _DrugBasicInfo  # noqa: E402
from entities.prescription_analysis_entity import (  # noqa: E402
    MedicationCandidate,
    MedicationCandidateList,
    PrescriptionAnalysisResult,
)


class _FakeGeminiResponse:
    def __init__(self, text: str) -> None:
        self.text = text


class _FakeGeminiModels:
    def __init__(self, response_text: str) -> None:
        self.response_text = response_text
        self.call_count = 0
        self.last_request = None

    async def generate_content(self, **kwargs):
        self.call_count += 1
        self.last_request = kwargs
        return _FakeGeminiResponse(self.response_text)


class _FakeGeminiAio:
    def __init__(self, models: _FakeGeminiModels) -> None:
        self.models = models


class _FakeGeminiClient:
    def __init__(self, response_text: str) -> None:
        self.models = _FakeGeminiModels(response_text)
        self.aio = _FakeGeminiAio(self.models)


class _RecordingOCRServiceBoundary:
    def __init__(self, response_text: str = "{}") -> None:
        self.response_text = response_text
        self.call_count = 0

    async def extractPrescriptionData(self, image: bytes) -> str:
        self.call_count += 1
        return self.response_text


class PrescriptionAnalysisControlMedicationNameVerificationTest(unittest.TestCase):
    def setUp(self) -> None:
        _PrescriptionMedicationNameVerifier.clear_ai_fallback_cache()
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
        self.control = PrescriptionAnalysisControl(client=object(), db=self.db)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()
        _PrescriptionMedicationNameVerifier.clear_ai_fallback_cache()

    def test_corrects_hangul_ocr_vowel_variant_from_local_catalog(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ud3ec\ub8e8\ucf54\ud504\uc815"
        self._save_basic_drug(canonical_name)

        medication_schedule, verification = self._verify_medication_item(
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

        medication_schedule, verification = self._verify_medication_item(
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

        medication_schedule, verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(medication_schedule.medication_name, canonical_name)
        self.assertEqual(verification.source, "local_catalog_ocr_vowel_variant")

    def test_uses_llm_fallback_only_when_catalog_candidate_is_selected(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ube0c\ub8e8\ucf54\ud504\uc815"
        self._save_basic_drug(canonical_name)
        fake_client = _FakeGeminiClient(
            json.dumps(
                {
                    "corrections": [
                        {
                            "index": 0,
                            "corrected_name": canonical_name,
                            "confidence": 0.94,
                        }
                    ]
                },
                ensure_ascii=False,
            )
        )
        self.control = PrescriptionAnalysisControl(client=fake_client, db=self.db)

        medication_schedule, verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(medication_schedule.medication_name, canonical_name)
        self.assertEqual(verification.raw_name, ocr_name)
        self.assertEqual(verification.source, "llm_catalog_candidate")
        self.assertEqual(verification.confidence, 0.89)
        self.assertEqual(fake_client.models.call_count, 1)

    def test_reuses_cached_llm_fallback_result(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ube0c\ub8e8\ucf54\ud504\uc815"
        self._save_basic_drug(canonical_name)
        first_client = _FakeGeminiClient(
            json.dumps(
                {
                    "corrections": [
                        {
                            "index": 0,
                            "corrected_name": canonical_name,
                            "confidence": 0.94,
                        }
                    ]
                },
                ensure_ascii=False,
            )
        )
        self.control = PrescriptionAnalysisControl(client=first_client, db=self.db)
        _, first_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        second_client = _FakeGeminiClient(json.dumps({"corrections": []}))
        self.control = PrescriptionAnalysisControl(client=second_client, db=self.db)
        medication_schedule, second_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(first_verification.source, "llm_catalog_candidate")
        self.assertEqual(medication_schedule.medication_name, canonical_name)
        self.assertEqual(second_verification.source, "llm_catalog_candidate")
        self.assertEqual(first_client.models.call_count, 1)
        self.assertEqual(second_client.models.call_count, 0)

    def test_llm_fallback_cache_is_separated_by_model_name(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ube0c\ub8e8\ucf54\ud504\uc815"
        self._save_basic_drug(canonical_name)
        first_client = _FakeGeminiClient(
            json.dumps(
                {
                    "corrections": [
                        {
                            "index": 0,
                            "corrected_name": canonical_name,
                            "confidence": 0.94,
                        }
                    ]
                },
                ensure_ascii=False,
            )
        )
        self.control = PrescriptionAnalysisControl(
            client=first_client,
            model_name="gemini-test-a",
            db=self.db,
        )
        _, first_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        second_client = _FakeGeminiClient(json.dumps({"corrections": []}))
        self.control = PrescriptionAnalysisControl(
            client=second_client,
            model_name="gemini-test-b",
            db=self.db,
        )
        medication_schedule, second_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(first_verification.source, "llm_catalog_candidate")
        self.assertEqual(medication_schedule.medication_name, ocr_name)
        self.assertEqual(second_verification.source, "unverified")
        self.assertEqual(first_client.models.call_count, 1)
        self.assertEqual(second_client.models.call_count, 1)

    def test_rejects_low_confidence_llm_fallback(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ube0c\ub8e8\ucf54\ud504\uc815"
        self._save_basic_drug(canonical_name)
        fake_client = _FakeGeminiClient(
            json.dumps(
                {
                    "corrections": [
                        {
                            "index": 0,
                            "corrected_name": canonical_name,
                            "confidence": 0.5,
                        }
                    ]
                },
                ensure_ascii=False,
            )
        )
        self.control = PrescriptionAnalysisControl(client=fake_client, db=self.db)

        medication_schedule, verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(medication_schedule.medication_name, ocr_name)
        self.assertEqual(verification.source, "unverified")
        self.assertEqual(fake_client.models.call_count, 1)

    def test_rejects_non_finite_llm_fallback_confidence(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ube0c\ub8e8\ucf54\ud504\uc815"
        self._save_basic_drug(canonical_name)
        fake_client = _FakeGeminiClient(
            json.dumps(
                {
                    "corrections": [
                        {
                            "index": 0,
                            "corrected_name": canonical_name,
                            "confidence": "NaN",
                        }
                    ]
                },
                ensure_ascii=False,
            )
        )
        self.control = PrescriptionAnalysisControl(client=fake_client, db=self.db)

        medication_schedule, verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(medication_schedule.medication_name, ocr_name)
        self.assertEqual(verification.source, "unverified")
        self.assertEqual(verification.confidence, 0.0)
        self.assertEqual(fake_client.models.call_count, 1)

    def test_reuses_cached_rejected_llm_fallback(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ube0c\ub8e8\ucf54\ud504\uc815"
        self._save_basic_drug(canonical_name)
        low_confidence_client = _FakeGeminiClient(
            json.dumps(
                {
                    "corrections": [
                        {
                            "index": 0,
                            "corrected_name": canonical_name,
                            "confidence": 0.5,
                        }
                    ]
                },
                ensure_ascii=False,
            )
        )
        self.control = PrescriptionAnalysisControl(
            client=low_confidence_client,
            db=self.db,
        )
        _, first_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        high_confidence_client = _FakeGeminiClient(
            json.dumps(
                {
                    "corrections": [
                        {
                            "index": 0,
                            "corrected_name": canonical_name,
                            "confidence": 0.95,
                        }
                    ]
                },
                ensure_ascii=False,
            )
        )
        self.control = PrescriptionAnalysisControl(
            client=high_confidence_client,
            db=self.db,
        )
        medication_schedule, second_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(medication_schedule.medication_name, ocr_name)
        self.assertEqual(first_verification.source, "unverified")
        self.assertEqual(second_verification.source, "unverified")
        self.assertEqual(low_confidence_client.models.call_count, 1)
        self.assertEqual(high_confidence_client.models.call_count, 0)

    def test_does_not_cache_failed_llm_fallback_request(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ube0c\ub8e8\ucf54\ud504\uc815"
        self._save_basic_drug(canonical_name)
        malformed_client = _FakeGeminiClient("not-json")
        self.control = PrescriptionAnalysisControl(client=malformed_client, db=self.db)
        _, first_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        valid_client = _FakeGeminiClient(
            json.dumps(
                {
                    "corrections": [
                        {
                            "index": 0,
                            "corrected_name": canonical_name,
                            "confidence": 0.95,
                        }
                    ]
                },
                ensure_ascii=False,
            )
        )
        self.control = PrescriptionAnalysisControl(client=valid_client, db=self.db)
        medication_schedule, second_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(first_verification.source, "unverified")
        self.assertEqual(medication_schedule.medication_name, canonical_name)
        self.assertEqual(second_verification.source, "llm_catalog_candidate")
        self.assertEqual(malformed_client.models.call_count, 1)
        self.assertEqual(valid_client.models.call_count, 1)

    def test_does_not_cache_malformed_llm_fallback_object(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ube0c\ub8e8\ucf54\ud504\uc815"
        self._save_basic_drug(canonical_name)
        malformed_client = _FakeGeminiClient(
            json.dumps({"unexpected": []}, ensure_ascii=False)
        )
        self.control = PrescriptionAnalysisControl(client=malformed_client, db=self.db)
        _, first_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        valid_client = _FakeGeminiClient(
            json.dumps(
                {
                    "corrections": [
                        {
                            "index": 0,
                            "corrected_name": canonical_name,
                            "confidence": 0.95,
                        }
                    ]
                },
                ensure_ascii=False,
            )
        )
        self.control = PrescriptionAnalysisControl(client=valid_client, db=self.db)
        medication_schedule, second_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(first_verification.source, "unverified")
        self.assertEqual(medication_schedule.medication_name, canonical_name)
        self.assertEqual(second_verification.source, "llm_catalog_candidate")
        self.assertEqual(malformed_client.models.call_count, 1)
        self.assertEqual(valid_client.models.call_count, 1)

    def test_rejects_llm_fallback_name_outside_candidate_set(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        hallucinated_name = "\uc874\uc7ac\ud558\uc9c0\uc54a\ub294\uc57d"
        ocr_name = "\ube0c\ub8e8\ucf54\ud504\uc815"
        self._save_basic_drug(canonical_name)
        fake_client = _FakeGeminiClient(
            json.dumps(
                {
                    "corrections": [
                        {
                            "index": 0,
                            "corrected_name": hallucinated_name,
                            "confidence": 0.99,
                        }
                    ]
                },
                ensure_ascii=False,
            )
        )
        self.control = PrescriptionAnalysisControl(client=fake_client, db=self.db)

        medication_schedule, verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(medication_schedule.medication_name, ocr_name)
        self.assertEqual(verification.source, "unverified")
        self.assertEqual(fake_client.models.call_count, 1)

    def test_batches_multiple_llm_fallback_requests(self) -> None:
        first_canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        second_canonical_name = "\uc560\ub2c8\ud39c\uc815"
        first_ocr_name = "\ube0c\ub8e8\ucf54\ud504\uc815"
        second_ocr_name = "\uc560\ub2c8\ud39c\uc808"
        self._save_basic_drug(first_canonical_name)
        self._save_basic_drug(second_canonical_name)
        fake_client = _FakeGeminiClient(
            json.dumps(
                {
                    "corrections": [
                        {
                            "index": 0,
                            "corrected_name": first_canonical_name,
                            "confidence": 0.91,
                        },
                        {
                            "index": 1,
                            "corrected_name": second_canonical_name,
                            "confidence": 0.88,
                        },
                    ]
                },
                ensure_ascii=False,
            )
        )
        self.control = PrescriptionAnalysisControl(client=fake_client, db=self.db)

        verified_schedules = asyncio.run(
            self.control._to_verified_medication_schedules(
                [
                    self._medication_item(first_ocr_name),
                    self._medication_item(second_ocr_name),
                ]
            )
        )

        self.assertEqual(
            [schedule.medication_name for schedule, _ in verified_schedules],
            [first_canonical_name, second_canonical_name],
        )
        self.assertEqual(fake_client.models.call_count, 1)

    def test_request_prescription_image_normalizes_alias_payload(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        fake_client = _FakeGeminiClient(
            json.dumps(
                {
                    "hospitalName": "\ud14c\uc2a4\ud2b8\uc57d\uad6d",
                    "prescriptionDate": "2026.7.8",
                    "medicines": [
                        {
                            "name": canonical_name,
                            "dose_per_time": 1.0,
                            "frequency_per_day": 3,
                            "duration_days": 5,
                        },
                        {
                            "drug_name": "\uc815\ubcf4 \uc5c6\uc74c",
                            "dosage_per_time": "1",
                            "daily_frequency": "3",
                            "total_days": "5",
                        },
                    ],
                },
                ensure_ascii=False,
            )
        )
        self.control = PrescriptionAnalysisControl(client=fake_client)

        with patch(
            "boundaries.prescription_ocr_boundary.preprocess_prescription_image",
            return_value=b"processed-image",
        ):
            payload = asyncio.run(
                self.control.request_prescription_image(b"raw-image"),
            )

        self.assertEqual(payload["hospital_name"], "\ud14c\uc2a4\ud2b8\uc57d\uad6d")
        self.assertEqual(payload["prescription_date"], "2026-07-08")
        self.assertEqual(len(payload["medications"]), 1)
        self.assertEqual(payload["raw_medication_count"], 2)
        self.assertEqual(payload["parsed_medication_count"], 1)
        self.assertEqual(payload["skipped_medication_count"], 1)
        self.assertEqual(payload["medications"][0]["drug_name"], canonical_name)
        self.assertEqual(payload["medications"][0]["dosage_per_time"], "1")
        self.assertEqual(payload["medications"][0]["daily_frequency"], "3")
        self.assertEqual(payload["medications"][0]["total_days"], "5")

    def test_request_prescription_image_rejects_empty_input_before_ocr(self) -> None:
        ocr_boundary = _RecordingOCRServiceBoundary()
        self.control = PrescriptionAnalysisControl(
            client=object(),
            ocr_service_boundary=ocr_boundary,
        )

        with self.assertRaisesRegex(ValueError, "empty"):
            asyncio.run(self.control.request_prescription_image(b""))

        self.assertEqual(ocr_boundary.call_count, 0)

    def test_request_prescription_image_rejects_oversized_input_before_ocr(
        self,
    ) -> None:
        ocr_boundary = _RecordingOCRServiceBoundary()
        self.control = PrescriptionAnalysisControl(
            client=object(),
            ocr_service_boundary=ocr_boundary,
        )

        with self.assertRaisesRegex(ValueError, "15 MB"):
            asyncio.run(
                self.control.request_prescription_image(
                    b"x" * (MAX_PRESCRIPTION_IMAGE_BYTES + 1)
                )
            )

        self.assertEqual(ocr_boundary.call_count, 0)

    def test_invalid_ocr_response_is_not_written_to_logs(self) -> None:
        sensitive_response = "patient-medication-data"
        ocr_boundary = _RecordingOCRServiceBoundary(sensitive_response)
        self.control = PrescriptionAnalysisControl(
            client=object(),
            ocr_service_boundary=ocr_boundary,
        )

        with self.assertLogs(
            "controls.input_prescription_control",
            level="ERROR",
        ) as captured_logs:
            with self.assertRaisesRegex(ValueError, "invalid JSON"):
                asyncio.run(
                    self.control.request_prescription_image(b"image"),
                )

        self.assertNotIn(sensitive_response, "\n".join(captured_logs.output))

    def test_build_analysis_result_returns_diagram_entity(self) -> None:
        medication_candidate_list = MedicationCandidateList()
        medication_candidate_list.addCandidate(
            MedicationCandidate(
                drug_name="\ud504\ub8e8\ucf54\ud504\uc815",
                dosage_per_time="1",
                daily_frequency="3",
                total_days="5",
            )
        )

        analysis_result = self.control.buildAnalysisResult(
            medication_candidate_list
        )

        self.assertIsInstance(analysis_result, PrescriptionAnalysisResult)
        self.assertEqual(analysis_result.candidateCount, 1)
        self.assertEqual(
            analysis_result.medication_candidates.findByName(
                "\ud504\ub8e8\ucf54\ud504\uc815"
            ),
            medication_candidate_list.candidates[0],
        )

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

    def _verify_medication_item(self, item: dict[str, str]):
        return asyncio.run(self.control._to_verified_medication_schedule(item))

    def _normalize_name(self, item_name: str) -> str:
        return "".join(item_name.split()).lower()


if __name__ == "__main__":
    unittest.main()
