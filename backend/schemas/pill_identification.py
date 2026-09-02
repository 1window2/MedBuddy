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


class PillIdentificationResponse(BaseModel):
    success: bool
    message: str
    is_confident: bool = False
    requires_confirmation: Literal[True] = True
    observed_features: PillVisualFeaturesResponse
    data: list[PillIdentificationCandidateResponse] = Field(default_factory=list)

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


class PillBoundingBoxResponse(BaseModel):
    left: float = Field(ge=0.0, le=1.0)
    top: float = Field(ge=0.0, le=1.0)
    width: float = Field(gt=0.0, le=1.0)
    height: float = Field(gt=0.0, le=1.0)

    @classmethod
    def from_domain(cls, box: PillBoundingBox) -> "PillBoundingBoxResponse":
        return cls(left=box.left, top=box.top, width=box.width, height=box.height)


class MultiplePillObservationResponse(BaseModel):
    index: int = Field(ge=1, le=10)
    bounding_box: PillBoundingBoxResponse
    identification: PillIdentificationResponse

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


class MultiplePillIdentificationResponse(BaseModel):
    success: Literal[True] = True
    message: str
    requires_confirmation: Literal[True] = True
    observations: list[MultiplePillObservationResponse] = Field(
        min_length=1,
        max_length=10,
    )

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
