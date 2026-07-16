import sys
import unittest
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from services.prescription_parser import (  # noqa: E402
    MAX_MEDICATION_NAME_LENGTH,
    normalize_date,
    normalize_prescription_candidates,
    parse_prescription,
)
from entities.prescription_analysis_entity import (  # noqa: E402
    MedicationCandidate,
    MedicationCandidateList,
    PrescriptionAnalysisResult,
    PrescriptionText,
)


class PrescriptionParserTest(unittest.TestCase):
    def test_normalize_date_rejects_invalid_calendar_values(self) -> None:
        self.assertIsNone(normalize_date("처방일자 2026-02-30"))
        self.assertIsNone(normalize_date("처방일자 2026-13-01"))

        _, normalized_date, _, _ = normalize_prescription_candidates(
            {"prescription_date": "2026-02-30"}
        )
        self.assertEqual(normalized_date, "정보 없음")

    def test_normalize_prescription_candidates_accepts_aliases_and_filters_noise(
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

        hospital_name, prescription_date, candidates, raw_count = (
            normalize_prescription_candidates(raw_payload)
        )

        self.assertEqual(hospital_name, "\ud14c\uc2a4\ud2b8\uc57d\uad6d")
        self.assertEqual(prescription_date, "2026-07-08")
        self.assertEqual(
            candidates.to_payload(),
            [
                {
                    "drug_name": "\ud504\ub8e8\ucf54\ud504\uc815",
                    "dosage_per_time": "1",
                    "daily_frequency": "3",
                    "total_days": "5",
                }
            ],
        )
        self.assertEqual(raw_count, 4)
        self.assertEqual(len(candidates.candidates), 1)

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

    def test_parse_prescription_rejects_nonpositive_schedule_values(self) -> None:
        parsed_payload = parse_prescription(
            [
                "zero-dose 0 3 5",
                "negative-frequency 1 -3 5",
                "zero-duration 1 3 0",
            ]
        )

        self.assertEqual(parsed_payload["medications"], [])

    def test_parser_rejects_unbounded_medication_names(self) -> None:
        oversized_name = "a" * (MAX_MEDICATION_NAME_LENGTH + 1)

        parsed_payload = parse_prescription([f"{oversized_name} 1 3 5"])
        _, _, candidates, _ = normalize_prescription_candidates(
            {
                "medications": [
                    {
                        "drug_name": oversized_name,
                        "dosage_per_time": "1",
                        "daily_frequency": "3",
                        "total_days": "5",
                    }
                ]
            }
        )

        self.assertEqual(parsed_payload["medications"], [])
        self.assertTrue(candidates.isEmpty())

    def test_normalize_prescription_candidates_skips_non_finite_numeric_aliases(
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

        _, _, candidates, _ = normalize_prescription_candidates(raw_payload)

        self.assertEqual(
            candidates.to_payload(),
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

    def test_normalize_prescription_candidates_rejects_non_object_response(self) -> None:
        with self.assertRaises(ValueError):
            normalize_prescription_candidates(["not", "an", "object"])


if __name__ == "__main__":
    unittest.main()
