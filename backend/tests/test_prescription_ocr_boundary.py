import asyncio
import threading
from typing import Any

import pytest
from google.genai import types

from boundaries.prescription_ocr_boundary import GeminiVisionAPI, OCRServiceBoundary


class _RecordingImageProcessingBoundary:
    def __init__(self) -> None:
        self.thread_id: int | None = None

    def preprocessPrescriptionImage(self, image: bytes) -> bytes:
        self.thread_id = threading.get_ident()
        return b"processed-image"


class _RecordingGeminiVisionAPI:
    async def requestStructuredExtraction(
        self,
        *,
        client: object,
        model_name: str,
        prompt: str,
        processed_image: bytes,
        response_schema: dict[str, Any],
    ) -> str:
        assert processed_image == b"processed-image"
        return "{}"


class _SlowGeminiVisionAPI:
    async def requestStructuredExtraction(
        self,
        **_kwargs: object,
    ) -> str:
        await asyncio.sleep(1)
        return "{}"


class _FakeGeminiResponse:
    text = "{}"


class _RecordingGeminiModels:
    def __init__(self) -> None:
        self.last_request: dict[str, Any] | None = None

    async def generate_content(self, **kwargs: Any) -> _FakeGeminiResponse:
        self.last_request = kwargs
        return _FakeGeminiResponse()


class _RecordingGeminiClient:
    def __init__(self) -> None:
        self.models = _RecordingGeminiModels()
        self.aio = type("FakeAio", (), {"models": self.models})()


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.mark.anyio
async def test_image_preprocessing_runs_outside_the_event_loop_thread() -> None:
    image_processing_boundary = _RecordingImageProcessingBoundary()
    event_loop_thread_id = threading.get_ident()
    ocr_boundary = OCRServiceBoundary(
        client=object(),  # type: ignore[arg-type]
        model_name="test-model",
        response_schema={},
        image_processing_boundary=image_processing_boundary,
        gemini_vision_api=_RecordingGeminiVisionAPI(),  # type: ignore[arg-type]
    )

    response = await ocr_boundary.extractText(b"source-image")

    assert response == "{}"
    assert image_processing_boundary.thread_id is not None
    assert image_processing_boundary.thread_id != event_loop_thread_id


@pytest.mark.anyio
async def test_structured_extraction_is_bounded_by_boundary_timeout() -> None:
    ocr_boundary = OCRServiceBoundary(
        client=object(),  # type: ignore[arg-type]
        model_name="test-model",
        response_schema={},
        image_processing_boundary=_RecordingImageProcessingBoundary(),
        gemini_vision_api=_SlowGeminiVisionAPI(),  # type: ignore[arg-type]
        request_timeout_seconds=0.01,
    )

    with pytest.raises(TimeoutError, match="OCR service timed out"):
        await ocr_boundary.extractText(b"source-image")


@pytest.mark.anyio
async def test_structured_extraction_uses_low_latency_high_resolution_config() -> None:
    client = _RecordingGeminiClient()

    response = await GeminiVisionAPI().requestStructuredExtraction(
        client=client,  # type: ignore[arg-type]
        model_name="test-model",
        prompt="extract",
        processed_image=b"processed-image",
        response_schema={},
    )

    assert response == "{}"
    assert client.models.last_request is not None
    config = client.models.last_request["config"]
    assert config.thinking_config.thinking_level == types.ThinkingLevel.MINIMAL
    assert (
        config.media_resolution
        == types.MediaResolution.MEDIA_RESOLUTION_HIGH
    )
    assert config.max_output_tokens == 2048
