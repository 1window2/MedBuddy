# File Name: test_input_prescription_control.py
# Role: Regression coverage for prescription text validation, catalog-backed name correction, AI
#   fallback isolation, and privacy.
import asyncio
import json
import os
import sys
import unittest
from pathlib import Path

from google.genai import types
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from controls.input_prescription_control import (  # noqa: E402
    InputPrescription,
    PrescriptionAnalysisTimeoutError,
    _PrescriptionMedicationNameVerifier,
)
from core.database import Base  # noqa: E402
from entities.medication_detail_entity import _DrugApprovalInfo, _DrugBasicInfo  # noqa: E402
from entities.prescription_analysis_entity import (  # noqa: E402
    MedicationCandidate,
    MedicationCandidateList,
    PrescriptionAnalysisResult,
)


# Class Name: _FakeGeminiResponse
# Role: Gemini response double carrying the configured analysis text.
# Responsibilities:
# - Gemini response double carrying the configured analysis text.
# Attributes:
# - text (str): Text payload exposed by the Gemini-compatible response.
class _FakeGeminiResponse:
    # Function Name: __init__
    # Description:
    # - Stores the response text exposed by the Gemini-compatible response object.
    # Parameters:
    # - text (str): Text captured by the response or prescription-analysis double.
    # Returns:
    # - None.
    def __init__(self, text: str) -> None:
        self.text = text


# Class Name: _FakeGeminiModels
# Role: Gemini models double that records calls and supplies deterministic text responses.
# Responsibilities:
# - Records the Gemini request, increments its call count, and returns the configured text
#   response.
# Attributes:
# - response_text (str): Deterministic AI text response returned by the double.
# - call_count (int): Number of external-analysis calls observed.
# - last_request (dict | None): Most recently captured Gemini request; initially absent.
class _FakeGeminiModels:
    # Function Name: __init__
    # Description:
    # - Stores the response text and initializes request tracking for fallback-cache
    #   assertions.
    # Parameters:
    # - response_text (str): Deterministic text/JSON output returned by the AI double.
    # Returns:
    # - None.
    def __init__(self, response_text: str) -> None:
        self.response_text = response_text
        self.call_count = 0
        self.last_request = None

    # Function Name: generate_content
    # Description:
    # - Records the Gemini request, increments its call count, and returns the configured
    #   text response.
    # Parameters:
    # - **kwargs (object): Keyword arguments accepted by the substituted service interface.
    # Returns:
    # - Gemini-compatible response carrying the configured analysis JSON.
    async def generate_content(self, **kwargs):
        self.call_count += 1
        self.last_request = kwargs
        return _FakeGeminiResponse(self.response_text)


# Class Name: _FakeGeminiAio
# Role: Async Gemini namespace double exposing the supplied models implementation.
# Responsibilities:
# - Async Gemini namespace double exposing the supplied models implementation.
# Attributes:
# - models (_FakeGeminiModels): Recording Gemini-compatible model interface.
class _FakeGeminiAio:
    # Function Name: __init__
    # Description:
    # - Attaches the models double through the SDK-compatible asynchronous namespace.
    # Parameters:
    # - models (_FakeGeminiModels): Injected Gemini-compatible model implementation.
    # Returns:
    # - None.
    def __init__(self, models: _FakeGeminiModels) -> None:
        self.models = models


# Class Name: _FakeGeminiClient
# Role: Gemini client double sharing one recording models object across sync and async access
#   paths.
# Responsibilities:
# - Gemini client double sharing one recording models object across sync and async access paths.
# Attributes:
# - models (_FakeGeminiModels): Recording Gemini-compatible model interface.
# - aio (_FakeGeminiAio): Gemini-compatible asynchronous namespace or owned async client.
class _FakeGeminiClient:
    # Function Name: __init__
    # Description:
    # - Builds response-backed models and exposes them through both models and aio.models.
    # Parameters:
    # - response_text (str): Deterministic text/JSON output returned by the AI double.
    # Returns:
    # - None.
    def __init__(self, response_text: str) -> None:
        self.models = _FakeGeminiModels(response_text)
        self.aio = _FakeGeminiAio(self.models)


