import asyncio
import json
import os
import sys
import threading
import time
from collections.abc import AsyncIterator
from datetime import timedelta
from pathlib import Path
from typing import Any

import cv2
import httpx
import numpy as np
import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

import boundaries.pill_identification_boundary as boundary_module
from boundaries.pill_identification_boundary import (
    MFDSPillCatalogBoundary,
    MFDSPillAPI,
    PillImageProcessingBoundary,
    PillImageQualityError,
    PillVisionResponseError,
    PillVisionUnavailableError,
    PillVisionBoundary,
)


class _PassthroughImageProcessingBoundary:
    def preprocessPillImage(self, image: bytes) -> bytes:
        return image


class _FakeVisionAPI:
    def __init__(self, payload: dict[str, Any]) -> None:
        self.payload = payload
        self.received_back_image = False

    async def requestVisualFeatures(
        self,
        **kwargs: object,
    ) -> str:
        self.received_back_image = kwargs.get("back_image") is not None
        return json.dumps(self.payload)


class _FailingVisionAPI:
    async def requestVisualFeatures(self, **_kwargs: object) -> str:
        raise ConnectionError("private upstream failure")


class _SlowImageProcessingBoundary:
    def preprocessPillImage(self, image: bytes) -> bytes:
        import time

        time.sleep(0.05)
        return image


class _ConcurrencyTrackingImageProcessingBoundary:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.active_workers = 0
        self.maximum_active_workers = 0
        self.delay_seconds = 0.08

    def preprocessPillImage(self, image: bytes) -> bytes:
        with self._lock:
            self.active_workers += 1
            self.maximum_active_workers = max(
                self.maximum_active_workers,
                self.active_workers,
            )
        try:
            time.sleep(self.delay_seconds)
            return image
        finally:
            with self._lock:
                self.active_workers -= 1


class _FailingAsyncClient:
    def __init__(self) -> None:
        self.close_called = False

    async def aclose(self) -> None:
        self.close_called = True
        raise RuntimeError("async close failed")


class _OwnedVisionClient:
    def __init__(self) -> None:
        self.aio = _FailingAsyncClient()
        self.close_called = False

    def close(self) -> None:
        self.close_called = True


def _valid_visual_payload(**overrides: object) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "shape": "round",
        "colors": ["yellow"],
        "front_imprint": "YH",
        "back_imprint": "LT",
        "front_line": "none",
        "back_line": "none",
        "quality": "good",
        "quality_issues": [],
        "same_pill": True,
        "side_consistency_confidence": 1.0,
    }
    payload.update(overrides)
    return payload


def _sample_image() -> bytes:
    image = np.full((500, 500, 3), 245, dtype=np.uint8)
    cv2.circle(image, (250, 250), 95, (30, 210, 230), thickness=-1)
    success, encoded = cv2.imencode(".jpg", image)
    assert success
    return encoded.tobytes()


def test_image_preprocessing_rejects_invalid_data() -> None:
    with pytest.raises(PillImageQualityError, match="valid image"):
        PillImageProcessingBoundary().preprocessPillImage(b"not-an-image")


