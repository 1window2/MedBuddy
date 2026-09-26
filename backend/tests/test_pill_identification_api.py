# File Name: test_pill_identification_api.py
# Role: Regression coverage for pill multipart uploads, request-body limits, and mandatory
#   confirmation contracts.
import os
import sys
from pathlib import Path
from typing import Any

import httpx
import pytest
from pydantic import ValidationError
from starlette.types import Message, Receive, Scope, Send

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from api.dependencies import get_identify_pill, get_registered_principal  # noqa: E402
from core.request_limits import RequestBodyLimitMiddleware  # noqa: E402
from boundaries.pill_identification_boundary import MAX_PILL_IMAGE_BYTES  # noqa: E402
from entities.authenticated_principal_entity import AuthenticatedPrincipal  # noqa: E402
from entities.pill_identification_entity import (  # noqa: E402
    PillIdentificationCandidate,
    PillIdentificationResult,
    PillVisualFeatures,
)
from main import create_app  # noqa: E402
from schemas.pill_identification import PillIdentificationResponse  # noqa: E402


# Class Name: _RecordingIdentifyPill
# Role: Pill identification double that captures both image sides and returns one confident
#   authoritative candidate.
# Responsibilities:
# - Captures uploaded image bytes and returns a fixed two-sided observation with one
#   perfect-match candidate.
# Attributes:
# - front_image (bytes): Captured front-side upload bytes.
# - back_image (bytes | None): Captured optional back-side upload bytes.
class _RecordingIdentifyPill:
    # Function Name: __init__
    # Description:
    # - Initializes empty front-image bytes and an absent optional back image.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.front_image = b""
        self.back_image: bytes | None = None

    # Function Name: requestPillIdentification
    # Description:
    # - Captures uploaded image bytes and returns a fixed two-sided observation with one
    #   perfect-match candidate.
    # Parameters:
    # - front_image (bytes): Front-side pill photograph bytes.
    # - back_image (bytes | None): Optional back-side pill photograph bytes.
    # Returns:
    # - PillIdentificationResult: Confident candidate result that still requires user
    #   confirmation.
    async def requestPillIdentification(
        self,
        front_image: bytes,
        back_image: bytes | None = None,
    ) -> PillIdentificationResult:
        self.front_image = front_image
        self.back_image = back_image
        return PillIdentificationResult(
            observed_features=PillVisualFeatures(
                shape="round",
                colors=("yellow",),
                front_imprint="YH",
                back_imprint="LT",
            ),
            candidates=(
                PillIdentificationCandidate(
                    item_seq="200808877",
                    item_name="Test pill",
                    entp_name="Test manufacturer",
                    image_url="https://nedrug.mfds.go.kr/pill.jpg",
                    shape="round",
                    colors=("yellow",),
                    print_front="YH",
                    print_back="LT",
                    match_score=1.0,
                    matched_attributes=("shape", "color", "imprint"),
                ),
            ),
            is_confident=True,
        )


# Function Name: _scope
# Description:
# - Builds a minimal HTTP POST scope with an optional Content-Length for body-limit tests.
# Parameters:
# - content_length (int | None): Declared request length, or no Content-Length header.
# Returns:
# - Scope: HTTP POST ASGI scope with an optional declared body length.
def _scope(*, content_length: int | None = None) -> Scope:
    headers = []
    if content_length is not None:
        headers.append((b"content-length", str(content_length).encode("ascii")))
    return {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "POST",
        "scheme": "http",
        "path": "/limited",
        "raw_path": b"/limited",
        "query_string": b"",
        "root_path": "",
        "headers": headers,
        "client": ("127.0.0.1", 1234),
        "server": ("test", 80),
    }


# Function Name: test_request_body_limit_rejects_declared_oversize_before_app
# Description:
# - Rejects an oversized declared body with HTTP 413 before invoking the downstream app.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_request_body_limit_rejects_declared_oversize_before_app() -> None:
    app_called = False

    # Function Name: app
    # Description:
    # - Records whether the downstream app was reached despite an oversized declared
    #   request.
    # Parameters:
    # - _scope (Scope): ASGI connection/request scope; unused by the downstream double.
    # - _receive (Receive): ASGI callable providing request-body events. Unused by this
    #   double.
    # - _send (Send): ASGI callable receiving response events. Unused by this double.
    # Returns:
    # - None.
    async def app(_scope: Scope, _receive: Receive, _send: Send) -> None:
        nonlocal app_called
        app_called = True

    # Function Name: receive
    # Description:
    # - Supplies an ASGI disconnect event for the declared-size rejection path.
    # Parameters:
    # - None.
    # Returns:
    # - Message: ASGI disconnect event.
    async def receive() -> Message:
        return {"type": "http.disconnect"}

    sent: list[Message] = []

    # Function Name: send
    # Description:
    # - Collects response messages for declared-size status assertions.
    # Parameters:
    # - message (Message): ASGI response event captured for status and header assertions.
    # Returns:
    # - None.
    async def send(message: Message) -> None:
        sent.append(message)

    middleware = RequestBodyLimitMiddleware(app, limits={"/limited": 10})

    await middleware(_scope(content_length=11), receive, send)

    assert app_called is False
    assert sent[0]["type"] == "http.response.start"
    assert sent[0]["status"] == 413


