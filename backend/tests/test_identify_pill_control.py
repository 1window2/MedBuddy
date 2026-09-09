# File Name: test_identify_pill_control.py
# Role: Regression coverage for pill ranking, confidence safeguards, stage cancellation, and
#   shared worker capacity.
import asyncio
import os
import sys
import threading
import time
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from boundaries.pill_identification_boundary import PillImageQualityError
from controls.identify_pill_control import IdentifyPill
from entities.pill_identification_entity import (
    PillCatalogEntry,
    PillIdentificationCandidate,
    PillVisualFeatures,
)


# Class Name: _FakeVisionBoundary
# Role: Vision double supplying configured visual observations without processing uploaded
#   images.
# Responsibilities:
# - Returns the configured features for either image orientation without external vision work.
# Attributes:
# - features (PillVisualFeatures): Configured visual observations returned to the ranking
#   control.
class _FakeVisionBoundary:
    # Function Name: __init__
    # Description:
    # - Stores the visual feature set to return during pill identification.
    # Parameters:
    # - features (PillVisualFeatures): Visual observations to rank or return from the vision
    #   double.
    # Returns:
    # - None.
    def __init__(self, features: PillVisualFeatures) -> None:
        self.features = features

    # Function Name: extractVisualFeatures
    # Description:
    # - Returns the configured features for either image orientation without external vision
    #   work.
    # Parameters:
    # - _front_image (bytes): Front-side pill photograph bytes. Unused by this double.
    # - _back_image (bytes | None): Optional back-side pill photograph bytes. Unused by this
    #   double.
    # Returns:
    # - PillVisualFeatures: Configured pill visual features without remote analysis.
    async def extractVisualFeatures(
        self,
        _front_image: bytes,
        _back_image: bytes | None = None,
    ) -> PillVisualFeatures:
        return self.features


# Class Name: _FakeCatalogBoundary
# Role: Catalog double exposing a fixed authoritative candidate set.
# Responsibilities:
# - Returns the configured catalog entries without refreshing a remote dataset.
# Attributes:
# - entries (tuple[PillCatalogEntry, ...]): Catalog references supplied without an external
#   fetch.
class _FakeCatalogBoundary:
    # Function Name: __init__
    # Description:
    # - Stores the pill entries used by ranking tests.
    # Parameters:
    # - entries (tuple[PillCatalogEntry, ...]): Configured catalog records returned by the
    #   double.
    # Returns:
    # - None.
    def __init__(self, entries: tuple[PillCatalogEntry, ...]) -> None:
        self.entries = entries

    # Function Name: getCatalog
    # Description:
    # - Returns the configured catalog entries without refreshing a remote dataset.
    # Parameters:
    # - None.
    # Returns:
    # - tuple[PillCatalogEntry, ...]: Configured pill-reference tuple, or an empty tuple if
    #   the delayed double completes.
    async def getCatalog(self) -> tuple[PillCatalogEntry, ...]:
        return self.entries


# Class Name: _FailingVisionBoundary
# Role: Vision double that asynchronously fails the required image-quality stage.
# Responsibilities:
# - Yields once and raises a retake-photo quality error to exercise sibling-stage cancellation.
class _FailingVisionBoundary:
    # Function Name: extractVisualFeatures
    # Description:
    # - Yields once and raises a retake-photo quality error to exercise sibling-stage
    #   cancellation.
    # Parameters:
    # - _front_image (bytes): Front-side pill photograph bytes. Unused by this double.
    # - _back_image (bytes | None): Optional back-side pill photograph bytes. Unused by this
    #   double.
    # Returns:
    # - No normal result; raises the configured failure described above.
    async def extractVisualFeatures(
        self,
        _front_image: bytes,
        _back_image: bytes | None = None,
    ) -> PillVisualFeatures:
        await asyncio.sleep(0)
        raise PillImageQualityError("Retake the pill photo.")


# Class Name: _SlowCatalogBoundary
# Role: Slow catalog double that records whether concurrent vision failure cancels its lookup.
# Responsibilities:
# - Waits for a slow catalog response, records cancellation when interrupted, and propagates it.
# Attributes:
# - was_cancelled (bool): Whether the sibling catalog task received cancellation.
class _SlowCatalogBoundary:
    # Function Name: __init__
    # Description:
    # - Marks catalog lookup as not yet cancelled.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.was_cancelled = False

    # Function Name: getCatalog
    # Description:
    # - Waits for a slow catalog response, records cancellation when interrupted, and
    #   propagates it.
    # Parameters:
    # - None.
    # Returns:
    # - tuple[PillCatalogEntry, ...]: Configured pill-reference tuple, or an empty tuple if
    #   the delayed double completes.
    async def getCatalog(self) -> tuple[PillCatalogEntry, ...]:
        try:
            await asyncio.sleep(60)
        except asyncio.CancelledError:
            self.was_cancelled = True
            raise
        return ()


