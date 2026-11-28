# 파일명: test_prescription_similarity.py
# 역할: 처방의 치료 맥락 유사성과 무관한 질환 처방의 비교 제외를 검증한다.

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


# 클래스명: PrescriptionSimilarityServiceTest
# 역할: 공통 치료 맥락이 있는 처방만 관련된 것으로 판정하는지 검증하는 테스트 모음이다.
# 주요 책임:
# - 공통 치료 맥락을 가진 처방을 관련 있음으로 판정하고 same_therapeutic_context 근거를 반환하는지 검증한다.
# - 감기와 위장관 처방은 관련 없음과 빈 일치 근거로 구분하는지 검증한다.
# 속성:
# - service (PrescriptionSimilarityService): 검증할 처방 치료 맥락 유사도 서비스.
class PrescriptionSimilarityServiceTest(unittest.TestCase):
    # 함수이름: setUp
    # 함수역할:
    # - 각 테스트에 독립된 처방 유사도 서비스를 준비한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def setUp(self) -> None:
        self.service = PrescriptionSimilarityService()

    # 함수이름: test_relates_prescriptions_with_shared_therapeutic_context
    # 함수역할:
    # - 공통 치료 맥락을 가진 처방을 관련 있음으로 판정하고 same_therapeutic_context 근거를 반환하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_does_not_relate_cold_and_gastrointestinal_prescriptions
    # 함수역할:
    # - 감기와 위장관 처방은 관련 없음과 빈 일치 근거로 구분하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_relates_coded_combination_products_by_shared_ingredient
    # 함수역할:
    # - 허가정보의 "[코드]성분|[코드]성분" 복합제를 성분별로 나눠 단일제와 같은 성분으로 판정하는지 검증한다.
    # - 이전에는 | 로 나누지 않아 복합제 전체가 하나의 키가 되어 겹침을 찾지 못했다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_relates_coded_combination_products_by_shared_ingredient(self) -> None:
        previous = [
            PrescriptionSimilarityMedication(
                item_seq="COMBINATION",
                item_name="복합정",
                main_ingredient="[M040702]아세트아미노펜|[M223303]카페인무수물",
            )
        ]
        current = [
            PrescriptionSimilarityMedication(
                item_seq="SINGLE",
                item_name="단일정",
                main_ingredient="[M040702]아세트아미노펜",
            )
        ]

        result = self.service.compare(previous, current)

        self.assertTrue(result.is_related)
        self.assertEqual(result.match_basis, "same_ingredient")
        self.assertEqual(
            self.service._ingredient_keys(previous),
            {"아세트아미노펜", "카페인무수물"},
        )

    # 함수이름: test_coded_ingredient_matches_parenthetical_name
    # 함수역할:
    # - 코드가 붙은 허가정보 성분명도 약품명 괄호의 성분명과 같은 키가 되는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_coded_ingredient_matches_parenthetical_name(self) -> None:
        previous = [
            PrescriptionSimilarityMedication(
                item_seq="CODED",
                item_name="브랜드정",
                main_ingredient="[M040702]아세트아미노펜",
            )
        ]
        current = [
            PrescriptionSimilarityMedication(
                item_name="다른브랜드정(아세트아미노펜)",
            )
        ]

        self.assertTrue(self.service.compare(previous, current).is_related)


if __name__ == "__main__":
    unittest.main()
