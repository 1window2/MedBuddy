# 파일명: test_request_health_recommendation_control.py
# 역할: 활성 복약 기반 건강 추천의 환자 범위·캐시·언어 및 응답 계약을 검증한다.

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


# Class Name: _FakeLLMService
# Role: Health recommendation generator double recording medication summaries and returning
#   fixed diet, exercise, and caution guidance without Gemini.
# Responsibilities:
# - Records the medication summaries, counts generation requests, and returns deterministic
#   diet, exercise, and caution recommendations.
# Attributes:
# - generation_count (int): Number of health recommendations generated.
# - received_medications (list[dict[str, str]]): Medication summaries captured from the
#   recommendation request.
class _FakeLLMService:
    # 함수이름: __init__
    # 함수역할:
    # - 추천 생성 횟수와 전달받은 약 요약 목록을 초기화한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def __init__(self) -> None:
        self.generation_count = 0
        self.received_medications: list[dict[str, str]] = []

    # Function Name: requestHealthRecommendation
    # Description:
    # - Records the medication summaries, counts generation requests, and returns
    #   deterministic diet, exercise, and caution recommendations.
    # Parameters:
    # - medication_summaries (list[dict[str, str]]): Active-medication summaries submitted
    #   for recommendations.
    # - language (str): Requested recommendation language.
    # Returns:
    # - dict[str, object]: Fixed diet, exercise, and caution recommendations.
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


# Class Name: CheckHealthRecommendationTest
# Role: Async database-backed tests for active-medication selection and health-recommendation
#   caching.
# Responsibilities:
# - Sends only active medication summaries to the LLM and returns their names with one generated
#   recommendation.
# - Keeps recommendation cache entries separate by language and generates once for each
#   language.
# - Returns HTTP 404 instead of generating recommendations when there are no active medications.
# Attributes:
# - engine (Engine): Isolated in-memory SQLite engine.
# - db (Session): SQLAlchemy session holding only this test's database state.
# - llm_service (_FakeLLMService): Recording recommendation generator replacing Gemini.
# - control (CheckHealthRecommendation): Use-case control under test, isolated from production
#   state.
class CheckHealthRecommendationTest(unittest.IsolatedAsyncioTestCase):
    # Function Name: setUp
    # Description:
    # - Creates an isolated medication database and recommendation control wired to a
    #   recording LLM double.
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

    # 함수이름: tearDown
    # 함수역할:
    # - 건강 추천 테스트의 DB 세션과 엔진을 닫는다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # 함수이름: _save_medication
    # 함수역할:
    # - 지정 환자·약명·처방일·기간의 약을 저장하고 갱신한 행을 반환하여 활성 복약 범위를 준비한다.
    # 매개변수:
    # - item_name (str): 공식 카탈로그 또는 저장 약 레코드의 제품명.
    # - patient_hash (str): 약 또는 연동 데이터 범위를 식별할 환자 소유자 해시.
    # - prescription_date (date | None): 처방 또는 복용 시작일이며 None이면 fixture 기본 날짜 사용.
    # - total_days (str): 처방된 복용 기간 문자열이며 미상일 수 있음.
    # 반환값:
    # - _SavedMedication: 생성된 ID를 포함하여 저장·갱신한 약 행.
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

    # Function Name: test_recommendation_uses_only_active_medications
    # Description:
    # - Sends only active medication summaries to the LLM and returns their names with one
    #   generated recommendation.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

    # Function Name: test_recommendation_reuses_cached_result_for_same_medication_combo
    # Description:
    # - Reuses an identical recommendation for the same medication combination without a
    #   second generation call.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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

    # Function Name: test_recommendation_cache_is_separated_by_language
    # Description:
    # - Keeps recommendation cache entries separate by language and generates once for each
    #   language.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def test_recommendation_cache_is_separated_by_language(self) -> None:
        self._save_medication(
            item_name="active-tablet",
            prescription_date=date.today(),
            total_days="7 days",
        )

        await self.control.requestHealthRecommendation("patient-a", language="ko")
        await self.control.requestHealthRecommendation("patient-a", language="en")

        self.assertEqual(self.llm_service.generation_count, 2)

    # Function Name: test_recommendation_without_active_medications_returns_not_found
    # Description:
    # - Returns HTTP 404 instead of generating recommendations when there are no active
    #   medications.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def test_recommendation_without_active_medications_returns_not_found(
        self,
    ) -> None:
        with self.assertRaises(HTTPException) as context:
            await self.control.requestHealthRecommendation("patient-a")

        self.assertEqual(context.exception.status_code, 404)


# Class Name: LLMServiceTest
# Role: Response-normalization tests for bounded health-recommendation caution lists.
# Responsibilities:
# - Preserves diet and exercise text while limiting caution items to the first five entries.
class LLMServiceTest(unittest.TestCase):
    # Function Name: test_normalize_response_limits_caution_items
    # Description:
    # - Preserves diet and exercise text while limiting caution items to the first five
    #   entries.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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


# Class Name: CheckHealthRecommendationContractTest
# Role: Contract tests ensuring the UML recommendation entrypoint executes the real
#   medication-based flow.
# Responsibilities:
# - Requires the diagram-named operation to return a successful recommendation containing the
#   active medication name.
class CheckHealthRecommendationContractTest(unittest.IsolatedAsyncioTestCase):
    # Function Name: test_diagram_method_name_executes_recommendation_flow
    # Description:
    # - Requires the diagram-named operation to return a successful recommendation
    #   containing the active medication name.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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
