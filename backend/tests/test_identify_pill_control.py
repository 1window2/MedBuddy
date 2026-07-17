import asyncio
import os
import sys
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from boundaries.pill_identification_boundary import PillImageQualityError
from controls.identify_pill_control import IdentifyPill
from entities.pill_identification_entity import PillCatalogEntry, PillVisualFeatures


class _FakeVisionBoundary:
    def __init__(self, features: PillVisualFeatures) -> None:
        self.features = features

    async def extractVisualFeatures(
        self,
        _front_image: bytes,
        _back_image: bytes | None = None,
    ) -> PillVisualFeatures:
        return self.features


class _FakeCatalogBoundary:
    def __init__(self, entries: tuple[PillCatalogEntry, ...]) -> None:
        self.entries = entries

    async def getCatalog(self) -> tuple[PillCatalogEntry, ...]:
        return self.entries


class _FailingVisionBoundary:
    async def extractVisualFeatures(
        self,
        _front_image: bytes,
        _back_image: bytes | None = None,
    ) -> PillVisualFeatures:
        await asyncio.sleep(0)
        raise PillImageQualityError("Retake the pill photo.")


class _SlowCatalogBoundary:
    def __init__(self) -> None:
        self.was_cancelled = False

    async def getCatalog(self) -> tuple[PillCatalogEntry, ...]:
        try:
            await asyncio.sleep(60)
        except asyncio.CancelledError:
            self.was_cancelled = True
            raise
        return ()


def _entry(
    item_seq: str,
    item_name: str,
    *,
    shape: str = "원형",
    color: str = "노랑",
    print_front: str = "YH",
    print_back: str = "LT",
) -> PillCatalogEntry:
    return PillCatalogEntry(
        item_seq=item_seq,
        item_name=item_name,
        entp_name="테스트제약",
        image_url=f"https://example.test/{item_seq}.jpg",
        shape=shape,
        color_primary=color,
        print_front=print_front,
        print_back=print_back,
        line_front="없음",
        line_back="없음",
    )


def _control(
    features: PillVisualFeatures,
    entries: tuple[PillCatalogEntry, ...],
) -> IdentifyPill:
    return IdentifyPill(
        vision_boundary=_FakeVisionBoundary(features),  # type: ignore[arg-type]
        catalog_boundary=_FakeCatalogBoundary(entries),  # type: ignore[arg-type]
    )


@pytest.mark.anyio
async def test_exact_imprints_rank_authoritative_product_first() -> None:
    features = PillVisualFeatures(
        shape="round",
        colors=("yellow",),
        front_imprint="YH",
        back_imprint="LT",
        front_line="none",
        back_line="none",
        quality="good",
    )
    control = _control(
        features,
        (
            _entry("other", "다른정", print_front="YH", print_back="10"),
            _entry("200808877", "페라트라정2.5밀리그램(레트로졸)"),
        ),
    )

    result = await control.requestPillIdentification(b"front", b"back")

    assert result.candidates[0].item_seq == "200808877"
    assert result.candidates[0].match_score == 1.0
    assert "imprint" in result.candidates[0].matched_attributes
    assert result.is_confident is True
    assert result.requires_confirmation is True


@pytest.mark.anyio
async def test_front_and_back_orientation_can_be_swapped() -> None:
    features = PillVisualFeatures(
        shape="round",
        colors=("yellow",),
        front_imprint="LT",
        back_imprint="YH",
        quality="good",
    )
    control = _control(features, (_entry("200808877", "페라트라정"),))

    result = await control.requestPillIdentification(b"front", b"back")

    assert result.candidates[0].item_seq == "200808877"
    assert result.candidates[0].match_score == 1.0


