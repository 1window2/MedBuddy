# File Name: pill_identification.py
# Role: HTTP response DTOs for experimental loose-pill candidate identification.

from pydantic import BaseModel, Field

from entities.pill_identification_entity import (
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
            image_url=candidate.image_url,
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
    requires_confirmation: bool = True
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
            is_confident=result.is_confident,
            requires_confirmation=result.requires_confirmation,
            observed_features=PillVisualFeaturesResponse.from_domain(
                result.observed_features
            ),
            data=[
                PillIdentificationCandidateResponse.from_domain(candidate)
                for candidate in result.candidates
            ],
        )
