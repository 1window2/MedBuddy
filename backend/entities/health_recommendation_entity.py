# File Name: health_recommendation_entity.py
# Role: Normalizes generated diet, exercise and caution guidance into a stable medication-linked response entity.

from typing import Any

from pydantic import BaseModel, Field


# Class Name: HealthRecommendation
# Role:
# - Represents structured health management recommendations.
# Responsibilities:
# - Validate the diet, exercise, caution, and medication context returned by CheckHealthRecommendation.
# - Keep API serialization independent from the recommendation generator.
# Attributes:
# - medication_names (list[str]): Source medication names to attach to health guidance.
class HealthRecommendation(BaseModel):
    diet_recommendation: str = ""
    exercise_recommendation: str = ""
    caution_items: list[str] = Field(default_factory=list)
    medication_names: list[str] = Field(default_factory=list)

    # Function Name: from_payload
    # Description:
    # - Normalizes AI dietary, exercise and caution guidance and attaches the medication names used to generate it.
    # Parameters:
    # - payload (dict[str, object]): Generated dietary, exercise and caution fields before normalization.
    # - medication_names (list[str]): Source medication names to attach to health guidance.
    # Returns:
    # - Validated recommendation with trimmed text and nonblank list entries.
    @classmethod
    def from_payload(
        cls,
        payload: dict[str, object],
        *,
        medication_names: list[str],
    ) -> "HealthRecommendation":
        return cls(
            diet_recommendation=cls._read_text(payload.get("diet_recommendation")),
            exercise_recommendation=cls._read_text(
                payload.get("exercise_recommendation")
            ),
            caution_items=cls._read_text_list(payload.get("caution_items")),
            medication_names=cls._read_text_list(medication_names),
        )

    # Function Name: _read_text
    # Description:
    # - Converts optional recommendation values to trimmed display text.
    # Parameters:
    # - value (Any): Optional raw recommendation text field.
    # Returns:
    # - Trimmed string, or an empty string for None.
    @staticmethod
    def _read_text(value: Any) -> str:
        return "" if value is None else str(value).strip()

    # Function Name: _read_text_list
    # Description:
    # - Keeps nonblank normalized text from list-valued guidance fields.
    # Parameters:
    # - value (Any): Untrusted recommendation text-list field.
    # Returns:
    # - Clean text list, or an empty list for non-list input.
    @classmethod
    def _read_text_list(cls, value: Any) -> list[str]:
        if not isinstance(value, list):
            return []
        return [
            text
            for item in value
            if (text := cls._read_text(item))
        ]
