# File Name: pill_identification_boundary.py
# Role: Image-analysis and public-catalog boundaries for loose-pill identification.

import asyncio
import json
import logging
import math
import time
from collections.abc import Callable
from dataclasses import replace
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
from entities.pill_identification_entity import PillCatalogEntry, PillVisualFeatures
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


class PillImageProcessingBoundary:
    """Bounds, decodes, crops, and normalizes an uploaded pill photo."""

    _MAX_ANALYSIS_DIMENSION = 1600
    _MIN_IMAGE_DIMENSION = 128

    def preprocessPillImage(self, image: bytes) -> bytes:
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

                # JPEG draft decoding avoids materializing the full camera frame
                # before it is reduced to the bounded analysis resolution.
                if source.format == "JPEG":
                    source.draft(
                        "RGB",
                        (
                            self._MAX_ANALYSIS_DIMENSION,
                            self._MAX_ANALYSIS_DIMENSION,
                        ),
                    )
                source.load()
                oriented = ImageOps.exif_transpose(source)
                oriented.thumbnail(
                    (
                        self._MAX_ANALYSIS_DIMENSION,
                        self._MAX_ANALYSIS_DIMENSION,
                    ),
                    Image.Resampling.LANCZOS,
                )
                rgb_image = oriented.convert("RGB")
                decoded = cv2.cvtColor(
                    np.asarray(rgb_image, dtype=np.uint8),
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
        height, width = decoded.shape[:2]
        if min(height, width) < self._MIN_IMAGE_DIMENSION:
            raise PillImageQualityError("The pill image resolution is too small.")

        normalized = self._resize_for_analysis(decoded)
        cropped = self._crop_likely_foreground(normalized)
        success, output = cv2.imencode(
            ".jpg",
            cropped,
            [cv2.IMWRITE_JPEG_QUALITY, 90],
        )
        if not success:
            raise PillImageQualityError("The pill image could not be normalized.")
        return output.tobytes()

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

    def _crop_likely_foreground(self, image: np.ndarray) -> np.ndarray:
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
            return image

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
            return image

        crop_candidates.sort(key=lambda candidate: candidate[0], reverse=True)
        best_score, best_area_ratio, contour = crop_candidates[0]
        if len(crop_candidates) > 1:
            second_score, second_area_ratio, _ = crop_candidates[1]
            comparable_area = (
                0.5 <= second_area_ratio / best_area_ratio <= 2.0
            )
            if comparable_area and second_score >= best_score * 0.93:
                # Contours alone cannot distinguish multiple pills from textured
                # backgrounds reliably. Preserve the frame so the vision boundary
                # can make the semantic image-quality decision.
                return image

        x, y, crop_width, crop_height = cv2.boundingRect(contour)
        padding = max(12, round(max(crop_width, crop_height) * 0.12))
        left = max(0, x - padding)
        top = max(0, y - padding)
        right = min(width, x + crop_width + padding)
        bottom = min(height, y + crop_height + padding)
        if right - left < self._MIN_IMAGE_DIMENSION // 2:
            return image
        if bottom - top < self._MIN_IMAGE_DIMENSION // 2:
            return image
        return image[top:bottom, left:right]


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
        - When two images are supplied, compare shape, color, score lines, and
          imprints. Set same_pill to false if they appear to be different pills.
        - side_consistency_confidence must be between 0.0 and 1.0.
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
            "same_pill": {"type": "BOOLEAN"},
            "side_consistency_confidence": {
                "type": "NUMBER",
                "minimum": 0.0,
                "maximum": 1.0,
            },
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

    async def _extract_visual_features(
        self,
        front_image: bytes,
        back_image: bytes | None,
    ) -> PillVisualFeatures:
        processed_front, processed_back = await self._preprocess_images_with_capacity(
            front_image,
            back_image,
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
    ) -> tuple[bytes, bytes | None]:
        """Normalizes both sides sequentially to cap per-request decode memory."""

        processed_front = self.image_processing_boundary.preprocessPillImage(
            front_image
        )
        processed_back = (
            self.image_processing_boundary.preprocessPillImage(back_image)
            if back_image is not None
            else None
        )
        return processed_front, processed_back

    async def _preprocess_images_with_capacity(
        self,
        front_image: bytes,
        back_image: bytes | None,
    ) -> tuple[bytes, bytes | None]:
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
        worker: asyncio.Task[tuple[bytes, bytes | None]],
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
        minimum_catalog_rows: int = 1_000,
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
        if minimum_catalog_rows < 1 or minimum_catalog_rows > self._MAX_CATALOG_ROWS:
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
        self.minimum_catalog_rows = minimum_catalog_rows
        self.client_factory = client_factory or httpx.AsyncClient

    async def requestCatalog(self) -> list[PillCatalogEntry]:
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
            ) -> tuple[list[PillCatalogEntry], int]:
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
                    return entries, len(items)

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
            page_row_count for _, page_row_count in remaining_pages
        )
        if raw_row_count > total_count or raw_row_count > self._MAX_CATALOG_ROWS:
            raise RuntimeError("MFDS pill catalog returned too many rows.")
        deduplicated: dict[str, PillCatalogEntry] = {}
        for item in first_items:
            entry = self._to_catalog_entry(item)
            if entry is not None:
                deduplicated[entry.item_seq] = entry
        for page_entries, _ in remaining_pages:
            for entry in page_entries:
                deduplicated[entry.item_seq] = entry

        expected_minimum = max(
            self.minimum_catalog_rows,
            math.ceil(total_count * 0.95),
        )
        if len(deduplicated) < expected_minimum:
            raise RuntimeError("MFDS pill catalog download was incomplete.")

        logger.info(
            "MFDS pill catalog refreshed: rows=%d, pages=%d",
            len(deduplicated),
            page_count,
        )
        return sorted(deduplicated.values(), key=lambda entry: entry.item_seq)

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
        if value.startswith("//"):
            value = f"https:{value}"
        if not value or len(value) > 3000:
            return ""
        try:
            parsed = urlsplit(value)
        except ValueError:
            return ""
        if parsed.scheme.lower() not in {"http", "https"} or not parsed.netloc:
            return ""
        return value


class MFDSPillCatalogBoundary:
    """Coordinates memory, SQLite, and MFDS sources for the pill catalog."""

    _STALE_RETRY_SECONDS = 300.0
    _FAILED_REFRESH_RETRY_SECONDS = 15.0

    def __init__(
        self,
        *,
        catalog_api: MFDSPillAPI | None = None,
        cache_ttl: timedelta | None = None,
        refresh_timeout_seconds: float | None = None,
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

        try:
            async with asyncio.timeout(self.refresh_timeout_seconds):
                return await self._get_catalog_with_lock()
        except TimeoutError as exc:
            self._last_refresh_failure_at = time.monotonic()
            if self._catalog is not None and self._catalog_is_stale:
                return self._catalog
            raise PillCatalogUnavailableError(
                "The public pill catalog request timed out."
            ) from exc

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
            if self._is_refresh_backoff_active():
                if stale_catalog:
                    return self._catalog or ()
                raise PillCatalogUnavailableError(
                    "The public pill catalog is temporarily unavailable."
                )
            try:
                catalog = await self.catalog_api.requestCatalog()
                if len(catalog) < self.minimum_catalog_rows:
                    raise RuntimeError("MFDS pill catalog download was incomplete.")
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
        """Keeps SQLite capacity reserved until a timed-out worker exits."""

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
        """Consumes a detached SQLite result and releases its capacity slot."""

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
