# File Name: gemini_outage_fallback.py
# Role: Re-runs an AI boundary call through Claude only after Gemini itself timed out or reported an outage.
"""Outage-only Claude fallback wrapped around unchanged Gemini boundaries.

The Gemini path is never altered: the wrapped call runs exactly as before, its
result is returned untouched, and any error that is not a Gemini outage is
re-raised as the same exception object. Only a Gemini 5xx, a Gemini 429, a
connection failure inside the Gemini SDK, or a timeout whose cancellation
landed inside the Gemini SDK lets a separate Claude-backed copy of the boundary
answer instead. If that copy fails for any reason, the original Gemini error is
raised, so a defect in the fallback can only cost the fallback itself.
"""

import asyncio
import logging
from collections.abc import Callable
from threading import Lock
from types import TracebackType
from typing import Any

import httpx
from google.genai import errors as genai_errors

from core.config import settings

logger = logging.getLogger(__name__)

_GEMINI_MODULE_PREFIX = "google.genai"
_MAX_CHAIN_DEPTH = 16
_RATE_LIMITED = 429
# The app stops waiting for these requests after 45 seconds; the Claude answer must arrive before that,
# counted from the moment the Gemini call started, with a margin for the response itself.
_CALL_BUDGET_SECONDS = 40.0
_MIN_FALLBACK_SECONDS = 5.0

_client_lock = Lock()
_claude_client: Any = None


# Function Name: _traceback_enters_gemini_sdk
# Description:
# - Tell whether a traceback passes through a frame of the Gemini SDK, which places the failure inside the Gemini request.
# Parameters:
# - traceback (TracebackType | None): Traceback of one exception in the chain.
# Returns:
# - True when a frame's module belongs to google.genai.
def _traceback_enters_gemini_sdk(traceback: TracebackType | None) -> bool:
    while traceback is not None:
        module_name = traceback.tb_frame.f_globals.get("__name__", "")
        if isinstance(module_name, str) and module_name.startswith(_GEMINI_MODULE_PREFIX):
            return True
        traceback = traceback.tb_next
    return False


# Function Name: _exception_chain
# Description:
# - List an exception and the causes and contexts it was raised from, without loops and within a fixed depth.
# Parameters:
# - error (BaseException): Error raised by the Gemini boundary.
# Returns:
# - Exceptions from the outermost to the innermost.
def _exception_chain(error: BaseException) -> list[BaseException]:
    chain: list[BaseException] = []
    seen: set[int] = set()
    current: BaseException | None = error
    while current is not None and id(current) not in seen and len(chain) < _MAX_CHAIN_DEPTH:
        chain.append(current)
        seen.add(id(current))
        current = current.__cause__ or current.__context__
    return chain


# Function Name: gemini_outage_reason
# Description:
# - Classify a boundary error as a Gemini-side outage, or None when it is anything else.
# - Outages: a Gemini server error (5xx); a Gemini rate or quota refusal (429); an HTTP connection or timeout
#   failure raised inside the Gemini SDK; a deadline whose cancellation landed inside the Gemini SDK.
# - Not outages: bad requests and other 4xx, safety blocks, empty or malformed answers, image-quality refusals,
#   timeouts spent waiting in a queue or preprocessing an image, and every non-Gemini error.
# Parameters:
# - error (BaseException): Error raised by the Gemini boundary.
# Returns:
# - Short reason such as "gemini_503" or "gemini_timeout"; None when no fallback may run.
def gemini_outage_reason(error: BaseException) -> str | None:
    chain = _exception_chain(error)
    for item in chain:
        if isinstance(item, genai_errors.ServerError):
            return f"gemini_{item.code}"
        if isinstance(item, genai_errors.ClientError):
            return "gemini_429" if item.code == _RATE_LIMITED else None
    for item in chain:
        if isinstance(item, (httpx.TimeoutException, asyncio.CancelledError)):
            if _traceback_enters_gemini_sdk(item.__traceback__):
                return "gemini_timeout"
        elif isinstance(item, httpx.TransportError):
            if _traceback_enters_gemini_sdk(item.__traceback__):
                return "gemini_connection"
    return None


# Function Name: get_claude_client
# Description:
# - Lazily create the process-shared asynchronous Claude client; the SDK is imported only here.
# - SDK retries are off: each boundary copy keeps its own deadline and a retry would only spend it.
# Parameters:
# - None.
# Returns:
# - Shared AsyncAnthropic client.
def get_claude_client() -> Any:
    global _claude_client
    with _client_lock:
        if _claude_client is None:
            import anthropic

            _claude_client = anthropic.AsyncAnthropic(
                api_key=settings.ANTHROPIC_API_KEY.strip(),
                max_retries=0,
                timeout=60.0,
            )
        return _claude_client


