import json
import os
import sys
from datetime import timedelta
from pathlib import Path
from typing import Any

import cv2
import numpy as np
import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from boundaries.pill_identification_boundary import (
    MFDSPillCatalogBoundary,
    PillImageProcessingBoundary,
    PillImageQualityError,
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


def test_image_preprocessing_returns_bounded_jpeg() -> None:
    processed = PillImageProcessingBoundary().preprocessPillImage(_sample_image())

    decoded = cv2.imdecode(np.frombuffer(processed, dtype=np.uint8), cv2.IMREAD_COLOR)
    assert decoded is not None
    assert max(decoded.shape[:2]) <= 1600
    assert min(decoded.shape[:2]) >= 64


def test_image_preprocessing_rejects_multiple_similar_pills() -> None:
    image = np.full((500, 700, 3), 245, dtype=np.uint8)
    cv2.circle(image, (210, 250), 80, (30, 210, 230), thickness=-1)
    cv2.circle(image, (490, 250), 80, (30, 210, 230), thickness=-1)
    success, encoded = cv2.imencode(".jpg", image)
    assert success

    with pytest.raises(PillImageQualityError, match="exactly one pill"):
        PillImageProcessingBoundary().preprocessPillImage(encoded.tobytes())


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


def test_visual_boundary_rejects_empty_model_name() -> None:
    with pytest.raises(ValueError, match="model name"):
        PillVisionBoundary(client=object(), model_name=" ")  # type: ignore[arg-type]


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

    items, total_count = MFDSPillCatalogBoundary._extract_items(payload)
    entry = MFDSPillCatalogBoundary._to_catalog_entry(items[0])

    assert total_count == 1
    assert entry is not None
    assert entry.item_seq == "200808877"
    assert entry.image_url == "https://example.test/pill.jpg"


def test_mfds_catalog_rejects_non_network_image_url() -> None:
    entry = MFDSPillCatalogBoundary._to_catalog_entry(
        {
            "ITEM_SEQ": "1",
            "ITEM_NAME": "테스트정",
            "ITEM_IMAGE": "file:///private/pill.jpg",
        }
    )

    assert entry is not None
    assert entry.image_url == ""


@pytest.mark.parametrize(
    "overrides, expected_message",
    [
        ({"timeout_seconds": 0}, "timeout must be positive"),
        ({"cache_ttl": timedelta(0)}, "cache lifetime"),
        ({"refresh_timeout_seconds": 0}, "refresh timeout"),
        ({"minimum_catalog_rows": 0}, "minimum rows"),
        ({"page_size": 501}, "page size"),
        ({"max_concurrency": 13}, "concurrency"),
    ],
)
def test_mfds_catalog_rejects_invalid_configuration(
    overrides: dict[str, object],
    expected_message: str,
) -> None:
    with pytest.raises(ValueError, match=expected_message):
        MFDSPillCatalogBoundary(**overrides)  # type: ignore[arg-type]


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