def test_image_preprocessing_rejects_oversized_dimensions_before_decode(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _OversizedMetadata:
        size = (10_000, 10_000)

        def __enter__(self) -> "_OversizedMetadata":
            return self

        def __exit__(self, *_args: object) -> None:
            return None

    monkeypatch.setattr(
        boundary_module.Image,
        "open",
        lambda _stream: _OversizedMetadata(),
    )

    def fail_decode(*_args: object, **_kwargs: object) -> None:
        raise AssertionError("OpenCV decode must not run for oversized metadata")

    monkeypatch.setattr(boundary_module.cv2, "imdecode", fail_decode)

    with pytest.raises(PillImageQualityError, match="too large"):
        PillImageProcessingBoundary().preprocessPillImage(b"image-header")


def test_image_preprocessing_returns_bounded_jpeg() -> None:
    processed = PillImageProcessingBoundary().preprocessPillImage(_sample_image())

    decoded = cv2.imdecode(np.frombuffer(processed, dtype=np.uint8), cv2.IMREAD_COLOR)
    assert decoded is not None
    assert max(decoded.shape[:2]) <= 1600
    assert min(decoded.shape[:2]) >= 64


def test_image_preprocessing_downsamples_high_resolution_jpeg() -> None:
    image = np.full((4000, 6000, 3), 245, dtype=np.uint8)
    cv2.circle(image, (3000, 2000), 700, (30, 210, 230), thickness=-1)
    success, encoded = cv2.imencode(".jpg", image)
    assert success

    processed = PillImageProcessingBoundary().preprocessPillImage(
        encoded.tobytes()
    )
    decoded = cv2.imdecode(
        np.frombuffer(processed, dtype=np.uint8),
        cv2.IMREAD_COLOR,
    )

    assert decoded is not None
    assert max(decoded.shape[:2]) <= 1600


def test_image_preprocessing_preserves_ambiguous_multi_object_frame() -> None:
    image = np.full((500, 700, 3), 245, dtype=np.uint8)
    cv2.circle(image, (210, 250), 80, (30, 210, 230), thickness=-1)
    cv2.circle(image, (490, 250), 80, (30, 210, 230), thickness=-1)
    success, encoded = cv2.imencode(".jpg", image)
    assert success

    processed = PillImageProcessingBoundary().preprocessPillImage(encoded.tobytes())
    decoded = cv2.imdecode(np.frombuffer(processed, dtype=np.uint8), cv2.IMREAD_COLOR)

    assert decoded is not None
    assert decoded.shape[:2] == image.shape[:2]


def test_image_preprocessing_ignores_edge_clutter_when_cropping() -> None:
    image = np.full((700, 900, 3), 235, dtype=np.uint8)
    cv2.rectangle(image, (0, 0), (900, 170), (80, 80, 80), thickness=-1)
    cv2.circle(image, (470, 420), 85, (80, 210, 120), thickness=-1)
    success, encoded = cv2.imencode(".jpg", image)
    assert success

    processed = PillImageProcessingBoundary().preprocessPillImage(encoded.tobytes())
    decoded = cv2.imdecode(np.frombuffer(processed, dtype=np.uint8), cv2.IMREAD_COLOR)

    assert decoded is not None
    assert decoded.shape[0] < image.shape[0]
    assert decoded.shape[1] < image.shape[1]
    center_pixel = decoded[decoded.shape[0] // 2, decoded.shape[1] // 2]
    assert int(center_pixel[1]) > int(center_pixel[0]) + 60


def test_image_preprocessing_crops_high_contrast_pill_on_textured_frame() -> None:
    image = np.full((700, 900, 3), (70, 90, 120), dtype=np.uint8)
    cv2.rectangle(image, (0, 300), (900, 700), (95, 115, 145), thickness=-1)
    cv2.ellipse(
        image,
        (260, 190),
        (75, 115),
        0,
        0,
        360,
        (90, 108, 135),
        thickness=-1,
    )
    cv2.circle(image, (520, 470), 80, (210, 220, 80), thickness=-1)
    success, encoded = cv2.imencode(".jpg", image)
    assert success

    processed = PillImageProcessingBoundary().preprocessPillImage(encoded.tobytes())
    decoded = cv2.imdecode(np.frombuffer(processed, dtype=np.uint8), cv2.IMREAD_COLOR)

    assert decoded is not None
    assert decoded.shape[0] < image.shape[0]
    assert decoded.shape[1] < image.shape[1]


@pytest.mark.anyio
async def test_visual_boundary_accepts_small_pill_with_usable_features() -> None:
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_PassthroughImageProcessingBoundary(),
        vision_api=_FakeVisionAPI(
            _valid_visual_payload(
                quality="poor",
                quality_issues=["pill occupies too little of the image"],
            )
        ),  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    features = await boundary.extractVisualFeatures(b"front")

    assert features.shape == "round"
    assert features.colors == ("yellow",)
    assert features.quality == "poor"


@pytest.mark.anyio
async def test_visual_boundary_still_rejects_small_blurred_pill() -> None:
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_PassthroughImageProcessingBoundary(),
        vision_api=_FakeVisionAPI(
            _valid_visual_payload(
                quality="poor",
                quality_issues=["pill is small and blurred"],
            )
        ),  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    with pytest.raises(PillImageQualityError, match="retake"):
        await boundary.extractVisualFeatures(b"front")


@pytest.mark.anyio
async def test_visual_boundary_preserves_front_and_back_features() -> None:
    vision_api = _FakeVisionAPI(_valid_visual_payload())
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_PassthroughImageProcessingBoundary(),
        vision_api=vision_api,  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    features = await boundary.extractVisualFeatures(b"front", b"back")

    assert features.front_imprint == "YH"
    assert features.back_imprint == "LT"
    assert vision_api.received_back_image is True


@pytest.mark.anyio
async def test_visual_boundary_discards_back_features_without_back_photo() -> None:
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_PassthroughImageProcessingBoundary(),
        vision_api=_FakeVisionAPI(
            _valid_visual_payload(
                front_imprint="",
                back_imprint="LT",
                back_line="plus",
            )
        ),  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    features = await boundary.extractVisualFeatures(b"front")

    assert features.back_imprint == ""
    assert features.back_line == "unknown"
    assert features.same_pill is True
    assert features.side_consistency_confidence == 1.0


@pytest.mark.anyio
async def test_visual_boundary_rejects_mismatched_front_and_back_photos() -> None:
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_PassthroughImageProcessingBoundary(),
        vision_api=_FakeVisionAPI(
            _valid_visual_payload(
                same_pill=False,
                side_consistency_confidence=0.95,
            )
        ),  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    with pytest.raises(PillImageQualityError, match="different pills"):
        await boundary.extractVisualFeatures(b"front", b"back")


@pytest.mark.anyio
async def test_visual_boundary_marks_uncertain_side_consistency() -> None:
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_PassthroughImageProcessingBoundary(),
        vision_api=_FakeVisionAPI(
            _valid_visual_payload(side_consistency_confidence=0.45)
        ),  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    features = await boundary.extractVisualFeatures(b"front", b"back")

    assert features.same_pill is True
    assert features.side_consistency_confidence == 0.45
    assert "front/back consistency is uncertain" in features.quality_issues


@pytest.mark.anyio
async def test_visual_boundary_rejects_poor_quality_result() -> None:
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_PassthroughImageProcessingBoundary(),
        vision_api=_FakeVisionAPI(
            _valid_visual_payload(quality="poor", quality_issues=["blur"])
        ),  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    with pytest.raises(PillImageQualityError, match="retake"):
        await boundary.extractVisualFeatures(b"front")


@pytest.mark.anyio
async def test_visual_boundary_rejects_non_string_imprint() -> None:
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_PassthroughImageProcessingBoundary(),
        vision_api=_FakeVisionAPI(
            _valid_visual_payload(front_imprint=["YH"])
        ),  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    with pytest.raises(PillVisionResponseError, match="invalid response"):
        await boundary.extractVisualFeatures(b"front")


@pytest.mark.anyio
async def test_visual_boundary_hides_upstream_failure_details() -> None:
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_PassthroughImageProcessingBoundary(),
        vision_api=_FailingVisionAPI(),  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    with pytest.raises(PillVisionUnavailableError) as context:
        await boundary.extractVisualFeatures(b"front")

    assert "private upstream failure" not in str(context.value)


@pytest.mark.anyio
async def test_visual_boundary_applies_timeout_to_preprocessing_stage() -> None:
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_SlowImageProcessingBoundary(),
        vision_api=_FakeVisionAPI(_valid_visual_payload()),  # type: ignore[arg-type]
        timeout_seconds=0.01,
    )

    with pytest.raises(TimeoutError, match="timed out"):
        await boundary.extractVisualFeatures(b"front")


@pytest.mark.anyio
async def test_visual_timeout_keeps_preprocessing_capacity_until_worker_exits() -> None:
    image_processing = _ConcurrencyTrackingImageProcessingBoundary()
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=image_processing,
        vision_api=_FakeVisionAPI(_valid_visual_payload()),  # type: ignore[arg-type]
        timeout_seconds=0.01,
        max_concurrency=1,
    )

    for _ in range(2):
        with pytest.raises(TimeoutError, match="timed out"):
            await boundary.extractVisualFeatures(b"front")

    await asyncio.sleep(0.1)

    assert image_processing.maximum_active_workers == 1
    assert image_processing.active_workers == 0

    image_processing.delay_seconds = 0
    boundary.timeout_seconds = 1
    recovered = await boundary.extractVisualFeatures(b"front")

    assert recovered.front_imprint == "YH"
    assert image_processing.maximum_active_workers == 1


