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

from api.dependencies import get_identify_pill  # noqa: E402
from core.request_limits import RequestBodyLimitMiddleware  # noqa: E402
from boundaries.pill_identification_boundary import MAX_PILL_IMAGE_BYTES  # noqa: E402
from entities.pill_identification_entity import (  # noqa: E402
    PillIdentificationCandidate,
    PillIdentificationResult,
    PillVisualFeatures,
)
from main import create_app  # noqa: E402
from schemas.pill_identification import PillIdentificationResponse  # noqa: E402


class _RecordingIdentifyPill:
    def __init__(self) -> None:
        self.front_image = b""
        self.back_image: bytes | None = None

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
                    image_url="https://example.test/pill.jpg",
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


@pytest.mark.anyio
async def test_request_body_limit_rejects_declared_oversize_before_app() -> None:
    app_called = False

    async def app(_scope: Scope, _receive: Receive, _send: Send) -> None:
        nonlocal app_called
        app_called = True

    async def receive() -> Message:
        return {"type": "http.disconnect"}

    sent: list[Message] = []

    async def send(message: Message) -> None:
        sent.append(message)

    middleware = RequestBodyLimitMiddleware(app, limits={"/limited": 10})

    await middleware(_scope(content_length=11), receive, send)

    assert app_called is False
    assert sent[0]["type"] == "http.response.start"
    assert sent[0]["status"] == 413


@pytest.mark.anyio
async def test_request_body_limit_counts_streamed_chunks() -> None:
    messages = iter(
        (
            {"type": "http.request", "body": b"123456", "more_body": True},
            {"type": "http.request", "body": b"78901", "more_body": False},
        )
    )

    async def receive() -> Message:
        return next(messages)  # type: ignore[return-value]

    async def drain_app(_scope: Scope, app_receive: Receive, send: Send) -> None:
        while True:
            message = await app_receive()
            if not message.get("more_body", False):
                break
        await send({"type": "http.response.start", "status": 200, "headers": []})
        await send({"type": "http.response.body", "body": b""})

    sent: list[Message] = []

    async def send(message: Message) -> None:
        sent.append(message)

    middleware = RequestBodyLimitMiddleware(
        drain_app,
        limits={"/limited": 10},
    )

    await middleware(_scope(), receive, send)

    assert sent[0]["type"] == "http.response.start"
    assert sent[0]["status"] == 413


@pytest.mark.anyio
async def test_pill_identification_accepts_front_and_optional_back_multipart() -> None:
    control = _RecordingIdentifyPill()
    app = create_app()
    app.dependency_overrides[get_identify_pill] = lambda: control

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


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
