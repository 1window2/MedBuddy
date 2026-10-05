# 파일명: test_request_health_recommendation_control.py
# 역할: 활성 복약 기반 건강 추천의 환자 범위·캐시·언어 및 응답 계약을 검증한다.

import asyncio
import sys
import threading
import unittest
from datetime import date, timedelta
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from boundaries.llm_service_boundary import LLMService  # noqa: E402
from controls.check_health_recommendation_control import (  # noqa: E402
    CheckHealthRecommendation,
)
from api.router import get_health_recommendation  # noqa: E402
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
            poolclass=StaticPool,
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

    # Function Name: test_database_phases_leave_event_loop_responsive_and_retain_transaction
    # Description:
    # - Requires lookup and cache operations off-loop, while preserving the request transaction during LLM generation.
    # Parameters:
    # - None.
    # Returns:
    # - None; fails if SQL blocks the loop, crosses concurrent phases or releases account serialization early.
    async def test_database_phases_leave_event_loop_responsive_and_retain_transaction(self) -> None:
        self._save_medication(item_name="active-tablet")
        loop = asyncio.get_running_loop()
        loop_thread = threading.get_ident()
        calls: list[str] = []
        original_read = self.control._get_active_medications
        original_cache_read = self.control._get_cached_recommendation
        original_cache_write = self.control._save_cached_recommendation
        original_generate = self.llm_service.requestHealthRecommendation

        # Function Name: require_worker
        # Description: Waits for an event-loop callback while proving the current operation uses a worker thread.
        # Parameters: name (str): Operation recorded for phase-order assertions.
        # Returns: None.
        def require_worker(name: str) -> None:
            assert threading.get_ident() != loop_thread
            pulse = threading.Event()
            loop.call_soon_threadsafe(pulse.set)
            assert pulse.wait(1), "Database work blocked the event loop."
            calls.append(name)

        # Function Name: read_active
        # Description: Exercises real medication lookup after checking worker isolation.
        # Parameters: patient_hash (str): Authorized owner; today (date): Active-course date.
        # Returns: Active medication rows.
        def read_active(patient_hash: str, today: date) -> list[_SavedMedication]:
            require_worker("medications")
            return original_read(patient_hash, today)

        # Function Name: read_cache
        # Description: Exercises real cache lookup in the same sequential database phase.
        # Parameters: patient_hash (str): Authorized owner; key (str): Medication/language signature.
        # Returns: Cached recommendation or None.
        def read_cache(patient_hash: str, key: str) -> dict[str, object] | None:
            require_worker("cache_read")
            return original_cache_read(patient_hash, key)

        # Function Name: write_cache
        # Description: Exercises the existing cache transaction after external generation has completed.
        # Parameters: patient_hash (str): Authorized owner; key (str): Cache signature; value (dict): Guidance payload.
        # Returns: None.
        def write_cache(patient_hash: str, key: str, value: dict[str, object]) -> None:
            require_worker("cache_write")
            original_cache_write(patient_hash, key, value)

        # Function Name: generate
        # Description: Verifies LLM execution stays async and does not end the request's authorization transaction.
        # Parameters: summaries (list[dict]): Plain medication values; language (str): Requested content language.
        # Returns: Synthetic guidance from the existing recording boundary.
        async def generate(summaries: list[dict[str, str]], language: str) -> dict[str, object]:
            assert threading.get_ident() == loop_thread
            assert self.db.in_transaction()
            calls.append("generate")
            return await original_generate(summaries, language)

        with (
            patch.object(self.control, "_get_active_medications", side_effect=read_active),
            patch.object(self.control, "_get_cached_recommendation", side_effect=read_cache),
            patch.object(self.control, "_save_cached_recommendation", side_effect=write_cache),
            patch.object(self.llm_service, "requestHealthRecommendation", side_effect=generate),
        ):
            response = await self.control.requestHealthRecommendation("patient-a")
        self.assertTrue(response["success"])
        self.assertEqual(calls, ["medications", "cache_read", "generate", "cache_write"])

    # Function Name: test_cancelled_recommendation_waits_for_database_before_cleanup
    # Description:
    # - Cancels a recommendation during snapshot work and requires session cleanup only after that work completes.
    # Parameters:
    # - None.
    # Returns:
    # - None; fails if cancellation races the request session or starts LLM generation.
    async def test_cancelled_recommendation_waits_for_database_before_cleanup(self) -> None:
        self._save_medication(item_name="active-tablet")
        started = threading.Event()
        release = threading.Event()
        calls: list[str] = []
        original_snapshot = self.control._read_recommendation_snapshot

        # Function Name: snapshot
        # Description: Holds real snapshot work until cancellation has been observed by the request.
        # Parameters: patient_hash (str): Authorized owner; today (date): Course date; language (str): Content language.
        # Returns: The original detached summary/cache snapshot.
        def snapshot(
            patient_hash: str, today: date, language: str,
        ) -> tuple[list[dict[str, str]], str, dict[str, object] | None]:
            started.set()
            if not release.wait(2):
                raise AssertionError("Recommendation cancellation did not release the worker.")
            result = original_snapshot(patient_hash, today, language)
            calls.append("database_complete")
            return result

        # Function Name: request
        # Description: Models dependency cleanup after a cancelled recommendation.
        # Parameters: None.
        # Returns: None; cancellation propagates after session work stops.
        async def request() -> None:
            try:
                await self.control.requestHealthRecommendation("patient-a")
            finally:
                self.db.close()
                calls.append("cleanup")

        with patch.object(self.control, "_read_recommendation_snapshot", side_effect=snapshot):
            task = asyncio.create_task(request())
            try:
                async with asyncio.timeout(1):
                    while not started.is_set():
                        await asyncio.sleep(0)
                task.cancel()
                await asyncio.sleep(0)
                self.assertFalse(task.done())
                self.assertEqual(calls, [])
            finally:
                release.set()
            with self.assertRaises(asyncio.CancelledError):
                await task
        self.assertEqual(calls, ["database_complete", "cleanup"])
        self.assertEqual(self.llm_service.generation_count, 0)

    # Function Name: test_health_route_denies_scope_before_generating_guidance
    # Description:
    # - Performs the unchanged caregiver-aware authorization off-loop and stops before recommendation generation when denied.
    # Parameters:
    # - None.
    # Returns:
    # - None; fails if denial is bypassed or the LLM is called.
    async def test_health_route_denies_scope_before_generating_guidance(self) -> None:
        loop_thread = threading.get_ident()

        # Function Name: deny_scope
        # Description: Rejects the requested caregiver scope from the worker without changing its HTTP status.
        # Parameters: principal (object): Verified caller; patient_hash (str): Requested patient; allow_caregiver (bool): Existing read policy.
        # Returns: No normal result; raises HTTP 403.
        def deny_scope(principal: object, patient_hash: str, *, allow_caregiver: bool) -> str:
            assert threading.get_ident() != loop_thread
            assert patient_hash == "other-patient" and allow_caregiver is True
            raise HTTPException(403, "Patient scope is not permitted.")

        recommendation = SimpleNamespace(requestHealthRecommendation=AsyncMock())
        with self.assertRaises(HTTPException) as rejected:
            await get_health_recommendation(
                patient_hash="other-patient", language="ko", principal=object(),
                authorization=SimpleNamespace(resolvePatientScope=deny_scope, db=self.db),
                check_health_recommendation=recommendation,
            )
        self.assertEqual(rejected.exception.status_code, 403)
        recommendation.requestHealthRecommendation.assert_not_awaited()

    # Function Name: test_cache_write_failure_preserves_guidance_and_hides_database_details
    # Description:
    # - Retains best-effort cache behavior and logs only the failure type when a worker commit fails.
    # Parameters:
    # - None.
    # Returns:
    # - None; fails if caching errors expose private data or fail otherwise valid guidance.
    async def test_cache_write_failure_preserves_guidance_and_hides_database_details(self) -> None:
        self._save_medication(item_name="active-tablet")
        with (
            patch.object(self.db, "commit", side_effect=RuntimeError("private database details")),
            self.assertLogs("controls.check_health_recommendation_control", level="WARNING") as captured,
        ):
            response = await self.control.requestHealthRecommendation("patient-a")
        self.assertTrue(response["success"])
        self.assertNotIn("private database details", "\n".join(captured.output))

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
            poolclass=StaticPool,
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
