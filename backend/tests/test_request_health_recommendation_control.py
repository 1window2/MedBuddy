# 파일명: test_request_health_recommendation_control.py
# 역할: 건강 관리 추천 control의 약 조합 조회와 AI 응답 정규화를 검증한다.

import sys
import unittest
from datetime import date, timedelta
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from boundaries.llm_service_boundary import LLMService  # noqa: E402
from controls.check_health_recommendation_control import (  # noqa: E402
    CheckHealthRecommendation,
)
from core.database import Base  # noqa: E402
from entities.saved_medication_entity import (  # noqa: E402
    _SavedMedication,
    ensure_saved_medication_schema,
)


# 클래스명: _FakeLLMService
# 역할: Gemini 호출 없이 control 입력값을 검증하기 위한 테스트용 생성기이다.
# 주요 책임:
#   - 전달된 약 요약 정보를 기록한다.
#   - 고정된 건강 관리 추천 응답을 반환한다.
class _FakeLLMService:
    def __init__(self) -> None:
        self.generation_count = 0
        self.received_medications: list[dict[str, str]] = []

    async def requestHealthRecommendation(
        self,
        medication_summaries: list[dict[str, str]],
        language: str = "ko",
    ) -> dict[str, object]:
        self.generation_count += 1
        self.received_medications = medication_summaries
        return {
            "diet_recommendation": "위 자극을 줄이는 식사를 권장합니다.",
            "exercise_recommendation": "가벼운 산책을 권장합니다.",
            "caution_items": ["이상 증상이 있으면 의료진과 상담하세요."],
        }


class CheckHealthRecommendationTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=self.engine)
        ensure_saved_medication_schema(self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.llm_service = _FakeLLMService()
        self.control = CheckHealthRecommendation(
            self.db,
            llm_service=self.llm_service,
        )

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def _save_medication(
        self,
        *,
        item_name: str,
        patient_hash: str = "patient-a",
        prescription_date: date | None = None,
        total_days: str = "7 days",
    ) -> _SavedMedication:
        medication = _SavedMedication(
            patient_hash=patient_hash,
            prescription_date=prescription_date or date.today(),
            item_name=item_name,
            efficacy="effect",
            use_method="usage",
            warning_message="warning",
            dosage_per_time="1 tablet",
            daily_frequency="3 times",
            total_days=total_days,
        )
        self.db.add(medication)
        self.db.commit()
        self.db.refresh(medication)
        return medication

    async def test_recommendation_uses_only_active_medications(self) -> None:
        self._save_medication(
            item_name="active-tablet",
            prescription_date=date.today() - timedelta(days=2),
            total_days="7 days",
        )
        self._save_medication(
            item_name="expired-tablet",
            prescription_date=date.today() - timedelta(days=10),
            total_days="3 days",
        )
        self._save_medication(
            item_name="other-patient-tablet",
            patient_hash="patient-b",
        )

        response = await self.control.requestHealthRecommendation("patient-a")

        self.assertTrue(response["success"])
        self.assertEqual(
            response["data"]["diet_recommendation"],
            "위 자극을 줄이는 식사를 권장합니다.",
        )
        self.assertEqual(
            response["data"]["medication_names"],
            ["active-tablet"],
        )
        self.assertEqual(
            [item["item_name"] for item in self.llm_service.received_medications],
            ["active-tablet"],
        )
        self.assertEqual(self.llm_service.generation_count, 1)

    async def test_recommendation_reuses_cached_result_for_same_medication_combo(
        self,
    ) -> None:
        self._save_medication(
            item_name="active-tablet",
            prescription_date=date.today(),
            total_days="7 days",
        )

        first_response = await self.control.requestHealthRecommendation("patient-a")
        second_response = await self.control.requestHealthRecommendation("patient-a")

        self.assertEqual(first_response["data"], second_response["data"])
        self.assertEqual(self.llm_service.generation_count, 1)

    async def test_recommendation_cache_is_separated_by_language(self) -> None:
        self._save_medication(
            item_name="active-tablet",
            prescription_date=date.today(),
            total_days="7 days",
        )

        await self.control.requestHealthRecommendation("patient-a", language="ko")
        await self.control.requestHealthRecommendation("patient-a", language="en")

        self.assertEqual(self.llm_service.generation_count, 2)

    async def test_recommendation_without_active_medications_returns_not_found(
        self,
    ) -> None:
        with self.assertRaises(HTTPException) as context:
            await self.control.requestHealthRecommendation("patient-a")

        self.assertEqual(context.exception.status_code, 404)


class LLMServiceTest(unittest.TestCase):
    def test_normalize_response_limits_caution_items(self) -> None:
        llm_service = LLMService(ai_client=object())

        normalized_response = llm_service._normalize_response(
            {
                "diet_recommendation": "식사",
                "exercise_recommendation": "운동",
                "caution_items": ["1", "2", "3", "4", "5", "6"],
            },
            "ko",
        )

        self.assertEqual(normalized_response["diet_recommendation"], "식사")
        self.assertEqual(normalized_response["exercise_recommendation"], "운동")
        self.assertEqual(normalized_response["caution_items"], ["1", "2", "3", "4", "5"])


class CheckHealthRecommendationContractTest(unittest.IsolatedAsyncioTestCase):
    async def test_diagram_method_name_executes_recommendation_flow(self) -> None:
        engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=engine)
        ensure_saved_medication_schema(engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=engine,
        )
        db = session_factory()
        llm_service = _FakeLLMService()
        try:
            medication = _SavedMedication(
                patient_hash="patient-a",
                prescription_date=date.today(),
                item_name="active-tablet",
                efficacy="effect",
                use_method="usage",
                warning_message="warning",
                dosage_per_time="1 tablet",
                daily_frequency="3 times",
                total_days="7 days",
            )
            db.add(medication)
            db.commit()
            control = CheckHealthRecommendation(
                db,
                llm_service=llm_service,
            )

            response = await control.requestHealthRecommendation("patient-a")

            self.assertTrue(response["success"])
            self.assertEqual(response["data"]["medication_names"], ["active-tablet"])
        finally:
            db.close()
            engine.dispose()


if __name__ == "__main__":
    unittest.main()
