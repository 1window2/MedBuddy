# File Name: pill_identification.py
# Role: HTTP response DTOs for experimental loose-pill candidate identification.

from typing import Literal

from pydantic import BaseModel, Field

from entities.medication_image_url_entity import safe_medication_image_url
from entities.pill_identification_entity import (
    MultiplePillIdentificationResult,
    MultiplePillObservation,
    PillBoundingBox,
    PillIdentificationCandidate,
    PillIdentificationResult,
    PillVisualFeatures,
)


# Class Name: PillVisualFeaturesResponse
# Role:
# - Exposes observed pill appearance and image-quality evidence with bounded side-consistency confidence.
# Responsibilities:
# - Serialize tuple-valued visual evidence as lists and retain quality and side-consistency indicators.
# Attributes:
# - shape (str): Observed or registered pill shape.
# - colors (list[str]): Observed or registered pill colors.
# - front_imprint (str): Imprint observed on the photographed front side.
# - back_imprint (str): Imprint observed on the photographed back side.
# - front_line (str): Division line observed on the photographed front side.
# - back_line (str): Division line observed on the photographed back side.
class PillVisualFeaturesResponse(BaseModel):
    shape: str = "unknown"
    colors: list[str] = Field(default_factory=list)
    front_imprint: str = ""
    back_imprint: str = ""
    front_line: str = "unknown"
    back_line: str = "unknown"
    quality: str = "usable"
    quality_issues: list[str] = Field(default_factory=list)
    same_pill: bool = True
    side_consistency_confidence: float = Field(default=1.0, ge=0.0, le=1.0)

    # Function Name: from_domain
    # Description:
    # - Copies visual evidence to the API model and converts immutable observation tuples into JSON lists.
    # Parameters:
    # - features (PillVisualFeatures): Observed shape, colors, imprints, score lines and image quality.
    # Returns:
    # - Visual-feature response preserving quality and same-pill evidence.
    @classmethod
    def from_domain(
        cls,
        features: PillVisualFeatures,
    ) -> "PillVisualFeaturesResponse":
        return cls(
            shape=features.shape,
            colors=list(features.colors),
            front_imprint=features.front_imprint,
            back_imprint=features.back_imprint,
            front_line=features.front_line,
            back_line=features.back_line,
            quality=features.quality,
            quality_issues=list(features.quality_issues),
            same_pill=features.same_pill,
            side_consistency_confidence=features.side_consistency_confidence,
        )


# Class Name: PillIdentificationCandidateResponse
# Role:
# - Exposes an MFDS product candidate with image, imprints, matched features and a score constrained to 0-1.
# Responsibilities:
# - Enforce bounded scores and sanitize candidate image URLs at the API boundary.
# Attributes:
# - item_seq (str): Canonical MFDS product identifier.
# - item_name (str): Public medication product name.
# - shape (str): Observed or registered pill shape.
# - colors (list[str]): Observed or registered pill colors.
class PillIdentificationCandidateResponse(BaseModel):
    item_seq: str
    item_name: str
    entp_name: str = ""
    image_url: str = ""
    shape: str = ""
    colors: list[str] = Field(default_factory=list)
    print_front: str = ""
    print_back: str = ""
    match_score: float = Field(ge=0.0, le=1.0)
    matched_attributes: list[str] = Field(default_factory=list)

    # Function Name: from_domain
    # Description:
    # - Maps a ranked catalog candidate and filters its medication image URL through the trusted-origin policy.
    # Parameters:
    # - candidate (PillIdentificationCandidate): Ranked MFDS product match and its visual evidence.
    # Returns:
    # - Candidate response with safe image URL and list-valued match evidence.
    @classmethod
    def from_domain(
        cls,
        candidate: PillIdentificationCandidate,
    ) -> "PillIdentificationCandidateResponse":
        return cls(
            item_seq=candidate.item_seq,
            item_name=candidate.item_name,
            entp_name=candidate.entp_name,
            image_url=safe_medication_image_url(candidate.image_url),
            shape=candidate.shape,
            colors=list(candidate.colors),
            print_front=candidate.print_front,
            print_back=candidate.print_back,
            match_score=candidate.match_score,
            matched_attributes=list(candidate.matched_attributes),
        )


