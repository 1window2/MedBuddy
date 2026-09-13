# File Name: pill_identification_boundary.py
# Role: Image-analysis and public-catalog boundaries for loose-pill identification.

import asyncio
import json
import logging
import math
import time
from collections.abc import Callable
from dataclasses import dataclass, replace
from datetime import timedelta
from io import BytesIO
from typing import Any, TypeVar
from urllib.parse import urlsplit

import cv2
import httpx
import numpy as np
from google import genai
from google.genai import types
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy.orm import Session

from core.config import settings
from entities.medication_image_url_entity import safe_medication_image_url
from entities.pill_identification_entity import (
    PillBoundingBox,
    PillCatalogDownloadReport,
    PillCatalogEntry,
    PillCatalogSnapshot,
    PillVisualFeatures,
)
from repositories.pill_identification_catalog_repository import (
    PillIdentificationCatalogRepository,
    open_pill_catalog_session,
)

logger = logging.getLogger(__name__)

_CatalogIOResult = TypeVar("_CatalogIOResult")

MAX_PILL_IMAGE_BYTES = 10 * 1024 * 1024
MAX_PILL_IMAGE_PIXELS = 24_000_000


# Class Name: PillImageQualityError
# Role:
# - Signals that a pill photo lacks safe, reliable evidence for analysis.
# Responsibilities:
# - Report invalid images, unsafe sizes, multiple pills or insufficient visual quality as retake conditions.
class PillImageQualityError(ValueError):
    """Raised when a pill photo cannot be analyzed safely or reliably."""


# Class Name: PillCatalogUnavailableError
# Role:
# - Signals that no usable public pill-catalog snapshot can be served.
# Responsibilities:
# - Distinguish unavailable or unsynchronized reference data from image-analysis failures.
class PillCatalogUnavailableError(RuntimeError):
    """Raised when neither MFDS nor the local catalog cache is available."""


# Class Name: PillVisionUnavailableError
# Role:
# - Signals temporary failure of the external visual-attribute service.
# Responsibilities:
# - Wrap provider execution errors without exposing SDK details to use-case controls.
class PillVisionUnavailableError(RuntimeError):
    """Raised when the external visual-attribute service is unavailable."""


# Class Name: PillVisionResponseError
# Role:
# - Signals an invalid visual-analysis response contract.
# Responsibilities:
# - Separate malformed or inconsistent provider output from image quality and network availability errors.
class PillVisionResponseError(RuntimeError):
    """Raised when the visual service returns an invalid response contract."""


# 클래스명: PillImagePreprocessingResult
# 역할:
# - 정규화된 이미지와 보수적으로 판정한 알약 수를 함께 전달한다.
# 주요 책임:
# - 확실히 구분한 개수만 제공하여 복수 알약 사진을 외부 AI 호출 전에 거부할 수 있게 한다.
# 속성:
# - image (bytes): 전처리한 JPEG 이미지.
# - detected_pill_count (int | None): 확실한 윤곽 개수; 판단할 수 없으면 None.
@dataclass(frozen=True)
class PillImagePreprocessingResult:
    """전처리 이미지와 보수적으로 판정한 알약 개수를 함께 전달한다."""

    image: bytes
    detected_pill_count: int | None


# Class Name: MultiplePillImagePreprocessingResult
# Role:
# - Carries a normalized photo whose full composition is preserved for multiple-pill detection.
# Responsibilities:
# - Keep JPEG bytes and resulting dimensions together so spatial observations refer to the analyzed image.
# Attributes:
# - image (bytes): Composition-preserving JPEG.
# - width / height (int): Normalized image dimensions in pixels.
@dataclass(frozen=True)
class MultiplePillImagePreprocessingResult:
    """Composition-preserving JPEG used for one-photo object detection."""

    image: bytes
    width: int
    height: int


