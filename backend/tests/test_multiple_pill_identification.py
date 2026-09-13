# File Name: test_multiple_pill_identification.py
# Role: Regression coverage for multi-pill observation parsing, independent ranking, and
#   multipart response contracts.

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


# Class Name: _CompositionProcessor
# Role: Multi-pill image processor double that supplies fixed image dimensions without altering
#   bytes.
# Responsibilities:
# - Wraps the uploaded image in an 800-by-600 preprocessing result for bounding-box tests.
class _CompositionProcessor:
    # Function Name: preprocessMultiplePillImage
    # Description:
    # - Wraps the uploaded image in an 800-by-600 preprocessing result for bounding-box
    #   tests.
    # Parameters:
    # - image (bytes): Encoded pill photograph passed through the test boundary.
    # Returns:
    # - MultiplePillImagePreprocessingResult: Original bytes with fixed 800-by-600 image
    #   dimensions.
    def preprocessMultiplePillImage(
        self,
        image: bytes,
    ) -> MultiplePillImagePreprocessingResult:
        return MultiplePillImagePreprocessingResult(image=image, width=800, height=600)


# Class Name: _MultipleVisionAPI
# Role: Multi-pill vision API double returning configurable observation JSON.
# Responsibilities:
# - Serializes the configured multi-pill observations without invoking a vision model.
# Attributes:
# - payload (dict[str, Any]): Configured vision result before JSON serialization.
class _MultipleVisionAPI:
    # Function Name: __init__
    # Description:
    # - Stores the vision payload used to test observation ordering and overlap validation.
    # Parameters:
    # - payload (dict[str, Any]): Configured vision-response fields to serialize as JSON.
    # Returns:
    # - None.
    def __init__(self, payload: dict[str, Any]) -> None:
        self.payload = payload

    # Function Name: requestMultipleVisualFeatures
    # Description:
    # - Serializes the configured multi-pill observations without invoking a vision model.
    # Parameters:
    # - **_kwargs (object): Keyword arguments accepted by the substituted service interface.
    # Returns:
    # - str: JSON encoding of the configured pill observations.
    async def requestMultipleVisualFeatures(self, **_kwargs: object) -> str:
        return json.dumps(self.payload)


# Class Name: _CatalogBoundary
# Role: Shared catalog double that counts loads and provides distinct yellow and white pill
#   references.
# Responsibilities:
# - Counts catalog access and returns the yellow YH and white SJ reference pills.
# Attributes:
# - request_count (int): Number of upstream calls made by the scenario.
class _CatalogBoundary:
    # Function Name: __init__
    # Description:
    # - Starts the catalog request counter at zero for per-image load assertions.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.request_count = 0

    # Function Name: getCatalog
    # Description:
    # - Counts catalog access and returns the yellow YH and white SJ reference pills.
    # Parameters:
    # - None.
    # Returns:
    # - tuple[PillCatalogEntry, ...]: Configured pill-reference tuple, or an empty tuple if
    #   the delayed double completes.
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


# Function Name: _pill
# Description:
# - Builds a good-quality round-pill observation with the requested box, color, and imprint.
# Parameters:
# - box (list[int]): Vision bounding box coordinates in the source response scale.
# - color (str): Observed or catalog pill color for the matching scenario.
# - imprint (str): Recognized characters printed on the pill.
# Returns:
# - dict[str, object]: Good-quality round-pill observation with the specified box, color, and
#   imprint.
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


# Function Name: test_multiple_visual_boundary_orders_and_parses_pills
# Description:
# - Parses two observations into normalized bounding boxes and orders their imprints
#   consistently by position.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_multiple_visual_boundary_rejects_overlapping_duplicate_boxes
# Description:
# - Rejects overlapping duplicate pill boxes with a vision-response error.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_multiple_control_loads_catalog_once_and_ranks_each_pill
# Description:
# - Loads the catalog once for the image, ranks each pill independently, and requires
#   confirmation for every observation.
# Parameters:
# - None.
# Returns:
# - None.
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


# Class Name: _RecordingMultipleControl
# Role: Multi-pill control double that records image bytes and returns one bounded observation.
# Responsibilities:
# - Captures the uploaded composition and returns one observation with a fixed box and visual
#   features.
# Attributes:
# - image (bytes): Captured multi-pill composition bytes.
class _RecordingMultipleControl:
    # Function Name: __init__
    # Description:
    # - Initializes empty captured-image bytes before the multipart request.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.image = b""

    # Function Name: requestMultiplePillIdentification
    # Description:
    # - Captures the uploaded composition and returns one observation with a fixed box and
    #   visual features.
    # Parameters:
    # - image (bytes): Encoded pill photograph passed through the test boundary.
    # Returns:
    # - MultiplePillIdentificationResult: One indexed pill observation with a fixed
    #   normalized bounding box.
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


# Function Name: test_multiple_pill_api_accepts_one_image_and_preserves_confirmation
# Description:
# - Accepts one multipart image and preserves mandatory confirmation, observation index, and
#   normalized bounding-box coordinates.
# Parameters:
# - None.
# Returns:
# - None.
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
