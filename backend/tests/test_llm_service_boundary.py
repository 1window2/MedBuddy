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


class _BlockingModels:
    def __init__(self) -> None:
        self.cancelled = False

    async def generate_content(self, **kwargs: object) -> object:
        try:
            await asyncio.Event().wait()
        except asyncio.CancelledError:
            self.cancelled = True
            raise


class _RespondingModels:
    def __init__(self) -> None:
        self.request: dict[str, object] = {}

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


class _FakeClient:
    def __init__(self, models: object) -> None:
        self.aio = type("Aio", (), {"models": models})()


class LLMServiceTimeoutTest(unittest.IsolatedAsyncioTestCase):
    def test_timeout_uses_configured_default(self) -> None:
        with patch.object(settings, "HEALTH_RECOMMENDATION_TIMEOUT_SECONDS", 0.25):
            service = LLMService(ai_client=object())

        self.assertEqual(service.timeout_seconds, 0.25)

    def test_rejects_unbounded_timeout(self) -> None:
        for timeout_seconds in (0.0, -1.0, float("nan"), float("inf")):
            with self.subTest(timeout_seconds=timeout_seconds):
                with self.assertRaisesRegex(ValueError, "finite and positive"):
                    LLMService(
                        ai_client=object(),
                        timeout_seconds=timeout_seconds,
                    )

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