# Class Name: PillImageProcessingBoundary
# Role:
# - Bounds, decodes and normalizes uploaded pill photographs.
# Responsibilities:
# - Enforce byte/pixel limits and EXIF orientation, crop conservative single-pill foregrounds and preserve multi-pill composition.
# Attributes:
# - _MAX_ANALYSIS_DIMENSION (int): Longest analysis side, 1600 pixels.
# - _MIN_IMAGE_DIMENSION (int): Minimum accepted decoded dimension, 128 pixels.
class PillImageProcessingBoundary:
    """Bounds, decodes, crops, and normalizes an uploaded pill photo."""

    _MAX_ANALYSIS_DIMENSION = 1600
    _MIN_IMAGE_DIMENSION = 128

    # 함수이름: preprocessPillImage
    # 함수역할:
    # - 개수 판정을 포함한 전처리를 사용하되 기존 호출자에게 정규화 이미지 바이트만 돌려준다.
    # 매개변수:
    # - image (bytes): 업로드한 원본 알약 사진 바이트.
    # 반환값:
    # - 분석용 JPEG 바이트; 유효하지 않은 이미지는 PillImageQualityError.
    def preprocessPillImage(self, image: bytes) -> bytes:
        return self.preprocessPillImageWithAssessment(image).image

    # Function Name: preprocessMultiplePillImage
    # Description:
    # - Validate and resize the image, then encode JPEG without cropping away object positions.
    # Parameters:
    # - image (bytes): Uploaded photo bytes containing one or more pills.
    # Returns:
    # - JPEG bytes and normalized dimensions; raises PillImageQualityError if decoding or encoding fails.
    def preprocessMultiplePillImage(
        self,
        image: bytes,
    ) -> MultiplePillImagePreprocessingResult:
        """Validates and bounds an image without cropping away spatial context."""

        decoded = self._decode_bounded_image(image)
        normalized = self._resize_for_analysis(decoded)
        height, width = normalized.shape[:2]
        success, output = cv2.imencode(
            ".jpg",
            normalized,
            [cv2.IMWRITE_JPEG_QUALITY, 90],
        )
        if not success:
            raise PillImageQualityError("The pill image could not be normalized.")
        return MultiplePillImagePreprocessingResult(
            image=output.tobytes(),
            width=width,
            height=height,
        )

    # Function Name: preprocessPillImageWithAssessment
    # Description:
    # - Decode and resize a photo, conservatively crop likely foreground and encode the assessed result as JPEG.
    # Parameters:
    # - image (bytes): Original uploaded pill-image bytes.
    # Returns:
    # - Normalized JPEG and locally detected pill count, with None when count evidence is inconclusive.
    def preprocessPillImageWithAssessment(
        self,
        image: bytes,
    ) -> PillImagePreprocessingResult:
        """이미지를 정규화하고 확실히 구분되는 알약 개수만 함께 반환한다."""

        decoded = self._decode_bounded_image(image)

        normalized = self._resize_for_analysis(decoded)
        cropped, detected_pill_count = self._crop_likely_foreground(normalized)
        success, output = cv2.imencode(
            ".jpg",
            cropped,
            [cv2.IMWRITE_JPEG_QUALITY, 90],
        )
        if not success:
            raise PillImageQualityError("The pill image could not be normalized.")
        return PillImagePreprocessingResult(
            image=output.tobytes(),
            detected_pill_count=detected_pill_count,
        )

    # Function Name: _decode_bounded_image
    # Description:
    # - Reject empty, oversized or undersized images before decoding; apply EXIF orientation and bound dimensions for analysis.
    # Parameters:
    # - image (bytes): Encoded upload bytes, limited to 10 MiB and 24 million source pixels.
    # Returns:
    # - Oriented BGR uint8 image array; raises PillImageQualityError for unsafe or invalid input.
    def _decode_bounded_image(self, image: bytes) -> np.ndarray:
        """Decodes an oriented RGB image after byte and pixel bounds are checked."""

        if not image:
            raise PillImageQualityError("The pill image is empty.")
        if len(image) > MAX_PILL_IMAGE_BYTES:
            raise PillImageQualityError("The pill image must be 10 MB or smaller.")
        try:
            with Image.open(BytesIO(image)) as source:
                width, height = source.size
                if min(height, width) < self._MIN_IMAGE_DIMENSION:
                    raise PillImageQualityError(
                        "The pill image resolution is too small."
                    )
                if height * width > MAX_PILL_IMAGE_PIXELS:
                    raise PillImageQualityError(
                        "The pill image resolution is too large."
                    )
                if source.format == "JPEG":
                    source.draft(
                        "RGB",
                        (self._MAX_ANALYSIS_DIMENSION, self._MAX_ANALYSIS_DIMENSION),
                    )
                source.load()
                oriented = ImageOps.exif_transpose(source)
                oriented.thumbnail(
                    (self._MAX_ANALYSIS_DIMENSION, self._MAX_ANALYSIS_DIMENSION),
                    Image.Resampling.LANCZOS,
                )
                decoded = cv2.cvtColor(
                    np.asarray(oriented.convert("RGB"), dtype=np.uint8),
                    cv2.COLOR_RGB2BGR,
                )
        except PillImageQualityError:
            raise
        except (
            Image.DecompressionBombError,
            UnidentifiedImageError,
            OSError,
            ValueError,
        ) as exc:
            raise PillImageQualityError(
                "The uploaded file is not a valid image."
            ) from exc
        if min(decoded.shape[:2]) < self._MIN_IMAGE_DIMENSION:
            raise PillImageQualityError("The pill image resolution is too small.")
        return decoded

    # Function Name: _resize_for_analysis
    # Description:
    # - Keep already bounded images unchanged or downscale proportionally so the longest side is at most 1600 pixels.
    # Parameters:
    # - image (np.ndarray): Decoded image array to resize for analysis.
    # Returns:
    # - Original or area-resampled BGR image array.
    def _resize_for_analysis(self, image: np.ndarray) -> np.ndarray:
        height, width = image.shape[:2]
        longest_side = max(height, width)
        if longest_side <= self._MAX_ANALYSIS_DIMENSION:
            return image

        scale = self._MAX_ANALYSIS_DIMENSION / longest_side
        return cv2.resize(
            image,
            (max(1, round(width * scale)), max(1, round(height * scale))),
            interpolation=cv2.INTER_AREA,
        )

    # 함수이름: _crop_likely_foreground
    # 함수역할:
    # - 테두리 배경색과의 대비로 윤곽을 추리고 형상·중심·면적 점수로 전경 후보를 고른다.
    # - 비슷한 고신뢰 후보가 여러 개면 구도를 보존하며 개수를 반환하고, 단일 후보는 여백을 두어 자른다.
    # 매개변수:
    # - image (np.ndarray): 크기가 제한된 BGR 이미지 배열.
    # 반환값:
    # - 전경 이미지와 확실한 개수; 적합한 후보가 없거나 너무 작으면 원본과 None.
    def _crop_likely_foreground(
        self,
        image: np.ndarray,
    ) -> tuple[np.ndarray, int | None]:
        height, width = image.shape[:2]
        border_size = max(2, min(height, width) // 40)
        border_pixels = np.concatenate(
            [
                image[:border_size, :, :].reshape(-1, 3),
                image[-border_size:, :, :].reshape(-1, 3),
                image[:, :border_size, :].reshape(-1, 3),
                image[:, -border_size:, :].reshape(-1, 3),
            ],
            axis=0,
        )
        background_bgr = np.median(border_pixels, axis=0).astype(np.uint8)
        image_lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB).astype(np.float32)
        background_lab = cv2.cvtColor(
            background_bgr.reshape(1, 1, 3),
            cv2.COLOR_BGR2LAB,
        ).astype(np.float32)[0, 0]
        color_distance = np.linalg.norm(image_lab - background_lab, axis=2)
        mask = np.where(color_distance >= 18.0, 255, 0).astype(np.uint8)

        kernel_size = max(3, min(height, width) // 120)
        if kernel_size % 2 == 0:
            kernel_size += 1
        kernel = cv2.getStructuringElement(
            cv2.MORPH_ELLIPSE,
            (kernel_size, kernel_size),
        )
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
        contours, _ = cv2.findContours(
            mask,
            cv2.RETR_EXTERNAL,
            cv2.CHAIN_APPROX_SIMPLE,
        )
        if not contours:
            return image, None

        image_area = float(height * width)
        frame_margin = max(border_size, min(height, width) // 100)
        crop_candidates: list[tuple[float, float, np.ndarray]] = []
        for contour in contours:
            contour_area = cv2.contourArea(contour)
            area_ratio = contour_area / image_area
            if not 0.003 <= area_ratio <= 0.45:
                continue

            x, y, crop_width, crop_height = cv2.boundingRect(contour)
            if (
                x <= frame_margin
                or y <= frame_margin
                or x + crop_width >= width - frame_margin
                or y + crop_height >= height - frame_margin
            ):
                continue

            perimeter = cv2.arcLength(contour, closed=True)
            hull_area = cv2.contourArea(cv2.convexHull(contour))
            bounding_area = float(crop_width * crop_height)
            if perimeter <= 0 or hull_area <= 0 or bounding_area <= 0:
                continue

            solidity = contour_area / hull_area
            extent = contour_area / bounding_area
            aspect_ratio = crop_width / crop_height
            circularity = 4.0 * math.pi * contour_area / (perimeter * perimeter)
            contour_mask = np.zeros((crop_height, crop_width), dtype=np.uint8)
            shifted_contour = contour - np.array([[[x, y]]], dtype=contour.dtype)
            cv2.drawContours(contour_mask, [shifted_contour], -1, 255, -1)
            mean_contrast = cv2.mean(
                color_distance[y : y + crop_height, x : x + crop_width],
                mask=contour_mask,
            )[0]
            if (
                solidity < 0.72
                or extent < 0.38
                or not 0.2 <= aspect_ratio <= 5.0
                or circularity < 0.18
                or mean_contrast < 35.0
            ):
                continue

            center_x = x + crop_width / 2.0
            center_y = y + crop_height / 2.0
            normalized_distance = math.hypot(
                (center_x - width / 2.0) / (width / 2.0),
                (center_y - height / 2.0) / (height / 2.0),
            )
            center_score = max(0.0, 1.0 - min(1.0, normalized_distance))
            shape_score = (
                0.4 * solidity
                + 0.35 * extent
                + 0.25 * min(1.0, circularity / 0.7)
            )
            area_score = min(1.0, area_ratio / 0.04)
            contrast_score = min(1.0, (mean_contrast - 18.0) / 70.0)
            score = (
                0.45 * shape_score
                + 0.20 * center_score
                + 0.15 * area_score
                + 0.20 * contrast_score
            )
            crop_candidates.append((score, area_ratio, contour))

        if not crop_candidates:
            return image, None

        # Function Name: foreground ranking lambda
        # Description:
        # - Select the composite foreground score used by descending candidate sorting.
        # Parameters:
        # - candidate (tuple): Foreground score, area ratio and contour.
        # Returns:
        # - Composite score; higher scores are sorted first.
        crop_candidates.sort(key=lambda candidate: candidate[0], reverse=True)
        best_score, best_area_ratio, contour = crop_candidates[0]
        comparable_candidates = [
            candidate
            for candidate in crop_candidates
            if candidate[0] >= max(0.72, best_score * 0.93)
            and 0.5 <= candidate[1] / best_area_ratio <= 2.0
        ]
        if len(comparable_candidates) > 1:
            # 서로 분리된 고신뢰 윤곽이 여러 개면 원본 구도를 보존하고
            # 외부 AI를 호출하기 전에 재촬영 대상으로 처리한다.
            return image, len(comparable_candidates)

        x, y, crop_width, crop_height = cv2.boundingRect(contour)
        padding = max(12, round(max(crop_width, crop_height) * 0.12))
        left = max(0, x - padding)
        top = max(0, y - padding)
        right = min(width, x + crop_width + padding)
        bottom = min(height, y + crop_height + padding)
        if right - left < self._MIN_IMAGE_DIMENSION // 2:
            return image, None
        if bottom - top < self._MIN_IMAGE_DIMENSION // 2:
            return image, None
        return image[top:bottom, left:right], 1


# Class Name: GeminiPillVisionAPI
# Role:
# - Extracts visible pill attributes through Gemini without identifying products.
# Responsibilities:
# - Send one/two-sided JPEG evidence or one multiple-pill photo with constrained JSON schemas and reject empty output.
class GeminiPillVisionAPI:
    """External Gemini boundary that extracts only visible pill attributes."""

    # Function Name: requestVisualFeatures
    # Description:
    # - Submit front and optional back JPEGs with visible-attribute-only instructions and constrained JSON generation.
    # Parameters:
    # - client (genai.Client): Gemini client used for the visual request.
    # - model_name (str): Gemini model identifier used for generation.
    # - front_image (bytes): Preprocessed front-side JPEG bytes.
    # - back_image (bytes | None): Optional preprocessed reverse-side JPEG bytes.
    # - response_schema (dict[str, Any]): JSON schema for single-pill visual attributes.
    # Returns:
    # - Nonblank provider JSON text; raises PillVisionResponseError for an empty response.
    async def requestVisualFeatures(
        self,
        *,
        client: genai.Client,
        model_name: str,
        front_image: bytes,
        back_image: bytes | None,
        response_schema: dict[str, Any],
    ) -> str:
        contents: list[Any] = [
            self._prompt(has_back_image=back_image is not None),
            types.Part.from_bytes(data=front_image, mime_type="image/jpeg"),
        ]
        if back_image is not None:
            contents.append(
                types.Part.from_bytes(data=back_image, mime_type="image/jpeg")
            )

        response = await client.aio.models.generate_content(
            model=model_name,
            contents=contents,
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=response_schema,
                temperature=0.0,
                thinking_config=types.ThinkingConfig(
                    thinking_level=types.ThinkingLevel.MINIMAL,
                ),
                media_resolution=types.MediaResolution.MEDIA_RESOLUTION_HIGH,
                max_output_tokens=512,
            ),
        )
        response_text = response.text
        if not response_text or not response_text.strip():
            raise PillVisionResponseError(
                "The visual analysis returned an invalid response."
            )
        return response_text

    # Function Name: requestMultipleVisualFeatures
    # Description:
    # - Submit a composition-preserving JPEG for per-object detection and visible-feature extraction without guessing product names.
    # Parameters:
    # - client (genai.Client): Gemini client used for the visual request.
    # - model_name (str): Gemini model identifier used for generation.
    # - image (bytes): Normalized JPEG containing all photographed pills.
    # - response_schema (dict[str, Any]): JSON schema for bounded boxes and per-pill attributes.
    # Returns:
    # - Nonblank multiple-pill JSON text; raises PillVisionResponseError for empty output.
    async def requestMultipleVisualFeatures(
        self,
        *,
        client: genai.Client,
        model_name: str,
        image: bytes,
        response_schema: dict[str, Any],
    ) -> str:
        """Detects every distinct pill and extracts only visible attributes."""

        response = await client.aio.models.generate_content(
            model=model_name,
            contents=[
                self._multiple_prompt(),
                types.Part.from_bytes(data=image, mime_type="image/jpeg"),
            ],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=response_schema,
                temperature=0.0,
                thinking_config=types.ThinkingConfig(
                    thinking_level=types.ThinkingLevel.MINIMAL,
                ),
                media_resolution=types.MediaResolution.MEDIA_RESOLUTION_HIGH,
                max_output_tokens=4096,
            ),
        )
        response_text = response.text
        if not response_text or not response_text.strip():
            raise PillVisionResponseError(
                "The multiple-pill analysis returned an invalid response."
            )
        return response_text

    # 함수이름: _prompt
    # 함수역할:
    # - 뒷면 사진 유무에 맞춘 지시문과 제품명 추측 금지, 각인·품질·개수 및 양면 일치 판정 규칙을 만든다.
    # 매개변수:
    # - has_back_image (bool): 같은 알약의 반대쪽 사진이 함께 제공되었는지 여부.
    # 반환값:
    # - 관찰 가능한 물리적 특징만 요청하는 영어 프롬프트.
    @staticmethod
    def _prompt(*, has_back_image: bool) -> str:
        back_instruction = (
            "A second image was supplied. Compare both images and report whether "
            "they show opposite sides of the same pill."
            if has_back_image
            else "No reverse-side image was supplied; leave back-side fields empty, "
            "set same_pill to true, and set side_consistency_confidence to 1.0."
        )
        return f"""
        Extract visible physical attributes from the photographed loose pill.
        The first image is the front side. {back_instruction}

        Safety rules:
        - Do not identify or guess a medicine or product name.
        - Read only characters that are visibly imprinted or engraved.
        - Use an empty string when imprint text is unreadable.
        - Search the entire image for the pill even when it occupies a small
          portion of the frame.
        - Any background color or texture is acceptable. Background texture
          alone is not an image-quality defect.
        - Mark quality as poor only when blur, glare, occlusion, multiple pills,
          or missing visual evidence prevents reliable attribute extraction.
        - detected_pill_count is the greatest number of distinct physical pills
          visible in either supplied image. Front and back images of the same pill
          still mean detected_pill_count is 1.
        - When two images are supplied, compare shape, color, score lines, and
          imprints. Set same_pill to false if they appear to be different pills.
        - side_consistency_confidence must be between 0.0 and 1.0.
        - Return only the requested JSON object.
        """

    # Function Name: _multiple_prompt
    # Description:
    # - Require one spatial observation per physical pill, normalized tight boxes and no invented reverse-side markings.
    # Parameters:
    # - None.
    # Returns:
    # - Prompt requesting at most ten pills in top-to-bottom, then left-to-right order.
    @staticmethod
    def _multiple_prompt() -> str:
        return """
        Detect every distinct loose pill, tablet, or capsule visible in this one
        image. Return one object per physical pill, even when pills look identical.
        box_2d is [ymin, xmin, ymax, xmax], normalized to integers from 0 to 1000.

        Safety rules:
        - Do not identify or guess medicine or product names.
        - Ignore packaging text, fingers, hands, bags, bottles, and printed labels.
        - Read only characters visibly imprinted or engraved on each pill.
        - Do not invent hidden reverse-side markings; back fields must be empty or unknown.
        - A partially occluded or blurry pill remains a separate object, but mark its
          quality poor and explain why.
        - Tight boxes must contain the complete visible pill and minimal background.
        - Return at most 10 pills in top-to-bottom, then left-to-right reading order.
        - Return only the requested JSON object.
        """


