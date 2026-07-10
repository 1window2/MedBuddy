import threading
from typing import Any

import pytest

from boundaries.prescription_ocr_boundary import OCRServiceBoundary


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