def test_visual_boundary_rejects_empty_model_name() -> None:
    with pytest.raises(ValueError, match="model name"):
        PillVisionBoundary(client=object(), model_name=" ")  # type: ignore[arg-type]


def test_visual_boundary_rejects_invalid_concurrency() -> None:
    with pytest.raises(ValueError, match="concurrency"):
        PillVisionBoundary(
            client=object(),  # type: ignore[arg-type]
            max_concurrency=0,
        )


@pytest.mark.anyio
async def test_visual_boundary_closes_sync_client_when_async_close_fails(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client = _OwnedVisionClient()
    monkeypatch.setattr(
        boundary_module.genai,
        "Client",
        lambda **_kwargs: client,
    )
    boundary = PillVisionBoundary()

    with pytest.raises(RuntimeError, match="async close failed"):
        await boundary.close()

    assert client.aio.close_called is True
    assert client.close_called is True


def test_mfds_catalog_parser_accepts_documented_response_shape() -> None:
    payload = {
        "header": {"resultCode": "00"},
        "body": {
            "totalCount": 1,
            "items": [
                {
                    "ITEM_SEQ": "200808877",
                    "ITEM_NAME": "페라트라정2.5밀리그램(레트로졸)",
                    "ENTP_NAME": "영풍제약",
                    "ITEM_IMAGE": "https://example.test/pill.jpg",
                    "DRUG_SHAPE": "원형",
                    "COLOR_CLASS1": "노랑",
                    "PRINT_FRONT": "YH",
                    "PRINT_BACK": "LT",
                }
            ],
        },
    }

    items, total_count = MFDSPillAPI._extract_items(payload)
    entry = MFDSPillAPI._to_catalog_entry(items[0])

    assert total_count == 1
    assert entry is not None
    assert entry.item_seq == "200808877"
    assert entry.image_url == "https://example.test/pill.jpg"


def test_mfds_catalog_rejects_non_network_image_url() -> None:
    entry = MFDSPillAPI._to_catalog_entry(
        {
            "ITEM_SEQ": "1",
            "ITEM_NAME": "테스트정",
            "ITEM_IMAGE": "file:///private/pill.jpg",
        }
    )

    assert entry is not None
    assert entry.image_url == ""


@pytest.mark.parametrize(
    "item",
    [
        {"ITEM_SEQ": ["1"], "ITEM_NAME": "test"},
        {"ITEM_SEQ": "1", "ITEM_NAME": {"text": "test"}},
    ],
)
def test_mfds_catalog_rejects_structured_required_text(
    item: dict[str, Any],
) -> None:
    assert MFDSPillAPI._to_catalog_entry(item) is None


@pytest.mark.anyio
async def test_mfds_api_downloads_and_normalizes_complete_catalog() -> None:
    requested_pages: list[int] = []

    def handler(request: httpx.Request) -> httpx.Response:
        page_no = int(request.url.params["pageNo"])
        requested_pages.append(page_no)
        items = (
            [
                {
                    "ITEM_SEQ": "2",
                    "ITEM_NAME": "second",
                    "ITEM_IMAGE": "//example.test/2.jpg",
                },
                {"ITEM_SEQ": "1", "ITEM_NAME": "first"},
            ]
            if page_no == 1
            else [{"ITEM_SEQ": "3", "ITEM_NAME": "third"}]
        )
        return httpx.Response(
            200,
            json={
                "response": {
                    "header": {"resultCode": "00"},
                    "body": {"totalCount": 3, "items": items},
                }
            },
        )

    def client_factory(**kwargs: object) -> httpx.AsyncClient:
        return httpx.AsyncClient(
            transport=httpx.MockTransport(handler),
            timeout=kwargs["timeout"],
            limits=kwargs["limits"],
        )

    catalog = await MFDSPillAPI(
        page_size=2,
        minimum_catalog_rows=1,
        client_factory=client_factory,
    ).requestCatalog()

    assert requested_pages == [1, 2]
    assert [entry.item_seq for entry in catalog] == ["1", "2", "3"]
    assert catalog[1].image_url == "https://example.test/2.jpg"


@pytest.mark.anyio
async def test_mfds_api_rejects_incomplete_multi_page_download() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        page_no = int(request.url.params["pageNo"])
        item_count = 10 if page_no == 1 else 8
        offset = (page_no - 1) * 10
        return httpx.Response(
            200,
            json={
                "header": {"resultCode": "00"},
                "body": {
                    "totalCount": 20,
                    "items": [
                        {
                            "ITEM_SEQ": str(offset + index),
                            "ITEM_NAME": f"pill-{offset + index}",
                        }
                        for index in range(item_count)
                    ],
                },
            },
        )

    def client_factory(**kwargs: object) -> httpx.AsyncClient:
        return httpx.AsyncClient(
            transport=httpx.MockTransport(handler),
            timeout=kwargs["timeout"],
            limits=kwargs["limits"],
        )

    api = MFDSPillAPI(
        page_size=10,
        minimum_catalog_rows=1,
        client_factory=client_factory,
    )

    with pytest.raises(RuntimeError, match="incomplete"):
        await api.requestCatalog()


@pytest.mark.anyio
async def test_mfds_api_rejects_oversized_chunked_page_response(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _OversizedStream(httpx.AsyncByteStream):
        async def __aiter__(self) -> AsyncIterator[bytes]:
            yield b"x" * 10
            yield b"y" * 10

    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, stream=_OversizedStream())

    def client_factory(**kwargs: object) -> httpx.AsyncClient:
        return httpx.AsyncClient(
            transport=httpx.MockTransport(handler),
            timeout=kwargs["timeout"],
            limits=kwargs["limits"],
        )

    monkeypatch.setattr(MFDSPillAPI, "_MAX_PAGE_RESPONSE_BYTES", 16)
    api = MFDSPillAPI(
        page_size=1,
        minimum_catalog_rows=1,
        client_factory=client_factory,
    )

    with pytest.raises(RuntimeError, match="page request failed") as context:
        await api.requestCatalog()

    assert context.value.__cause__ is not None
    assert "too large" in str(context.value.__cause__)


@pytest.mark.anyio
async def test_mfds_api_rejects_page_with_more_rows_than_requested() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={
                "header": {"resultCode": "00"},
                "body": {
                    "totalCount": 2,
                    "items": [
                        {"ITEM_SEQ": "1", "ITEM_NAME": "first"},
                        {"ITEM_SEQ": "2", "ITEM_NAME": "second"},
                    ],
                },
            },
        )

    def client_factory(**kwargs: object) -> httpx.AsyncClient:
        return httpx.AsyncClient(
            transport=httpx.MockTransport(handler),
            timeout=kwargs["timeout"],
            limits=kwargs["limits"],
        )

    api = MFDSPillAPI(
        page_size=1,
        minimum_catalog_rows=1,
        client_factory=client_factory,
    )

    with pytest.raises(RuntimeError, match="page request failed") as context:
        await api.requestCatalog()

    assert context.value.__cause__ is not None
    assert "too many rows" in str(context.value.__cause__)