# Class Name: PillVisionBoundary
# Role:
# - Coordinates bounded local preprocessing and external pill-attribute extraction.
# Responsibilities:
# - Limit concurrent analysis and decode work, validate feature schemas and check pill count and front/back consistency.
# - Validate multi-pill boxes and reject duplicate or implausibly overlapping observations.
# Attributes:
# - client (genai.Client): Owned or injected Gemini transport.
# - image_processing_boundary (PillImageProcessingBoundary): Local normalization and count assessment.
# - vision_api (GeminiPillVisionAPI): External visible-feature adapter.
# - _analysis_semaphore / _preprocessing_semaphore (asyncio.Semaphore): Analysis and decode capacity.
# - timeout_seconds (float): Whole-analysis time budget.
class PillVisionBoundary:
    """Coordinates bounded local preprocessing and visual attribute extraction."""

    _NON_BLOCKING_QUALITY_MARKERS = (
        "pill occupies too little",
        "pill is small",
        "small portion",
        "background texture",
        "textured background",
        "imprint is unreadable",
        "imprint unreadable",
    )
    _BLOCKING_QUALITY_MARKERS = (
        "blur",
        "glare",
        "occlusion",
        "occluded",
        "multiple pill",
        "more than one pill",
        "two pill",
        "three pill",
        "several pill",
        "multiple tablet",
        "more than one tablet",
        "two tablet",
        "multiple capsule",
        "more than one capsule",
        "two capsule",
        "no pill",
        "missing pill",
        "not visible",
        "cannot extract",
    )

    _SHAPES = (
        "round",
        "oval",
        "oblong",
        "semicircle",
        "triangle",
        "square",
        "diamond",
        "pentagon",
        "hexagon",
        "octagon",
        "other",
        "unknown",
    )
    _COLORS = (
        "white",
        "yellow",
        "orange",
        "pink",
        "red",
        "brown",
        "light_green",
        "green",
        "teal",
        "blue",
        "navy",
        "purple",
        "gray",
        "black",
        "transparent",
        "other",
        "unknown",
    )
    _LINES = ("none", "minus", "plus", "other", "unknown")
    _QUALITIES = ("good", "usable", "poor")
    _RESPONSE_SCHEMA: dict[str, Any] = {
        "type": "OBJECT",
        "required": [
            "shape",
            "colors",
            "front_imprint",
            "back_imprint",
            "front_line",
            "back_line",
            "quality",
            "quality_issues",
            "detected_pill_count",
            "same_pill",
            "side_consistency_confidence",
        ],
        "properties": {
            "shape": {"type": "STRING", "enum": list(_SHAPES)},
            "colors": {
                "type": "ARRAY",
                "items": {"type": "STRING", "enum": list(_COLORS)},
                "maxItems": 2,
            },
            "front_imprint": {"type": "STRING", "maxLength": 32},
            "back_imprint": {"type": "STRING", "maxLength": 32},
            "front_line": {"type": "STRING", "enum": list(_LINES)},
            "back_line": {"type": "STRING", "enum": list(_LINES)},
            "quality": {"type": "STRING", "enum": list(_QUALITIES)},
            "quality_issues": {
                "type": "ARRAY",
                "items": {"type": "STRING", "maxLength": 80},
                "maxItems": 5,
            },
            "detected_pill_count": {
                "type": "INTEGER",
                "minimum": 1,
                "maximum": 10,
            },
            "same_pill": {"type": "BOOLEAN"},
            "side_consistency_confidence": {
                "type": "NUMBER",
                "minimum": 0.0,
                "maximum": 1.0,
            },
        },
    }
    _MULTI_RESPONSE_SCHEMA: dict[str, Any] = {
        "type": "OBJECT",
        "required": ["pills"],
        "properties": {
            "pills": {
                "type": "ARRAY",
                "minItems": 1,
                "maxItems": 10,
                "items": {
                    "type": "OBJECT",
                    "required": [
                        "box_2d",
                        "shape",
                        "colors",
                        "front_imprint",
                        "front_line",
                        "quality",
                        "quality_issues",
                    ],
                    "properties": {
                        "box_2d": {
                            "type": "ARRAY",
                            "minItems": 4,
                            "maxItems": 4,
                            "items": {
                                "type": "INTEGER",
                                "minimum": 0,
                                "maximum": 1000,
                            },
                        },
                        "shape": {"type": "STRING", "enum": list(_SHAPES)},
                        "colors": {
                            "type": "ARRAY",
                            "items": {"type": "STRING", "enum": list(_COLORS)},
                            "maxItems": 2,
                        },
                        "front_imprint": {"type": "STRING", "maxLength": 32},
                        "front_line": {"type": "STRING", "enum": list(_LINES)},
                        "quality": {"type": "STRING", "enum": list(_QUALITIES)},
                        "quality_issues": {
                            "type": "ARRAY",
                            "items": {"type": "STRING", "maxLength": 80},
                            "maxItems": 5,
                        },
                    },
                },
            }
        },
    }

    # Function Name: __init__
    # Description:
    # - Resolve model, timeout and injected boundaries; validate concurrency and create separate analysis/preprocessing capacity guards.
    # Parameters:
    # - client (genai.Client | None): Optional borrowed Gemini client; omitted to create an owned v1alpha client.
    # - model_name (str | None): Optional Gemini model ID; None reads the configured pill model.
    # - image_processing_boundary (PillImageProcessingBoundary | None): Optional local image normalization and count-assessment implementation.
    # - vision_api (GeminiPillVisionAPI | None): Optional Gemini visible-feature request adapter.
    # - timeout_seconds (float | None): Maximum external request duration in seconds; None uses settings.
    # - max_concurrency (int): Maximum concurrent analyses and preprocessing workers, from 1 through 16.
    # Returns:
    # - None; invalid concurrency, blank model or nonpositive timeout raises ValueError.
    def __init__(
        self,
        *,
        client: genai.Client | None = None,
        model_name: str | None = None,
        image_processing_boundary: PillImageProcessingBoundary | None = None,
        vision_api: GeminiPillVisionAPI | None = None,
        timeout_seconds: float | None = None,
        max_concurrency: int = 4,
    ) -> None:
        if max_concurrency < 1 or max_concurrency > 16:
            raise ValueError("Pill vision concurrency must be between 1 and 16.")
        self._owns_client = client is None
        self.client = client or genai.Client(
            api_key=settings.GEMINI_API_KEY,
            http_options={"api_version": "v1alpha"},
        )
        self.model_name = (
            model_name
            if model_name is not None
            else settings.PILL_IDENTIFICATION_MODEL_NAME
        ).strip()
        if not self.model_name:
            raise ValueError("Pill identification model name must not be empty.")
        self.image_processing_boundary = (
            image_processing_boundary or PillImageProcessingBoundary()
        )
        self.vision_api = vision_api or GeminiPillVisionAPI()
        self.timeout_seconds = (
            timeout_seconds
            if timeout_seconds is not None
            else settings.PILL_IDENTIFICATION_TIMEOUT_SECONDS
        )
        if self.timeout_seconds <= 0:
            raise ValueError("Pill identification timeout must be positive.")
        self._analysis_semaphore = asyncio.Semaphore(max_concurrency)
        self._preprocessing_semaphore = asyncio.Semaphore(max_concurrency)

    # Function Name: extractVisualFeatures
    # Description:
    # - Bound semaphore waiting and single-pill analysis by the overall timeout.
    # Parameters:
    # - front_image (bytes): Original front-side image bytes.
    # - back_image (bytes | None): Optional original reverse-side image bytes.
    # Returns:
    # - Validated single-pill features; timeout is re-raised with a pill-analysis message.
    async def extractVisualFeatures(
        self,
        front_image: bytes,
        back_image: bytes | None = None,
    ) -> PillVisualFeatures:
        try:
            async with asyncio.timeout(self.timeout_seconds):
                async with self._analysis_semaphore:
                    return await self._extract_visual_features(
                        front_image,
                        back_image,
                    )
        except TimeoutError as exc:
            raise TimeoutError("Pill visual analysis timed out.") from exc

    # Function Name: extractMultipleVisualFeatures
    # Description:
    # - Bound concurrent multi-pill analysis, preprocess without cropping and validate the spatial provider response.
    # Parameters:
    # - image (bytes): Original photo containing up to ten pills to analyze separately.
    # Returns:
    # - Immutable, spatially ordered box/feature pairs; raises quality, response, timeout or availability errors.
    async def extractMultipleVisualFeatures(
        self,
        image: bytes,
    ) -> tuple[tuple[PillBoundingBox, PillVisualFeatures], ...]:
        """Returns validated, spatially ordered observations from one image."""

        try:
            async with asyncio.timeout(self.timeout_seconds):
                async with self._analysis_semaphore:
                    processed = await asyncio.to_thread(
                        self.image_processing_boundary.preprocessMultiplePillImage,
                        image,
                    )
                    response_text = await self.vision_api.requestMultipleVisualFeatures(
                        client=self.client,
                        model_name=self.model_name,
                        image=processed.image,
                        response_schema=self._MULTI_RESPONSE_SCHEMA,
                    )
                    return self._parse_multiple_visual_features(response_text)
        except TimeoutError as exc:
            raise TimeoutError("Multiple-pill visual analysis timed out.") from exc
        except (PillImageQualityError, PillVisionResponseError):
            raise
        except Exception as exc:
            raise PillVisionUnavailableError(
                "The multiple-pill visual analysis service is temporarily unavailable."
            ) from exc

    # Function Name: _parse_multiple_visual_features
    # Description:
    # - Validate 1-10 observations, integer 0-1000 boxes, minimum area and per-pill features; reject pairwise overlap above 0.72 IoU.
    # Parameters:
    # - response_text (str): Raw Gemini JSON for multiple-pill detection.
    # Returns:
    # - Immutable box/feature pairs ordered by rounded top position then left coordinate.
    def _parse_multiple_visual_features(
        self,
        response_text: str,
    ) -> tuple[tuple[PillBoundingBox, PillVisualFeatures], ...]:
        """Rejects malformed, duplicate, or implausibly overlapping observations."""

        try:
            payload = json.loads(response_text)
            raw_pills = payload["pills"]
            if not isinstance(raw_pills, list) or not 1 <= len(raw_pills) <= 10:
                raise ValueError
            observations: list[tuple[PillBoundingBox, PillVisualFeatures]] = []
            for raw_pill in raw_pills:
                if not isinstance(raw_pill, dict):
                    raise ValueError
                raw_box = raw_pill["box_2d"]
                if (
                    not isinstance(raw_box, list)
                    or len(raw_box) != 4
                    or any(isinstance(value, bool) or not isinstance(value, int) for value in raw_box)
                ):
                    raise ValueError
                ymin, xmin, ymax, xmax = raw_box
                if not (0 <= ymin < ymax <= 1000 and 0 <= xmin < xmax <= 1000):
                    raise ValueError
                box = PillBoundingBox(
                    left=xmin / 1000.0,
                    top=ymin / 1000.0,
                    width=(xmax - xmin) / 1000.0,
                    height=(ymax - ymin) / 1000.0,
                )
                if box.width * box.height < 0.0004:
                    raise ValueError
                feature_payload = dict(raw_pill)
                feature_payload.update(
                    {
                        "back_imprint": "",
                        "back_line": "unknown",
                        "same_pill": True,
                        "side_consistency_confidence": 1.0,
                    }
                )
                features = self._to_features(feature_payload, has_back_image=False)
                observations.append((box, features))
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
            raise PillVisionResponseError(
                "The multiple-pill analysis returned an invalid response."
            ) from exc

        observations.sort(
            # Function Name: spatial ordering lambda
            # Description:
            # - Group nearby top positions to two decimal places, then order detected pills from left to right.
            # Parameters:
            # - observation (tuple): Normalized bounding box and validated pill features.
            # Returns:
            # - Rounded top coordinate and left coordinate as a sort-key tuple.
            key=lambda observation: (
                round(observation[0].top, 2),
                observation[0].left,
            )
        )
        for index, (box, _features) in enumerate(observations):
            for other_box, _other_features in observations[index + 1 :]:
                if self._intersection_over_union(box, other_box) > 0.72:
                    raise PillVisionResponseError(
                        "The multiple-pill analysis returned overlapping observations."
                    )
        return tuple(observations)

    # Function Name: _intersection_over_union
    # Description:
    # - Compute bounding-box intersection area divided by union area for duplicate-detection checks.
    # Parameters:
    # - first (PillBoundingBox): First normalized pill bounding box.
    # - second (PillBoundingBox): Second normalized pill bounding box.
    # Returns:
    # - Overlap ratio from 0 to 1, or 0 for disjoint boxes.
    @staticmethod
    def _intersection_over_union(
        first: PillBoundingBox,
        second: PillBoundingBox,
    ) -> float:
        left = max(first.left, second.left)
        top = max(first.top, second.top)
        right = min(first.left + first.width, second.left + second.width)
        bottom = min(first.top + first.height, second.top + second.height)
        intersection = max(0.0, right - left) * max(0.0, bottom - top)
        if intersection == 0.0:
            return 0.0
        union = (
            first.width * first.height
            + second.width * second.height
            - intersection
        )
        return intersection / union

    # 함수이름: _extract_visual_features
    # 함수역할:
    # - 로컬 전처리 개수와 AI 개수를 교차 확인하고 양면 일치 및 품질 조건을 검증한다.
    # - 동일 알약 신뢰도가 낮으면 주의 문구를 추가하고, 사용 가능한 특징이 없는 저품질 응답은 재촬영 오류로 처리한다.
    # 매개변수:
    # - front_image (bytes): 앞면 원본 사진 바이트.
    # - back_image (bytes | None): 선택 뒷면 원본 사진 바이트; 없으면 None.
    # 반환값:
    # - 검증된 PillVisualFeatures; 품질·응답 형식·외부 서비스 실패는 해당 경계 예외.
    async def _extract_visual_features(
        self,
        front_image: bytes,
        back_image: bytes | None,
    ) -> PillVisualFeatures:
        (
            processed_front,
            processed_back,
            front_pill_count,
            back_pill_count,
        ) = await self._preprocess_images_with_capacity(front_image, back_image)
        local_counts = tuple(
            count
            for count in (front_pill_count, back_pill_count)
            if count is not None
        )
        if any(count > 1 for count in local_counts):
            raise PillImageQualityError(
                "Multiple pills were detected. Please photograph one pill at a time."
            )

        try:
            response_text = await self.vision_api.requestVisualFeatures(
                client=self.client,
                model_name=self.model_name,
                front_image=processed_front,
                back_image=processed_back,
                response_schema=self._RESPONSE_SCHEMA,
            )
        except (PillImageQualityError, PillVisionResponseError):
            raise
        except Exception as exc:
            raise PillVisionUnavailableError(
                "The pill visual analysis service is temporarily unavailable."
            ) from exc

        try:
            payload = json.loads(response_text)
        except json.JSONDecodeError as exc:
            raise PillVisionResponseError(
                "The visual analysis returned an invalid response."
            ) from exc
        if not isinstance(payload, dict):
            raise PillVisionResponseError(
                "The visual analysis returned an invalid response."
            )

        try:
            ai_pill_count = self._required_int(
                payload,
                "detected_pill_count",
                minimum=1,
                maximum=10,
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise PillVisionResponseError(
                "The visual analysis returned an invalid response."
            ) from exc
        if ai_pill_count != 1:
            raise PillImageQualityError(
                "Multiple pills were detected. Please photograph one pill at a time."
            )
        if local_counts and any(count != ai_pill_count for count in local_counts):
            raise PillImageQualityError(
                "The detected pill count is inconsistent. Please retake the photo."
            )

        features = self._to_features(
            payload,
            has_back_image=back_image is not None,
        )
        if back_image is not None and not features.same_pill:
            raise PillImageQualityError(
                "The front and back photos appear to show different pills."
            )
        if (
            back_image is not None
            and features.side_consistency_confidence < 0.7
        ):
            features = replace(
                features,
                quality_issues=(
                    *features.quality_issues[:4],
                    "front/back consistency is uncertain",
                ),
            )
        if features.quality == "poor" and not self._has_usable_low_quality_features(
            features
        ):
            detail = ", ".join(features.quality_issues[:3])
            message = "Please retake a clear photo of one pill."
            if detail:
                message = f"{message} Detected issues: {detail}."
            raise PillImageQualityError(message)
        return features

    # 함수이름: _preprocess_images
    # 함수역할:
    # - 요청당 디코딩 메모리가 겹치지 않도록 앞면과 뒷면을 순서대로 전처리한다.
    # 매개변수:
    # - front_image (bytes): 앞면 원본 사진 바이트.
    # - back_image (bytes | None): 선택 뒷면 사진 바이트; 없으면 뒷면 결과와 개수는 None.
    # 반환값:
    # - 앞면 JPEG, 선택 뒷면 JPEG, 앞면·뒷면의 보수적 알약 개수 튜플.
    def _preprocess_images(
        self,
        front_image: bytes,
        back_image: bytes | None,
    ) -> tuple[bytes, bytes | None, int | None, int | None]:
        """Normalizes both sides sequentially to cap per-request decode memory."""

        processed_front, front_pill_count = self._preprocess_one_image(front_image)
        if back_image is None:
            return processed_front, None, front_pill_count, None
        processed_back, back_pill_count = self._preprocess_one_image(back_image)
        return (
            processed_front,
            processed_back,
            front_pill_count,
            back_pill_count,
        )

    # 함수이름: _preprocess_one_image
    # 함수역할:
    # - 개수 판정 전처리 API를 우선 사용하고 지원하지 않는 기존 구현·테스트 대역에는 이미지 전용 API를 사용한다.
    # 매개변수:
    # - image (bytes): 전처리할 한쪽 면의 원본 이미지 바이트.
    # 반환값:
    # - 정규화 이미지와 판정 개수; 이전 API 경로는 개수 None.
    def _preprocess_one_image(
        self,
        image: bytes,
    ) -> tuple[bytes, int | None]:
        """신규 개수 판정 API가 없는 테스트 대역과 기존 구현도 계속 지원한다."""

        processor = self.image_processing_boundary
        assessment_method = getattr(
            processor,
            "preprocessPillImageWithAssessment",
            None,
        )
        if callable(assessment_method):
            assessment = assessment_method(image)
            if isinstance(assessment, PillImagePreprocessingResult):
                return assessment.image, assessment.detected_pill_count
        return processor.preprocessPillImage(image), None

    # 함수이름: _preprocess_images_with_capacity
    # 함수역할:
    # - 전처리 용량을 예약하고 스레드 작업을 취소로부터 보호하여 호출이 취소돼도 실제 작업 종료까지 슬롯을 유지한다.
    # 매개변수:
    # - front_image (bytes): 앞면 원본 이미지 바이트.
    # - back_image (bytes | None): 선택 뒷면 원본 이미지 바이트.
    # 반환값:
    # - 앞·뒷면 정규화 이미지와 개수; 호출 취소는 정리 콜백을 등록한 뒤 전파한다.
    async def _preprocess_images_with_capacity(
        self,
        front_image: bytes,
        back_image: bytes | None,
    ) -> tuple[bytes, bytes | None, int | None, int | None]:
        """Keeps decode capacity reserved until a timed-out worker really exits."""

        await self._preprocessing_semaphore.acquire()
        worker = asyncio.create_task(
            asyncio.to_thread(
                self._preprocess_images,
                front_image,
                back_image,
            )
        )
        release_on_exit = True
        try:
            try:
                return await asyncio.shield(worker)
            except asyncio.CancelledError:
                worker.add_done_callback(self._release_preprocessing_capacity)
                release_on_exit = False
                raise
        finally:
            if release_on_exit:
                self._preprocessing_semaphore.release()

    # 함수이름: _release_preprocessing_capacity
    # 함수역할:
    # - 호출자와 분리된 전처리 작업의 예외를 회수하고 예약된 디코딩 용량을 해제한다.
    # 매개변수:
    # - worker (asyncio.Task[tuple[bytes, bytes | None, int | None, int | None]]): 취소된 호출에서 계속 실행되어 완료된 전처리 태스크.
    # 반환값:
    # - 없음; 전처리 세마포어 슬롯을 하나 반환한다.
    def _release_preprocessing_capacity(
        self,
        worker: asyncio.Task[
            tuple[bytes, bytes | None, int | None, int | None]
        ],
    ) -> None:
        """Consumes a detached worker result and releases its capacity slot."""

        try:
            worker.exception()
        except asyncio.CancelledError:
            pass
        self._preprocessing_semaphore.release()

    # Function Name: _has_usable_low_quality_features
    # Description:
    # - Accept poor-quality results only when shape and colors are usable and every issue is an explicitly nonblocking warning.
    # Parameters:
    # - features (PillVisualFeatures): Validated visual attributes whose poor-quality warnings need classification.
    # Returns:
    # - True for usable low-quality evidence; False for blocking, unrecognized or absent warnings.
    @classmethod
    def _has_usable_low_quality_features(
        cls,
        features: PillVisualFeatures,
    ) -> bool:
        """Allows non-blocking model warnings without treating them as success."""

        if features.shape in {"unknown", "other"} or not features.colors:
            return False
        if not features.quality_issues:
            return False
        for issue in features.quality_issues:
            normalized_issue = issue.casefold()
            if any(
                marker in normalized_issue
                for marker in cls._BLOCKING_QUALITY_MARKERS
            ):
                return False
            if not any(
                marker in normalized_issue
                for marker in cls._NON_BLOCKING_QUALITY_MARKERS
            ):
                return False
        return True

    # Function Name: close
    # Description:
    # - Close asynchronous and synchronous Gemini resources only when this boundary owns the client.
    # Parameters:
    # - None.
    # Returns:
    # - None; borrowed clients are left open and synchronous closure runs even if async closure fails.
    async def close(self) -> None:
        """Closes HTTP resources owned by the reusable Gemini client."""

        if not self._owns_client:
            return
        try:
            await self.client.aio.aclose()
        finally:
            self.client.close()

    # Function Name: _to_features
    # Description:
    # - Validate all visual fields and normalize reverse-side values when no back image was supplied.
    # Parameters:
    # - payload (dict[str, Any]): Decoded single-pill visual-feature object.
    # - has_back_image (bool): Whether an actual reverse-side photo supports the returned back-side fields.
    # Returns:
    # - PillVisualFeatures; malformed required values become PillVisionResponseError.
    def _to_features(
        self,
        payload: dict[str, Any],
        *,
        has_back_image: bool,
    ) -> PillVisualFeatures:
        try:
            shape = self._required_enum(payload, "shape", self._SHAPES)
            colors = tuple(
                color
                for color in self._required_enum_list(
                    payload,
                    "colors",
                    self._COLORS,
                    limit=2,
                    max_length=24,
                )
                if color != "unknown"
            )
            front_imprint = self._required_text(payload, "front_imprint", 32)
            back_imprint = self._required_text(payload, "back_imprint", 32)
            front_line = self._required_enum(payload, "front_line", self._LINES)
            back_line = self._required_enum(payload, "back_line", self._LINES)
            quality = self._required_enum(payload, "quality", self._QUALITIES)
            quality_issues = tuple(
                self._required_string_list(
                    payload,
                    "quality_issues",
                    limit=5,
                    max_length=80,
                )
            )
            same_pill = self._required_bool(payload, "same_pill")
            side_consistency_confidence = self._required_score(
                payload,
                "side_consistency_confidence",
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise PillVisionResponseError(
                "The visual analysis returned an invalid response."
            ) from exc

        if not has_back_image:
            back_imprint = ""
            back_line = "unknown"
            same_pill = True
            side_consistency_confidence = 1.0

        return PillVisualFeatures(
            shape=shape,
            colors=colors,
            front_imprint=front_imprint,
            back_imprint=back_imprint,
            front_line=front_line,
            back_line=back_line,
            quality=quality,
            quality_issues=quality_issues,
            same_pill=same_pill,
            side_consistency_confidence=side_consistency_confidence,
        )

    # Function Name: _required_bool
    # Description:
    # - Require an actual JSON boolean instead of coercing numeric or text values.
    # Parameters:
    # - payload (dict[str, Any]): Decoded visual-feature object.
    # - key (str): Required boolean field name.
    # Returns:
    # - Boolean field value; missing keys or nonbooleans raise KeyError or ValueError.
    @staticmethod
    def _required_bool(payload: dict[str, Any], key: str) -> bool:
        value = payload[key]
        if not isinstance(value, bool):
            raise ValueError(f"Invalid {key} value.")
        return value

    # Function Name: _required_score
    # Description:
    # - Require a finite numeric confidence in the inclusive range 0-1, explicitly rejecting booleans.
    # Parameters:
    # - payload (dict[str, Any]): Decoded visual-feature object.
    # - key (str): Required confidence field name.
    # Returns:
    # - Normalized float score; missing or invalid values raise KeyError or ValueError.
    @staticmethod
    def _required_score(payload: dict[str, Any], key: str) -> float:
        value = payload[key]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError(f"Invalid {key} value.")
        normalized = float(value)
        if not math.isfinite(normalized) or not 0.0 <= normalized <= 1.0:
            raise ValueError(f"Invalid {key} value.")
        return normalized

    # 함수이름: _required_int
    # 함수역할:
    # - 불리언을 제외한 정수만 허용하고 필수 개수 값이 지정된 양 끝 포함 범위에 있는지 검증한다.
    # 매개변수:
    # - payload (dict[str, Any]): AI가 반환한 특징 사전.
    # - key (str): 검증할 필수 정수 필드명.
    # - minimum (int): 허용할 최소 정수값(포함).
    # - maximum (int): 허용할 최대 정수값(포함).
    # 반환값:
    # - 검증된 정수; 필드 부재는 KeyError, 형식·범위 오류는 ValueError.
    @staticmethod
    def _required_int(
        payload: dict[str, Any],
        key: str,
        *,
        minimum: int,
        maximum: int,
    ) -> int:
        """AI 응답의 필수 정수 필드와 허용 범위를 함께 검증한다."""

        value = payload[key]
        if isinstance(value, bool) or not isinstance(value, int):
            raise ValueError(f"Invalid {key} value.")
        if not minimum <= value <= maximum:
            raise ValueError(f"Invalid {key} value.")
        return value

    # Function Name: _required_enum
    # Description:
    # - Read a bounded string, lowercase it and require membership in the permitted feature vocabulary.
    # Parameters:
    # - payload (dict[str, Any]): Decoded visual-feature object.
    # - key (str): Required enum field name.
    # - allowed (tuple[str, ...]): Permitted normalized vocabulary values.
    # Returns:
    # - Validated lowercase enum value; missing or invalid fields raise KeyError or ValueError.
    @classmethod
    def _required_enum(
        cls,
        payload: dict[str, Any],
        key: str,
        allowed: tuple[str, ...],
    ) -> str:
        normalized = cls._required_text(payload, key, 24).lower()
        if normalized not in allowed:
            raise ValueError(f"Invalid {key} value.")
        return normalized

    # Function Name: _required_text
    # Description:
    # - Require string type and a pre-trim length bound, then strip surrounding whitespace.
    # Parameters:
    # - payload (dict[str, Any]): Decoded visual-feature object.
    # - key (str): Required string field name.
    # - max_length (int): Maximum raw string length before trimming.
    # Returns:
    # - Trimmed required text, including an allowed empty string; invalid values raise ValueError.
    @staticmethod
    def _required_text(
        payload: dict[str, Any],
        key: str,
        max_length: int,
    ) -> str:
        value = payload[key]
        if not isinstance(value, str) or len(value) > max_length:
            raise ValueError(f"Invalid {key} value.")
        return value.strip()

    # Function Name: _required_string_list
    # Description:
    # - Require a bounded list of bounded strings, trimming and lowercasing each element without truncation.
    # Parameters:
    # - payload (dict[str, Any]): Decoded visual-feature object.
    # - key (str): Required string-list field name.
    # - limit (int): Maximum list item count.
    # - max_length (int): Maximum raw length of each string item.
    # Returns:
    # - Normalized string list; missing keys or invalid list/string sizes raise KeyError or ValueError.
    @classmethod
    def _required_string_list(
        cls,
        payload: dict[str, Any],
        key: str,
        *,
        limit: int,
        max_length: int,
    ) -> list[str]:
        value = payload[key]
        if not isinstance(value, list) or len(value) > limit:
            raise ValueError(f"Invalid {key} value.")
        normalized: list[str] = []
        for item in value:
            if not isinstance(item, str) or len(item) > max_length:
                raise ValueError(f"Invalid {key} value.")
            normalized.append(item.strip().lower())
        return normalized

    # Function Name: _required_enum_list
    # Description:
    # - Validate a bounded string list and ensure every normalized item belongs to the allowed vocabulary.
    # Parameters:
    # - payload (dict[str, Any]): Decoded visual-feature object.
    # - key (str): Required enum-list field name.
    # - allowed (tuple[str, ...]): Permitted lowercase vocabulary values.
    # - limit (int): Maximum allowed list size.
    # - max_length (int): Maximum raw string length for each list item.
    # Returns:
    # - Validated enum strings in original order; invalid entries raise ValueError.
    @classmethod
    def _required_enum_list(
        cls,
        payload: dict[str, Any],
        key: str,
        allowed: tuple[str, ...],
        *,
        limit: int,
        max_length: int,
    ) -> list[str]:
        normalized = cls._required_string_list(
            payload,
            key,
            limit=limit,
            max_length=max_length,
        )
        if any(item not in allowed for item in normalized):
            raise ValueError(f"Invalid {key} value.")
        return normalized


# Class Name: MFDSPillAPI
# Role:
# - Downloads fully accounted MFDS pill-reference catalog generations.
# Responsibilities:
# - Bound page concurrency, response bytes and total rows; reconcile fetched, rejected and duplicate rows before publishing a complete snapshot.
# Attributes:
# - base_url / api_key (str): HTTPS endpoint and public-data credential.
# - page_size / max_concurrency (int): Bounded page size and concurrent page count.
# - minimum_catalog_rows (int): Product-count floor for a publishable generation.
# - client_factory (Callable): Creates the generation-scoped HTTP client.
class MFDSPillAPI:
    """Downloads and validates the authoritative MFDS pill catalog."""

    _MAX_CATALOG_ROWS = 50_000
    _MAX_PAGE_RESPONSE_BYTES = 5 * 1024 * 1024
    _MAX_REFRESH_RESPONSE_BYTES = 128 * 1024 * 1024

    # Function Name: __init__
    # Description:
    # - Validate HTTPS, page/concurrency bounds, positive timeout and product-count floor before storing MFDS request settings.
    # Parameters:
    # - base_url (str | None): Optional HTTPS MFDS pill-identification endpoint.
    # - api_key (str | None): Optional public-data credential; defaults to the configured service key.
    # - timeout_seconds (float | None): Maximum external request duration in seconds; None uses settings.
    # - page_size (int): Rows requested per page, from 1 through 500.
    # - max_concurrency (int): Maximum concurrent page requests, from 1 through 12.
    # - minimum_catalog_rows (int | None): Minimum accepted unique product count; None uses the configured KPIC floor.
    # - client_factory (Callable[..., httpx.AsyncClient] | None): Optional factory for a generation-scoped httpx.AsyncClient.
    # Returns:
    # - None; invalid endpoint or resource limits raise ValueError.
    def __init__(
        self,
        *,
        base_url: str | None = None,
        api_key: str | None = None,
        timeout_seconds: float | None = None,
        page_size: int = 500,
        max_concurrency: int = 12,
        minimum_catalog_rows: int | None = None,
        client_factory: Callable[..., httpx.AsyncClient] | None = None,
    ) -> None:
        if page_size < 1 or page_size > 500:
            raise ValueError("MFDS pill catalog page size must be between 1 and 500.")
        if max_concurrency < 1 or max_concurrency > 12:
            raise ValueError("MFDS pill catalog concurrency must be between 1 and 12.")
        resolved_timeout = (
            timeout_seconds
            if timeout_seconds is not None
            else settings.PILL_IMAGE_API_TIMEOUT_SECONDS
        )
        if resolved_timeout <= 0:
            raise ValueError("MFDS pill catalog timeout must be positive.")
        resolved_minimum_catalog_rows = (
            minimum_catalog_rows
            if minimum_catalog_rows is not None
            else settings.PILL_IDENTIFICATION_KPIC_PRODUCT_FLOOR
        )
        if (
            resolved_minimum_catalog_rows < 1
            or resolved_minimum_catalog_rows > self._MAX_CATALOG_ROWS
        ):
            raise ValueError(
                "MFDS pill catalog minimum rows must be between 1 and 50000."
            )
        self.base_url = base_url or settings.PILL_IMAGE_API_BASE_URL
        parsed_base_url = urlsplit(self.base_url)
        if parsed_base_url.scheme.lower() != "https" or not parsed_base_url.netloc:
            raise ValueError("MFDS pill catalog endpoint must use HTTPS.")
        self.api_key = api_key or settings.PUBLIC_DATA_API_KEY
        self.timeout_seconds = resolved_timeout
        self.page_size = page_size
        self.max_concurrency = max_concurrency
        self.minimum_catalog_rows = resolved_minimum_catalog_rows
        self.client_factory = client_factory or httpx.AsyncClient

    # Function Name: requestCatalog
    # Description:
    # - Download a fully reconciled catalog snapshot and expose its entries as a mutable list.
    # Parameters:
    # - None.
    # Returns:
    # - Sorted unique pill-reference entries from a complete generation.
    async def requestCatalog(self) -> list[PillCatalogEntry]:
        """Returns entries from a fully accounted MFDS catalog generation."""

        snapshot = await self.requestCatalogSnapshot()
        return list(snapshot.entries)

    # Function Name: requestCatalogSnapshot
    # Description:
    # - Download every page advertised by the MFDS pill-identification API.
    # - Account for rejected and duplicate rows and reject any generation with unfetched advertised rows.
    # - Bound total response bytes and require unique entries to satisfy both the configured floor and 95% of advertised rows.
    # Parameters:
    # - None.
    # Returns:
    # - A sorted unique catalog and its immutable reconciliation report.
    async def requestCatalogSnapshot(self) -> PillCatalogSnapshot:
        limits = httpx.Limits(
            max_connections=self.max_concurrency,
            max_keepalive_connections=self.max_concurrency,
        )
        async with self.client_factory(
            timeout=self.timeout_seconds,
            limits=limits,
        ) as client:
            first_items, total_count, first_response_bytes = await self._request_page(
                client,
                1,
            )
            if total_count < 1 or total_count > self._MAX_CATALOG_ROWS:
                raise RuntimeError("MFDS pill catalog returned an invalid row count.")
            if first_response_bytes > self._MAX_REFRESH_RESPONSE_BYTES:
                raise RuntimeError("MFDS pill catalog refresh response is too large.")

            page_count = math.ceil(total_count / self.page_size)
            semaphore = asyncio.Semaphore(self.max_concurrency)
            response_budget_lock = asyncio.Lock()
            total_response_bytes = first_response_bytes

            # Function Name: fetch_page
            # Description:
            # - Fetch a remaining page under the generation's semaphore, verify the unchanged total count and atomically charge the shared response budget.
            # Parameters:
            # - page_no (int): One-based upstream result page number.
            # Returns:
            # - Accepted entries, raw row count and rejected row count for this page; invalid totals or byte overruns raise RuntimeError.
            async def fetch_page(
                page_no: int,
            ) -> tuple[list[PillCatalogEntry], int, int]:
                nonlocal total_response_bytes
                async with semaphore:
                    items, page_total_count, response_bytes = await self._request_page(
                        client,
                        page_no,
                    )
                    if page_total_count != total_count:
                        raise RuntimeError(
                            "MFDS pill catalog returned inconsistent row counts."
                        )
                    async with response_budget_lock:
                        total_response_bytes += response_bytes
                        if total_response_bytes > self._MAX_REFRESH_RESPONSE_BYTES:
                            raise RuntimeError(
                                "MFDS pill catalog refresh response is too large."
                            )
                    entries = [
                        entry
                        for item in items
                        if (entry := self._to_catalog_entry(item)) is not None
                    ]
                    return entries, len(items), len(items) - len(entries)

            page_tasks = [
                asyncio.create_task(fetch_page(page_no))
                for page_no in range(2, page_count + 1)
            ]
            try:
                remaining_pages = await asyncio.gather(*page_tasks)
            except BaseException:
                for task in page_tasks:
                    if not task.done():
                        task.cancel()
                await asyncio.gather(*page_tasks, return_exceptions=True)
                raise

        raw_row_count = len(first_items) + sum(
            page_row_count for _, page_row_count, _ in remaining_pages
        )
        if raw_row_count > total_count or raw_row_count > self._MAX_CATALOG_ROWS:
            raise RuntimeError("MFDS pill catalog returned too many rows.")
        if raw_row_count != total_count:
            raise RuntimeError("MFDS pill catalog download was incomplete.")
        deduplicated: dict[str, PillCatalogEntry] = {}
        valid_row_count = 0
        rejected_row_count = 0
        for item in first_items:
            entry = self._to_catalog_entry(item)
            if entry is not None:
                valid_row_count += 1
                deduplicated[entry.item_seq] = entry
            else:
                rejected_row_count += 1
        for page_entries, _, page_rejected_count in remaining_pages:
            valid_row_count += len(page_entries)
            rejected_row_count += page_rejected_count
            for entry in page_entries:
                deduplicated[entry.item_seq] = entry

        duplicate_row_count = valid_row_count - len(deduplicated)

        expected_minimum = max(
            self.minimum_catalog_rows,
            math.ceil(total_count * 0.95),
        )
        if len(deduplicated) < expected_minimum:
            raise RuntimeError("MFDS pill catalog download was incomplete.")

        logger.info(
            "MFDS pill catalog refreshed: advertised=%d, fetched=%d, "
            "valid=%d, unique=%d, rejected=%d, duplicates=%d, pages=%d",
            total_count,
            raw_row_count,
            valid_row_count,
            len(deduplicated),
            rejected_row_count,
            duplicate_row_count,
            page_count,
        )
        entries = tuple(
            # Function Name: catalog ordering lambda
            # Description:
            # - Select each public product identifier to give catalog snapshots deterministic ordering.
            # Parameters:
            # - entry (PillCatalogEntry): Accepted unique catalog record.
            # Returns:
            # - Item-sequence string used for ascending order.
            sorted(deduplicated.values(), key=lambda entry: entry.item_seq)
        )
        return PillCatalogSnapshot(
            entries=entries,
            report=PillCatalogDownloadReport(
                advertised_rows=total_count,
                fetched_rows=raw_row_count,
                valid_rows=valid_row_count,
                accepted_unique_rows=len(entries),
                rejected_rows=rejected_row_count,
                duplicate_rows=duplicate_row_count,
                page_count=page_count,
                response_bytes=total_response_bytes,
            ),
        )

    # Function Name: _request_page
    # Description:
    # - Stream a bounded MFDS page, validate row count and retry once after a short delay on failure.
    # Parameters:
    # - client (httpx.AsyncClient): Generation-scoped HTTP client shared across page requests.
    # - page_no (int): One-based upstream result page number.
    # Returns:
    # - Raw item dictionaries, advertised total count and response bytes; raises RuntimeError after both attempts fail.
    async def _request_page(
        self,
        client: httpx.AsyncClient,
        page_no: int,
    ) -> tuple[list[dict[str, Any]], int, int]:
        params = {
            "serviceKey": self.api_key,
            "type": "json",
            "pageNo": page_no,
            "numOfRows": self.page_size,
        }
        last_error: Exception | None = None
        for attempt in range(2):
            try:
                async with client.stream(
                    "GET",
                    self.base_url,
                    params=params,
                ) as response:
                    response.raise_for_status()
                    payload, response_bytes = await self._read_bounded_json(response)
                items, total_count = self._extract_items(payload)
                if len(items) > self.page_size:
                    raise RuntimeError(
                        "MFDS pill catalog page returned too many rows."
                    )
                return items, total_count, response_bytes
            except Exception as exc:
                last_error = exc
                if attempt == 0:
                    await asyncio.sleep(0.25)
        raise RuntimeError("MFDS pill catalog page request failed.") from last_error

    # Function Name: _read_bounded_json
    # Description:
    # - Reject oversized declared or streamed page bodies before parsing JSON within the five-MiB page limit.
    # Parameters:
    # - response (httpx.Response): Open streaming MFDS HTTP response.
    # Returns:
    # - Decoded JSON and actual byte count; malformed or oversized bodies raise RuntimeError.
    @classmethod
    async def _read_bounded_json(
        cls,
        response: httpx.Response,
    ) -> tuple[Any, int]:
        content_length = response.headers.get("content-length")
        if content_length is not None:
            try:
                declared_length = int(content_length)
            except ValueError:
                declared_length = 0
            if declared_length > cls._MAX_PAGE_RESPONSE_BYTES:
                raise RuntimeError("MFDS pill catalog page response is too large.")

        body = bytearray()
        async for chunk in response.aiter_bytes():
            body.extend(chunk)
            if len(body) > cls._MAX_PAGE_RESPONSE_BYTES:
                raise RuntimeError("MFDS pill catalog page response is too large.")
        try:
            return json.loads(body), len(body)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise RuntimeError(
                "MFDS pill catalog returned invalid JSON."
            ) from exc

    # Function Name: _extract_items
    # Description:
    # - Validate direct or nested provider envelopes, normalize object/list item shapes and parse the advertised row count.
    # Parameters:
    # - payload (Any): Unvalidated JSON value from a bounded MFDS page.
    # Returns:
    # - Item dictionaries and integer total count; invalid envelopes or provider failure statuses raise RuntimeError.
    @staticmethod
    def _extract_items(payload: Any) -> tuple[list[dict[str, Any]], int]:
        if not isinstance(payload, dict):
            raise RuntimeError("MFDS pill catalog returned an invalid response.")
        response = payload.get("response")
        header = payload.get("header")
        body = payload.get("body")
        if isinstance(response, dict):
            header = response.get("header", header)
            body = response.get("body", body)
        if isinstance(header, dict):
            result_code = str(header.get("resultCode", "")).strip()
            if result_code and result_code not in {"00", "0000"}:
                raise RuntimeError("MFDS pill catalog rejected the request.")
        if not isinstance(body, dict):
            raise RuntimeError("MFDS pill catalog response has no body.")

        raw_items = body.get("items")
        if isinstance(raw_items, dict):
            raw_items = raw_items.get("item", raw_items.get("items"))
        if raw_items is None:
            items: list[dict[str, Any]] = []
        elif isinstance(raw_items, list):
            items = [item for item in raw_items if isinstance(item, dict)]
        elif isinstance(raw_items, dict):
            items = [raw_items]
        else:
            raise RuntimeError("MFDS pill catalog returned invalid items.")
        try:
            total_count = int(body.get("totalCount", 0))
        except (TypeError, ValueError) as exc:
            raise RuntimeError("MFDS pill catalog returned an invalid row count.") from exc
        return items, total_count

    # Function Name: _to_catalog_entry
    # Description:
    # - Require product ID and name, bound descriptive fields and sanitize image URLs before creating a reference entry.
    # Parameters:
    # - item (dict[str, Any]): Raw MFDS item dictionary.
    # Returns:
    # - PillCatalogEntry, or None when the required ID or name is missing.
    @classmethod
    def _to_catalog_entry(cls, item: dict[str, Any]) -> PillCatalogEntry | None:
        item_seq = cls._read_text(item, "ITEM_SEQ", max_length=64)
        item_name = cls._read_text(item, "ITEM_NAME", max_length=512)
        if not item_seq or not item_name:
            return None
        return PillCatalogEntry(
            item_seq=item_seq,
            item_name=item_name,
            entp_name=cls._read_text(item, "ENTP_NAME", max_length=256),
            image_url=cls._safe_image_url(cls._read_text(item, "ITEM_IMAGE")),
            shape=cls._read_text(item, "DRUG_SHAPE", max_length=128),
            color_primary=cls._read_text(item, "COLOR_CLASS1", max_length=128),
            color_secondary=cls._read_text(item, "COLOR_CLASS2", max_length=128),
            print_front=cls._read_text(item, "PRINT_FRONT", max_length=128),
            print_back=cls._read_text(item, "PRINT_BACK", max_length=128),
            line_front=cls._read_text(item, "LINE_FRONT", max_length=128),
            line_back=cls._read_text(item, "LINE_BACK", max_length=128),
        )

    # Function Name: _read_text
    # Description:
    # - Read an exact key or lowercase alias, accepting strings only and trimming them to the field's maximum length.
    # Parameters:
    # - item (dict[str, Any]): Raw MFDS product dictionary.
    # - key (str): Preferred uppercase field key with a lowercase fallback.
    # - max_length (int): Maximum retained characters after surrounding whitespace is removed.
    # Returns:
    # - Bounded text, or an empty string for a missing or nonstring field.
    @staticmethod
    def _read_text(
        item: dict[str, Any],
        key: str,
        *,
        max_length: int = 3000,
    ) -> str:
        value = item.get(key)
        if value is None:
            value = item.get(key.lower())
        if not isinstance(value, str):
            return ""
        return value.strip()[:max_length]

    # Function Name: _safe_image_url
    # Description:
    # - Apply the shared medication-image URL safety policy to an MFDS image link.
    # Parameters:
    # - value (str): Unvalidated catalog image URL.
    # Returns:
    # - Permitted image URL, or an empty string when the link is unsafe or absent.
    @staticmethod
    def _safe_image_url(value: str) -> str:
        return safe_medication_image_url(value)


# Class Name: MFDSPillCatalogBoundary
# Role:
# - Coordinates memory, shared database and MFDS pill-catalog sources.
# Responsibilities:
# - Serialize cache misses, serve sufficiently complete stale snapshots during outages and bound refresh retry windows.
# - Keep persistence-worker capacity reserved until workers actually exit even after caller cancellation.
# Attributes:
# - _catalog (tuple | None): Immutable in-process snapshot.
# - _catalog_loaded_at / _last_refresh_failure_at (float): Monotonic cache and backoff timestamps.
# - _catalog_is_stale (bool): Selects the shorter stale reuse interval.
# - _catalog_lock / _cache_io_semaphore: Cache-fill and persistence concurrency guards.
# - cache_ttl (timedelta): Normal snapshot lifetime.
# - allow_inline_refresh (bool): Whether requests may download upstream data.
class MFDSPillCatalogBoundary:
    """Coordinates memory, shared persistence, and MFDS catalog sources."""

    _STALE_RETRY_SECONDS = 300.0
    _FAILED_REFRESH_RETRY_SECONDS = 15.0

    # Function Name: __init__
    # Description:
    # - Resolve positive cache/refresh limits, bind the catalog provider and DB-session factory, and initialize empty cache and capacity guards.
    # Parameters:
    # - catalog_api (MFDSPillAPI | None): Optional MFDS catalog download boundary.
    # - cache_ttl (timedelta | None): Optional positive snapshot lifetime; defaults to configured catalog TTL.
    # - refresh_timeout_seconds (float | None): Optional maximum full-refresh duration in seconds.
    # - allow_inline_refresh (bool | None): Whether requests may refresh from MFDS; None reads the deployment setting.
    # - session_factory (Callable[[], Session] | None): Optional factory opening a shared-database session for each cache operation.
    # Returns:
    # - None; invalid cache lifetime or refresh timeout raises ValueError.
    def __init__(
        self,
        *,
        catalog_api: MFDSPillAPI | None = None,
        cache_ttl: timedelta | None = None,
        refresh_timeout_seconds: float | None = None,
        allow_inline_refresh: bool | None = None,
        session_factory: Callable[[], Session] | None = None,
    ) -> None:
        resolved_cache_ttl = (
            cache_ttl
            if cache_ttl is not None
            else timedelta(hours=settings.PILL_IDENTIFICATION_CATALOG_TTL_HOURS)
        )
        resolved_refresh_timeout = (
            refresh_timeout_seconds
            if refresh_timeout_seconds is not None
            else settings.PILL_IDENTIFICATION_CATALOG_REFRESH_TIMEOUT_SECONDS
        )
        if resolved_cache_ttl.total_seconds() <= 0:
            raise ValueError("MFDS pill catalog cache lifetime must be positive.")
        if resolved_refresh_timeout <= 0:
            raise ValueError("MFDS pill catalog refresh timeout must be positive.")
        self.catalog_api = catalog_api or MFDSPillAPI()
        self.cache_ttl = resolved_cache_ttl
        self.refresh_timeout_seconds = resolved_refresh_timeout
        self.minimum_catalog_rows = self.catalog_api.minimum_catalog_rows
        self.allow_inline_refresh = (
            allow_inline_refresh
            if allow_inline_refresh is not None
            else settings.PILL_IDENTIFICATION_CATALOG_ALLOW_INLINE_REFRESH
        )
        self.session_factory = session_factory or open_pill_catalog_session
        self._catalog: tuple[PillCatalogEntry, ...] | None = None
        self._catalog_loaded_at = 0.0
        self._catalog_is_stale = False
        self._last_refresh_failure_at = 0.0
        self._catalog_lock = asyncio.Lock()
        self._cache_io_semaphore = asyncio.Semaphore(1)

    # Function Name: getCatalog
    # Description:
    # - Serve a still-valid in-memory snapshot immediately or enter serialized cache resolution.
    # Parameters:
    # - None.
    # Returns:
    # - Immutable pill-reference catalog; raises PillCatalogUnavailableError when no usable source exists.
    async def getCatalog(self) -> tuple[PillCatalogEntry, ...]:
        if self._is_memory_cache_fresh():
            return self._catalog or ()
        return await self._get_catalog_with_lock()

    # Function Name: _get_catalog_with_lock
    # Description:
    # - Under the catalog lock, prefer fresh persistence, publish complete stale fallback and optionally refresh within timeout/backoff limits.
    # - Do not classify caller cancellation as an upstream outage; cache-write failure still allows a successful download to be served.
    # Parameters:
    # - None.
    # Returns:
    # - Immutable fresh or accepted stale catalog; raises PillCatalogUnavailableError when no complete snapshot can be served.
    async def _get_catalog_with_lock(self) -> tuple[PillCatalogEntry, ...]:
        async with self._catalog_lock:
            if self._is_memory_cache_fresh():
                return self._catalog or ()

            try:
                is_fresh, persisted_catalog = await self._run_cache_io(
                    self._load_persisted_catalog,
                )
            except Exception as exc:
                logger.warning(
                    "Pill catalog cache read failed: %s",
                    type(exc).__name__,
                )
                is_fresh, persisted_catalog = False, []
            if is_fresh:
                self._set_memory_catalog(persisted_catalog)
                return self._catalog or ()

            stale_catalog = (
                persisted_catalog
                if len(persisted_catalog) >= self.minimum_catalog_rows
                else []
            )
            if stale_catalog:
                # Publish a complete stale snapshot before remote refresh so
                # timeout and cancellation paths can still serve known data.
                self._set_memory_catalog(stale_catalog, stale=True)
            if not self.allow_inline_refresh:
                if stale_catalog:
                    return self._catalog or ()
                raise PillCatalogUnavailableError(
                    "The shared pill catalog has not been synchronized."
                )
            if self._is_refresh_backoff_active():
                if stale_catalog:
                    return self._catalog or ()
                raise PillCatalogUnavailableError(
                    "The public pill catalog is temporarily unavailable."
                )
            try:
                async with asyncio.timeout(self.refresh_timeout_seconds):
                    catalog = await self.catalog_api.requestCatalog()
                if len(catalog) < self.minimum_catalog_rows:
                    raise RuntimeError("MFDS pill catalog download was incomplete.")
            except TimeoutError as exc:
                self._last_refresh_failure_at = time.monotonic()
                if stale_catalog:
                    return self._catalog or ()
                raise PillCatalogUnavailableError(
                    "The public pill catalog request timed out."
                ) from exc
            except asyncio.CancelledError:
                # A sibling use-case failure or client cancellation is not an
                # upstream outage and must not poison the next refresh attempt.
                raise
            except Exception as exc:
                self._last_refresh_failure_at = time.monotonic()
                if not stale_catalog:
                    raise PillCatalogUnavailableError(
                        "The public pill catalog is temporarily unavailable."
                    ) from exc
                logger.warning(
                    "MFDS pill catalog refresh failed; using local cache: %s",
                    type(exc).__name__,
                )
                return self._catalog or ()

            try:
                await self._run_cache_io(
                    # Function Name: catalog persistence lambda
                    # Description:
                    # - Capture the downloaded catalog for the zero-argument persistence worker.
                    # Parameters:
                    # - None; captures catalog and the boundary instance.
                    # Returns:
                    # - None after the replacement repository operation finishes.
                    lambda: self._replace_persisted_catalog(catalog),
                )
            except Exception as exc:
                logger.warning(
                    "Pill catalog cache write failed: %s",
                    type(exc).__name__,
                )
            self._set_memory_catalog(catalog)
            self._last_refresh_failure_at = 0.0
            return self._catalog or ()

    # Function Name: _run_cache_io
    # Description:
    # - Run one persistence operation in a shielded worker and retain its single I/O slot until actual completion after cancellation.
    # Parameters:
    # - operation (Callable[[], _CatalogIOResult]): Zero-argument blocking catalog read or write to run off the event loop.
    # Returns:
    # - The operation's result; exceptions propagate and caller cancellation registers deferred slot release.
    async def _run_cache_io(
        self,
        operation: Callable[[], _CatalogIOResult],
    ) -> _CatalogIOResult:
        """Keeps persistence capacity reserved until a timed-out worker exits."""

        await self._cache_io_semaphore.acquire()
        worker = asyncio.create_task(asyncio.to_thread(operation))
        release_on_exit = True
        try:
            try:
                return await asyncio.shield(worker)
            except asyncio.CancelledError:
                worker.add_done_callback(self._release_cache_io_capacity)
                release_on_exit = False
                raise
        finally:
            if release_on_exit:
                self._cache_io_semaphore.release()

    # Function Name: _release_cache_io_capacity
    # Description:
    # - Consume a detached persistence worker's exception and release its reserved cache-I/O slot.
    # Parameters:
    # - worker (asyncio.Task[_CatalogIOResult]): Completed persistence task detached by a cancelled caller.
    # Returns:
    # - None; returns one permit to the persistence semaphore.
    def _release_cache_io_capacity(
        self,
        worker: asyncio.Task[_CatalogIOResult],
    ) -> None:
        """Consumes a detached persistence result and releases its capacity slot."""

        try:
            worker.exception()
        except asyncio.CancelledError:
            pass
        self._cache_io_semaphore.release()

    # Function Name: invalidateMemoryCache
    # Description:
    # - Discard the in-memory snapshot, loaded/stale state and refresh-failure backoff without deleting persisted data.
    # Parameters:
    # - None.
    # Returns:
    # - None; the next lookup rechecks shared persistence.
    def invalidateMemoryCache(self) -> None:
        self._catalog = None
        self._catalog_loaded_at = 0.0
        self._catalog_is_stale = False
        self._last_refresh_failure_at = 0.0

    # Function Name: _is_refresh_backoff_active
    # Description:
    # - Check whether the most recent failed refresh lies within the 15-second retry cooldown.
    # Parameters:
    # - None.
    # Returns:
    # - True while refresh backoff is active; False before any failure or after expiry.
    def _is_refresh_backoff_active(self) -> bool:
        return (
            self._last_refresh_failure_at > 0.0
            and time.monotonic() - self._last_refresh_failure_at
            < self._FAILED_REFRESH_RETRY_SECONDS
        )

    # Function Name: _is_memory_cache_fresh
    # Description:
    # - Check loaded snapshot age against its normal TTL or the shorter five-minute stale-reuse limit.
    # Parameters:
    # - None.
    # Returns:
    # - True when a snapshot exists and remains within the applicable in-memory reuse interval.
    def _is_memory_cache_fresh(self) -> bool:
        if self._catalog is None:
            return False
        max_age_seconds = self.cache_ttl.total_seconds()
        if self._catalog_is_stale:
            max_age_seconds = min(max_age_seconds, self._STALE_RETRY_SECONDS)
        return (time.monotonic() - self._catalog_loaded_at) < max_age_seconds

    # Function Name: _set_memory_catalog
    # Description:
    # - Publish an immutable catalog tuple with a new monotonic load timestamp and explicit stale status.
    # Parameters:
    # - catalog (list[PillCatalogEntry]): Complete accepted pill-reference entries to publish in memory.
    # - stale (bool): Whether the snapshot uses the shorter stale-data reuse interval.
    # Returns:
    # - None; future cache checks use the new snapshot and age.
    def _set_memory_catalog(
        self,
        catalog: list[PillCatalogEntry],
        *,
        stale: bool = False,
    ) -> None:
        self._catalog = tuple(catalog)
        self._catalog_loaded_at = time.monotonic()
        self._catalog_is_stale = stale

    # Function Name: _load_persisted_catalog
    # Description:
    # - Open an independent session, evaluate snapshot size/age and read all persisted references, then always close the session.
    # Parameters:
    # - None.
    # Returns:
    # - Freshness flag and persisted entry list, even when that list is stale.
    def _load_persisted_catalog(self) -> tuple[bool, list[PillCatalogEntry]]:
        db = self.session_factory()
        try:
            repository = PillIdentificationCatalogRepository(db)
            is_fresh = repository.is_fresh(
                minimum_rows=self.minimum_catalog_rows,
                max_age=self.cache_ttl,
            )
            return is_fresh, repository.list_all()
        finally:
            db.close()

    # Function Name: _replace_persisted_catalog
    # Description:
    # - Replace the persisted reference snapshot in an independent session and close it on both success and failure.
    # Parameters:
    # - catalog (list[PillCatalogEntry]): Complete validated reference entries to persist.
    # Returns:
    # - None; repository replacement commits the snapshot and failures propagate.
    def _replace_persisted_catalog(self, catalog: list[PillCatalogEntry]) -> None:
        db = self.session_factory()
        try:
            PillIdentificationCatalogRepository(db).replace_all(catalog)
        finally:
            db.close()
