# File Name: test_prescription_ocr_boundary.py
# Role: Verifies the de-identified prescription text boundary and Gemini request.

import asyncio
from typing import Any

import pytest
from google.genai import types

from boundaries.prescription_ocr_boundary import (
    GeminiPrescriptionTextClient,
    OCRServiceBoundary,
)


class _RecordingPrescriptionTextClient:
    def __init__(self) -> None:
        self.masked_text = ""

    async def generate_text_content(
        self,
        *,
        client: object,
        model_name: str,
        prompt: str,
        masked_text: str,
        response_schema: dict[str, Any],
    ) -> str:
        self.masked_text = masked_text
        return "{}"


class _SlowPrescriptionTextClient:
    async def generate_text_content(self, **_kwargs: object) -> str:
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


# Function Name: test_text_extraction_normalizes_input_before_delegation
# Description:
# - Verifies that only normalized, de-identified text reaches Gemini.
# Returns:
# - None.
@pytest.mark.anyio
async def test_text_extraction_normalizes_input_before_delegation() -> None:
    text_client = _RecordingPrescriptionTextClient()
    boundary = OCRServiceBoundary(
        client=object(),  # type: ignore[arg-type]
        model_name="test-model",
        response_schema={},
        gemini_text_client=text_client,  # type: ignore[arg-type]
    )

    response = await boundary.extractPrescriptionTextData("  masked text  ")

    assert response == "{}"
    assert text_client.masked_text == "masked text"


# Function Name: test_text_extraction_rejects_empty_input
# Description:
# - Prevents empty requests from consuming the external AI quota.
# Returns:
# - None.
@pytest.mark.anyio
async def test_text_extraction_rejects_empty_input() -> None:
    boundary = OCRServiceBoundary(
        client=object(),  # type: ignore[arg-type]
        model_name="test-model",
        response_schema={},
    )

    with pytest.raises(ValueError, match="empty"):
        await boundary.extractPrescriptionTextData("  ")


# Function Name: test_text_extraction_is_bounded_by_boundary_timeout
# Description:
# - Verifies that stalled Gemini text analysis cannot run indefinitely.
# Returns:
# - None.
@pytest.mark.anyio
async def test_text_extraction_is_bounded_by_boundary_timeout() -> None:
    boundary = OCRServiceBoundary(
        client=object(),  # type: ignore[arg-type]
        model_name="test-model",
        response_schema={},
        gemini_text_client=_SlowPrescriptionTextClient(),  # type: ignore[arg-type]
        request_timeout_seconds=0.01,
    )

    with pytest.raises(TimeoutError, match="text service timed out"):
        await boundary.extractPrescriptionTextData("masked text")


# Function Name: test_timeout_does_not_log_request_configuration
# Description:
# - Ensures a timeout does not expose model or prescription request details.
# Returns:
# - None.
@pytest.mark.anyio
async def test_timeout_does_not_log_request_configuration(
    caplog: pytest.LogCaptureFixture,
) -> None:
    boundary = OCRServiceBoundary(
        client=object(),  # type: ignore[arg-type]
        model_name="sensitive-test-model",
        response_schema={},
        gemini_text_client=_SlowPrescriptionTextClient(),  # type: ignore[arg-type]
        request_timeout_seconds=0.01,
    )

    with pytest.raises(TimeoutError, match="text service timed out"):
        await boundary.extractPrescriptionTextData("masked text")

    records = [
        record
        for record in caplog.records
        if record.name == "boundaries.prescription_ocr_boundary"
    ]
    assert records == []


# Function Name: test_structured_text_request_uses_low_latency_config
# Description:
# - Keeps the text-only Gemini request deterministic and output-bounded.
# Returns:
# - None.
@pytest.mark.anyio
async def test_structured_text_request_uses_low_latency_config() -> None:
    client = _RecordingGeminiClient()

    response = await GeminiPrescriptionTextClient().generate_text_content(
        client=client,  # type: ignore[arg-type]
        model_name="test-model",
        prompt="extract",
        masked_text="masked text",
        response_schema={},
    )

    assert response == "{}"
    assert client.models.last_request is not None
    assert client.models.last_request["contents"] == ["extract", "masked text"]
    config = client.models.last_request["config"]
    assert config.thinking_config.thinking_level == types.ThinkingLevel.MINIMAL
    assert config.max_output_tokens == 2048


# Function Name: test_text_prompt_preserves_the_privacy_boundary
# Description:
# - Verifies that the prompt forbids reconstructing images or removed identifiers.
# Returns:
# - None.
def test_text_prompt_preserves_the_privacy_boundary() -> None:
    prompt = OCRServiceBoundary._masked_text_extraction_prompt()

    assert "원본 이미지나 제거된 개인정보를 추측하지 말고" in prompt
    assert "반드시 지정된 JSON 스키마로만 반환하세요" in prompt