@pytest.mark.anyio
async def test_mfds_api_rejects_inconsistent_page_totals() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        page_no = int(request.url.params["pageNo"])
        return httpx.Response(
            200,
            json={
                "header": {"resultCode": "00"},
                "body": {
                    "totalCount": 2 if page_no == 1 else 3,
                    "items": [
                        {
                            "ITEM_SEQ": str(page_no),
                            "ITEM_NAME": f"pill-{page_no}",
                        }
                    ],
                },
            },
        )

    def client_factory(**kwargs: object) -> httpx.AsyncClient:
        return httpx.AsyncClient(
            transport=httpx.MockTransport(handler),
            timeout=kwargs["timeout"],
            limits=kwargs["limits"],
        )

    api = MFDSPillAPI(
        page_size=1,
        minimum_catalog_rows=1,
        client_factory=client_factory,
    )

    with pytest.raises(RuntimeError, match="inconsistent row counts"):
        await api.requestCatalog()


@pytest.mark.anyio
async def test_mfds_api_rejects_aggregate_rows_above_advertised_total() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        page_no = int(request.url.params["pageNo"])
        offset = (page_no - 1) * 2
        return httpx.Response(
            200,
            json={
                "header": {"resultCode": "00"},
                "body": {
                    "totalCount": 3,
                    "items": [
                        {
                            "ITEM_SEQ": str(offset + index),
                            "ITEM_NAME": f"pill-{offset + index}",
                        }
                        for index in range(2)
                    ],
                },
            },
        )

    def client_factory(**kwargs: object) -> httpx.AsyncClient:
        return httpx.AsyncClient(
            transport=httpx.MockTransport(handler),
            timeout=kwargs["timeout"],
            limits=kwargs["limits"],
        )

    api = MFDSPillAPI(
        page_size=2,
        minimum_catalog_rows=1,
        client_factory=client_factory,
    )

    with pytest.raises(RuntimeError, match="too many rows"):
        await api.requestCatalog()


