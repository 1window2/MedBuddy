# File Name: test_pill_identification_boundary.py
# Role: Regression coverage for pill-image quality, vision safety, resource cleanup, and bounded
#   complete MFDS catalog downloads.
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


# Class Name: _PassthroughImageProcessingBoundary
# Role: Image processor double that preserves input bytes for isolated vision-response tests.
# Responsibilities:
# - Returns image bytes unchanged so vision parsing can be exercised without preprocessing.
class _PassthroughImageProcessingBoundary:
    # Function Name: preprocessPillImage
    # Description:
    # - Returns image bytes unchanged so vision parsing can be exercised without
    #   preprocessing.
    # Parameters:
    # - image (bytes): Encoded pill photograph passed through the test boundary.
    # Returns:
    # - bytes: Input image bytes unchanged by the processing double.
    def preprocessPillImage(self, image: bytes) -> bytes:
        return image


# 클래스명: _FakeVisionAPI
# 역할: 정해진 시각 특징을 제공하고 뒷면 전달 여부와 요청 횟수를 기록하는 AI 대체 경계다.
# 주요 책임:
# - 요청 횟수와 뒷면 사진 여부를 기록하고 설정된 시각 특징을 JSON으로 반환한다.
# 속성:
# - payload (dict[str, Any]): JSON 직렬화 전의 시각 인식 결과.
# - received_back_image (bool): 선택적 뒷면 사진의 AI 요청 도달 여부.
# - request_count (int): 검증 조건에서 수행한 외부 요청 횟수.
class _FakeVisionAPI:
    # 함수이름: __init__
    # 함수역할:
    # - 반환할 특징 JSON과 초기 요청 횟수·뒷면 수신 상태를 준비한다.
    # 매개변수:
    # - payload (dict[str, Any]): JSON으로 직렬화할 시각 인식 응답 필드.
    # 반환값:
    # - 없음 (None).
    def __init__(self, payload: dict[str, Any]) -> None:
        self.payload = payload
        self.received_back_image = False
        self.request_count = 0

    # 함수이름: requestVisualFeatures
    # 함수역할:
    # - 요청 횟수와 뒷면 사진 여부를 기록하고 설정된 시각 특징을 JSON으로 반환한다.
    # 매개변수:
    # - **kwargs (object): 시각 인식 요청 필드이며 back_image 제공 여부를 기록하고 나머지 인자는 그대로 수용함.
    # 반환값:
    # - str: 설정된 시각 특징의 JSON 문자열.
    async def requestVisualFeatures(
        self,
        **kwargs: object,
    ) -> str:
        self.request_count += 1
        self.received_back_image = kwargs.get("back_image") is not None
        return json.dumps(self.payload)


# Class Name: _FailingVisionAPI
# Role: Vision API double that raises a private upstream connection failure.
# Responsibilities:
# - Raises an upstream connection error containing private details to test public-error
#   sanitization.
class _FailingVisionAPI:
    # Function Name: requestVisualFeatures
    # Description:
    # - Raises an upstream connection error containing private details to test public-error
    #   sanitization.
    # Parameters:
    # - **_kwargs (object): Vision request fields ignored before the injected upstream
    #   failure.
    # Returns:
    # - No normal result; raises the configured failure described above.
    async def requestVisualFeatures(self, **_kwargs: object) -> str:
        raise ConnectionError("private upstream failure")


# Class Name: _SlowImageProcessingBoundary
# Role: Image processor double that delays work to exercise preprocessing timeouts.
# Responsibilities:
# - Blocks briefly before returning the image unchanged so preprocessing exceeds a short
#   deadline.
class _SlowImageProcessingBoundary:
    # Function Name: preprocessPillImage
    # Description:
    # - Blocks briefly before returning the image unchanged so preprocessing exceeds a short
    #   deadline.
    # Parameters:
    # - image (bytes): Encoded pill photograph passed through the test boundary.
    # Returns:
    # - bytes: Input image bytes unchanged by the processing double.
    def preprocessPillImage(self, image: bytes) -> bytes:
        import time

        time.sleep(0.05)
        return image


