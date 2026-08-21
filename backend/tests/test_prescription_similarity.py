# 파일명: test_prescription_similarity.py
# 역할: 처방 관련성 정책의 치료 맥락 판정과 보수적 제외 규칙을 검증한다.

import sys
import unittest
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from services.prescription_similarity import (  # noqa: E402
    PrescriptionSimilarityMedication,
    PrescriptionSimilarityService,
)


class PrescriptionSimilarityServiceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.service = PrescriptionSimilarityService()

    def test_relates_prescriptions_with_shared_therapeutic_context(self) -> None:
        previous = [
            PrescriptionSimilarityMedication(
                item_seq="OLD-COLD",
                item_name="기침약A",
                efficacy="기관지염의 기침과 가래를 완화합니다.",
            )
        ]
        current = [
            PrescriptionSimilarityMedication(
                item_seq="NEW-COLD",
                item_name="기침약B",
                efficacy="감기와 기관지 질환의 기침을 줄입니다.",
            )
        ]

        result = self.service.compare(previous, current)

        self.assertTrue(result.is_related)
        self.assertEqual(result.match_basis, "same_therapeutic_context")

    def test_does_not_relate_cold_and_gastrointestinal_prescriptions(self) -> None:
        previous = [
            PrescriptionSimilarityMedication(
                item_seq="COLD",
                item_name="감기약",
                efficacy="기침과 가래, 콧물을 완화합니다.",
            )
        ]
        current = [
            PrescriptionSimilarityMedication(
                item_seq="GI",
                item_name="위장약",
                efficacy="위산 과다와 속쓰림을 완화합니다.",
            )
        ]

        result = self.service.compare(previous, current)

        self.assertFalse(result.is_related)
        self.assertEqual(result.match_basis, "")


if __name__ == "__main__":
    unittest.main()