@pytest.mark.anyio
async def test_mfds_api_rejects_refresh_above_aggregate_byte_budget(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    payloads = {
        page_no: json.dumps(
            {
                "header": {"resultCode": "00"},
                "body": {
                    "totalCount": 2,
                    "items": [
                        {
                            "ITEM_SEQ": str(page_no),
                            "ITEM_NAME": f"pill-{page_no}",
                        }
                    ],
                },
            }
        ).encode("utf-8")
        for page_no in (1, 2)
    }

    def handler(request: httpx.Request) -> httpx.Response:
        page_no = int(request.url.params["pageNo"])
        return httpx.Response(
            200,
            content=payloads[page_no],
            headers={"content-type": "application/json"},
        )

    def client_factory(**kwargs: object) -> httpx.AsyncClient:
        return httpx.AsyncClient(
            transport=httpx.MockTransport(handler),
            timeout=kwargs["timeout"],
            limits=kwargs["limits"],
        )

    monkeypatch.setattr(
        MFDSPillAPI,
        "_MAX_REFRESH_RESPONSE_BYTES",
        len(payloads[1]) + len(payloads[2]) - 1,
    )
    api = MFDSPillAPI(
        page_size=1,
        minimum_catalog_rows=1,
        client_factory=client_factory,
    )

    with pytest.raises(RuntimeError, match="refresh response is too large"):
        await api.requestCatalog()


@pytest.mark.parametrize(
    "overrides, expected_message",
    [
        ({"timeout_seconds": 0}, "timeout must be positive"),
        ({"minimum_catalog_rows": 0}, "minimum rows"),
        ({"page_size": 501}, "page size"),
        ({"max_concurrency": 13}, "concurrency"),
        ({"base_url": "http://mfds.test/catalog"}, "HTTPS"),
    ],
)
def test_mfds_api_rejects_invalid_configuration(
    overrides: dict[str, object],
    expected_message: str,
) -> None:
    with pytest.raises(ValueError, match=expected_message):
        MFDSPillAPI(**overrides)  # type: ignore[arg-type]


@pytest.mark.parametrize(
    "overrides, expected_message",
    [
        ({"cache_ttl": timedelta(0)}, "cache lifetime"),
        ({"refresh_timeout_seconds": 0}, "refresh timeout"),
    ],
)
def test_mfds_catalog_boundary_rejects_invalid_configuration(
    overrides: dict[str, object],
    expected_message: str,
) -> None:
    with pytest.raises(ValueError, match=expected_message):
        MFDSPillCatalogBoundary(**overrides)  # type: ignore[arg-type]


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
