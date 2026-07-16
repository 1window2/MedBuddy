# File Name: health_recommendation_entity.py
# Role: Entity returned by the health recommendation use case.

from typing import Any

from pydantic import BaseModel, Field


# Class Name: HealthRecommendation
# Role: Represents structured health management recommendations.
# Responsibilities:
#   - Validate the diet, exercise, caution, and medication context returned by
#     CheckHealthRecommendation.
#   - Keep API serialization independent from the recommendation generator.
class HealthRecommendation(BaseModel):
    diet_recommendation: str = ""
    exercise_recommendation: str = ""
    caution_items: list[str] = Field(default_factory=list)
    medication_names: list[str] = Field(default_factory=list)

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

    @staticmethod
    def _read_text(value: Any) -> str:
        return "" if value is None else str(value).strip()

    @classmethod
    def _read_text_list(cls, value: Any) -> list[str]:
        if not isinstance(value, list):
            return []
        return [
            text
            for item in value
            if (text := cls._read_text(item))
        ]