# Function Name: build_claude_generate_content_client
# Description:
# - Create the Gemini-shaped Claude client used by the fallback boundary copies.
# Parameters:
# - None.
# Returns:
# - ClaudeGenerateContentClient on the shared SDK client.
def build_claude_generate_content_client() -> Any:
    from boundaries.claude_fallback_boundary import ClaudeGenerateContentClient

    return ClaudeGenerateContentClient(
        anthropic_client=get_claude_client(),
        model_name=settings.CLAUDE_FALLBACK_MODEL.strip(),
        effort=settings.CLAUDE_FALLBACK_EFFORT,
    )


# Class Name: GeminiOutageFallback
# Role:
# - Wraps one Gemini boundary so that named async methods fall back to a Claude copy on a Gemini outage.
# Responsibilities:
# - Delegate every attribute to the wrapped boundary; intercept only the named methods.
# - Return the Gemini result unchanged and re-raise non-outage errors as the same object.
# - Build the Claude copy lazily on the first outage and raise the original error if the copy fails.
# Attributes:
# - _primary (Any): Unchanged Gemini boundary.
# - _label (str): Boundary label for logs.
# - _methods (frozenset[str]): Async method names that may fall back.
# - _fallback_factory (Callable[[Any], Any]): Builds the Claude copy from the primary.
# - _fallback (Any): Cached Claude copy, or None until the first outage.
class GeminiOutageFallback:
    def __init__(
        self,
        primary: Any,
        *,
        label: str,
        methods: frozenset[str],
        fallback_factory: Callable[[Any], Any],
    ) -> None:
        object.__setattr__(self, "_primary", primary)
        object.__setattr__(self, "_label", label)
        object.__setattr__(self, "_methods", methods)
        object.__setattr__(self, "_fallback_factory", fallback_factory)
        object.__setattr__(self, "_fallback", None)
        object.__setattr__(self, "_fallback_lock", Lock())

    # Function Name: __getattr__
    # Description:
    # - Return the primary's attribute, or a fallback-guarded wrapper for a named async method.
    # Parameters:
    # - name (str): Attribute requested by the caller.
    # Returns:
    # - The primary's attribute or its guarded wrapper.
    def __getattr__(self, name: str) -> Any:
        attribute = getattr(self._primary, name)
        if name not in self._methods:
            return attribute

        async def guarded(*args: Any, **kwargs: Any) -> Any:
            started_at = asyncio.get_running_loop().time()
            try:
                return await attribute(*args, **kwargs)
            except Exception as primary_error:
                reason = gemini_outage_reason(primary_error)
                if reason is None:
                    raise
                outage = primary_error
            remaining = _CALL_BUDGET_SECONDS - (asyncio.get_running_loop().time() - started_at)
            return await self._serve_with_claude(name, reason, outage, remaining, args, kwargs)

        return guarded

    # Function Name: __setattr__
    # Description:
    # - Forward attribute writes to the primary so the wrapper never hides state from it.
    # Parameters:
    # - name (str): Attribute name.
    # - value (Any): New value.
    # Returns:
    # - None.
    def __setattr__(self, name: str, value: Any) -> None:
        setattr(self._primary, name, value)

    # Function Name: _get_fallback
    # Description:
    # - Build the Claude copy once and reuse it.
    # Parameters:
    # - None.
    # Returns:
    # - The Claude-backed boundary copy.
    def _get_fallback(self) -> Any:
        with self._fallback_lock:
            if self._fallback is None:
                object.__setattr__(self, "_fallback", self._fallback_factory(self._primary))
            return self._fallback

    # Function Name: _serve_with_claude
    # Description:
    # - Run the same method on the Claude copy within the time left before the app stops waiting.
    # - With too little time left, or on any failure, log the type only and raise the original Gemini error.
    # Parameters:
    # - name (str): Method name.
    # - reason (str): Outage classification.
    # - outage (Exception): Original Gemini error.
    # - remaining (float): Seconds left in the call budget.
    # - args (tuple[Any, ...]) / kwargs (dict[str, Any]): Original call arguments.
    # Returns:
    # - The Claude copy's result.
    async def _serve_with_claude(
        self,
        name: str,
        reason: str,
        outage: Exception,
        remaining: float,
        args: tuple[Any, ...],
        kwargs: dict[str, Any],
    ) -> Any:
        if remaining < _MIN_FALLBACK_SECONDS:
            logger.warning(
                "Gemini outage on %s.%s (%s); no time left for the Claude fallback.",
                self._label, name, reason,
            )
            raise outage
        logger.warning(
            "Gemini outage on %s.%s (%s); trying the Claude fallback.",
            self._label, name, reason,
        )
        try:
            async with asyncio.timeout(remaining):
                result = await getattr(self._get_fallback(), name)(*args, **kwargs)
        except Exception as fallback_error:
            logger.warning(
                "Claude fallback failed on %s.%s: %s",
                self._label, name, type(fallback_error).__name__,
            )
        else:
            logger.warning("Claude fallback served %s.%s.", self._label, name)
            return result
        raise outage


