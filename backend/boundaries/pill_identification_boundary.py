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


class PillImageQualityError(ValueError):
    """Raised when a pill photo cannot be analyzed safely or reliably."""


class PillCatalogUnavailableError(RuntimeError):
    """Raised when neither MFDS nor the local catalog cache is available."""


class PillVisionUnavailableError(RuntimeError):
    """Raised when the external visual-attribute service is unavailable."""


class PillVisionResponseError(RuntimeError):
    """Raised when the visual service returns an invalid response contract."""


@dataclass(frozen=True)
class PillImagePreprocessingResult:
    """전처리 이미지와 보수적으로 판정한 알약 개수를 함께 전달한다."""

    image: bytes
    detected_pill_count: int | None


@dataclass(frozen=True)
class MultiplePillImagePreprocessingResult:
    """Composition-preserving JPEG used for one-photo object detection."""

    image: bytes
    width: int
    height: int


class PillImageProcessingBoundary:
    """Bounds, decodes, crops, and normalizes an uploaded pill photo."""

    _MAX_ANALYSIS_DIMENSION = 1600
    _MIN_IMAGE_DIMENSION = 128

    def preprocessPillImage(self, image: bytes) -> bytes:
        return self.preprocessPillImageWithAssessment(image).image

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


class GeminiPillVisionAPI:
    """External Gemini boundary that extracts only visible pill attributes."""

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

    async def close(self) -> None:
        """Closes HTTP resources owned by the reusable Gemini client."""

        if not self._owns_client:
            return
        try:
            await self.client.aio.aclose()
        finally:
            self.client.close()

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

    @staticmethod
    def _required_bool(payload: dict[str, Any], key: str) -> bool:
        value = payload[key]
        if not isinstance(value, bool):
            raise ValueError(f"Invalid {key} value.")
        return value

    @staticmethod
    def _required_score(payload: dict[str, Any], key: str) -> float:
        value = payload[key]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError(f"Invalid {key} value.")
        normalized = float(value)
        if not math.isfinite(normalized) or not 0.0 <= normalized <= 1.0:
            raise ValueError(f"Invalid {key} value.")
        return normalized

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


class MFDSPillAPI:
    """Downloads and validates the authoritative MFDS pill catalog."""

    _MAX_CATALOG_ROWS = 50_000
    _MAX_PAGE_RESPONSE_BYTES = 5 * 1024 * 1024
    _MAX_REFRESH_RESPONSE_BYTES = 128 * 1024 * 1024

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

    async def requestCatalog(self) -> list[PillCatalogEntry]:
        """Returns entries from a fully accounted MFDS catalog generation."""

        snapshot = await self.requestCatalogSnapshot()
        return list(snapshot.entries)

    # Function Name: requestCatalogSnapshot
    # Description:
    # - Downloads every page advertised by the MFDS pill-identification API.
    # - Accounts for rejected and duplicate rows before returning a generation.
    # - Rejects a generation when any advertised row was not fetched.
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

    @staticmethod
    def _safe_image_url(value: str) -> str:
        return safe_medication_image_url(value)


class MFDSPillCatalogBoundary:
    """Coordinates memory, shared persistence, and MFDS catalog sources."""

    _STALE_RETRY_SECONDS = 300.0
    _FAILED_REFRESH_RETRY_SECONDS = 15.0

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

    async def getCatalog(self) -> tuple[PillCatalogEntry, ...]:
        if self._is_memory_cache_fresh():
            return self._catalog or ()
        return await self._get_catalog_with_lock()

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

    def invalidateMemoryCache(self) -> None:
        self._catalog = None
        self._catalog_loaded_at = 0.0
        self._catalog_is_stale = False
        self._last_refresh_failure_at = 0.0

    def _is_refresh_backoff_active(self) -> bool:
        return (
            self._last_refresh_failure_at > 0.0
            and time.monotonic() - self._last_refresh_failure_at
            < self._FAILED_REFRESH_RETRY_SECONDS
        )

    def _is_memory_cache_fresh(self) -> bool:
        if self._catalog is None:
            return False
        max_age_seconds = self.cache_ttl.total_seconds()
        if self._catalog_is_stale:
            max_age_seconds = min(max_age_seconds, self._STALE_RETRY_SECONDS)
        return (time.monotonic() - self._catalog_loaded_at) < max_age_seconds

    def _set_memory_catalog(
        self,
        catalog: list[PillCatalogEntry],
        *,
        stale: bool = False,
    ) -> None:
        self._catalog = tuple(catalog)
        self._catalog_loaded_at = time.monotonic()
        self._catalog_is_stale = stale

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

    def _replace_persisted_catalog(self, catalog: list[PillCatalogEntry]) -> None:
        db = self.session_factory()
        try:
            PillIdentificationCatalogRepository(db).replace_all(catalog)
        finally:
            db.close()