# Class Name: _ConcurrencyTrackingImageProcessingBoundary
# Role: Image processor double that measures concurrent worker occupancy around delayed
#   preprocessing.
# Responsibilities:
# - Tracks peak preprocessing concurrency and always releases its active-worker count after
#   delayed work.
# Attributes:
# - _lock (threading.Lock): Lock protecting preprocessing worker counters.
# - active_workers (int): Number of worker threads still processing a request.
# - maximum_active_workers (int): Peak worker concurrency observed during the test.
# - delay_seconds (float): Artificial worker delay used to trigger deadline and concurrency
#   paths.
class _ConcurrencyTrackingImageProcessingBoundary:
    # Function Name: __init__
    # Description:
    # - Initializes synchronized worker counters and a configurable preprocessing delay.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.active_workers = 0
        self.maximum_active_workers = 0
        self.delay_seconds = 0.08

    # Function Name: preprocessPillImage
    # Description:
    # - Tracks peak preprocessing concurrency and always releases its active-worker count
    #   after delayed work.
    # Parameters:
    # - image (bytes): Encoded pill photograph passed through the test boundary.
    # Returns:
    # - bytes: Input image bytes unchanged by the processing double.
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


# Class Name: _FailingAsyncClient
# Role: Async client double that records cleanup and then fails during closure.
# Responsibilities:
# - Records asynchronous closure and raises an error to test fallback cleanup.
# Attributes:
# - close_called (bool): Whether client cleanup was invoked.
class _FailingAsyncClient:
    # Function Name: __init__
    # Description:
    # - Marks asynchronous cleanup as not yet called.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.close_called = False

    # Function Name: aclose
    # Description:
    # - Records asynchronous closure and raises an error to test fallback cleanup.
    # Parameters:
    # - None.
    # Returns:
    # - No normal result; raises the configured failure described above.
    async def aclose(self) -> None:
        self.close_called = True
        raise RuntimeError("async close failed")


# Class Name: _OwnedVisionClient
# Role: Owned vision client double exposing a failing async client and separately tracked
#   synchronous closure.
# Responsibilities:
# - Records synchronous closure even when asynchronous cleanup has failed.
# Attributes:
# - aio (_FailingAsyncClient): Gemini-compatible asynchronous namespace or owned async client.
# - close_called (bool): Whether client cleanup was invoked.
class _OwnedVisionClient:
    # Function Name: __init__
    # Description:
    # - Creates the failing asynchronous client and initializes the synchronous close
    #   marker.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.aio = _FailingAsyncClient()
        self.close_called = False

    # Function Name: close
    # Description:
    # - Records synchronous closure even when asynchronous cleanup has failed.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def close(self) -> None:
        self.close_called = True


# 함수이름: _valid_visual_payload
# 함수역할:
# - 정상 단일 알약의 양면 특징·품질·일치 확신도를 구성하고 선택한 필드를 덮어써 검증 입력을 만든다.
# 매개변수:
# - **overrides (object): 정상 기본값을 대체할 설정 또는 응답 필드.
# 반환값:
# - dict[str, Any]: 선택한 덮어쓰기 값을 반영한 정상 시각 특징 사전.
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
        "detected_pill_count": 1,
        "same_pill": True,
        "side_consistency_confidence": 1.0,
    }
    payload.update(overrides)
    return payload


# Function Name: _sample_image
# Description:
# - Encodes a synthetic yellow pill on a light background as JPEG bytes for preprocessing tests.
# Parameters:
# - None.
# Returns:
# - bytes: JPEG bytes of a synthetic centered yellow pill.
def _sample_image() -> bytes:
    image = np.full((500, 500, 3), 245, dtype=np.uint8)
    cv2.circle(image, (250, 250), 95, (30, 210, 230), thickness=-1)
    success, encoded = cv2.imencode(".jpg", image)
    assert success
    return encoded.tobytes()


