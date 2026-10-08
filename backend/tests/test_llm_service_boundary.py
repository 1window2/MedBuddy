# File Name: test_llm_service_boundary.py
# Role: Regression coverage for health-recommendation response contracts, timeout validation,
#   and cancellation.
"""Focused tests for bounded health-recommendation Gemini requests."""

import asyncio
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from boundaries.llm_service_boundary import LLMService  # noqa: E402
from core.config import settings  # noqa: E402


# Class Name: _BlockingModels
# Role: Gemini models double that blocks indefinitely and records request cancellation.
# Responsibilities:
# - Waits until cancellation, records it, and propagates CancelledError to the service boundary.
# Attributes:
# - cancelled (bool): Whether cancellation reached the blocked request.
class _BlockingModels:
    # Function Name: __init__
    # Description:
    # - Starts the blocking model with cancellation unset.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.cancelled = False

    # Function Name: generate_content
    # Description:
    # - Waits until cancellation, records it, and propagates CancelledError to the service
    #   boundary.
    # Parameters:
    # - **kwargs (object): Keyword arguments accepted by the substituted service interface.
    # Returns:
    # - No normal result; propagates cancellation of the indefinitely blocked request.
    async def generate_content(self, **kwargs: object) -> object:
        try:
            await asyncio.Event().wait()
        except asyncio.CancelledError:
            self.cancelled = True
            raise


# Class Name: _RespondingModels
# Role: Gemini models double that records the request and returns fixed health-recommendation
#   JSON.
# Responsibilities:
# - Records model configuration and returns diet, exercise, and caution recommendations as JSON.
# Attributes:
# - request (dict[str, object]): Captured Gemini request fields.
class _RespondingModels:
    # Function Name: __init__
    # Description:
    # - Initializes an empty request record for model and response-format assertions.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.request: dict[str, object] = {}

    # Function Name: generate_content
    # Description:
    # - Records model configuration and returns diet, exercise, and caution recommendations
    #   as JSON.
    # Parameters:
    # - **kwargs (object): Keyword arguments accepted by the substituted service interface.
    # Returns:
    # - object: Gemini-compatible response carrying the configured analysis JSON.
    async def generate_content(self, **kwargs: object) -> object:
        self.request = kwargs
        return type(
            "Response",
            (),
            {
                "text": (
                    '{"diet_recommendation":"diet","exercise_recommendation":'
                    '"exercise","caution_items":["caution"]}'
                )
            },
        )()


# Class Name: _ScriptedModels
# Role: Gemini models double that answers each call with the next scripted text or error.
# Responsibilities:
# - Counts calls and returns or raises the scripted answers in order.
# Attributes:
# - answers (list[object]): Response texts (None for a blank body) or exceptions, one per call.
# - call_count (int): Number of generation requests received.
class _ScriptedModels:
    # Function Name: __init__
    # Description:
    # - Stores the scripted answers and starts the call counter at zero.
    # Parameters:
    # - *answers (object): Response text, None, or an exception to raise, in call order.
    # Returns:
    # - None.
    def __init__(self, *answers: object) -> None:
        self.answers = list(answers)
        self.call_count = 0

    # Function Name: generate_content
    # Description:
    # - Counts the call and returns a response with the next scripted text, or raises the
    #   next scripted exception.
    # Parameters:
    # - **kwargs (object): Keyword arguments accepted by the substituted service interface.
    # Returns:
    # - object: Gemini-compatible response whose text is the scripted answer.
    async def generate_content(self, **kwargs: object) -> object:
        answer = self.answers[self.call_count]
        self.call_count += 1
        if isinstance(answer, BaseException):
            raise answer
        return type("Response", (), {"text": answer})()


# Class Name: _StallingModels
# Role: Gemini models double that fails a set number of calls and then never answers.
# Responsibilities:
# - Counts calls, raises a provider error for the first calls and blocks on the next one.
# Attributes:
# - failures_before_stall (int): Number of leading calls answered with ConnectionError.
# - call_count (int): Number of generation requests received.
class _StallingModels:
    # Function Name: __init__
    # Description:
    # - Stores how many calls fail before the blocking call and starts the counter at zero.
    # Parameters:
    # - failures_before_stall (int): Number of leading calls that raise ConnectionError.
    # Returns:
    # - None.
    def __init__(self, failures_before_stall: int) -> None:
        self.failures_before_stall = failures_before_stall
        self.call_count = 0

    # Function Name: generate_content
    # Description:
    # - Counts the call, raises for the configured leading calls and otherwise waits until
    #   the caller's deadline cancels it.
    # Parameters:
    # - **kwargs (object): Keyword arguments accepted by the substituted service interface.
    # Returns:
    # - No normal result; raises ConnectionError or waits for cancellation.
    async def generate_content(self, **kwargs: object) -> object:
        self.call_count += 1
        if self.call_count <= self.failures_before_stall:
            raise ConnectionError("reset")
        await asyncio.Event().wait()


