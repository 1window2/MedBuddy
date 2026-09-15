# File Name: test_prescription_ocr_boundary.py
# Role: Regression coverage for text-only prescription analysis, bounded Gemini requests, and
#   privacy-safe failures.

import asyncio
from typing import Any

import pytest
from google.genai import types

from boundaries.prescription_ocr_boundary import (
    GeminiPrescriptionTextClient,
    OCRServiceBoundary,
)


# Class Name: _RecordingPrescriptionTextClient
# Role: Prescription text client double recording the masked text passed across the
#   external-analysis boundary.
# Responsibilities:
# - Captures masked text and returns empty JSON without using the Gemini client or prompt.
# Attributes:
# - masked_text (str): De-identified prescription text captured at the AI boundary.
class _RecordingPrescriptionTextClient:
    # Function Name: __init__
    # Description:
    # - Initializes empty captured prescription text before delegation.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.masked_text = ""

    # Function Name: generate_text_content
    # Description:
    # - Captures masked text and returns empty JSON without using the Gemini client or
    #   prompt.
    # Parameters:
    # - client (object): Injected Gemini client; no real service is used by this double.
    # - model_name (str): Gemini model selected for text analysis.
    # - prompt (str): Instruction text accompanying the masked prescription input.
    # - masked_text (str): De-identified prescription text allowed across the AI boundary.
    # - response_schema (dict[str, Any]): JSON schema constraining prescription analysis
    #   output.
    # Returns:
    # - str: '{}', the empty structured response when the simulated call completes.
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


# Class Name: _SlowPrescriptionTextClient
# Role: Slow prescription text client double used to force boundary timeouts.
# Responsibilities:
# - Delays an empty JSON response so a short text-analysis deadline expires.
class _SlowPrescriptionTextClient:
    # Function Name: generate_text_content
    # Description:
    # - Delays an empty JSON response so a short text-analysis deadline expires.
    # Parameters:
    # - **_kwargs (object): Keyword arguments accepted by the substituted service interface.
    # Returns:
    # - str: '{}', the empty structured response when the simulated call completes.
    async def generate_text_content(self, **_kwargs: object) -> str:
        await asyncio.sleep(1)
        return "{}"


# Class Name: _FakeGeminiResponse
# Role: Gemini response double exposing an empty JSON text payload.
# Responsibilities:
# - Gemini response double exposing an empty JSON text payload.
# Attributes:
# - text (str): Text payload exposed by the Gemini-compatible response.
class _FakeGeminiResponse:
    text = "{}"


# Class Name: _RecordingGeminiModels
# Role: Gemini models double recording structured text request contents and configuration.
# Responsibilities:
# - Records the complete Gemini request and returns an empty JSON response object.
# Attributes:
# - last_request (dict[str, Any] | None): Most recently captured Gemini request; initially
#   absent.
class _RecordingGeminiModels:
    # Function Name: __init__
    # Description:
    # - Marks the last Gemini request absent until text analysis is invoked.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.last_request: dict[str, Any] | None = None

    # Function Name: generate_content
    # Description:
    # - Records the complete Gemini request and returns an empty JSON response object.
    # Parameters:
    # - **kwargs (Any): Keyword arguments accepted by the substituted service interface.
    # Returns:
    # - _FakeGeminiResponse: Gemini-compatible response carrying the configured analysis
    #   JSON.
    async def generate_content(self, **kwargs: Any) -> _FakeGeminiResponse:
        self.last_request = kwargs
        return _FakeGeminiResponse()


# Class Name: _RecordingGeminiClient
# Role: Gemini client double exposing one recording model through synchronous and asynchronous
#   namespaces.
# Responsibilities:
# - Gemini client double exposing one recording model through synchronous and asynchronous
#   namespaces.
# Attributes:
# - models (_RecordingGeminiModels): Recording Gemini-compatible model interface.
# - aio (object): Gemini-compatible asynchronous namespace or owned async client.
class _RecordingGeminiClient:
    # Function Name: __init__
    # Description:
    # - Creates the recording models object and connects it to the async SDK access path.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.models = _RecordingGeminiModels()
        self.aio = type("FakeAio", (), {"models": self.models})()


# Function Name: anyio_backend
# Description:
# - Selects asyncio for prescription text-boundary tests.
# Parameters:
# - None.
# Returns:
# - str: 'asyncio', the event loop backend selected for the test.
@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


# Function Name: test_text_extraction_normalizes_input_before_delegation
# Description:
# - Requires normalized, de-identified prescription text to reach the external client and
#   preserves its JSON response.
# Parameters:
# - None.
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
# - Rejects empty prescription text before it can consume external AI quota.
# Parameters:
# - None.
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
# - Raises the stable text-service timeout when stalled analysis exceeds the boundary deadline.
# Parameters:
# - None.
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
# - Raises a timeout without logging request configuration or prescription details.
# Parameters:
# - caplog (pytest.LogCaptureFixture): Pytest log capture used to check sensitive-data exposure.
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
# - Uses only prompt and masked text as content, minimal thinking, and a 2048-token output bound
#   for structured analysis.
# Parameters:
# - None.
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
# - Requires the prompt to forbid reconstructing images or removed identifiers and to demand the
#   designated JSON schema.
# Parameters:
# - None.
# Returns:
# - None.
def test_text_prompt_preserves_the_privacy_boundary() -> None:
    prompt = OCRServiceBoundary._masked_text_extraction_prompt()

    assert "원본 이미지나 제거된 개인정보를 추측하지 말고" in prompt
    assert "반드시 지정된 JSON 스키마로만 반환하세요" in prompt