@pytest.mark.anyio
async def test_one_character_imprint_error_keeps_plausible_candidate() -> None:
    features = PillVisualFeatures(
        shape="round",
        colors=("yellow",),
        front_imprint="YB",
        back_imprint="LT",
        quality="usable",
    )
    control = _control(
        features,
        (
            _entry("unrelated", "무관정", print_front="AB", print_back="12"),
            _entry("200808877", "페라트라정"),
        ),
    )

    result = await control.requestPillIdentification(b"front", b"back")

    assert result.candidates[0].item_seq == "200808877"


@pytest.mark.anyio
async def test_shape_and_color_only_result_is_never_confident() -> None:
    features = PillVisualFeatures(
        shape="round",
        colors=("yellow",),
        quality="usable",
    )
    control = _control(features, (_entry("200808877", "페라트라정"),))

    result = await control.requestPillIdentification(b"front")

    assert result.candidates[0].match_score <= 0.68
    assert result.is_confident is False
    assert result.requires_confirmation is True


@pytest.mark.anyio
async def test_poor_quality_result_is_never_confident() -> None:
    features = PillVisualFeatures(
        shape="round",
        colors=("yellow",),
        front_imprint="YH",
        back_imprint="LT",
        quality="poor",
        quality_issues=("pill occupies too little of the image",),
    )
    control = _control(features, (_entry("200808877", "test pill"),))

    result = await control.requestPillIdentification(b"front", b"back")

    assert result.candidates
    assert result.is_confident is False
    assert result.requires_confirmation is True


@pytest.mark.anyio
async def test_round_observation_does_not_match_oval_catalog_shape() -> None:
    features = PillVisualFeatures(
        shape="round",
        colors=("yellow",),
        quality="usable",
    )
    control = _control(
        features,
        (
            _entry(
                "oval",
                "타원정",
                shape="타원형",
                print_front="",
                print_back="",
            ),
        ),
    )

    result = await control.requestPillIdentification(b"front")

    assert result.candidates == ()
    assert result.is_confident is False


@pytest.mark.anyio
async def test_single_weak_attribute_does_not_generate_candidates() -> None:
    features = PillVisualFeatures(
        shape="unknown",
        colors=(),
        front_line="none",
        quality="usable",
    )
    control = _control(features, (_entry("200808877", "페라트라정"),))

    result = await control.requestPillIdentification(b"front")

    assert result.candidates == ()
    assert result.is_confident is False


@pytest.mark.anyio
async def test_one_character_imprint_is_never_confident() -> None:
    features = PillVisualFeatures(
        shape="round",
        colors=("yellow",),
        front_imprint="Y",
        quality="good",
    )
    control = _control(
        features,
        (_entry("200808877", "페라트라정", print_front="Y", print_back=""),),
    )

    result = await control.requestPillIdentification(b"front")

    assert result.candidates
    assert result.is_confident is False


@pytest.mark.anyio
async def test_single_result_limit_still_checks_tied_runner_up() -> None:
    features = PillVisualFeatures(
        shape="round",
        colors=("yellow",),
        front_imprint="YH",
        back_imprint="LT",
        quality="good",
    )
    entries = (
        _entry("1", "첫번째정"),
        _entry("2", "두번째정"),
    )
    control = IdentifyPill(
        vision_boundary=_FakeVisionBoundary(features),  # type: ignore[arg-type]
        catalog_boundary=_FakeCatalogBoundary(entries),  # type: ignore[arg-type]
        candidate_limit=1,
    )

    result = await control.requestPillIdentification(b"front", b"back")

    assert len(result.candidates) == 1
    assert result.is_confident is False
    assert result.requires_confirmation is True


@pytest.mark.anyio
async def test_failed_required_stage_cancels_sibling_work() -> None:
    catalog_boundary = _SlowCatalogBoundary()
    control = IdentifyPill(
        vision_boundary=_FailingVisionBoundary(),  # type: ignore[arg-type]
        catalog_boundary=catalog_boundary,  # type: ignore[arg-type]
    )

    with pytest.raises(PillImageQualityError, match="Retake"):
        await control.requestPillIdentification(b"front")

    assert catalog_boundary.was_cancelled is True


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
