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


if __name__ == "__main__":
    unittest.main()