# Class Name: PillIdentificationResponse
# Role:
# - Carries one pill's observed features and ranked products while keeping user confirmation mandatory.
# Responsibilities:
# - Derive success/confidence from actual candidates and always preserve the confirmation requirement.
# Attributes:
# - message (str): User-facing operation status message.
# - is_confident (bool): Whether candidate and image evidence meets the confidence policy.
# - requires_confirmation (Literal[True]): Mandatory user confirmation before using an identification candidate.
# - observed_features (PillVisualFeaturesResponse): Visual evidence extracted from the supplied pill photographs.
class PillIdentificationResponse(BaseModel):
    success: bool
    message: str
    is_confident: bool = False
    requires_confirmation: Literal[True] = True
    observed_features: PillVisualFeaturesResponse
    data: list[PillIdentificationCandidateResponse] = Field(default_factory=list)

    # Function Name: from_domain
    # Description:
    # - Selects no-match, confident or uncertain messaging and serializes candidates without relaxing confirmation.
    # Parameters:
    # - result (PillIdentificationResult): Single-pill domain result with mandatory confirmation.
    # Returns:
    # - Single-pill response whose success and confidence require nonempty candidates.
    @classmethod
    def from_domain(
        cls,
        result: PillIdentificationResult,
    ) -> "PillIdentificationResponse":
        if not result.candidates:
            message = "No matching pill candidates were found."
        elif result.is_confident:
            message = "Likely candidates were found. Confirm the product before use."
        else:
            message = "Possible candidates were found. Additional confirmation is required."
        return cls(
            success=bool(result.candidates),
            message=message,
            is_confident=result.is_confident and bool(result.candidates),
            requires_confirmation=True,
            observed_features=PillVisualFeaturesResponse.from_domain(
                result.observed_features
            ),
            data=[
                PillIdentificationCandidateResponse.from_domain(candidate)
                for candidate in result.candidates
            ],
        )


# Class Name: PillBoundingBoxResponse
# Role:
# - Constrains pill-box coordinates to normalized image space with positive width and height.
# Responsibilities:
# - Validate coordinate bounds and expose a stable left/top/width/height response shape.
# Attributes:
# - left (float): Left edge as a fraction of image width.
# - top (float): Top edge as a fraction of image height.
# - width (float): Positive box width relative to the source image.
# - height (float): Positive box height relative to the source image.
class PillBoundingBoxResponse(BaseModel):
    left: float = Field(ge=0.0, le=1.0)
    top: float = Field(ge=0.0, le=1.0)
    width: float = Field(gt=0.0, le=1.0)
    height: float = Field(gt=0.0, le=1.0)

    # Function Name: from_domain
    # Description:
    # - Copies the validated domain box into API coordinate fields.
    # Parameters:
    # - box (PillBoundingBox): Validated normalized pill location within the image.
    # Returns:
    # - Bounding-box response with left, top, width and height.
    @classmethod
    def from_domain(cls, box: PillBoundingBox) -> "PillBoundingBoxResponse":
        return cls(left=box.left, top=box.top, width=box.width, height=box.height)


# Class Name: MultiplePillObservationResponse
# Role:
# - Associates a one-based pill index and normalized image box with its independent identification result.
# Responsibilities:
# - Serialize the spatial box and candidate list independently for each numbered pill.
# Attributes:
# - bounding_box (PillBoundingBoxResponse): Normalized image region containing the observed pill.
class MultiplePillObservationResponse(BaseModel):
    index: int = Field(ge=1, le=10)
    bounding_box: PillBoundingBoxResponse
    identification: PillIdentificationResponse

    # Function Name: from_domain
    # Description:
    # - Serializes one pill's box and independent candidate result under its observation index.
    # Parameters:
    # - observation (MultiplePillObservation): Numbered pill box and its independent identification result.
    # Returns:
    # - Numbered pill observation response.
    @classmethod
    def from_domain(
        cls,
        observation: MultiplePillObservation,
    ) -> "MultiplePillObservationResponse":
        return cls(
            index=observation.index,
            bounding_box=PillBoundingBoxResponse.from_domain(
                observation.bounding_box
            ),
            identification=PillIdentificationResponse.from_domain(
                observation.identification
            ),
        )


# Class Name: MultiplePillIdentificationResponse
# Role:
# - Returns one to ten independently identified pill observations with confirmation required for every result.
# Responsibilities:
# - Bound the observation count and retain confirmation requirements across the complete photo response.
# Attributes:
# - message (str): User-facing operation status message.
# - requires_confirmation (Literal[True]): Mandatory user confirmation before using an identification candidate.
# - observations (list[MultiplePillObservationResponse]): Spatially separate pills with independent identification results.
class MultiplePillIdentificationResponse(BaseModel):
    success: Literal[True] = True
    message: str
    requires_confirmation: Literal[True] = True
    observations: list[MultiplePillObservationResponse] = Field(
        min_length=1,
        max_length=10,
    )

    # Function Name: from_domain
    # Description:
    # - Serializes all numbered observations and reports the detected pill count with a confirmation reminder.
    # Parameters:
    # - result (MultiplePillIdentificationResult): Independently ranked observations from one multi-pill image.
    # Returns:
    # - Successful multi-pill response retaining mandatory confirmation.
    @classmethod
    def from_domain(
        cls,
        result: MultiplePillIdentificationResult,
    ) -> "MultiplePillIdentificationResponse":
        return cls(
            success=True,
            message=(
                f"Detected {len(result.observations)} pills. "
                "Confirm each candidate before saving."
            ),
            requires_confirmation=True,
            observations=[
                MultiplePillObservationResponse.from_domain(observation)
                for observation in result.observations
            ],
        )
