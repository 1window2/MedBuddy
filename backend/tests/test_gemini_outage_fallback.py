# File Name: test_gemini_outage_fallback.py
# Role: Regression coverage proving the Claude fallback runs only after a Gemini outage and never alters the
#   Gemini path: results pass through untouched, other errors are re-raised as the same object, and a failed
#   fallback surfaces the original Gemini error.

import asyncio
import json
import sys
from types import SimpleNamespace
from typing import Any

import httpx
import pytest
from google.genai import errors as genai_errors
from google.genai import types

import services.gemini_outage_fallback as fallback_module
from api import dependencies
from boundaries.claude_fallback_boundary import (
    ClaudeFallbackError,
    ClaudeGenerateContentClient,
    to_claude_json_schema,
)
from boundaries.pill_identification_boundary import (
    PillVisionBoundary,
    PillVisionResponseError,
)
from boundaries.prescription_ocr_boundary import OCRServiceBoundary
from controls.input_prescription_control import InputPrescription
from core.config import settings
from services.gemini_outage_fallback import (
    GeminiOutageFallback,
    gemini_outage_reason,
    wrap_with_claude_fallback,
)

# A coroutine compiled with google.genai as its module name stands for a request in flight inside the SDK.
_GEMINI_FRAME_GLOBALS: dict[str, Any] = {"__name__": "google.genai._fake_models", "asyncio": asyncio, "httpx": httpx}
exec(
    "async def stalled_gemini_request():\n"
    "    await asyncio.sleep(10)\n"
    "async def gemini_connection_failure():\n"
    "    raise httpx.ConnectError('connection refused')\n",
    _GEMINI_FRAME_GLOBALS,
)
_stalled_gemini_request = _GEMINI_FRAME_GLOBALS["stalled_gemini_request"]
_gemini_connection_failure = _GEMINI_FRAME_GLOBALS["gemini_connection_failure"]


# Function Name: _server_error
# Description:
# - Build the Gemini SDK error for an HTTP status.
# Parameters:
# - code (int): HTTP status.
# Returns:
# - genai ServerError for 5xx, ClientError otherwise.
def _gemini_error(code: int) -> genai_errors.APIError:
    payload = {"error": {"code": code, "message": "provider message", "status": "STATUS"}}
    if code >= 500:
        return genai_errors.ServerError(code, payload)
    return genai_errors.ClientError(code, payload)