# Class Name: _FakeClient
# Role: Minimal Gemini client double exposing a supplied model through aio.models.
# Responsibilities:
# - Minimal Gemini client double exposing a supplied model through aio.models.
# Attributes:
# - aio (object): Gemini-compatible asynchronous namespace or owned async client.
class _FakeClient:
    # Function Name: __init__
    # Description:
    # - Attaches the provided models object to the asynchronous SDK-compatible namespace.
    # Parameters:
    # - models (object): Injected Gemini-compatible model implementation.
    # Returns:
    # - None.
    def __init__(self, models: object) -> None:
        self.aio = type("Aio", (), {"models": models})()


# Class Name: LLMServiceTimeoutTest
# Role: Asynchronous tests of bounded health-recommendation calls and stable error contracts.
# Responsibilities:
# - Uses the configured quarter-second default when the service timeout is omitted.
# - Preserves diet, exercise, and caution fields while requesting the configured model and JSON
#   response format.
# - Cancels a stalled request and wraps TimeoutError in the stable health-recommendation timeout
#   message.
# - Rejects an answer without diet and exercise text, retries a failed attempt once and never
#   retries a timeout.
class LLMServiceTimeoutTest(unittest.IsolatedAsyncioTestCase):
    # Function Name: test_timeout_uses_configured_default
    # Description:
    # - Uses the configured quarter-second default when the service timeout is omitted.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_timeout_uses_configured_default(self) -> None:
        with patch.object(settings, "HEALTH_RECOMMENDATION_TIMEOUT_SECONDS", 0.25):
            service = LLMService(ai_client=object())

        self.assertEqual(service.timeout_seconds, 0.25)

    # Function Name: test_rejects_unbounded_timeout
    # Description:
    # - Rejects non-finite or non-positive health-recommendation timeouts.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_rejects_unbounded_timeout(self) -> None:
        for timeout_seconds in (0.0, -1.0, float("nan"), float("inf")):
            with self.subTest(timeout_seconds=timeout_seconds):
                with self.assertRaisesRegex(ValueError, "finite and positive"):
                    LLMService(
                        ai_client=object(),
                        timeout_seconds=timeout_seconds,
                    )

    # Function Name: test_successful_request_preserves_response_contract
    # Description:
    # - Preserves diet, exercise, and caution fields while requesting the configured model
    #   and JSON response format.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def test_successful_request_preserves_response_contract(self) -> None:
        models = _RespondingModels()
        service = LLMService(
            ai_client=_FakeClient(models),
            model_name="gemini-test",
            timeout_seconds=1.0,
        )

        recommendation = await service.requestHealthRecommendation(
            [{"item_name": "test-tablet"}],
            language="en",
        )

        self.assertEqual(recommendation["diet_recommendation"], "diet")
        self.assertEqual(recommendation["exercise_recommendation"], "exercise")
        self.assertEqual(recommendation["caution_items"], ["caution"])
        self.assertEqual(models.request["model"], "gemini-test")
        self.assertEqual(
            models.request["config"],
            {"response_mime_type": "application/json"},
        )

    # Function Name: test_timeout_is_stable_and_cancels_request
    # Description:
    # - Cancels a stalled request and wraps TimeoutError in the stable health-recommendation
    #   timeout message.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def test_timeout_is_stable_and_cancels_request(self) -> None:
        models = _BlockingModels()
        service = LLMService(
            ai_client=_FakeClient(models),
            timeout_seconds=0.01,
        )

        with self.assertRaises(RuntimeError) as context:
            await service.requestHealthRecommendation(
                [{"item_name": "test-tablet"}],
            )

        self.assertEqual(
            str(context.exception),
            "Health recommendation generation timed out.",
        )
        self.assertIsInstance(context.exception.__cause__, TimeoutError)
        self.assertTrue(models.cancelled)

    # Function Name: test_blank_answer_is_rejected_after_one_retry
    # Description:
    # - Raises instead of returning fallback text when the answer has neither diet nor
    #   exercise guidance, after asking exactly twice.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def test_blank_answer_is_rejected_after_one_retry(self) -> None:
        for blank_answer in (
            "{}",
            '{"diet_recommendation":"  ","exercise_recommendation":null,'
            '"caution_items":["caution"]}',
        ):
            with self.subTest(blank_answer=blank_answer):
                models = _ScriptedModels(blank_answer, blank_answer)
                service = LLMService(
                    ai_client=_FakeClient(models),
                    timeout_seconds=1.0,
                )

                with self.assertRaises(RuntimeError) as context:
                    await service.requestHealthRecommendation(
                        [{"item_name": "test-tablet"}],
                    )

                self.assertEqual(
                    str(context.exception),
                    "The health recommendation response is empty.",
                )
                self.assertEqual(models.call_count, 2)

    # Function Name: test_one_missing_field_keeps_localized_fallback
    # Description:
    # - Accepts an answer with only diet guidance and fills the missing exercise field with
    #   the localized fallback, without a second request.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def test_one_missing_field_keeps_localized_fallback(self) -> None:
        models = _ScriptedModels('{"diet_recommendation":"diet"}')
        service = LLMService(ai_client=_FakeClient(models), timeout_seconds=1.0)

        recommendation = await service.requestHealthRecommendation(
            [{"item_name": "test-tablet"}],
            language="en",
        )

        self.assertEqual(recommendation["diet_recommendation"], "diet")
        self.assertEqual(
            recommendation["exercise_recommendation"],
            "Exercise recommendation could not be generated.",
        )
        self.assertEqual(models.call_count, 1)

    # Function Name: test_failed_first_attempt_is_retried_once
    # Description:
    # - Recovers from a blank response body or a provider error on the first attempt by
    #   asking once more within the same deadline.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def test_failed_first_attempt_is_retried_once(self) -> None:
        valid_answer = (
            '{"diet_recommendation":"diet","exercise_recommendation":"exercise",'
            '"caution_items":["caution"]}'
        )
        for first_answer in (None, "not-json", "[]", "{}", ConnectionError("reset")):
            with self.subTest(first_answer=first_answer):
                models = _ScriptedModels(first_answer, valid_answer)
                service = LLMService(
                    ai_client=_FakeClient(models),
                    timeout_seconds=1.0,
                )

                recommendation = await service.requestHealthRecommendation(
                    [{"item_name": "test-tablet"}],
                )

                self.assertEqual(recommendation["diet_recommendation"], "diet")
                self.assertEqual(recommendation["exercise_recommendation"], "exercise")
                self.assertEqual(models.call_count, 2)

    # Function Name: test_second_failure_keeps_stable_error
    # Description:
    # - Stops after the second failed attempt and reports the stable generation-failure
    #   message with the provider error as its cause.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def test_second_failure_keeps_stable_error(self) -> None:
        models = _ScriptedModels(ConnectionError("reset"), ConnectionError("reset"))
        service = LLMService(ai_client=_FakeClient(models), timeout_seconds=1.0)

        with self.assertRaises(RuntimeError) as context:
            await service.requestHealthRecommendation([{"item_name": "test-tablet"}])

        self.assertEqual(
            str(context.exception),
            "Health recommendation generation failed.",
        )
        self.assertIsInstance(context.exception.__cause__, ConnectionError)
        self.assertEqual(models.call_count, 2)

    # Function Name: test_timeout_is_not_retried
    # Description:
    # - Makes one request only when the provider call itself times out or the deadline
    #   passes while the first attempt is pending.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def test_timeout_is_not_retried(self) -> None:
        provider_timeout = _ScriptedModels(TimeoutError("provider deadline"), "{}")
        service = LLMService(ai_client=_FakeClient(provider_timeout), timeout_seconds=1.0)

        with self.assertRaisesRegex(RuntimeError, "timed out"):
            await service.requestHealthRecommendation([{"item_name": "test-tablet"}])

        self.assertEqual(provider_timeout.call_count, 1)

        pending = _StallingModels(failures_before_stall=0)
        service = LLMService(ai_client=_FakeClient(pending), timeout_seconds=0.02)

        with self.assertRaisesRegex(RuntimeError, "timed out"):
            await service.requestHealthRecommendation([{"item_name": "test-tablet"}])

        self.assertEqual(pending.call_count, 1)

    # Function Name: test_retry_shares_the_deadline
    # Description:
    # - Ends with the timeout error when the retry is still pending at the deadline that
    #   started before the first attempt.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def test_retry_shares_the_deadline(self) -> None:
        models = _StallingModels(failures_before_stall=1)
        service = LLMService(ai_client=_FakeClient(models), timeout_seconds=0.05)

        with self.assertRaises(RuntimeError) as context:
            await service.requestHealthRecommendation([{"item_name": "test-tablet"}])

        self.assertEqual(
            str(context.exception),
            "Health recommendation generation timed out.",
        )
        self.assertEqual(models.call_count, 2)


if __name__ == "__main__":
    unittest.main()