# Function Name: test_request_body_limit_counts_streamed_chunks
# Description:
# - Counts streamed chunks and returns 413 when the combined body exceeds the limit.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_request_body_limit_counts_streamed_chunks() -> None:
    messages = iter(
        (
            {"type": "http.request", "body": b"123456", "more_body": True},
            {"type": "http.request", "body": b"78901", "more_body": False},
        )
    )

    # Function Name: receive
    # Description:
    # - Feeds the next preconfigured request chunk to the body-limit middleware.
    # Parameters:
    # - None.
    # Returns:
    # - Message: Next configured ASGI request-body chunk.
    async def receive() -> Message:
        return next(messages)  # type: ignore[return-value]

    # Function Name: drain_app
    # Description:
    # - Drains all request chunks and sends a success response only if the middleware
    #   permits the complete body.
    # Parameters:
    # - _scope (Scope): ASGI connection/request scope; unused by the downstream double.
    # - app_receive (Receive): Middleware-wrapped ASGI request receiver.
    # - send (Send): ASGI callable receiving response events.
    # Returns:
    # - None.
    async def drain_app(_scope: Scope, app_receive: Receive, send: Send) -> None:
        while True:
            message = await app_receive()
            if not message.get("more_body", False):
                break
        await send({"type": "http.response.start", "status": 200, "headers": []})
        await send({"type": "http.response.body", "body": b""})

    sent: list[Message] = []

    # Function Name: send
    # Description:
    # - Collects response messages to inspect the streamed-body rejection status.
    # Parameters:
    # - message (Message): ASGI response event captured for status and header assertions.
    # Returns:
    # - None.
    async def send(message: Message) -> None:
        sent.append(message)

    middleware = RequestBodyLimitMiddleware(
        drain_app,
        limits={"/limited": 10},
    )

    await middleware(_scope(), receive, send)

    assert sent[0]["type"] == "http.response.start"
    assert sent[0]["status"] == 413


# Function Name: test_request_body_limit_applies_default_to_json_routes
# Description:
# - Applies the default body-size limit to JSON routes and rejects oversize before calling the
#   app.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_request_body_limit_applies_default_to_json_routes() -> None:
    app_called = False

    # Function Name: app
    # Description:
    # - Records whether an oversized JSON request reaches the downstream app.
    # Parameters:
    # - _scope (Scope): ASGI connection/request scope; unused by the downstream double.
    # - _receive (Receive): ASGI callable providing request-body events. Unused by this
    #   double.
    # - _send (Send): ASGI callable receiving response events. Unused by this double.
    # Returns:
    # - None.
    async def app(_scope: Scope, _receive: Receive, _send: Send) -> None:
        nonlocal app_called
        app_called = True

    # Function Name: receive
    # Description:
    # - Supplies an ASGI disconnect event for the JSON body-limit test.
    # Parameters:
    # - None.
    # Returns:
    # - Message: ASGI disconnect event.
    async def receive() -> Message:
        return {"type": "http.disconnect"}

    sent: list[Message] = []

    # Function Name: send
    # Description:
    # - Collects the JSON-route response messages for HTTP 413 assertions.
    # Parameters:
    # - message (Message): ASGI response event captured for status and header assertions.
    # Returns:
    # - None.
    async def send(message: Message) -> None:
        sent.append(message)

    middleware = RequestBodyLimitMiddleware(
        app,
        limits={},
        default_limit=10,
    )

    await middleware(_scope(content_length=11), receive, send)

    assert app_called is False
    assert sent[0]["type"] == "http.response.start"
    assert sent[0]["status"] == 413