# Class Name: _RecordingOCRServiceBoundary
# Role: Prescription text-analysis double that records only the text submitted to the OCR
#   boundary.
# Responsibilities:
# - Records masked prescription text and returns the configured analysis payload.
# Attributes:
# - response_text (str): Deterministic AI text response returned by the double.
# - call_count (int): Number of external-analysis calls observed.
# - received_text (str): Prescription text captured by the analysis double.
class _RecordingOCRServiceBoundary:
    # Function Name: __init__
    # Description:
    # - Stores analysis output and initializes the input-text and call-count recorders.
    # Parameters:
    # - response_text (str): Deterministic text/JSON output returned by the AI double.
    # Returns:
    # - None.
    def __init__(self, response_text: str = "{}") -> None:
        self.response_text = response_text
        self.call_count = 0
        self.received_text = ""

    # Function Name: extractPrescriptionTextData
    # Description:
    # - Records masked prescription text and returns the configured analysis payload.
    # Parameters:
    # - masked_text (str): De-identified prescription text allowed across the AI boundary.
    # Returns:
    # - str: Configured prescription analysis JSON text.
    async def extractPrescriptionTextData(self, masked_text: str) -> str:
        self.call_count += 1
        self.received_text = masked_text
        return self.response_text


# Class Name: _TimedOutOCRServiceBoundary
# Role: Prescription text-analysis double that simulates an external deadline failure.
# Responsibilities:
# - Raises an analysis timeout without forwarding prescription text to an external service.
class _TimedOutOCRServiceBoundary:
    # Function Name: extractPrescriptionTextData
    # Description:
    # - Raises an analysis timeout without forwarding prescription text to an external
    #   service.
    # Parameters:
    # - masked_text (str): De-identified prescription text allowed across the AI boundary.
    # Returns:
    # - No normal result; raises the configured failure described above.
    async def extractPrescriptionTextData(self, masked_text: str) -> str:
        raise TimeoutError("external text analysis deadline exceeded")