# Class Name: _ConcurrencyTrackingIdentifyPill
# Role: Identification control instrumented to track overlapping ranking workers under
#   cancellation.
# Responsibilities:
# - Tracks active ranking workers around a delayed real ranking call and decrements the count
#   even on failure.
# Attributes:
# - _worker_lock (threading.Lock): Lock protecting ranking worker counters.
# - worker_started (threading.Event): Thread-safe signal that background work has begun.
# - active_workers (int): Number of worker threads still processing a request.
# - maximum_active_workers (int): Peak worker concurrency observed during the test.
class _ConcurrencyTrackingIdentifyPill(IdentifyPill):
    # Function Name: __init__
    # Description:
    # - Initializes the normal control plus synchronized worker counters and a worker-start
    #   signal.
    # Parameters:
    # - **kwargs (object): Keyword arguments accepted by the substituted service interface.
    # Returns:
    # - None.
    def __init__(self, **kwargs: object) -> None:
        super().__init__(**kwargs)  # type: ignore[arg-type]
        self._worker_lock = threading.Lock()
        self.worker_started = threading.Event()
        self.active_workers = 0
        self.maximum_active_workers = 0

    # Function Name: _rank_candidates
    # Description:
    # - Tracks active ranking workers around a delayed real ranking call and decrements the
    #   count even on failure.
    # Parameters:
    # - features (PillVisualFeatures): Visual observations to rank or return from the vision
    #   double.
    # - catalog (tuple[PillCatalogEntry, ...]): Authoritative pill references used for
    #   candidate ranking.
    # - ranking_limit (int | None): Maximum ranked candidates, or None for the default
    #   policy.
    # Returns:
    # - list[PillIdentificationCandidate]: Candidates produced by the real ranking
    #   implementation.
    def _rank_candidates(
        self,
        features: PillVisualFeatures,
        catalog: tuple[PillCatalogEntry, ...],
        ranking_limit: int | None = None,
    ) -> list[PillIdentificationCandidate]:
        with self._worker_lock:
            self.active_workers += 1
            self.maximum_active_workers = max(
                self.maximum_active_workers,
                self.active_workers,
            )
            self.worker_started.set()
        try:
            time.sleep(0.08)
            return super()._rank_candidates(features, catalog, ranking_limit)
        finally:
            with self._worker_lock:
                self.active_workers -= 1


# Function Name: _entry
# Description:
# - Builds an authoritative pill reference with configurable code, name, shape, color, and
#   two-sided imprints.
# Parameters:
# - item_seq (str): Authoritative product code identifying the medication.
# - item_name (str): Product name in the authoritative or saved medication record.
# - shape (str): Observed or catalog pill shape used for matching.
# - color (str): Observed or catalog pill color for the matching scenario.
# - print_front (str): Catalog imprint on the pill's front side.
# - print_back (str): Catalog imprint on the pill's back side.
# Returns:
# - PillCatalogEntry: Synthetic authoritative catalog record with the requested identity and
#   matching fields.
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
        image_url=f"https://nedrug.mfds.go.kr/{item_seq}.jpg",
        shape=shape,
        color_primary=color,
        print_front=print_front,
        print_back=print_back,
        line_front="없음",
        line_back="없음",
    )


# Function Name: _control
# Description:
# - Wires fixed vision features and catalog entries into the real identification control.
# Parameters:
# - features (PillVisualFeatures): Visual observations to rank or return from the vision double.
# - entries (tuple[PillCatalogEntry, ...]): Configured catalog records returned by the double.
# Returns:
# - IdentifyPill: Identification control wired to fixed vision and catalog doubles.
def _control(
    features: PillVisualFeatures,
    entries: tuple[PillCatalogEntry, ...],
) -> IdentifyPill:
    return IdentifyPill(
        vision_boundary=_FakeVisionBoundary(features),  # type: ignore[arg-type]
        catalog_boundary=_FakeCatalogBoundary(entries),  # type: ignore[arg-type]
    )


# Function Name: test_exact_imprints_rank_authoritative_product_first
# Description:
# - Ranks the exact authoritative imprint match first with score 1.0 while still requiring user
#   confirmation.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_front_and_back_orientation_can_be_swapped
# Description:
# - Keeps a perfect match when front and back imprints are swapped.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_one_character_imprint_error_keeps_plausible_candidate
# Description:
# - Retains the plausible product despite a one-character imprint recognition error.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_shape_and_color_only_result_is_never_confident
# Description:
# - Caps shape-and-color-only scores at 0.68 and never marks them confident or exempt from
#   confirmation.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_poor_quality_result_is_never_confident
# Description:
# - Retains candidates from poor-quality observations but requires confirmation and withholds
#   confidence.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_uncertain_front_back_pair_is_never_confident
# Description:
# - Withholds confidence when the two photographed sides may not belong to the same pill.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_uncertain_front_back_pair_is_never_confident() -> None:
    features = PillVisualFeatures(
        shape="round",
        colors=("yellow",),
        front_imprint="YH",
        back_imprint="LT",
        quality="good",
        side_consistency_confidence=0.45,
    )
    control = _control(features, (_entry("200808877", "test pill"),))

    result = await control.requestPillIdentification(b"front", b"back")

    assert result.candidates
    assert result.is_confident is False