# Function Name: test_request_body_limit_applies_default_to_delete_json_routes
# Description:
# - Applies the default body limit to DELETE JSON requests before the downstream app is called.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_request_body_limit_applies_default_to_delete_json_routes() -> None:
    app_called = False

    # Function Name: app
    # Description:
    # - Records unexpected downstream execution for an oversized DELETE request.
    # Parameters:
    # - _scope (Scope): ASGI connection/request scope; unused by the downstream double.
    # - _receive (Receive): ASGI callable providing request-body events. Unused by this
    #   double.
    # - _send (Send): ASGI callable receiving response events. Unused by this double.
    # Returns:
    # - None.
    async def app(_scope: Scope, _receive: Receive, _send: Send) -> None:
        nonlocal app_called
        app_called = True

    # Function Name: receive
    # Description:
    # - Supplies the disconnect event for the DELETE body-limit rejection path.
    # Parameters:
    # - None.
    # Returns:
    # - Message: ASGI disconnect event.
    async def receive() -> Message:
        return {"type": "http.disconnect"}

    sent: list[Message] = []

    # Function Name: send
    # Description:
    # - Collects DELETE response messages for the oversize status assertion.
    # Parameters:
    # - message (Message): ASGI response event captured for status and header assertions.
    # Returns:
    # - None.
    async def send(message: Message) -> None:
        sent.append(message)

    middleware = RequestBodyLimitMiddleware(app, limits={}, default_limit=10)
    scope = _scope(content_length=11)
    scope["method"] = "DELETE"

    await middleware(scope, receive, send)

    assert app_called is False
    assert sent[0]["status"] == 413


# Function Name: test_pill_identification_accepts_front_and_optional_back_multipart
# Description:
# - Accepts front and optional back multipart images while preserving candidate identity,
#   same-pill status, confidence, and mandatory confirmation.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_pill_identification_accepts_front_and_optional_back_multipart() -> None:
    control = _RecordingIdentifyPill()
    app = create_app()
    app.dependency_overrides[get_identify_pill] = lambda: control
    app.dependency_overrides[get_registered_principal] = (
        AuthenticatedPrincipal.development_principal
    )

    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.post(
            "/api/v1/medication/pill-identification/candidates",
            files={
                "front": ("front.jpg", b"front-image", "image/jpeg"),
                "back": ("back.jpg", b"back-image", "image/jpeg"),
            },
        )

    assert response.status_code == 200
    assert control.front_image == b"front-image"
    assert control.back_image == b"back-image"
    payload: dict[str, Any] = response.json()
    assert payload["is_confident"] is True
    assert payload["requires_confirmation"] is True
    assert payload["observed_features"]["same_pill"] is True
    assert payload["data"][0]["item_seq"] == "200808877"


# Function Name: test_application_wiring_rejects_oversized_pill_multipart
# Description:
# - Requires the fully wired app to reject an oversized pill multipart upload with HTTP 413.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_application_wiring_rejects_oversized_pill_multipart() -> None:
    app = create_app()
    production_limit = (2 * MAX_PILL_IMAGE_BYTES) + (512 * 1024)

    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.post(
            "/api/v1/medication/pill-identification/candidates",
            content=b"--boundary--\r\n",
            headers={
                "content-type": "multipart/form-data; boundary=boundary",
                "content-length": str(production_limit + 1),
            },
        )

    assert response.status_code == 413


# Function Name: test_response_contract_always_requires_confirmation
# Description:
# - Requires unsuccessful empty responses to stay nonconfident and always require confirmation,
#   rejecting an unsafe response schema.
# Parameters:
# - None.
# Returns:
# - None.
def test_response_contract_always_requires_confirmation() -> None:
    response = PillIdentificationResponse.from_domain(
        PillIdentificationResult(
            observed_features=PillVisualFeatures(),
            candidates=(),
        )
    )

    assert response.success is False
    assert response.is_confident is False
    assert response.requires_confirmation is True

    with pytest.raises(ValidationError):
        PillIdentificationResponse.model_validate(
            {
                "success": False,
                "message": "No matching pill candidates were found.",
                "requires_confirmation": False,
                "observed_features": {},
                "data": [],
            }
        )


# Function Name: test_domain_result_rejects_unsafe_confirmation_states
# Description:
# - Rejects domain results that disable confirmation or claim confidence without candidates.
# Parameters:
# - None.
# Returns:
# - None.
def test_domain_result_rejects_unsafe_confirmation_states() -> None:
    with pytest.raises(ValueError, match="always requires confirmation"):
        PillIdentificationResult(
            observed_features=PillVisualFeatures(),
            requires_confirmation=False,  # type: ignore[arg-type]
        )

    with pytest.raises(ValueError, match="cannot be confident"):
        PillIdentificationResult(
            observed_features=PillVisualFeatures(),
            is_confident=True,
        )


# Function Name: anyio_backend
# Description:
# - Selects asyncio for the ASGI and multipart asynchronous tests.
# Parameters:
# - None.
# Returns:
# - str: 'asyncio', the event loop backend selected for the test.
@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