# Class Name: InputPrescriptionMedicationNameVerificationTest
# Role: Database-backed tests for safe medication-name verification and normalized
#   prescription-analysis responses.
# Responsibilities:
# - Corrects a Hangul OCR vowel variant from the local catalog while preserving the raw name and
#   high-confidence correction provenance.
# - Does not cache a malformed fallback object, allowing later valid analysis to recover.
# - Removes all whitespace and lowercases a catalog name for normalized test lookup keys.
# Attributes:
# - engine (Engine): Isolated in-memory SQLite engine.
# - db (Session): SQLAlchemy session holding only this test's database state.
# - control (InputPrescription): Use-case control under test, isolated from production state.
class InputPrescriptionMedicationNameVerificationTest(unittest.TestCase):
    # Function Name: setUp
    # Description:
    # - Creates an isolated drug catalog and prescription input control without a live
    #   Gemini client.
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
        self.control = InputPrescription(client=object(), db=self.db)

    # Function Name: tearDown
    # Description:
    # - Closes the prescription test session and disposes its in-memory engine.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # Function Name: test_corrects_hangul_ocr_vowel_variant_from_local_catalog
    # Description:
    # - Corrects a Hangul OCR vowel variant from the local catalog while preserving the raw
    #   name and high-confidence correction provenance.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

    # Function Name: test_keeps_unverified_name_when_catalog_has_no_safe_match
    # Description:
    # - Preserves the original OCR name with unverified provenance and zero confidence when
    #   no safe catalog match exists.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

    # Function Name: test_uses_approval_catalog_when_basic_catalog_misses
    # Description:
    # - Uses the approval catalog to correct a name when the basic-drug catalog has no
    #   match.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_uses_approval_catalog_when_basic_catalog_misses(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ud3ec\ub8e8\ucf54\ud504\uc815"
        self._save_approval_drug(canonical_name)

        medication_schedule, verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(medication_schedule.medication_name, canonical_name)
        self.assertEqual(verification.source, "local_catalog_ocr_vowel_variant")

    # Function Name: test_fuzzy_catalog_lookup_bounds_fragments_and_queries
    # Description:
    # - Bounds fuzzy name fragments and performs only two catalog queries when no candidates
    #   match.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_fuzzy_catalog_lookup_bounds_fragments_and_queries(self) -> None:
        verifier = _PrescriptionMedicationNameVerifier(self.db)
        query_count = 0

        # Function Name: count_catalog_queries
        # Description:
        # - Counts SQL statements touching either drug catalog to detect excessive
        #   candidate queries.
        # Parameters:
        # - connection (Connection): SQLAlchemy connection passed to the query listener.
        # - cursor (DBAPI cursor): Database cursor supplied to the SQL event listener.
        # - statement (str): SQL statement inspected for query shape or count.
        # - parameters (SQL parameters): Bound SQL parameters supplied to the event
        #   listener.
        # - context (ExecutionContext): SQL execution context supplied to the query
        #   listener.
        # - executemany (bool): SQL event flag indicating batch execution.
        # Returns:
        # - None.
        def count_catalog_queries(
            connection,
            cursor,
            statement,
            parameters,
            context,
            executemany,
        ) -> None:
            nonlocal query_count
            if (
                "drug_basic_infos" in statement
                or "drug_approval_infos" in statement
            ):
                query_count += 1

        event.listen(self.engine, "before_cursor_execute", count_catalog_queries)
        try:
            long_name = "".join(chr(0xAC00 + index) for index in range(200))
            fragments = verifier._candidate_fragments(long_name)
            candidates = verifier._find_similar_catalog_names(long_name)
        finally:
            event.remove(
                self.engine,
                "before_cursor_execute",
                count_catalog_queries,
            )

        self.assertLessEqual(
            len(fragments),
            verifier._MAX_CANDIDATE_FRAGMENTS,
        )
        self.assertEqual(query_count, 2)
        self.assertEqual(candidates, [])

    # Function Name: test_prefix_catalog_lookup_uses_indexable_range_predicate
    # Description:
    # - Uses an indexable normalized-name range for prefix lookup rather than a LIKE scan.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_prefix_catalog_lookup_uses_indexable_range_predicate(self) -> None:
        canonical_name = "\ud504\ub85c\ucf54\ud478\uc815(\ub808\ubcf4\ub4dc\ub85c\ud504\ub85c\ud53c\uc9c4)"
        self._save_approval_drug(canonical_name)
        statements: list[str] = []

        # Function Name: capture_catalog_queries
        # Description:
        # - Captures approval-catalog SQL so prefix predicate shape can be asserted.
        # Parameters:
        # - connection (Connection): SQLAlchemy connection passed to the query listener.
        # - cursor (DBAPI cursor): Database cursor supplied to the SQL event listener.
        # - statement (str): SQL statement inspected for query shape or count.
        # - parameters (SQL parameters): Bound SQL parameters supplied to the event
        #   listener.
        # - context (ExecutionContext): SQL execution context supplied to the query
        #   listener.
        # - executemany (bool): SQL event flag indicating batch execution.
        # Returns:
        # - None.
        def capture_catalog_queries(
            connection,
            cursor,
            statement,
            parameters,
            context,
            executemany,
        ) -> None:
            if "drug_approval_infos" in statement:
                statements.append(statement)

        event.listen(self.engine, "before_cursor_execute", capture_catalog_queries)
        try:
            verification = _PrescriptionMedicationNameVerifier(self.db).verify(
                "\ud504\ub85c\ucf54\ud478\uc815"
            )
        finally:
            event.remove(
                self.engine,
                "before_cursor_execute",
                capture_catalog_queries,
            )

        self.assertEqual(verification.canonical_name, canonical_name)
        self.assertEqual(verification.source, "local_catalog_prefix")
        self.assertTrue(
            any(
                "normalized_item_name >=" in statement
                and "normalized_item_name <" in statement
                for statement in statements
            )
        )
        self.assertFalse(any(" LIKE " in statement for statement in statements))

    # Function Name: test_uses_llm_fallback_only_when_catalog_candidate_is_selected
    # Description:
    # - Accepts only an AI-selected catalog candidate and requires one low-latency,
    #   output-bounded Gemini request.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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
        self.control = InputPrescription(client=fake_client, db=self.db)

        medication_schedule, verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(medication_schedule.medication_name, canonical_name)
        self.assertEqual(verification.raw_name, ocr_name)
        self.assertEqual(verification.source, "llm_catalog_candidate")
        self.assertEqual(verification.confidence, 0.89)
        self.assertEqual(fake_client.models.call_count, 1)
        config = fake_client.models.last_request["config"]
        self.assertEqual(
            config.thinking_config.thinking_level,
            types.ThinkingLevel.MINIMAL,
        )
        self.assertEqual(config.max_output_tokens, 1024)

    # Function Name: test_llm_fallback_cache_does_not_cross_verifier_instances
    # Description:
    # - Keeps successful fallback decisions within one verifier instance so another verifier
    #   evaluates its own response.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_llm_fallback_cache_does_not_cross_verifier_instances(self) -> None:
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
        self.control = InputPrescription(client=first_client, db=self.db)
        _, first_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        second_client = _FakeGeminiClient(json.dumps({"corrections": []}))
        self.control = InputPrescription(client=second_client, db=self.db)
        medication_schedule, second_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(first_verification.source, "llm_catalog_candidate")
        self.assertEqual(medication_schedule.medication_name, ocr_name)
        self.assertEqual(second_verification.source, "unverified")
        self.assertEqual(first_client.models.call_count, 1)
        self.assertEqual(second_client.models.call_count, 1)

    # Function Name: test_llm_fallback_cache_reuses_result_within_one_verifier
    # Description:
    # - Reuses a successful fallback correction within one verifier and avoids a second
    #   Gemini call.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_llm_fallback_cache_reuses_result_within_one_verifier(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ube0c\ub8e8\ucf54\ud504\uc815"
        self._save_basic_drug(canonical_name)
        client = _FakeGeminiClient(
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
        self.control = InputPrescription(client=client, db=self.db)

        first_schedule, _ = self._verify_medication_item(
            self._medication_item(ocr_name)
        )
        second_schedule, _ = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(first_schedule.medication_name, canonical_name)
        self.assertEqual(second_schedule.medication_name, canonical_name)
        self.assertEqual(client.models.call_count, 1)

    # Function Name: test_prefix_match_checks_distinct_names_before_limiting_rows
    # Description:
    # - Checks distinct product names before row limiting so repeated rows cannot make an
    #   ambiguous prefix appear unique.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_prefix_match_checks_distinct_names_before_limiting_rows(self) -> None:
        verifier = _PrescriptionMedicationNameVerifier(self.db)
        self.db.add_all(
            [
                _DrugBasicInfo(
                    item_seq="prefix-a-1",
                    item_name="A",
                    normalized_item_name="alpha-1",
                    raw_json="{}",
                ),
                _DrugBasicInfo(
                    item_seq="prefix-a-2",
                    item_name="A",
                    normalized_item_name="alpha-2",
                    raw_json="{}",
                ),
                _DrugBasicInfo(
                    item_seq="prefix-b-1",
                    item_name="B",
                    normalized_item_name="alpha-3",
                    raw_json="{}",
                ),
            ]
        )
        self.db.commit()

        self.assertIsNone(verifier._find_unique_catalog_prefix_match("alpha"))

    # Function Name: test_llm_fallback_cache_is_separated_by_model_name
    # Description:
    # - Separates fallback results by model name so a different model does not inherit a
    #   prior correction.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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
        self.control = InputPrescription(
            client=first_client,
            model_name="gemini-test-a",
            db=self.db,
        )
        _, first_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        second_client = _FakeGeminiClient(json.dumps({"corrections": []}))
        self.control = InputPrescription(
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

    # Function Name: test_rejects_low_confidence_llm_fallback
    # Description:
    # - Rejects a low-confidence AI fallback and leaves the OCR name unverified.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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
        self.control = InputPrescription(client=fake_client, db=self.db)

        medication_schedule, verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(medication_schedule.medication_name, ocr_name)
        self.assertEqual(verification.source, "unverified")
        self.assertEqual(fake_client.models.call_count, 1)

    # Function Name: test_rejects_non_finite_llm_fallback_confidence
    # Description:
    # - Rejects non-finite AI confidence values and preserves the original name with zero
    #   confidence.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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
        self.control = InputPrescription(client=fake_client, db=self.db)

        medication_schedule, verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(medication_schedule.medication_name, ocr_name)
        self.assertEqual(verification.source, "unverified")
        self.assertEqual(verification.confidence, 0.0)
        self.assertEqual(fake_client.models.call_count, 1)

    # Function Name: test_rejected_llm_fallback_does_not_cross_verifier_instances
    # Description:
    # - Prevents a rejected low-confidence decision in one verifier from suppressing a valid
    #   correction in another.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_rejected_llm_fallback_does_not_cross_verifier_instances(self) -> None:
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
        self.control = InputPrescription(
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
        self.control = InputPrescription(
            client=high_confidence_client,
            db=self.db,
        )
        medication_schedule, second_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(medication_schedule.medication_name, canonical_name)
        self.assertEqual(first_verification.source, "unverified")
        self.assertEqual(second_verification.source, "llm_catalog_candidate")
        self.assertEqual(low_confidence_client.models.call_count, 1)
        self.assertEqual(high_confidence_client.models.call_count, 1)

    # Function Name: test_does_not_cache_failed_llm_fallback_request
    # Description:
    # - Does not cache a failed fallback request, allowing a subsequent valid response to
    #   correct the name.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_does_not_cache_failed_llm_fallback_request(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ube0c\ub8e8\ucf54\ud504\uc815"
        self._save_basic_drug(canonical_name)
        malformed_client = _FakeGeminiClient("not-json")
        self.control = InputPrescription(client=malformed_client, db=self.db)
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
        self.control = InputPrescription(client=valid_client, db=self.db)
        medication_schedule, second_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(first_verification.source, "unverified")
        self.assertEqual(medication_schedule.medication_name, canonical_name)
        self.assertEqual(second_verification.source, "llm_catalog_candidate")
        self.assertEqual(malformed_client.models.call_count, 1)
        self.assertEqual(valid_client.models.call_count, 1)

    # Function Name: test_does_not_cache_malformed_llm_fallback_object
    # Description:
    # - Does not cache a malformed fallback object, allowing later valid analysis to
    #   recover.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_does_not_cache_malformed_llm_fallback_object(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_name = "\ube0c\ub8e8\ucf54\ud504\uc815"
        self._save_basic_drug(canonical_name)
        malformed_client = _FakeGeminiClient(
            json.dumps({"unexpected": []}, ensure_ascii=False)
        )
        self.control = InputPrescription(client=malformed_client, db=self.db)
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
        self.control = InputPrescription(client=valid_client, db=self.db)
        medication_schedule, second_verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(first_verification.source, "unverified")
        self.assertEqual(medication_schedule.medication_name, canonical_name)
        self.assertEqual(second_verification.source, "llm_catalog_candidate")
        self.assertEqual(malformed_client.models.call_count, 1)
        self.assertEqual(valid_client.models.call_count, 1)

    # Function Name: test_rejects_llm_fallback_name_outside_candidate_set
    # Description:
    # - Rejects an AI-proposed name outside the supplied catalog candidates and preserves
    #   the OCR name.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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
        self.control = InputPrescription(client=fake_client, db=self.db)

        medication_schedule, verification = self._verify_medication_item(
            self._medication_item(ocr_name)
        )

        self.assertEqual(medication_schedule.medication_name, ocr_name)
        self.assertEqual(verification.source, "unverified")
        self.assertEqual(fake_client.models.call_count, 1)

    # Function Name: test_batches_multiple_llm_fallback_requests
    # Description:
    # - Batches multiple uncertain names into one Gemini request while applying each
    #   accepted catalog correction.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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
        self.control = InputPrescription(client=fake_client, db=self.db)

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

    # Function Name: test_request_prescription_text_normalizes_alias_payload
    # Description:
    # - Normalizes response aliases, assigns a valid analysis batch, corrects the parsed
    #   medication, and reports skipped items without exposing recognition regions.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_request_prescription_text_normalizes_alias_payload(self) -> None:
        canonical_name = "\ud504\ub8e8\ucf54\ud504\uc815"
        ocr_boundary = _RecordingOCRServiceBoundary(
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
        self.control = InputPrescription(
            client=object(),
            ocr_service_boundary=ocr_boundary,
        )

        payload = asyncio.run(
            self.control.requestPrescriptionText("masked prescription text"),
        )

        self.assertEqual(ocr_boundary.received_text, "masked prescription text")
        self.assertEqual(payload["hospital_name"], "\ud14c\uc2a4\ud2b8\uc57d\uad6d")
        self.assertEqual(payload["prescription_date"], "2026-07-08")
        self.assertRegex(
            payload["prescription_batch_id"],
            r"^[A-Za-z0-9_-]{16,64}$",
        )
        self.assertEqual(len(payload["medications"]), 1)
        self.assertEqual(payload["raw_medication_count"], 2)
        self.assertEqual(payload["parsed_medication_count"], 1)
        self.assertEqual(payload["skipped_medication_count"], 1)
        self.assertEqual(payload["medications"][0]["drug_name"], canonical_name)
        self.assertEqual(payload["medications"][0]["dosage_per_time"], "1")
        self.assertEqual(payload["medications"][0]["daily_frequency"], "3")
        self.assertEqual(payload["medications"][0]["total_days"], "5")
        self.assertNotIn("recognized_regions", payload)

    # Function Name: test_request_prescription_text_rejects_empty_input_before_analysis
    # Description:
    # - Rejects empty prescription text before the analysis boundary is called.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_request_prescription_text_rejects_empty_input_before_analysis(
        self,
    ) -> None:
        ocr_boundary = _RecordingOCRServiceBoundary()
        self.control = InputPrescription(
            client=object(),
            ocr_service_boundary=ocr_boundary,
        )

        with self.assertRaisesRegex(ValueError, "empty"):
            asyncio.run(self.control.requestPrescriptionText("  "))

        self.assertEqual(ocr_boundary.call_count, 0)

    # Function Name: test_request_prescription_text_rejects_oversized_input_before_analysis
    # Description:
    # - Rejects prescription text over 100,000 characters before consuming external analysis
    #   quota.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_request_prescription_text_rejects_oversized_input_before_analysis(
        self,
    ) -> None:
        ocr_boundary = _RecordingOCRServiceBoundary()
        self.control = InputPrescription(
            client=object(),
            ocr_service_boundary=ocr_boundary,
        )

        with self.assertRaisesRegex(ValueError, "100,000 characters"):
            asyncio.run(self.control.requestPrescriptionText("x" * 100_001))

        self.assertEqual(ocr_boundary.call_count, 0)

    # Function Name: test_request_prescription_text_translates_analysis_timeout
    # Description:
    # - Translates an external analysis timeout into the prescription-specific timeout
    #   error.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_request_prescription_text_translates_analysis_timeout(self) -> None:
        self.control = InputPrescription(
            client=object(),
            ocr_service_boundary=_TimedOutOCRServiceBoundary(),
        )

        with self.assertRaisesRegex(
            PrescriptionAnalysisTimeoutError,
            "응답 시간이 초과",
        ):
            asyncio.run(self.control.requestPrescriptionText("masked text"))

    # Function Name: test_invalid_ocr_response_is_not_written_to_logs
    # Description:
    # - Rejects invalid analysis JSON while keeping the sensitive raw response out of error
    #   logs.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_invalid_ocr_response_is_not_written_to_logs(self) -> None:
        sensitive_response = "patient-medication-data"
        ocr_boundary = _RecordingOCRServiceBoundary(sensitive_response)
        self.control = InputPrescription(
            client=object(),
            ocr_service_boundary=ocr_boundary,
        )

        with self.assertLogs(
            "controls.input_prescription_control",
            level="ERROR",
        ) as captured_logs:
            with self.assertRaisesRegex(ValueError, "invalid JSON"):
                asyncio.run(
                    self.control.requestPrescriptionText("masked text"),
                )

        self.assertNotIn(sensitive_response, "\n".join(captured_logs.output))

    # Function Name: test_build_analysis_result_returns_diagram_entity
    # Description:
    # - Builds the UML prescription-analysis entity and preserves candidate count and lookup
    #   by medication name.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

    # Function Name: _save_basic_drug
    # Description:
    # - Persists a basic-drug catalog record with normalized lookup text and its source
    #   payload.
    # Parameters:
    # - item_name (str): Product name in the authoritative or saved medication record.
    # Returns:
    # - None.
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

    # Function Name: _save_approval_drug
    # Description:
    # - Persists an approval-catalog record with normalized lookup text and its source
    #   payload.
    # Parameters:
    # - item_name (str): Product name in the authoritative or saved medication record.
    # Returns:
    # - None.
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

    # Function Name: _medication_item
    # Description:
    # - Builds a minimal prescription medication item with one-unit doses, three daily
    #   doses, and five treatment days.
    # Parameters:
    # - drug_name (str): OCR or canonical medication name used in the payload.
    # Returns:
    # - dict[str, str]: One medication payload with fixed dose, frequency, and duration.
    def _medication_item(self, drug_name: str) -> dict[str, str]:
        return {
            "drug_name": drug_name,
            "dosage_per_time": "1",
            "daily_frequency": "3",
            "total_days": "5",
        }

    # Function Name: _verify_medication_item
    # Description:
    # - Runs asynchronous verification for one medication item and returns its schedule and
    #   verification result.
    # Parameters:
    # - item (dict[str, str]): Medication or catalog payload being parsed or verified.
    # Returns:
    # - The verified medication schedule and its name-verification metadata.
    def _verify_medication_item(self, item: dict[str, str]):
        return asyncio.run(self.control._to_verified_medication_schedules([item]))[0]

    # Function Name: _normalize_name
    # Description:
    # - Removes all whitespace and lowercases a catalog name for normalized test lookup
    #   keys.
    # Parameters:
    # - item_name (str): Product name in the authoritative or saved medication record.
    # Returns:
    # - str: Lowercase name with all whitespace removed.
    def _normalize_name(self, item_name: str) -> str:
        return "".join(item_name.split()).lower()


if __name__ == "__main__":
    unittest.main()