# Function Name: _summary_copy
# Description:
# - Build a Claude-backed MedicationSummaryGenerator with the primary's deadline.
# Parameters:
# - primary (Any): Gemini MedicationSummaryGenerator.
# Returns:
# - Separate MedicationSummaryGenerator instance.
def _summary_copy(primary: Any) -> Any:
    from boundaries.medication_summary_boundary import MedicationSummaryGenerator

    return MedicationSummaryGenerator(
        ai_client=build_claude_generate_content_client(),
        model_name=settings.CLAUDE_FALLBACK_MODEL.strip(),
        timeout_seconds=primary.timeout_seconds,
    )


# Function Name: _health_copy
# Description:
# - Build a Claude-backed LLMService with the primary's deadline.
# Parameters:
# - primary (Any): Gemini LLMService.
# Returns:
# - Separate LLMService instance.
def _health_copy(primary: Any) -> Any:
    from boundaries.llm_service_boundary import LLMService

    return LLMService(
        ai_client=build_claude_generate_content_client(),
        model_name=settings.CLAUDE_FALLBACK_MODEL.strip(),
        timeout_seconds=primary.timeout_seconds,
    )


# Function Name: _prescription_copy
# Description:
# - Build a Claude-backed OCRServiceBoundary with the primary's schema and deadline.
# Parameters:
# - primary (Any): Gemini OCRServiceBoundary.
# Returns:
# - Separate OCRServiceBoundary instance; its last-boundary de-identification still runs.
def _prescription_copy(primary: Any) -> Any:
    from boundaries.prescription_ocr_boundary import OCRServiceBoundary

    return OCRServiceBoundary(
        client=build_claude_generate_content_client(),
        model_name=settings.CLAUDE_FALLBACK_MODEL.strip(),
        response_schema=primary.response_schema,
        request_timeout_seconds=primary.request_timeout_seconds,
    )


# Function Name: _pill_vision_copy
# Description:
# - Build a Claude-backed PillVisionBoundary with the primary's deadline and its own capacity limits.
# Parameters:
# - primary (Any): Gemini PillVisionBoundary.
# Returns:
# - Separate PillVisionBoundary instance.
def _pill_vision_copy(primary: Any) -> Any:
    from boundaries.pill_identification_boundary import PillVisionBoundary

    return PillVisionBoundary(
        client=build_claude_generate_content_client(),
        model_name=settings.CLAUDE_FALLBACK_MODEL.strip(),
        timeout_seconds=primary.timeout_seconds,
    )


_BOUNDARY_SPECS: dict[str, tuple[frozenset[str], Callable[[Any], Any]]] = {
    "medication_summary": (frozenset({"summarize_advanced_item"}), _summary_copy),
    "health_recommendation": (frozenset({"requestHealthRecommendation"}), _health_copy),
    "prescription_text": (frozenset({"extractPrescriptionTextData"}), _prescription_copy),
    "pill_vision": (
        frozenset({"extractVisualFeatures", "extractMultipleVisualFeatures"}),
        _pill_vision_copy,
    ),
}


# Function Name: wrap_with_claude_fallback
# Description:
# - Wrap a Gemini boundary of a known kind with the outage-only Claude fallback.
# Parameters:
# - primary (Any): Unchanged Gemini boundary.
# - kind (str): One of medication_summary, health_recommendation, prescription_text, pill_vision.
# Returns:
# - GeminiOutageFallback around the primary; raises KeyError for an unknown kind.
def wrap_with_claude_fallback(primary: Any, kind: str) -> GeminiOutageFallback:
    methods, factory = _BOUNDARY_SPECS[kind]
    return GeminiOutageFallback(
        primary,
        label=kind,
        methods=methods,
        fallback_factory=factory,
    )
