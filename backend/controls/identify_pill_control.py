# File Name: identify_pill_control.py
# Role: Ranks MFDS pill candidates from bounded visual observations while preserving mandatory user confirmation.

import asyncio
import heapq
import unicodedata
from difflib import SequenceMatcher
from functools import lru_cache

from boundaries.pill_identification_boundary import (
    MFDSPillCatalogBoundary,
    PillVisionBoundary,
)
from entities.pill_identification_entity import (
    MAX_RETURNED_PILL_CANDIDATES,
    MultiplePillIdentificationResult,
    MultiplePillObservation,
    PillCatalogEntry,
    PillIdentificationCandidate,
    PillIdentificationResult,
    PillVisualFeatures,
)


# Class Name: IdentifyPill
# Role:
# - Identifies candidate products without treating a visual match as a diagnosis.
# Responsibilities:
# - Bound image-analysis and ranking work, score catalog evidence deterministically and require confirmation even for confident candidates.
# Attributes:
# - vision_boundary (PillVisionBoundary): External pill-appearance extraction boundary.
# - catalog_boundary (MFDSPillCatalogBoundary): Shared MFDS pill-reference catalog provider.
# - candidate_limit (int): Maximum pill matches exposed to the user.
# - _ranking_semaphore (asyncio.Semaphore): Shared concurrency gate for CPU-heavy catalog ranking.
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

    # Function Name: __init__
    # Description:
    # - Validates the candidate limit and binds visual extraction, the shared MFDS catalog and bounded ranking concurrency.
    # Parameters:
    # - vision_boundary (PillVisionBoundary): External pill-appearance extraction boundary.
    # - catalog_boundary (MFDSPillCatalogBoundary): Shared MFDS pill-reference catalog provider.
    # - candidate_limit (int): Maximum pill matches exposed to the user.
    # - ranking_semaphore (asyncio.Semaphore | None): Shared concurrency gate for CPU-heavy catalog ranking.
    # Returns:
    # - None.
    def __init__(
        self,
        *,
        vision_boundary: PillVisionBoundary,
        catalog_boundary: MFDSPillCatalogBoundary,
        candidate_limit: int = 5,
        ranking_semaphore: asyncio.Semaphore | None = None,
    ) -> None:
        if candidate_limit < 1 or candidate_limit > 20:
            raise ValueError("Pill candidate limit must be between 1 and 20.")
        self.vision_boundary = vision_boundary
        self.catalog_boundary = catalog_boundary
        self.candidate_limit = candidate_limit
        self._ranking_semaphore = ranking_semaphore or asyncio.Semaphore(1)

    # Function Name: requestPillIdentification
    # Description:
    # - Returns ranked candidates while keeping confirmation mandatory.
    # Parameters:
    # - front_image (bytes): Required front-side pill image bytes.
    # - back_image (bytes | None): Optional back-side image bytes for the same pill.
    # Returns:
    # - Single-pill candidates and observed features with user confirmation always required.
    async def requestPillIdentification(
        self,
        front_image: bytes,
        back_image: bytes | None = None,
    ) -> PillIdentificationResult:
        """Returns ranked candidates while keeping confirmation mandatory."""

        vision_task = asyncio.create_task(
            self.vision_boundary.extractVisualFeatures(front_image, back_image)
        )
        catalog_task = asyncio.create_task(self.catalog_boundary.getCatalog())
        required_tasks = (vision_task, catalog_task)
        try:
            features, catalog = await asyncio.gather(*required_tasks)
        except BaseException:
            for task in required_tasks:
                if not task.done():
                    task.cancel()
            await asyncio.gather(*required_tasks, return_exceptions=True)
            raise
        return await self._build_result(features, catalog)

    # Function Name: requestMultiplePillIdentification
    # Description:
    # - Detects and independently ranks every pill visible in one photo.
    # Parameters:
    # - image (bytes): Image bytes containing one to ten separate pills.
    # Returns:
    # - One to ten numbered observations with independent candidates and mandatory confirmation.
    async def requestMultiplePillIdentification(
        self,
        image: bytes,
    ) -> MultiplePillIdentificationResult:
        """Detects and independently ranks every pill visible in one photo."""

        vision_task = asyncio.create_task(
            self.vision_boundary.extractMultipleVisualFeatures(image)
        )
        catalog_task = asyncio.create_task(self.catalog_boundary.getCatalog())
        required_tasks = (vision_task, catalog_task)
        try:
            observations, catalog = await asyncio.gather(*required_tasks)
        except BaseException:
            for task in required_tasks:
                if not task.done():
                    task.cancel()
            await asyncio.gather(*required_tasks, return_exceptions=True)
            raise

        results: list[MultiplePillObservation] = []
        for index, (bounding_box, features) in enumerate(observations, start=1):
            identification = await self._build_result(features, catalog)
            results.append(
                MultiplePillObservation(
                    index=index,
                    bounding_box=bounding_box,
                    identification=identification,
                )
            )
        return MultiplePillIdentificationResult(observations=tuple(results))

    # 함수이름: _build_result
    # 함수역할: 기본 후보 경계와 동점인 제품을 최대 100개까지 보존하고 초과 여부를 알린다.
    # 매개변수: features는 관찰 속성, catalog는 공공 약품 목록이다.
    # 반환값: 동점 후보와 추가 촬영 필요 여부를 포함하는 확인 필수 결과.
    async def _build_result(
        self,
        features: PillVisualFeatures,
        catalog: tuple[PillCatalogEntry, ...],
    ) -> PillIdentificationResult:
        """동점인 정답 후보가 기본 표시 개수 때문에 누락되지 않게 한다."""

        ranked_candidates = await self._rank_candidates_with_capacity(
            features,
            catalog,
            MAX_RETURNED_PILL_CANDIDATES + 1,
        )
        if ranked_candidates:
            cutoff = ranked_candidates[
                min(self.candidate_limit, len(ranked_candidates)) - 1
            ].match_score
            eligible = [c for c in ranked_candidates if c.match_score >= cutoff]
        else:
            eligible = []
        return PillIdentificationResult(
            observed_features=features,
            candidates=tuple(eligible[:MAX_RETURNED_PILL_CANDIDATES]),
            is_confident=self._is_confident(features, ranked_candidates),
            requires_confirmation=True,
            has_more_candidates=len(eligible) > MAX_RETURNED_PILL_CANDIDATES,
        )

    # Function Name: _rank_candidates_with_capacity
    # Description:
    # - Keeps shared CPU capacity reserved until a detached worker exits.
    # Parameters:
    # - features (PillVisualFeatures): Observed shape, colors, imprints, score lines and image quality.
    # - catalog (tuple[PillCatalogEntry, ...]): Immutable MFDS pill-reference catalog used for ranking.
    # - ranking_limit (int): Maximum matches retained by this ranking operation.
    # Returns:
    # - Ranked candidates after acquiring the shared capacity permit; caller cancellation retains the permit until the worker completes.
    async def _rank_candidates_with_capacity(
        self,
        features: PillVisualFeatures,
        catalog: tuple[PillCatalogEntry, ...],
        ranking_limit: int,
    ) -> list[PillIdentificationCandidate]:
        """Keeps shared CPU capacity reserved until a detached worker exits."""

        await self._ranking_semaphore.acquire()
        worker = asyncio.create_task(
            asyncio.to_thread(
                self._rank_candidates,
                features,
                catalog,
                ranking_limit,
            )
        )
        release_on_exit = True
        try:
            try:
                return await asyncio.shield(worker)
            except asyncio.CancelledError:
                worker.add_done_callback(self._release_ranking_capacity)
                release_on_exit = False
                raise
        finally:
            if release_on_exit:
                self._ranking_semaphore.release()

    # Function Name: _release_ranking_capacity
    # Description:
    # - Consumes a detached ranking result and releases its shared slot.
    # Parameters:
    # - worker (asyncio.Task[list[PillIdentificationCandidate]]): Background ranking task that retains the concurrency permit until completion.
    # Returns:
    # - None.
    def _release_ranking_capacity(
        self,
        worker: asyncio.Task[list[PillIdentificationCandidate]],
    ) -> None:
        """Consumes a detached ranking result and releases its shared slot."""

        try:
            worker.exception()
        except asyncio.CancelledError:
            pass
        self._ranking_semaphore.release()

    # Function Name: _rank_candidates
    # Description:
    # - Maintains a bounded heap of plausible visual matches and caps imprint-free scores at 0.68.
    # Parameters:
    # - features (PillVisualFeatures): Observed shape, colors, imprints, score lines and image quality.
    # - catalog (tuple[PillCatalogEntry, ...]): Immutable MFDS pill-reference catalog used for ranking.
    # - ranking_limit (int | None): Optional ranking bound overriding the default candidate limit.
    # Returns:
    # - Candidates ordered by score, image availability and product ID.
    def _rank_candidates(
        self,
        features: PillVisualFeatures,
        catalog: tuple[PillCatalogEntry, ...],
        ranking_limit: int | None = None,
    ) -> list[PillIdentificationCandidate]:
        selection_limit = ranking_limit or self.candidate_limit
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
            if len(top_matches) < selection_limit:
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

    # Function Name: _is_plausible_candidate
    # Description:
    # - Prunes unrelated imprints, requiring both shape and color when usable imprint evidence is unavailable.
    # Parameters:
    # - features (PillVisualFeatures): Observed shape, colors, imprints, score lines and image quality.
    # - entry (PillCatalogEntry): MFDS reference product and its registered visual attributes.
    # Returns:
    # - True when the catalog entry has sufficient evidence for detailed scoring.
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

    # Function Name: _imprints_are_plausibly_related
    # Description:
    # - Accepts equal or contained imprints, then permits limited length differences when characters overlap.
    # Parameters:
    # - observed (str): Normalized imprint extracted from the image.
    # - catalog (str): Normalized imprint registered for the catalog product.
    # Returns:
    # - True when the normalized imprints can enter similarity scoring.
    @staticmethod
    def _imprints_are_plausibly_related(observed: str, catalog: str) -> bool:
        if observed == catalog or observed in catalog or catalog in observed:
            return True
        if abs(len(observed) - len(catalog)) > 2:
            return False
        return not set(observed).isdisjoint(catalog)

    # Function Name: _score_entry
    # Description:
    # - Combines available shape, color, imprint and score-line evidence using normalized weights.
    # Parameters:
    # - features (PillVisualFeatures): Observed shape, colors, imprints, score lines and image quality.
    # - entry (PillCatalogEntry): MFDS reference product and its registered visual attributes.
    # Returns:
    # - Weighted score and the names of sufficiently matched visual attributes.
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

    # Function Name: _shape_score
    # Description:
    # - Compares the catalog shape against aliases for the observed shape.
    # Parameters:
    # - observed (str): Normalized shape label extracted from the image.
    # - catalog_shape (str): Registered MFDS pill shape label.
    # Returns:
    # - 1.0 for an alias match; otherwise 0.0.
    @classmethod
    def _shape_score(cls, observed: str, catalog_shape: str) -> float:
        normalized_catalog = cls._normalize_label(catalog_shape)
        aliases = cls._SHAPE_ALIASES.get(observed, ())
        return 1.0 if normalized_catalog in aliases else 0.0

    # Function Name: _color_score
    # Description:
    # - Matches each observed color against normalized catalog color aliases.
    # Parameters:
    # - observed_colors (tuple[str, ...]): Color labels extracted from the pill image.
    # - catalog_colors (tuple[str, str]): Catalog primary and secondary color labels.
    # Returns:
    # - Fraction of observed colors matched, or 0.0 without color evidence.
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

    # Function Name: _oriented_text_score
    # Description:
    # - Compares pill imprints in direct and swapped orientations, allowing a single observed side.
    # Parameters:
    # - observed_front (str): Observed front-side imprint.
    # - observed_back (str): Observed back-side imprint.
    # - catalog_front (str): Catalog front-side imprint.
    # - catalog_back (str): Catalog back-side imprint.
    # Returns:
    # - Highest orientation-aware imprint similarity.
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

    # Function Name: _oriented_line_score
    # Description:
    # - Scores pill division lines in direct and reversed front/back orientations.
    # Parameters:
    # - features (PillVisualFeatures): Observed shape, colors, imprints, score lines and image quality.
    # - entry (PillCatalogEntry): MFDS reference product and its registered visual attributes.
    # Returns:
    # - Highest mean score-line agreement for the available observations.
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

    # Function Name: _has_line_observation
    # Description:
    # - Checks for at least one observed division-line value beyond blank or unknown.
    # Parameters:
    # - features (PillVisualFeatures): Observed shape, colors, imprints, score lines and image quality.
    # Returns:
    # - True when line evidence can contribute to ranking.
    @staticmethod
    def _has_line_observation(features: PillVisualFeatures) -> bool:
        return any(
            line not in {"", "unknown"}
            for line in (features.front_line, features.back_line)
        )

    # Function Name: _mean_available_similarity
    # Description:
    # - Averages paired imprint similarities only for sides with observed text.
    # Parameters:
    # - observed (tuple[str, str]): Observed front/back values; unavailable sides do not contribute.
    # - catalog (tuple[str, str]): Catalog front/back values in the orientation being tested.
    # Returns:
    # - Mean similarity, or 0.0 when no side has text.
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

    # Function Name: _mean_available_line_score
    # Description:
    # - Averages paired division-line matches only for known observed sides.
    # Parameters:
    # - observed (tuple[str, str]): Observed front/back values; unavailable sides do not contribute.
    # - catalog (tuple[str, str]): Catalog front/back values in the orientation being tested.
    # Returns:
    # - Mean line score, or 0.0 without observations.
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

    # Function Name: _line_score
    # Description:
    # - Matches division-line aliases and treats blank catalog lines as a possible no-line observation.
    # Parameters:
    # - observed (str): Observed division-line label, including explicit none.
    # - catalog_value (str): Registered pill division-line label.
    # Returns:
    # - 1.0 for a supported match; otherwise 0.0.
    @classmethod
    def _line_score(cls, observed: str, catalog_value: str) -> float:
        normalized_catalog = cls._normalize_label(catalog_value)
        aliases = cls._LINE_ALIASES.get(observed, ())
        if observed == "none":
            return 1.0 if not normalized_catalog or normalized_catalog in aliases else 0.0
        return 1.0 if any(alias in normalized_catalog for alias in aliases) else 0.0

    # Function Name: _text_similarity
    # Description:
    # - Scores exact and contained imprints before applying bounded SequenceMatcher comparison.
    # Parameters:
    # - left (str): First normalized string in the similarity comparison.
    # - right (str): Second normalized string in the similarity comparison.
    # Returns:
    # - Similarity from 0.0 to 1.0; containment receives 0.9.
    @staticmethod
    def _text_similarity(left: str, right: str) -> float:
        if not left or not right:
            return 0.0
        if left == right:
            return 1.0
        if left in right or right in left:
            return 0.9
        return SequenceMatcher(None, left[:64], right[:64], autojunk=False).ratio()

    # Function Name: _normalize_imprint
    # Description:
    # - Applies NFKC normalization and uppercase, retaining at most 64 alphanumeric imprint characters.
    # Parameters:
    # - value (str): Raw pill imprint text, possibly blank.
    # Returns:
    # - Bounded imprint comparison key.
    @staticmethod
    @lru_cache(maxsize=131_072)
    def _normalize_imprint(value: str) -> str:
        normalized = unicodedata.normalize("NFKC", value or "").upper()
        return "".join(character for character in normalized if character.isalnum())[:64]

    # Function Name: _normalize_label
    # Description:
    # - Applies NFKC normalization, trimming and lowercase to bounded visual labels.
    # Parameters:
    # - value (str): Raw shape, color or division-line label.
    # Returns:
    # - Normalized label limited to 128 characters.
    @staticmethod
    @lru_cache(maxsize=16_384)
    def _normalize_label(value: str) -> str:
        return unicodedata.normalize("NFKC", value or "").strip().lower()[:128]

    # Function Name: _is_confident
    # Description:
    # - Requires usable same-pill evidence, at least two imprint characters and a sufficiently strong, separated top candidate.
    # Parameters:
    # - features (PillVisualFeatures): Observed shape, colors, imprints, score lines and image quality.
    # - candidates (list[PillIdentificationCandidate]): Ranked MFDS product match and its visual evidence.
    # Returns:
    # - True only when side confidence is at least 0.7, top score at least 0.84 and margin at least 0.06.
    @staticmethod
    def _is_confident(
        features: PillVisualFeatures,
        candidates: list[PillIdentificationCandidate],
    ) -> bool:
        if (
            features.quality == "poor"
            or not features.same_pill
            or features.side_consistency_confidence < 0.7
        ):
            return False
        observed_imprint_length = sum(
            len(IdentifyPill._normalize_imprint(value))
            for value in (features.front_imprint, features.back_imprint)
        )
        if observed_imprint_length < 2 or not candidates:
            return False
        top_score = candidates[0].match_score
        runner_up_score = candidates[1].match_score if len(candidates) > 1 else 0.0
        return top_score >= 0.84 and (top_score - runner_up_score) >= 0.06
