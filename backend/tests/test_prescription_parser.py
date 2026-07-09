import sys
import unittest
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from services.prescription_parser import (  # noqa: E402
    normalize_prescription_payload,
    parse_prescription,
)
from entities.prescription_analysis_entity import (  # noqa: E402
    MedicationCandidate,
    MedicationCandidateList,
    PrescriptionAnalysisResult,
    PrescriptionText,
)


class PrescriptionParserTest(unittest.TestCase):
    def test_normalize_prescription_payload_accepts_aliases_and_filters_noise(
        self,
    ) -> None:
        raw_payload = {
            "hospitalName": "\ud14c\uc2a4\ud2b8\uc57d\uad6d",
            "prescriptionDate": "2026.7.8",
            "medicines": [
                {
                    "name": "1) \uc57d\ud488\uba85 \ud504\ub8e8\ucf54\ud504\uc815",
                    "dose_per_time": 1.0,
                    "frequency_per_day": 3,
                    "duration_days": 5,
                },
                {
                    "name": "\ud504\ub8e8\ucf54\ud504\uc815",
                    "dose_per_time": "1",
                    "frequency_per_day": "3",
                    "duration_days": "5",
                },
                {
                    "drug_name": "\uc815\ubcf4 \uc5c6\uc74c",
                    "dosage_per_time": "1",
                    "daily_frequency": "3",
                    "total_days": "5",
                },
                ["invalid row"],
            ],
        }

        normalized_payload = normalize_prescription_payload(raw_payload)

        self.assertEqual(normalized_payload["hospital_name"], "\ud14c\uc2a4\ud2b8\uc57d\uad6d")
        self.assertEqual(normalized_payload["prescription_date"], "2026-07-08")
        self.assertEqual(
            normalized_payload["medications"],
            [
                {
                    "drug_name": "\ud504\ub8e8\ucf54\ud504\uc815",
                    "dosage_per_time": "1",
                    "daily_frequency": "3",
                    "total_days": "5",
                }
            ],
        )
        self.assertEqual(normalized_payload["raw_medication_count"], 4)
        self.assertEqual(normalized_payload["parsed_medication_count"], 1)
        self.assertEqual(normalized_payload["skipped_medication_count"], 3)

    def test_parse_prescription_keeps_legacy_and_upload_shapes(self) -> None:
        parsed_payload = parse_prescription(
            [
                "\ucc98\ubc29\uc77c\uc790 2026.7.8",
                "\ud504\ub8e8\ucf54\ud504\uc815 1 3 5",
            ]
        )

        self.assertEqual(parsed_payload["prescription_date"], "2026-07-08")
        self.assertEqual(parsed_payload["medicines"][0]["name"], "\ud504\ub8e8\ucf54\ud504\uc815")
        self.assertEqual(parsed_payload["medicines"][0]["dose_per_time"], 1)
        self.assertEqual(parsed_payload["medicines"][0]["frequency_per_day"], 3)
        self.assertEqual(parsed_payload["medicines"][0]["duration_days"], 5)
        self.assertEqual(
            parsed_payload["medications"],
            [
                {
                    "drug_name": "\ud504\ub8e8\ucf54\ud504\uc815",
                    "dosage_per_time": "1",
                    "daily_frequency": "3",
                    "total_days": "5",
                }
            ],
        )

    def test_parse_prescription_rejects_unstructured_long_line(self) -> None:
        parsed_payload = parse_prescription(
            [
                ("a" * 10000) + " " + ("." * 10000),
            ]
        )

        self.assertEqual(parsed_payload["medicines"], [])
        self.assertEqual(parsed_payload["medications"], [])

    def test_parse_prescription_keeps_names_with_spaces(self) -> None:
        parsed_payload = parse_prescription(["compound cold tablet 1 3 5"])

        self.assertEqual(
            parsed_payload["medications"][0]["drug_name"],
            "compound cold tablet",
        )
        self.assertEqual(parsed_payload["medications"][0]["dosage_per_time"], "1")
        self.assertEqual(parsed_payload["medications"][0]["daily_frequency"], "3")
        self.assertEqual(parsed_payload["medications"][0]["total_days"], "5")

    def test_normalize_prescription_payload_skips_non_finite_numeric_aliases(
        self,
    ) -> None:
        raw_payload = {
            "medications": [
                {
                    "drug_name": "\ud504\ub8e8\ucf54\ud504\uc815",
                    "dosage_per_time": float("nan"),
                    "dose": "1",
                    "daily_frequency": "Infinity",
                    "frequency": "3",
                    "total_days": "-Infinity",
                    "days": "5",
                }
            ],
        }

        normalized_payload = normalize_prescription_payload(raw_payload)

        self.assertEqual(
            normalized_payload["medications"],
            [
                {
                    "drug_name": "\ud504\ub8e8\ucf54\ud504\uc815",
                    "dosage_per_time": "1",
                    "daily_frequency": "3",
                    "total_days": "5",
                }
            ],
        )

    def test_prescription_analysis_entities_preserve_diagram_operations(
        self,
    ) -> None:
        medication_candidate = MedicationCandidate(
            drug_name="\ud504\ub8e8\ucf54\ud504\uc815",
            dosage_per_time="1",
            daily_frequency="3",
            total_days="5",
        )
        candidate_list = MedicationCandidateList()

        self.assertTrue(candidate_list.isEmpty())
        candidate_list.addCandidate(medication_candidate)

        self.assertFalse(candidate_list.isEmpty())
        self.assertEqual(
            candidate_list.findByName("\ud504\ub8e8\ucf54\ud504\uc815"),
            medication_candidate,
        )
        self.assertEqual(medication_candidate.drugName, "\ud504\ub8e8\ucf54\ud504\uc815")
        self.assertEqual(medication_candidate.dosagePerTime, "1")
        self.assertEqual(medication_candidate.dailyFrequency, "3")
        self.assertEqual(medication_candidate.totalDays, "5")
        self.assertEqual(
            PrescriptionText(raw_text="900101-1234567").removeSensitiveInfoByRegex(),
            "900101-*******",
        )
        analysis_result = PrescriptionAnalysisResult(
            hospital_name="\ud14c\uc2a4\ud2b8\uc57d\uad6d",
            prescription_date="2026-07-09",
            medication_candidates=candidate_list,
        )
        self.assertEqual(
            analysis_result.to_payload(raw_medication_count=0)[
                "skipped_medication_count"
            ],
            0,
        )

    def test_normalize_prescription_payload_rejects_non_object_response(self) -> None:
        with self.assertRaises(ValueError):
            normalize_prescription_payload(["not", "an", "object"])


if __name__ == "__main__":
    unittest.main()
