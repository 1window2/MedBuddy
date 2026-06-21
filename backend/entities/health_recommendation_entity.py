# 파일명: health_recommendation_entity.py
# 역할: ClassDiagram2의 HealthRecommendation에 대응하는 미구현 엔티티이다.

from pydantic import BaseModel


# 클래스명: HealthRecommendation
# 역할: 건강 관리 추천 문구를 표현한다.
class HealthRecommendation(BaseModel):
    recommendation_text: str = ""

    def getHealthRecommendation(self) -> str:
        return self.recommendation_text