# Function Name: test_image_preprocessing_rejects_invalid_data
# Description:
# - Rejects non-image input with a pill-quality error instead of attempting identification.
# Parameters:
# - None.
# Returns:
# - None.
def test_image_preprocessing_rejects_invalid_data() -> None:
    with pytest.raises(PillImageQualityError, match="valid image"):
        PillImageProcessingBoundary().preprocessPillImage(b"not-an-image")


# Function Name: test_image_preprocessing_rejects_oversized_dimensions_before_decode
# Description:
# - Rejects oversized image metadata before OpenCV can decode the pixel buffer.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
def test_image_preprocessing_rejects_oversized_dimensions_before_decode(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Class Name: _OversizedMetadata
    # Role: Image metadata context double exposing oversized dimensions without allocating
    #   image pixels.
    # Responsibilities:
    # - Returns the oversized metadata object when the image header context is entered.
    # - Leaves the metadata context without suppressing an exception.
    # Attributes:
    # - size (tuple): Oversized width and height exposed by the image metadata double.
    class _OversizedMetadata:
        size = (10_000, 10_000)

        # Function Name: __enter__
        # Description:
        # - Returns the oversized metadata object when the image header context is
        #   entered.
        # Parameters:
        # - None.
        # Returns:
        # - '_OversizedMetadata': The same oversized metadata object for header
        #   inspection.
        def __enter__(self) -> "_OversizedMetadata":
            return self

        # Function Name: __exit__
        # Description:
        # - Leaves the metadata context without suppressing an exception.
        # Parameters:
        # - *_args (object): Exception type, value, and traceback supplied on context
        #   exit; not suppressed.
        # Returns:
        # - None.
        def __exit__(self, *_args: object) -> None:
            return None

    monkeypatch.setattr(
        boundary_module.Image,
        "open",
        lambda _stream: _OversizedMetadata(),
    )

    # Function Name: fail_decode
    # Description:
    # - Fails immediately if pixel decoding is attempted after oversized metadata should
    #   already have been rejected.
    # Parameters:
    # - *_args (object): Positional interface arguments; ignored by this test double.
    # - **_kwargs (object): Keyword arguments accepted by the substituted service interface.
    # Returns:
    # - No normal result; raises the configured failure described above.
    def fail_decode(*_args: object, **_kwargs: object) -> None:
        raise AssertionError("OpenCV decode must not run for oversized metadata")

    monkeypatch.setattr(boundary_module.cv2, "imdecode", fail_decode)

    with pytest.raises(PillImageQualityError, match="too large"):
        PillImageProcessingBoundary().preprocessPillImage(b"image-header")


# Function Name: test_image_preprocessing_returns_bounded_jpeg
# Description:
# - Produces a decodable JPEG with dimensions between the minimum usable size and the 1600-pixel
#   bound.
# Parameters:
# - None.
# Returns:
# - None.
def test_image_preprocessing_returns_bounded_jpeg() -> None:
    processed = PillImageProcessingBoundary().preprocessPillImage(_sample_image())

    decoded = cv2.imdecode(np.frombuffer(processed, dtype=np.uint8), cv2.IMREAD_COLOR)
    assert decoded is not None
    assert max(decoded.shape[:2]) <= 1600
    assert min(decoded.shape[:2]) >= 64


# Function Name: test_image_preprocessing_downsamples_high_resolution_jpeg
# Description:
# - Downsamples a high-resolution JPEG to a decodable image within the 1600-pixel limit.
# Parameters:
# - None.
# Returns:
# - None.
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


# 함수이름: test_image_preprocessing_preserves_ambiguous_multi_object_frame
# 함수역할:
# - 복수 물체가 모호한 프레임은 임의로 자르지 않고 원래 크기와 두 알약 감지 결과를 유지하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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

    assessment = PillImageProcessingBoundary().preprocessPillImageWithAssessment(
        encoded.tobytes()
    )
    assert assessment.detected_pill_count == 2


# Function Name: test_image_preprocessing_ignores_edge_clutter_when_cropping
# Description:
# - Crops around the central pill rather than edge clutter and retains its yellow-dominant
#   center pixels.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_image_preprocessing_crops_high_contrast_pill_on_textured_frame
# Description:
# - Finds and crops a high-contrast pill despite a textured background.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_visual_boundary_accepts_small_pill_with_usable_features
# Description:
# - Accepts usable shape and color from a small pill while preserving its poor-quality
#   classification.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_visual_boundary_still_rejects_small_blurred_pill
# Description:
# - Rejects a small blurred pill with a retake-photo error despite size-tolerant preprocessing.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_visual_boundary_rejects_two_pills_even_when_one_is_small
# Description:
# - Rejects a two-pill image even when one pill occupies only a small area.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_visual_boundary_rejects_two_pills_even_when_one_is_small() -> None:
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_PassthroughImageProcessingBoundary(),
        vision_api=_FakeVisionAPI(
            _valid_visual_payload(
                quality="poor",
                quality_issues=["two pills are visible and one pill is small"],
            )
        ),  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    with pytest.raises(PillImageQualityError, match="retake"):
        await boundary.extractVisualFeatures(b"front")


# 함수이름: test_visual_boundary_rejects_multiple_local_contours_before_ai
# 함수역할:
# - 로컬 윤곽 검사에서 여러 알약을 발견하면 AI 호출 전에 거절하고 요청 횟수를 0으로 유지하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
@pytest.mark.anyio
async def test_visual_boundary_rejects_multiple_local_contours_before_ai() -> None:
    image = np.full((500, 700, 3), 245, dtype=np.uint8)
    cv2.circle(image, (210, 250), 80, (30, 210, 230), thickness=-1)
    cv2.circle(image, (490, 250), 80, (30, 210, 230), thickness=-1)
    success, encoded = cv2.imencode(".jpg", image)
    assert success
    vision_api = _FakeVisionAPI(_valid_visual_payload())
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=PillImageProcessingBoundary(),
        vision_api=vision_api,  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    with pytest.raises(PillImageQualityError, match="Multiple pills"):
        await boundary.extractVisualFeatures(encoded.tobytes())

    assert vision_api.request_count == 0


# 함수이름: test_visual_boundary_rejects_ai_multiple_pill_count
# 함수역할:
# - AI가 여러 알약을 감지한 응답을 재촬영이 필요한 품질 오류로 거절하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
@pytest.mark.anyio
async def test_visual_boundary_rejects_ai_multiple_pill_count() -> None:
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_PassthroughImageProcessingBoundary(),
        vision_api=_FakeVisionAPI(
            _valid_visual_payload(detected_pill_count=2)
        ),  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    with pytest.raises(PillImageQualityError, match="Multiple pills"):
        await boundary.extractVisualFeatures(b"front")


# 함수이름: test_visual_boundary_rejects_invalid_ai_pill_count
# 함수역할:
# - AI의 잘못된 알약 개수 값을 응답 형식 오류로 거절하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
@pytest.mark.anyio
async def test_visual_boundary_rejects_invalid_ai_pill_count() -> None:
    boundary = PillVisionBoundary(
        client=object(),  # type: ignore[arg-type]
        image_processing_boundary=_PassthroughImageProcessingBoundary(),
        vision_api=_FakeVisionAPI(
            _valid_visual_payload(detected_pill_count="two")
        ),  # type: ignore[arg-type]
        timeout_seconds=1,
    )

    with pytest.raises(PillVisionResponseError, match="invalid response"):
        await boundary.extractVisualFeatures(b"front")


# Function Name: test_visual_boundary_preserves_front_and_back_features
# Description:
# - Preserves front and back imprints and confirms the optional back image reached the vision
#   API.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_visual_boundary_discards_back_features_without_back_photo
# Description:
# - Discards invented back-side features without a back photo and restores single-photo
#   consistency defaults.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_visual_boundary_rejects_mismatched_front_and_back_photos
# Description:
# - Rejects front and back photos identified as different pills.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_visual_boundary_marks_uncertain_side_consistency
# Description:
# - Preserves uncertain side-consistency confidence and adds an explicit quality issue without
#   falsely declaring different pills.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_visual_boundary_rejects_poor_quality_result
# Description:
# - Rejects an unusable poor-quality vision result with a retake-photo error.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_visual_boundary_rejects_non_string_imprint
# Description:
# - Rejects a non-string imprint as an invalid vision response.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_visual_boundary_hides_upstream_failure_details
# Description:
# - Maps upstream failure to the public vision-unavailable error without exposing private
#   failure text.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_visual_boundary_applies_timeout_to_preprocessing_stage
# Description:
# - Applies the overall vision deadline to preprocessing, not only the external AI request.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_visual_timeout_keeps_preprocessing_capacity_until_worker_exits
# Description:
# - Keeps timed-out preprocessing workers within shared capacity until they exit and allows a
#   later request to recover without overlap.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_visual_boundary_rejects_empty_model_name
# Description:
# - Rejects an empty vision model name during boundary construction.
# Parameters:
# - None.
# Returns:
# - None.
def test_visual_boundary_rejects_empty_model_name() -> None:
    with pytest.raises(ValueError, match="model name"):
        PillVisionBoundary(client=object(), model_name=" ")  # type: ignore[arg-type]


# Function Name: test_visual_boundary_rejects_invalid_concurrency
# Description:
# - Rejects invalid preprocessing concurrency values during boundary construction.
# Parameters:
# - None.
# Returns:
# - None.
def test_visual_boundary_rejects_invalid_concurrency() -> None:
    with pytest.raises(ValueError, match="concurrency"):
        PillVisionBoundary(
            client=object(),  # type: ignore[arg-type]
            max_concurrency=0,
        )


# Function Name: test_visual_boundary_closes_sync_client_when_async_close_fails
# Description:
# - Closes the owned synchronous client even if asynchronous client cleanup raises, while
#   preserving that failure.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
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


# Function Name: test_mfds_catalog_parser_accepts_documented_response_shape
# Description:
# - Parses the documented MFDS response shape into the advertised count and correctly identified
#   official-image entry.
# Parameters:
# - None.
# Returns:
# - None.
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
                    "ITEM_IMAGE": "https://nedrug.mfds.go.kr/pill.jpg",
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
    assert entry.image_url == "https://nedrug.mfds.go.kr/pill.jpg"


# Function Name: test_mfds_catalog_rejects_non_network_image_url
# Description:
# - Drops a non-network image URL while retaining the otherwise valid catalog entry.
# Parameters:
# - None.
# Returns:
# - None.
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


# Function Name: test_mfds_catalog_rejects_structured_required_text
# Description:
# - Rejects catalog items whose required text fields contain structured values.
# Parameters:
# - item (dict[str, Any]): Medication or catalog payload being parsed or verified.
# Returns:
# - None.
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


# Function Name: test_mfds_api_downloads_and_normalizes_complete_catalog
# Description:
# - Downloads every advertised page, sorts the complete catalog by code, and normalizes
#   protocol-relative image URLs.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_mfds_api_downloads_and_normalizes_complete_catalog() -> None:
    requested_pages: list[int] = []

    # Function Name: handler
    # Description:
    # - Records page requests and serves three out-of-order entries across two pages with a
    #   stable total.
    # Parameters:
    # - request (httpx.Request): Intercepted HTTP request used to select or validate the
    #   mock response.
    # Returns:
    # - httpx.Response: Synthetic HTTP response containing the selected catalog page or byte
    #   stream.
    def handler(request: httpx.Request) -> httpx.Response:
        page_no = int(request.url.params["pageNo"])
        requested_pages.append(page_no)
        items = (
            [
                {
                    "ITEM_SEQ": "2",
                    "ITEM_NAME": "second",
                        "ITEM_IMAGE": "//nedrug.mfds.go.kr/2.jpg",
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

    # Function Name: client_factory
    # Description:
    # - Builds an HTTP client over the paginated mock transport while preserving requested
    #   timeout and connection limits.
    # Parameters:
    # - **kwargs (object): Timeout and connection limits forwarded to the mock HTTP client.
    # Returns:
    # - httpx.AsyncClient: Async HTTP client using only the scenario mock transport.
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
    assert catalog[1].image_url == "https://nedrug.mfds.go.kr/2.jpg"


# Function Name: test_mfds_api_reports_rejected_and_duplicate_rows
# Description:
# - Reports fetched, valid, unique, rejected, duplicate, page, and byte counts separately for a
#   mixed forty-row response.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_mfds_api_reports_rejected_and_duplicate_rows() -> None:
    # Function Name: handler
    # Description:
    # - Serves thirty-eight unique valid entries, one duplicate, and one invalid row with an
    #   advertised total of forty.
    # Parameters:
    # - _request (httpx.Request): Intercepted HTTP request used to select or validate the
    #   mock response. Unused by this double.
    # Returns:
    # - httpx.Response: Synthetic HTTP response containing the selected catalog page or byte
    #   stream.
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={
                "header": {"resultCode": "00"},
                "body": {
                    "totalCount": 40,
                    "items": [
                        *[
                            {
                                "ITEM_SEQ": str(index),
                                "ITEM_NAME": f"pill-{index}",
                            }
                            for index in range(1, 39)
                        ],
                        {"ITEM_SEQ": "1", "ITEM_NAME": "pill-1"},
                        {"ITEM_SEQ": "", "ITEM_NAME": "invalid"},
                    ],
                },
            },
        )

    # Function Name: client_factory
    # Description:
    # - Builds a bounded mock HTTP client for reconciliation-count reporting.
    # Parameters:
    # - **kwargs (object): Timeout and connection limits forwarded to the mock HTTP client.
    # Returns:
    # - httpx.AsyncClient: Async HTTP client using only the scenario mock transport.
    def client_factory(**kwargs: object) -> httpx.AsyncClient:
        return httpx.AsyncClient(
            transport=httpx.MockTransport(handler),
            timeout=kwargs["timeout"],
            limits=kwargs["limits"],
        )

    snapshot = await MFDSPillAPI(
        page_size=40,
        minimum_catalog_rows=1,
        client_factory=client_factory,
    ).requestCatalogSnapshot()

    assert len(snapshot.entries) == 38
    assert snapshot.report.advertised_rows == 40
    assert snapshot.report.fetched_rows == 40
    assert snapshot.report.valid_rows == 39
    assert snapshot.report.accepted_unique_rows == 38
    assert snapshot.report.rejected_rows == 1
    assert snapshot.report.duplicate_rows == 1
    assert snapshot.report.page_count == 1
    assert snapshot.report.response_bytes > 0


# Function Name: test_mfds_api_rejects_incomplete_multi_page_download
# Description:
# - Rejects a multi-page catalog that stops two rows short of the advertised total.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_mfds_api_rejects_incomplete_multi_page_download() -> None:
    # Function Name: handler
    # Description:
    # - Serves ten rows then eight while advertising twenty to simulate a truncated
    #   download.
    # Parameters:
    # - request (httpx.Request): Intercepted HTTP request used to select or validate the
    #   mock response.
    # Returns:
    # - httpx.Response: Synthetic HTTP response containing the selected catalog page or byte
    #   stream.
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

    # Function Name: client_factory
    # Description:
    # - Builds a bounded mock HTTP client for the two-row-short catalog response.
    # Parameters:
    # - **kwargs (object): Timeout and connection limits forwarded to the mock HTTP client.
    # Returns:
    # - httpx.AsyncClient: Async HTTP client using only the scenario mock transport.
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


# Function Name: test_mfds_api_requires_every_advertised_raw_row
# Description:
# - Rejects a catalog missing even one advertised raw row rather than tolerating a nearly
#   complete refresh.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_mfds_api_requires_every_advertised_raw_row() -> None:
    # Function Name: handler
    # Description:
    # - Serves ten rows then nine while advertising twenty to test strict completeness.
    # Parameters:
    # - request (httpx.Request): Intercepted HTTP request used to select or validate the
    #   mock response.
    # Returns:
    # - httpx.Response: Synthetic HTTP response containing the selected catalog page or byte
    #   stream.
    def handler(request: httpx.Request) -> httpx.Response:
        page_no = int(request.url.params["pageNo"])
        item_count = 10 if page_no == 1 else 9
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

    # Function Name: client_factory
    # Description:
    # - Builds a bounded mock HTTP client for the one-row-short catalog response.
    # Parameters:
    # - **kwargs (object): Timeout and connection limits forwarded to the mock HTTP client.
    # Returns:
    # - httpx.AsyncClient: Async HTTP client using only the scenario mock transport.
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
        await api.requestCatalogSnapshot()


# Function Name: test_mfds_api_rejects_oversized_chunked_page_response
# Description:
# - Rejects a chunked page exceeding the byte budget and retains the size failure as the request
#   error's cause.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
@pytest.mark.anyio
async def test_mfds_api_rejects_oversized_chunked_page_response(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Class Name: _OversizedStream
    # Role: Streaming response double that crosses the configured byte limit in separate
    #   chunks.
    # Responsibilities:
    # - Yields two ten-byte chunks to test cumulative response-size enforcement.
    class _OversizedStream(httpx.AsyncByteStream):
        # Function Name: __aiter__
        # Description:
        # - Yields two ten-byte chunks to test cumulative response-size enforcement.
        # Parameters:
        # - None.
        # Returns:
        # - Yields two ten-byte chunks whose combined size crosses the test limit.
        async def __aiter__(self) -> AsyncIterator[bytes]:
            yield b"x" * 10
            yield b"y" * 10

    # Function Name: handler
    # Description:
    # - Serves the oversized byte stream without a predeclared response length.
    # Parameters:
    # - _request (httpx.Request): Intercepted HTTP request used to select or validate the
    #   mock response. Unused by this double.
    # Returns:
    # - httpx.Response: Synthetic HTTP response containing the selected catalog page or byte
    #   stream.
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, stream=_OversizedStream())

    # Function Name: client_factory
    # Description:
    # - Builds a bounded mock HTTP client for streamed page-size enforcement.
    # Parameters:
    # - **kwargs (object): Timeout and connection limits forwarded to the mock HTTP client.
    # Returns:
    # - httpx.AsyncClient: Async HTTP client using only the scenario mock transport.
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


# Function Name: test_mfds_api_rejects_page_with_more_rows_than_requested
# Description:
# - Rejects a page containing more rows than requested and preserves the row-limit error as its
#   cause.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_mfds_api_rejects_page_with_more_rows_than_requested() -> None:
    # Function Name: handler
    # Description:
    # - Serves two entries in a response used to violate a one-row page request.
    # Parameters:
    # - _request (httpx.Request): Intercepted HTTP request used to select or validate the
    #   mock response. Unused by this double.
    # Returns:
    # - httpx.Response: Synthetic HTTP response containing the selected catalog page or byte
    #   stream.
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

    # Function Name: client_factory
    # Description:
    # - Builds a bounded mock HTTP client for per-page row-limit enforcement.
    # Parameters:
    # - **kwargs (object): Timeout and connection limits forwarded to the mock HTTP client.
    # Returns:
    # - httpx.AsyncClient: Async HTTP client using only the scenario mock transport.
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


# Function Name: test_mfds_api_rejects_inconsistent_page_totals
# Description:
# - Rejects a refresh whose upstream total changes between pages.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_mfds_api_rejects_inconsistent_page_totals() -> None:
    # Function Name: handler
    # Description:
    # - Serves one row per page while changing the advertised total from two to three.
    # Parameters:
    # - request (httpx.Request): Intercepted HTTP request used to select or validate the
    #   mock response.
    # Returns:
    # - httpx.Response: Synthetic HTTP response containing the selected catalog page or byte
    #   stream.
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

    # Function Name: client_factory
    # Description:
    # - Builds a bounded mock HTTP client for inconsistent upstream totals.
    # Parameters:
    # - **kwargs (object): Timeout and connection limits forwarded to the mock HTTP client.
    # Returns:
    # - httpx.AsyncClient: Async HTTP client using only the scenario mock transport.
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


# Function Name: test_mfds_api_rejects_aggregate_rows_above_advertised_total
# Description:
# - Rejects an aggregate download containing more rows than the advertised catalog total.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_mfds_api_rejects_aggregate_rows_above_advertised_total() -> None:
    # Function Name: handler
    # Description:
    # - Serves two rows on each page while advertising only three in total.
    # Parameters:
    # - request (httpx.Request): Intercepted HTTP request used to select or validate the
    #   mock response.
    # Returns:
    # - httpx.Response: Synthetic HTTP response containing the selected catalog page or byte
    #   stream.
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

    # Function Name: client_factory
    # Description:
    # - Builds a bounded mock HTTP client for aggregate row-count overflow.
    # Parameters:
    # - **kwargs (object): Timeout and connection limits forwarded to the mock HTTP client.
    # Returns:
    # - httpx.AsyncClient: Async HTTP client using only the scenario mock transport.
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


# Function Name: test_mfds_api_rejects_refresh_above_aggregate_byte_budget
# Description:
# - Rejects a refresh whose individually acceptable pages exceed the aggregate byte budget.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
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

    # Function Name: handler
    # Description:
    # - Serves the requested prebuilt JSON page for aggregate response-byte accounting.
    # Parameters:
    # - request (httpx.Request): Intercepted HTTP request used to select or validate the
    #   mock response.
    # Returns:
    # - httpx.Response: Synthetic HTTP response containing the selected catalog page or byte
    #   stream.
    def handler(request: httpx.Request) -> httpx.Response:
        page_no = int(request.url.params["pageNo"])
        return httpx.Response(
            200,
            content=payloads[page_no],
            headers={"content-type": "application/json"},
        )

    # Function Name: client_factory
    # Description:
    # - Builds a bounded mock HTTP client for aggregate response-size enforcement.
    # Parameters:
    # - **kwargs (object): Timeout and connection limits forwarded to the mock HTTP client.
    # Returns:
    # - httpx.AsyncClient: Async HTTP client using only the scenario mock transport.
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


# Function Name: test_mfds_api_rejects_invalid_configuration
# Description:
# - Rejects each invalid MFDS API configuration with the corresponding validation message.
# Parameters:
# - overrides (dict[str, object]): Selected configuration or response fields replacing the valid
#   defaults.
# - expected_message (str): Expected configuration validation error text.
# Returns:
# - None.
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


# Function Name: test_mfds_catalog_boundary_rejects_invalid_configuration
# Description:
# - Rejects each invalid catalog-boundary configuration with the corresponding validation
#   message.
# Parameters:
# - overrides (dict[str, object]): Selected configuration or response fields replacing the valid
#   defaults.
# - expected_message (str): Expected configuration validation error text.
# Returns:
# - None.
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


# Function Name: anyio_backend
# Description:
# - Selects asyncio for asynchronous vision and catalog boundary tests.
# Parameters:
# - None.
# Returns:
# - str: 'asyncio', the event loop backend selected for the test.
@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
