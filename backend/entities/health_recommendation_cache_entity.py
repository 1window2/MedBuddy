# 파일명: health_recommendation_cache_entity.py
# 역할: 약 조합 기반 건강 관리 추천 결과를 로컬 DB에 캐시한다.

from datetime import datetime

from sqlalchemy import Column, DateTime, Integer, String, Text

from core.database import Base
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH


# 클래스명: _HealthRecommendationCache
# 역할: Gemini가 생성한 건강 관리 추천 결과를 약 조합별로 보관한다.
# 주요 책임:
#   - 같은 환자와 같은 복용 약 조합에 대해 AI 추천 결과를 재사용한다.
#   - 반복 조회 시 Gemini 토큰 사용량과 대기 시간을 줄인다.
class _HealthRecommendationCache(Base):
    __tablename__ = "health_recommendation_cache"

    id = Column(Integer, primary_key=True, index=True)
    patient_hash = Column(
        String,
        index=True,
        nullable=False,
        default=DEFAULT_PATIENT_HASH,
        server_default=DEFAULT_PATIENT_HASH,
    )
    recommendation_key = Column(String, index=True, nullable=False)
    payload = Column(Text, nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