# Function Name: _no_retry_pause
# Description:
# - Skip the one-second pause before the Gemini retry so the suite stays fast.
@pytest.fixture(autouse=True)
def _no_retry_pause(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(fallback_module, "_GEMINI_RETRY_DELAY_SECONDS", 0.0)


# Function Name: _raised
# Description:
# - Raise an error from a cause and return it with its traceback, as a boundary would produce it.
# Parameters:
# - error (Exception): Outer error.
# - cause (BaseException | None): Error it is raised from.
# Returns:
# - The raised outer error.
def _raised(error: Exception, cause: BaseException | None = None) -> Exception:
    try:
        raise error from cause
    except Exception as raised:
        return raised


# Class Name: _Boundary
# Role: Primary or fallback boundary double with one wrapped and one plain method.
# Responsibilities:
# - Return a configured result or raise a configured error, and record calls.
# Attributes:
# - result (Any) / error (BaseException | None) / delay (float): Behaviour of analyse.
# - calls (list[tuple]): Recorded analyse arguments.
class _Boundary:
    def __init__(self, result: Any = None, error: BaseException | None = None, delay: float = 0.0) -> None:
        self.result = result
        self.error = error
        self.delay = delay
        self.calls: list[tuple[tuple[Any, ...], dict[str, Any]]] = []
        self.plain_value = "plain"

    async def analyse(self, *args: Any, **kwargs: Any) -> Any:
        self.calls.append((args, kwargs))
        if self.delay:
            await asyncio.sleep(self.delay)
        if self.error is not None:
            raise self.error
        return self.result

    async def other(self) -> str:
        raise _raised(RuntimeError("other failed"), _gemini_error(503))


# Function Name: _wrap
# Description:
# - Wrap a primary double with a factory that records whether it ran.
# Parameters:
# - primary (_Boundary): Gemini boundary double.
# - fallback (_Boundary | Exception): Fallback double, or an error the factory raises.
# Returns:
# - Wrapper and the list of factory calls.
def _wrap(primary: _Boundary, fallback: Any) -> tuple[GeminiOutageFallback, list[Any]]:
    built: list[Any] = []

    def factory(source: Any) -> Any:
        built.append(source)
        if isinstance(fallback, Exception):
            raise fallback
        return fallback

    wrapper = GeminiOutageFallback(
        primary,
        label="test",
        methods=frozenset({"analyse"}),
        fallback_factory=factory,
    )
    return wrapper, built


# Function Name: test_server_errors_and_rate_limits_are_outages
# Description:
# - A Gemini 5xx or 429 anywhere in the cause chain is an outage; other 4xx are not.
@pytest.mark.parametrize(
    ("code", "expected"),
    [(500, "gemini_500"), (503, "gemini_503"), (504, "gemini_504"), (429, "gemini_429"),
     (400, None), (403, None), (404, None)],
)
def test_server_errors_and_rate_limits_are_outages(code: int, expected: str | None) -> None:
    error = _raised(RuntimeError("AI 요약 처리 중 오류가 발생했습니다."), _gemini_error(code))
    assert gemini_outage_reason(error) == expected


# Function Name: test_non_gemini_errors_are_not_outages
# Description:
# - Format, quality, value and plain timeout errors never trigger the fallback.
@pytest.mark.parametrize(
    "error",
    [
        PillVisionResponseError("The visual analysis returned an invalid response."),
        ValueError("Masked prescription text is empty."),
        json.JSONDecodeError("bad", "{", 0),
        TimeoutError("Prescription OCR text service timed out."),
        httpx.ConnectError("refused"),
    ],
)
def test_non_gemini_errors_are_not_outages(error: Exception) -> None:
    assert gemini_outage_reason(_raised(RuntimeError("failed"), error)) is None


# Function Name: test_timeout_inside_the_gemini_request_is_an_outage
# Description:
# - A deadline whose cancellation landed inside the Gemini SDK counts, through asyncio.timeout and wait_for.
@pytest.mark.anyio
async def test_timeout_inside_the_gemini_request_is_an_outage() -> None:
    try:
        async with asyncio.timeout(0.01):
            await _stalled_gemini_request()
    except TimeoutError as exc:
        outer = _raised(TimeoutError("Pill visual analysis timed out."), exc)
    assert gemini_outage_reason(outer) == "gemini_timeout"

    try:
        await asyncio.wait_for(_stalled_gemini_request(), timeout=0.01)
    except TimeoutError as exc:
        wrapped = _raised(RuntimeError("Medication summary generation timed out."), exc)
    assert gemini_outage_reason(wrapped) == "gemini_timeout"


# Function Name: test_timeout_outside_the_gemini_request_is_not_an_outage
# Description:
# - A deadline spent waiting for capacity or preprocessing (outside the SDK) never triggers the fallback.
@pytest.mark.anyio
async def test_timeout_outside_the_gemini_request_is_not_an_outage() -> None:
    semaphore = asyncio.Semaphore(0)
    try:
        async with asyncio.timeout(0.01):
            await semaphore.acquire()
    except TimeoutError as exc:
        outer = _raised(TimeoutError("Pill visual analysis timed out."), exc)
    assert gemini_outage_reason(outer) is None


# Function Name: test_connection_failure_counts_only_inside_the_gemini_sdk
# Description:
# - An httpx connection error is an outage only when raised from within the Gemini SDK.
@pytest.mark.anyio
async def test_connection_failure_counts_only_inside_the_gemini_sdk() -> None:
    try:
        await _gemini_connection_failure()
    except httpx.ConnectError as exc:
        inside = _raised(RuntimeError("failed"), exc)
    assert gemini_outage_reason(inside) == "gemini_connection"
    assert gemini_outage_reason(_raised(RuntimeError("failed"), httpx.ConnectError("x"))) is None


# Function Name: test_gemini_success_passes_through_without_building_the_fallback
@pytest.mark.anyio
async def test_gemini_success_passes_through_without_building_the_fallback() -> None:
    result = object()
    primary = _Boundary(result=result)
    wrapper, built = _wrap(primary, _Boundary(result="claude"))

    assert await wrapper.analyse("text", flag=True) is result
    assert primary.calls == [(("text",), {"flag": True})]
    assert built == []


# Function Name: test_non_outage_error_is_reraised_as_the_same_object
@pytest.mark.anyio
async def test_non_outage_error_is_reraised_as_the_same_object() -> None:
    error = _raised(RuntimeError("AI 요약 처리 중 오류가 발생했습니다."), _gemini_error(400))
    primary = _Boundary(error=error)
    wrapper, built = _wrap(primary, _Boundary(result="claude"))

    with pytest.raises(RuntimeError) as caught:
        await wrapper.analyse("text")
    assert caught.value is error
    assert isinstance(caught.value.__cause__, genai_errors.ClientError)
    assert built == []


# Function Name: test_outage_is_served_by_the_fallback_with_the_same_arguments
@pytest.mark.anyio
async def test_outage_is_served_by_the_fallback_with_the_same_arguments() -> None:
    primary = _Boundary(error=_raised(RuntimeError("failed"), _gemini_error(503)))
    fallback = _Boundary(result="claude")
    wrapper, built = _wrap(primary, fallback)

    assert await wrapper.analyse("text", flag=True) == "claude"
    assert fallback.calls == [(("text",), {"flag": True})]
    assert built == [primary]
    assert await wrapper.analyse("again") == "claude"
    assert built == [primary]


# Function Name: test_failed_fallback_surfaces_the_original_gemini_error
@pytest.mark.anyio
@pytest.mark.parametrize("fallback", ["raises", "factory_raises"])
async def test_failed_fallback_surfaces_the_original_gemini_error(fallback: str) -> None:
    cause = _gemini_error(503)
    error = _raised(RuntimeError("failed"), cause)
    primary = _Boundary(error=error)
    replacement: Any = (
        _Boundary(error=ClaudeFallbackError("Claude stopped with refusal."))
        if fallback == "raises"
        else ImportError("anthropic")
    )
    wrapper, _ = _wrap(primary, replacement)

    with pytest.raises(RuntimeError) as caught:
        await wrapper.analyse("text")
    assert caught.value is error
    assert caught.value.__cause__ is cause


# Function Name: test_a_photo_verdict_from_the_fallback_is_its_answer
# Description:
# - During a Gemini outage the Claude copy can judge the photo itself ("no pill"); that verdict
#   propagates (HTTP 422 "retake") instead of the Gemini outage (HTTP 503, shown as a connection
#   problem). Found on the phone with an empty-palm photo. Other kinds keep hiding every error.
@pytest.mark.anyio
async def test_a_photo_verdict_from_the_fallback_is_its_answer() -> None:
    from boundaries.pill_identification_boundary import PillImageQualityError
    from services.gemini_outage_fallback import wrap_with_claude_fallback

    outage = _raised(RuntimeError("failed"), _gemini_error(503))
    verdict = PillImageQualityError("No separate pills were found.")
    wrapper = wrap_with_claude_fallback(object(), "pill_vision")
    object.__setattr__(wrapper, "_primary", _Boundary(error=outage))
    object.__setattr__(wrapper, "_methods", frozenset({"analyse"}))
    object.__setattr__(wrapper, "_fallback", _Boundary(error=verdict))
    with pytest.raises(PillImageQualityError) as caught:
        await wrapper.analyse("photo")
    assert caught.value is verdict

    other = wrap_with_claude_fallback(object(), "health_recommendation")
    object.__setattr__(other, "_primary", _Boundary(error=outage))
    object.__setattr__(other, "_methods", frozenset({"analyse"}))
    object.__setattr__(other, "_fallback", _Boundary(error=PillImageQualityError("x")))
    with pytest.raises(RuntimeError) as hidden:
        await other.analyse("text")
    assert hidden.value is outage


# Class Name: _FlakyBoundary
# Role: Gemini double that fails the first calls with a configured error, then answers.
class _FlakyBoundary(_Boundary):
    def __init__(self, failures: list[BaseException], result: Any = "gemini") -> None:
        super().__init__(result=result)
        self.failures = list(failures)

    async def analyse(self, *args: Any, **kwargs: Any) -> Any:
        self.calls.append((args, kwargs))
        if self.failures:
            raise self.failures.pop(0)
        return self.result


# Function Name: test_gemini_gets_one_retry_on_a_fast_failure_before_claude
# Description:
# - Owner's rule (2026-11-28): Gemini first. A fast 503/429 is retried once on Gemini; only a second
#   outage goes to Claude. A timeout goes to Claude at once (a retry would not fit the app's wait).
@pytest.mark.anyio
async def test_gemini_gets_one_retry_on_a_fast_failure_before_claude(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(fallback_module, "_GEMINI_RETRY_DELAY_SECONDS", 0.0)
    primary = _FlakyBoundary([_raised(RuntimeError("busy"), _gemini_error(503))])
    claude = _Boundary(result="claude")
    wrapper, built = _wrap(primary, claude)
    assert await wrapper.analyse("photo") == "gemini"
    assert len(primary.calls) == 2
    assert built == [] and claude.calls == []

    twice = _FlakyBoundary([_raised(RuntimeError("busy"), _gemini_error(503)),
                            _raised(RuntimeError("limit"), _gemini_error(429))])
    wrapper, built = _wrap(twice, claude)
    assert await wrapper.analyse("photo") == "claude"
    assert len(twice.calls) == 2

    try:
        await asyncio.wait_for(_stalled_gemini_request(), timeout=0.01)
    except TimeoutError as exc:
        timeout = _raised(TimeoutError("timed out"), exc)
    slow = _FlakyBoundary([timeout])
    wrapper, built = _wrap(slow, claude)
    assert await wrapper.analyse("photo") == "claude"
    assert len(slow.calls) == 1


# Function Name: test_fallback_never_runs_past_the_app_wait
@pytest.mark.anyio
async def test_fallback_never_runs_past_the_app_wait(monkeypatch: pytest.MonkeyPatch) -> None:
    error = _raised(RuntimeError("failed"), _gemini_error(503))
    monkeypatch.setattr(fallback_module, "_CALL_BUDGET_SECONDS", 0.05)
    monkeypatch.setattr(fallback_module, "_MIN_FALLBACK_SECONDS", 0.01)
    slow = _Boundary(result="claude", delay=1.0)
    wrapper, _ = _wrap(_Boundary(error=error), slow)
    with pytest.raises(RuntimeError) as caught:
        await wrapper.analyse("text")
    assert caught.value is error

    monkeypatch.setattr(fallback_module, "_MIN_FALLBACK_SECONDS", 1.0)
    unused = _Boundary(result="claude")
    wrapper, built = _wrap(_Boundary(error=error), unused)
    with pytest.raises(RuntimeError) as caught:
        await wrapper.analyse("text")
    assert caught.value is error
    assert built == [] and unused.calls == []


# Function Name: test_cancellation_and_other_attributes_are_untouched
@pytest.mark.anyio
async def test_cancellation_and_other_attributes_are_untouched() -> None:
    primary = _Boundary(error=asyncio.CancelledError())
    wrapper, built = _wrap(primary, _Boundary(result="claude"))
    with pytest.raises(asyncio.CancelledError):
        await wrapper.analyse("text")
    assert built == []

    assert wrapper.plain_value == "plain"
    wrapper.plain_value = "changed"
    assert primary.plain_value == "changed"
    with pytest.raises(RuntimeError, match="other failed"):
        await wrapper.other()
    assert built == []


# Class Name: _FakeAnthropic
# Role: AsyncAnthropic double recording beta.messages.create requests.
# Attributes:
# - requests (list[dict]): Recorded keyword arguments.
# - text (str) / stop_reason (str): Answer returned.
class _FakeAnthropic:
    def __init__(self, text: str, stop_reason: str = "end_turn") -> None:
        self.requests: list[dict[str, Any]] = []
        self.text = text
        self.stop_reason = stop_reason
        self.beta = SimpleNamespace(messages=SimpleNamespace(create=self._create))

    async def _create(self, **kwargs: Any) -> SimpleNamespace:
        self.requests.append(kwargs)
        return SimpleNamespace(
            stop_reason=self.stop_reason,
            content=[SimpleNamespace(type="thinking", thinking=""), SimpleNamespace(type="text", text=self.text)],
        )


# Function Name: _walk
# Description:
# - Yield every dictionary node of a schema.
def _walk(node: Any):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from _walk(value)


# Function Name: test_gemini_schemas_convert_to_the_claude_subset
@pytest.mark.parametrize(
    "schema",
    [
        PillVisionBoundary._RESPONSE_SCHEMA,
        PillVisionBoundary._MULTI_RESPONSE_SCHEMA,
        InputPrescription._PRESCRIPTION_RESPONSE_SCHEMA,
    ],
)
def test_gemini_schemas_convert_to_the_claude_subset(schema: dict[str, Any]) -> None:
    converted = to_claude_json_schema(schema)
    objects = 0
    for node in _walk(converted):
        if node.get("type") == "object":
            objects += 1
            assert node["additionalProperties"] is False
            assert set(node["required"]) <= set(node["properties"])
        if isinstance(node.get("type"), str):
            assert node["type"] == node["type"].lower()
    assert objects >= 1
    flattened = json.dumps(converted)
    for removed in ("minimum", "maximum", "minItems", "maxItems", "OBJECT", "STRING"):
        assert f'"{removed}"' not in flattened


# Function Name: test_claude_request_carries_images_schema_and_refusal_fallback
@pytest.mark.anyio
async def test_claude_request_carries_images_schema_and_refusal_fallback() -> None:
    fake = _FakeAnthropic('{"pills": []}')
    client = ClaudeGenerateContentClient(anthropic_client=fake, model_name="claude-opus-5-5", effort="low")
    image = b"\xff\xd8\xff\xe0jpeg"

    response = await client.aio.models.generate_content(
        model="gemini-3.1-flash-lite",
        contents=["Describe the pill.", types.Part.from_bytes(data=image, mime_type="image/jpeg")],
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema={"type": "OBJECT", "properties": {"pills": {"type": "ARRAY", "items": {"type": "STRING"}}}},
            temperature=0.0,
            max_output_tokens=512,
        ),
    )

    assert response.text == '{"pills": []}'
    request = fake.requests[0]
    assert request["model"] == "claude-opus-5-5"
    assert request["betas"] == ["server-side-fallback-2026-07-01"]
    assert request["fallbacks"] == "default"
    assert request["output_config"]["effort"] == "low"
    assert request["output_config"]["format"]["schema"]["additionalProperties"] is False
    assert "temperature" not in request
    content = request["messages"][0]["content"]
    assert content[0] == {"type": "text", "text": "Describe the pill."}
    assert content[1]["type"] == "image"
    assert content[1]["source"]["media_type"] == "image/jpeg"


# Function Name: test_json_without_schema_and_stopped_answers
@pytest.mark.anyio
async def test_json_without_schema_and_stopped_answers() -> None:
    fake = _FakeAnthropic('```json\n{"efficacy": "a"}\n```')
    client = ClaudeGenerateContentClient(anthropic_client=fake, model_name="m", effort="low")
    response = await client.aio.models.generate_content(
        model="g", contents="Summarize.", config={"response_mime_type": "application/json"},
    )
    assert json.loads(response.text) == {"efficacy": "a"}
    assert "JSON" in fake.requests[0]["system"]

    for text, stop in (('{"a": 1}', "refusal"), ('{"a": 1}', "max_tokens"), ("not json", "end_turn")):
        stopped = ClaudeGenerateContentClient(anthropic_client=_FakeAnthropic(text, stop), model_name="m", effort="low")
        with pytest.raises(ClaudeFallbackError):
            await stopped.aio.models.generate_content(
                model="g", contents="Summarize.", config={"response_mime_type": "application/json"},
            )


# Class Name: _FailingTextClient
# Role: Gemini prescription text adapter double raising a Gemini 503.
class _FailingTextClient:
    def __init__(self) -> None:
        self.calls = 0

    async def generate_text_content(self, **kwargs: Any) -> str:
        self.calls += 1
        raise _gemini_error(503)


# Function Name: test_prescription_outage_is_answered_by_a_separate_claude_copy
# Description:
# - On a Gemini 503 the real OCRServiceBoundary class answers through Claude with the same schema,
#   and the Claude copy still de-identifies the text at its last boundary.
@pytest.mark.anyio
async def test_prescription_outage_is_answered_by_a_separate_claude_copy(monkeypatch: pytest.MonkeyPatch) -> None:
    fake = _FakeAnthropic('{"hospital_name": "정보 없음", "prescription_date": "정보 없음", "medications": []}')
    monkeypatch.setattr(fallback_module, "get_claude_client", lambda: fake)
    failing = _FailingTextClient()
    primary = OCRServiceBoundary(
        client=object(),  # type: ignore[arg-type]
        model_name="gemini-3.1-flash-lite",
        response_schema=InputPrescription._PRESCRIPTION_RESPONSE_SCHEMA,
        gemini_text_client=failing,  # type: ignore[arg-type]
    )
    wrapper = wrap_with_claude_fallback(primary, "prescription_text")

    text = await wrapper.extractPrescriptionTextData("타이레놀정 500mg 1정 3회 3일\n주민번호 900101-1234567")

    assert json.loads(text)["medications"] == []
    # Gemini first: a fast 5xx gets one more Gemini attempt before Claude answers.
    assert failing.calls == 2
    request = fake.requests[0]
    sent = json.dumps(request["messages"], ensure_ascii=False)
    assert "타이레놀정" in sent
    assert "900101-1234567" not in sent
    schema = request["output_config"]["format"]["schema"]
    assert schema["required"] == ["hospital_name", "prescription_date", "medications"]


# Function Name: test_dependencies_install_the_wrapper_only_with_a_key
@pytest.mark.anyio
async def test_dependencies_install_the_wrapper_only_with_a_key(monkeypatch: pytest.MonkeyPatch) -> None:
    primary = _Boundary(result="gemini")
    monkeypatch.setattr(settings, "ANTHROPIC_API_KEY", "")
    monkeypatch.setattr(dependencies, "_claude_fallback_wrappers", {})
    assert dependencies._with_claude_fallback(primary, "pill_vision") is primary

    monkeypatch.setattr(settings, "ANTHROPIC_API_KEY", "test-key")
    wrapped = dependencies._with_claude_fallback(primary, "pill_vision")
    assert isinstance(wrapped, GeminiOutageFallback)
    assert dependencies._with_claude_fallback(primary, "pill_vision") is wrapped
    assert dependencies._with_claude_fallback(primary, "prescription_text") is not dependencies._with_claude_fallback(
        primary, "prescription_text"
    )
    assert await wrapped.analyse() == "gemini"


# Function Name: test_dependencies_fall_back_to_gemini_when_the_module_cannot_load
def test_dependencies_fall_back_to_gemini_when_the_module_cannot_load(monkeypatch: pytest.MonkeyPatch) -> None:
    primary = _Boundary(result="gemini")
    monkeypatch.setattr(settings, "ANTHROPIC_API_KEY", "test-key")
    monkeypatch.setattr(dependencies, "_claude_fallback_wrappers", {})
    monkeypatch.setitem(sys.modules, "services.gemini_outage_fallback", None)
    assert dependencies._with_claude_fallback(primary, "medication_summary") is primary

    monkeypatch.delitem(sys.modules, "services.gemini_outage_fallback")
    monkeypatch.setitem(sys.modules, "services.gemini_outage_fallback", fallback_module)
    assert dependencies._with_claude_fallback(primary, "unknown_kind") is primary


# Function Name: test_input_prescription_dependency_is_unchanged_without_a_key
def test_input_prescription_dependency_is_unchanged_without_a_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "ANTHROPIC_API_KEY", "")
    control = dependencies.get_input_prescription(db=None)  # type: ignore[arg-type]
    assert type(control.ocr_service_boundary) is OCRServiceBoundary