# Function Name: test_round_observation_does_not_match_oval_catalog_shape
# Description:
# - Rejects an oval catalog shape for a round observation and returns no confident candidate.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_single_weak_attribute_does_not_generate_candidates
# Description:
# - Returns no candidates when only one weak visual attribute supports a match.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_one_character_imprint_is_never_confident
# Description:
# - Allows candidates from a one-character imprint without treating them as confident matches.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_single_result_limit_still_checks_tied_runner_up
# Description:
# - Checks a tied runner-up before truncating to one result so the visible candidate remains
#   nonconfident.
# Parameters:
# - None.
# Returns:
# - None.
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

    # 표시 기본값이 1이어도 동점 후보는 함께 반환하여 임의 탈락을 막는다.
    assert len(result.candidates) == 2
    assert result.is_confident is False
    assert result.requires_confirmation is True


# 함수이름: test_tied_candidates_survive_default_limit
# 함수역할: 6번째 정답이 5개 표시 경계 때문에 누락되지 않는지 검증한다.
# 매개변수: 없음. 반환값: 비동기 검증 완료.
@pytest.mark.anyio
async def test_tied_candidates_survive_default_limit() -> None:
    features = PillVisualFeatures(shape="round", colors=("yellow",), front_imprint="YH")
    entries = tuple(_entry(f"{i:02}", f"후보{i}") for i in range(11))
    result = await _control(features, entries).requestPillIdentification(b"front")
    assert len(result.candidates) == 11
    assert result.candidates[5].item_seq == "05"
    assert not result.is_confident
    assert not result.has_more_candidates


# 함수이름: test_tie_response_cap_is_explicit
# 함수역할: 대량 동점 응답은 100개로 제한하되 누락 후보 존재를 HTTP 계약에 알린다.
# 매개변수: 없음. 반환값: 비동기 검증 완료.
@pytest.mark.anyio
async def test_tie_response_cap_is_explicit() -> None:
    from schemas.pill_identification import PillIdentificationResponse

    features = PillVisualFeatures(front_imprint="YH")
    entries = tuple(_entry(f"{i:03}", f"후보{i}") for i in range(145))
    result = await _control(features, entries).requestPillIdentification(b"front")
    assert len(result.candidates) == 100
    assert result.has_more_candidates
    assert not result.is_confident
    assert PillIdentificationResponse.from_domain(result).has_more_candidates
    assert result.requires_confirmation


# 함수이름: test_back_imprint_breaks_common_front_tie
# 함수역할: 동일한 앞면 각인의 여러 후보 중 사용자 대응 뒷면이 정답을 분리하는지 검증한다.
# 매개변수: 없음. 반환값: 비동기 검증 완료.
@pytest.mark.anyio
async def test_back_imprint_breaks_common_front_tie() -> None:
    entries = tuple(_entry(f"{i:02}", f"후보{i}", print_back="LT" if i == 5 else "RC2")
                    for i in range(11))
    features = PillVisualFeatures(shape="round", colors=("yellow",),
                                  front_imprint="YH", back_imprint="LT")
    result = await _control(features, entries).requestPillIdentification(b"front", b"back")
    assert result.candidates[0].item_seq == "05"
    assert result.is_confident
    assert result.requires_confirmation


# Function Name: test_failed_required_stage_cancels_sibling_work
# Description:
# - Propagates the required vision-stage quality error and cancels the sibling catalog lookup.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_cancelled_ranking_retains_shared_capacity_until_worker_exits
# Description:
# - Retains shared ranking capacity until the cancelled request's worker exits, preventing
#   overlap and allowing a later request to recover.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_cancelled_ranking_retains_shared_capacity_until_worker_exits() -> None:
    features = PillVisualFeatures(
        shape="round",
        colors=("yellow",),
        front_imprint="YH",
        quality="good",
    )
    control = _ConcurrencyTrackingIdentifyPill(
        vision_boundary=_FakeVisionBoundary(features),  # type: ignore[arg-type]
        catalog_boundary=_FakeCatalogBoundary((_entry("1", "pill"),)),  # type: ignore[arg-type]
        ranking_semaphore=asyncio.Semaphore(1),
    )
    first_request = asyncio.create_task(control.requestPillIdentification(b"front"))
    while not control.worker_started.is_set():
        await asyncio.sleep(0.001)

    first_request.cancel()
    with pytest.raises(asyncio.CancelledError):
        await first_request

    recovered = await control.requestPillIdentification(b"front")

    assert recovered.candidates
    assert control.maximum_active_workers == 1
    assert control.active_workers == 0


# Function Name: anyio_backend
# Description:
# - Selects asyncio as the backend for asynchronous pill-identification tests.
# Parameters:
# - None.
# Returns:
# - str: 'asyncio', the event loop backend selected for the test.
@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
