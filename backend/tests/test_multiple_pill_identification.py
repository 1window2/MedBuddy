# File Name: test_multiple_pill_identification.py
# Role: Verifies safe one-photo multi-pill detection, ranking, and API contracts.

import json
import os
import sys
from pathlib import Path
from typing import Any

import httpx
import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from api.dependencies import get_identify_pill, get_registered_principal  # noqa: E402
from boundaries.pill_identification_boundary import (  # noqa: E402
    MultiplePillImagePreprocessingResult,
    PillVisionBoundary,
    PillVisionResponseError,
)
from controls.identify_pill_control import IdentifyPill  # noqa: E402
from entities.authenticated_principal_entity import AuthenticatedPrincipal  # noqa: E402
from entities.pill_identification_entity import (  # noqa: E402
    MultiplePillIdentificationResult,
    MultiplePillObservation,
    PillBoundingBox,
    PillCatalogEntry,
    PillIdentificationResult,
    PillVisualFeatures,
)
from main import create_app  # noqa: E402


class _CompositionProcessor:
    def preprocessMultiplePillImage(
        self,
        image: bytes,
    ) -> MultiplePillImagePreprocessingResult:
        return MultiplePillImagePreprocessingResult(image=image, width=800, height=600)


class _MultipleVisionAPI:
    def __init__(self, payload: dict[str, Any]) -> None:
        self.payload = payload

    async def requestMultipleVisualFeatures(self, **_kwargs: object) -> str:
        return json.dumps(self.payload)


class _CatalogBoundary:
    def __init__(self) -> None:
        self.request_count = 0

    async def getCatalog(self) -> tuple[PillCatalogEntry, ...]:
        self.request_count += 1
        return (
            PillCatalogEntry(
                item_seq="yellow",
                item_name="Yellow pill",
                shape="원형",
                color_primary="노랑",
                print_front="YH",
            ),
            PillCatalogEntry(
                item_seq="white",
                item_name="White pill",
                shape="원형",
                color_primary="백색",
                print_front="SJ",
            ),
        )


def _pill(
    box: list[int],
    *,
    color: str,
    imprint: str,
) -> dict[str, object]:
    return {
        "box_2d": box,
        "shape": "round",
        "colors": [color],
        "front_imprint": imprint,
        "front_line": "none",
        "quality": "good",
        "quality_issues": [],
    }


@pytest.mark.anyio
async def test_multiple_visual_boundary_orders_and_parses_pills() -> None:
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_CompositionProcessor(),  # type: ignore[arg-type]
        vision_api=_MultipleVisionAPI(
            {
                "pills": [
                    _pill([500, 600, 800, 900], color="white", imprint="SJ"),
                    _pill([100, 100, 350, 350], color="yellow", imprint="YH"),
                ]
            }
        ),  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    observations = await boundary.extractMultipleVisualFeatures(b"photo")

    assert len(observations) == 2
    assert observations[0][0].left == pytest.approx(0.1)
    assert observations[0][1].front_imprint == "YH"
    assert observations[1][1].front_imprint == "SJ"


@pytest.mark.anyio
async def test_multiple_visual_boundary_rejects_overlapping_duplicate_boxes() -> None:
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_CompositionProcessor(),  # type: ignore[arg-type]
        vision_api=_MultipleVisionAPI(
            {
                "pills": [
                    _pill([100, 100, 500, 500], color="white", imprint="SJ"),
                    _pill([110, 110, 490, 490], color="white", imprint="SJ"),
                ]
            }
        ),  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    with pytest.raises(PillVisionResponseError, match="overlapping"):
        await boundary.extractMultipleVisualFeatures(b"photo")


@pytest.mark.anyio
async def test_multiple_control_loads_catalog_once_and_ranks_each_pill() -> None:
    vision_boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_CompositionProcessor(),  # type: ignore[arg-type]
        vision_api=_MultipleVisionAPI(
            {
                "pills": [
                    _pill([100, 100, 350, 350], color="yellow", imprint="YH"),
                    _pill([500, 600, 800, 900], color="white", imprint="SJ"),
                ]
            }
        ),  # type: ignore[arg-type]
        timeout_seconds=1,
    )
    catalog_boundary = _CatalogBoundary()
    control = IdentifyPill(
        vision_boundary=vision_boundary,
        catalog_boundary=catalog_boundary,  # type: ignore[arg-type]
    )

    result = await control.requestMultiplePillIdentification(b"photo")

    assert catalog_boundary.request_count == 1
    assert [item.index for item in result.observations] == [1, 2]
    assert result.observations[0].identification.candidates[0].item_seq == "yellow"
    assert result.observations[1].identification.candidates[0].item_seq == "white"
    assert all(
        item.identification.requires_confirmation for item in result.observations
    )


class _RecordingMultipleControl:
    def __init__(self) -> None:
        self.image = b""

    async def requestMultiplePillIdentification(
        self,
        image: bytes,
    ) -> MultiplePillIdentificationResult:
        self.image = image
        return MultiplePillIdentificationResult(
            observations=(
                MultiplePillObservation(
                    index=1,
                    bounding_box=PillBoundingBox(
                        left=0.1,
                        top=0.2,
                        width=0.3,
                        height=0.4,
                    ),
                    identification=PillIdentificationResult(
                        observed_features=PillVisualFeatures(
                            shape="round",
                            colors=("yellow",),
                        )
                    ),
                ),
            )
        )


@pytest.mark.anyio
async def test_multiple_pill_api_accepts_one_image_and_preserves_confirmation() -> None:
    control = _RecordingMultipleControl()
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
            "/api/v1/medication/pill-identification/multiple-candidates",
            files={"image": ("pills.jpg", b"multi-photo", "image/jpeg")},
        )

    assert response.status_code == 200
    assert control.image == b"multi-photo"
    payload = response.json()
    assert payload["requires_confirmation"] is True
    assert payload["observations"][0]["index"] == 1
    assert payload["observations"][0]["bounding_box"]["left"] == 0.1
