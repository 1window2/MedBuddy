# File Name: health_recommendation_entity.py
# Role: Skeleton entity mapped from the HealthRecommendation box in ClassDiagram2.

from pydantic import BaseModel


# Class Name: HealthRecommendation
# Role: Represents health management recommendation text.
class HealthRecommendation(BaseModel):
    recommendation_text: str = ""

    def getHealthRecommendation(self) -> str:
        return self.recommendation_text
