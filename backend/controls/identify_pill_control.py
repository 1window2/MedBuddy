# File Name: identify_pill_control.py
# Role: Coordinates visual feature extraction and deterministic MFDS candidate ranking.

import asyncio
import heapq
import unicodedata
from difflib import SequenceMatcher
from functools import lru_cache

from sqlalchemy.orm import Session

from boundaries.pill_identification_boundary import (
    MFDSPillCatalogBoundary,
    PillVisionBoundary,
)
from entities.pill_identification_entity import (
    PillCatalogEntry,
    PillIdentificationCandidate,
    PillIdentificationResult,
    PillVisualFeatures,
)


class IdentifyPill:
    """Identifies candidate products without treating a visual match as a diagnosis."""

    _SHAPE_ALIASES = {
        "round": ("원형", "원형정"),
        "oval": ("타원형",),
        "oblong": ("장방형", "장방정"),
        "semicircle": ("반원형",),
        "triangle": ("삼각형",),
        "square": ("사각형",),
        "diamond": ("마름모형",),
        "pentagon": ("오각형",),
        "hexagon": ("육각형",),
        "octagon": ("팔각형",),
        "other": ("기타",),
    }
    _COLOR_ALIASES = {
        "white": ("하양", "백색", "흰색"),
        "yellow": ("노랑", "황색"),
        "orange": ("주황",),
        "pink": ("분홍",),
        "red": ("빨강", "적색"),
        "brown": ("갈색",),
        "light_green": ("연두",),
        "green": ("초록", "녹색"),
        "teal": ("청록",),
        "blue": ("파랑", "청색"),
        "navy": ("남색",),
        "purple": ("보라", "자주"),
        "gray": ("회색",),
        "black": ("검정", "흑색"),
        "transparent": ("투명",),
        "other": ("기타",),
    }
    _LINE_ALIASES = {
        "none": ("", "없음", "없다"),
        "minus": ("-", "음각", "분할선"),
        "plus": ("+", "십자", "십자분할선"),
        "other": ("기타",),
    }

    def __init__(
        self,
        *,
        db: Session,
        vision_boundary: PillVisionBoundary,
        catalog_boundary: MFDSPillCatalogBoundary,
        candidate_limit: int = 5,
    ) -> None:
        if candidate_limit < 1 or candidate_limit > 20:
            raise ValueError("Pill candidate limit must be between 1 and 20.")
        self.db = db
        self.vision_boundary = vision_boundary
        self.catalog_boundary = catalog_boundary
        self.candidate_limit = candidate_limit

    async def requestPillIdentification(
        self,
        front_image: bytes,
        back_image: bytes | None = None,
    ) -> PillIdentificationResult:
        """Returns ranked candidates while keeping confirmation mandatory."""

        vision_task = asyncio.create_task(
            self.vision_boundary.extractVisualFeatures(front_image, back_image)
        )
        catalog_task = asyncio.create_task(self.catalog_boundary.getCatalog(self.db))
        required_tasks = (vision_task, catalog_task)
        try:
            features, catalog = await asyncio.gather(*required_tasks)
        except BaseException:
            for task in required_tasks:
                if not task.done():
                    task.cancel()
            await asyncio.gather(*required_tasks, return_exceptions=True)
            raise
        candidates = await asyncio.to_thread(
            self._rank_candidates,
            features,
            catalog,
        )
        is_confident = self._is_confident(features, candidates)
        return PillIdentificationResult(
            observed_features=features,
            candidates=tuple(candidates),
            is_confident=is_confident,
            requires_confirmation=True,
        )

    async def request_pill_identification(
        self,
        front_image: bytes,
        back_image: bytes | None = None,
    ) -> PillIdentificationResult:
        return await self.requestPillIdentification(front_image, back_image)

    def _rank_candidates(
        self,
        features: PillVisualFeatures,
        catalog: tuple[PillCatalogEntry, ...],
    ) -> list[PillIdentificationCandidate]:
        top_matches: list[
            tuple[
                tuple[float, int, str],
                PillCatalogEntry,
                tuple[str, ...],
            ]
        ] = []
        has_imprint = bool(features.front_imprint or features.back_imprint)

        for entry in catalog:
            if not self._is_plausible_candidate(features, entry):
                continue
            score, matched_attributes = self._score_entry(features, entry)
            if score <= 0.0:
                continue
            if not has_imprint:
                score = min(score, 0.68)
            ranking_key = (
                round(score, 4),
                int(bool(entry.image_url)),
                entry.item_seq,
            )
            match = (ranking_key, entry, tuple(matched_attributes))
            if len(top_matches) < self.candidate_limit:
                heapq.heappush(top_matches, match)
            elif ranking_key > top_matches[0][0]:
                heapq.heapreplace(top_matches, match)

        top_matches.sort(key=lambda match: match[0], reverse=True)
        return [
            PillIdentificationCandidate(
                item_seq=entry.item_seq,
                item_name=entry.item_name,
                entp_name=entry.entp_name,
                image_url=entry.image_url,
                shape=entry.shape,
                colors=tuple(
                    color
                    for color in (
                        entry.color_primary,
                        entry.color_secondary,
                    )
                    if color
                ),
                print_front=entry.print_front,
                print_back=entry.print_back,
                match_score=ranking_key[0],
                matched_attributes=matched_attributes,
            )
            for ranking_key, entry, matched_attributes in top_matches
        ]

    @classmethod
    def _is_plausible_candidate(
        cls,
        features: PillVisualFeatures,
        entry: PillCatalogEntry,
    ) -> bool:
        has_shape_match = (
            features.shape not in {"", "unknown"}
            and cls._shape_score(features.shape, entry.shape) > 0.0
        )
        has_color_match = bool(features.colors) and cls._color_score(
            features.colors,
            (entry.color_primary, entry.color_secondary),
        ) > 0.0
        observed_imprints = tuple(
            imprint
            for imprint in (
                cls._normalize_imprint(features.front_imprint),
                cls._normalize_imprint(features.back_imprint),
            )
            if imprint
        )
        if not observed_imprints:
            return has_shape_match and has_color_match

        catalog_imprints = tuple(
            imprint
            for imprint in (
                cls._normalize_imprint(entry.print_front),
                cls._normalize_imprint(entry.print_back),
            )
            if imprint
        )
        has_related_imprint = any(
            cls._imprints_are_plausibly_related(observed, catalog)
            for observed in observed_imprints
            for catalog in catalog_imprints
        )
        if catalog_imprints:
            return has_related_imprint
        return has_shape_match and has_color_match

    @staticmethod
    def _imprints_are_plausibly_related(observed: str, catalog: str) -> bool:
        if observed == catalog or observed in catalog or catalog in observed:
            return True
        if abs(len(observed) - len(catalog)) > 2:
            return False
        return not set(observed).isdisjoint(catalog)

    def _score_entry(
        self,
        features: PillVisualFeatures,
        entry: PillCatalogEntry,
    ) -> tuple[float, list[str]]:
        components: list[tuple[float, float]] = []
        matched_attributes: list[str] = []

        if features.shape not in {"", "unknown"}:
            shape_score = self._shape_score(features.shape, entry.shape)
            components.append((0.22, shape_score))
            if shape_score >= 0.99:
                matched_attributes.append("shape")

        if features.colors:
            color_score = self._color_score(
                features.colors,
                (entry.color_primary, entry.color_secondary),
            )
            components.append((0.22, color_score))
            if color_score >= 0.5:
                matched_attributes.append("color")

        if features.front_imprint or features.back_imprint:
            imprint_score = self._oriented_text_score(
                features.front_imprint,
                features.back_imprint,
                entry.print_front,
                entry.print_back,
            )
            components.append((0.48, imprint_score))
            if imprint_score >= 0.78:
                matched_attributes.append("imprint")

        if self._has_line_observation(features):
            line_score = self._oriented_line_score(features, entry)
            components.append((0.08, line_score))
            if line_score >= 0.99:
                matched_attributes.append("score_line")

        if not components:
            return 0.0, []
        weight_sum = sum(weight for weight, _ in components)
        weighted_score = sum(weight * score for weight, score in components)
        return weighted_score / weight_sum, matched_attributes

    @classmethod
    def _shape_score(cls, observed: str, catalog_shape: str) -> float:
        normalized_catalog = cls._normalize_label(catalog_shape)
        aliases = cls._SHAPE_ALIASES.get(observed, ())
        return 1.0 if any(alias in normalized_catalog for alias in aliases) else 0.0

    @classmethod
    def _color_score(
        cls,
        observed_colors: tuple[str, ...],
        catalog_colors: tuple[str, str],
    ) -> float:
        normalized_catalog = cls._normalize_label(" ".join(catalog_colors))
        matched = 0
        for observed in observed_colors:
            aliases = cls._COLOR_ALIASES.get(observed, ())
            if any(alias in normalized_catalog for alias in aliases):
                matched += 1
        return matched / len(observed_colors) if observed_colors else 0.0

    @classmethod
    def _oriented_text_score(
        cls,
        observed_front: str,
        observed_back: str,
        catalog_front: str,
        catalog_back: str,
    ) -> float:
        observed = (
            cls._normalize_imprint(observed_front),
            cls._normalize_imprint(observed_back),
        )
        catalog = (
            cls._normalize_imprint(catalog_front),
            cls._normalize_imprint(catalog_back),
        )
        if observed[0] and not observed[1]:
            return max(
                cls._text_similarity(observed[0], catalog[0]),
                cls._text_similarity(observed[0], catalog[1]),
            )
        if observed[1] and not observed[0]:
            return max(
                cls._text_similarity(observed[1], catalog[0]),
                cls._text_similarity(observed[1], catalog[1]),
            )

        direct = cls._mean_available_similarity(observed, catalog)
        swapped = cls._mean_available_similarity(observed, catalog[::-1])
        return max(direct, swapped)

    @classmethod
    def _oriented_line_score(
        cls,
        features: PillVisualFeatures,
        entry: PillCatalogEntry,
    ) -> float:
        observed = (features.front_line, features.back_line)
        catalog = (entry.line_front, entry.line_back)
        direct = cls._mean_available_line_score(observed, catalog)
        swapped = cls._mean_available_line_score(observed, catalog[::-1])
        return max(direct, swapped)

    @staticmethod
    def _has_line_observation(features: PillVisualFeatures) -> bool:
        return any(
            line not in {"", "unknown"}
            for line in (features.front_line, features.back_line)
        )

    @classmethod
    def _mean_available_similarity(
        cls,
        observed: tuple[str, str],
        catalog: tuple[str, str],
    ) -> float:
        scores = [
            cls._text_similarity(observed_value, catalog_value)
            for observed_value, catalog_value in zip(observed, catalog)
            if observed_value
        ]
        return sum(scores) / len(scores) if scores else 0.0

    @classmethod
    def _mean_available_line_score(
        cls,
        observed: tuple[str, str],
        catalog: tuple[str, str],
    ) -> float:
        scores = [
            cls._line_score(observed_value, catalog_value)
            for observed_value, catalog_value in zip(observed, catalog)
            if observed_value not in {"", "unknown"}
        ]
        return sum(scores) / len(scores) if scores else 0.0

    @classmethod
    def _line_score(cls, observed: str, catalog_value: str) -> float:
        normalized_catalog = cls._normalize_label(catalog_value)
        aliases = cls._LINE_ALIASES.get(observed, ())
        if observed == "none":
            return 1.0 if not normalized_catalog or normalized_catalog in aliases else 0.0
        return 1.0 if any(alias in normalized_catalog for alias in aliases) else 0.0

    @staticmethod
    def _text_similarity(left: str, right: str) -> float:
        if not left or not right:
            return 0.0
        if left == right:
            return 1.0
        if left in right or right in left:
            return 0.9
        return SequenceMatcher(None, left[:64], right[:64], autojunk=False).ratio()

    @staticmethod
    @lru_cache(maxsize=131_072)
    def _normalize_imprint(value: str) -> str:
        normalized = unicodedata.normalize("NFKC", value or "").upper()
        return "".join(character for character in normalized if character.isalnum())[:64]

    @staticmethod
    @lru_cache(maxsize=16_384)
    def _normalize_label(value: str) -> str:
        return unicodedata.normalize("NFKC", value or "").strip().lower()[:128]

    @staticmethod
    def _is_confident(
        features: PillVisualFeatures,
        candidates: list[PillIdentificationCandidate],
    ) -> bool:
        observed_imprint_length = sum(
            len(IdentifyPill._normalize_imprint(value))
            for value in (features.front_imprint, features.back_imprint)
        )
        if observed_imprint_length < 2 or not candidates:
            return False
        top_score = candidates[0].match_score
        runner_up_score = candidates[1].match_score if len(candidates) > 1 else 0.0
        return top_score >= 0.84 and (top_score - runner_up_score) >= 0.06
