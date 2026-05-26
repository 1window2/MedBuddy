# File Name: drug_cache_service.py
# Role: Handles Redis-backed caching for drug information responses.

import json
import logging
from typing import Optional

import redis.asyncio as redis

from core.config import settings
from schemas.medication import MedicationDetail

logger = logging.getLogger(__name__)


# Class Name: DrugCacheService
# Role: Boundary adapter for Redis medication detail cache.
# Responsibilities:
#   - Read cached MedicationDetail lists.
#   - Write MedicationDetail lists with a fixed TTL.
# Attributes:
#   - redis_client: Async Redis client.
#   - ttl_seconds: Cache duration for drug info entries.
class DrugCacheService:
    DEFAULT_TTL_SECONDS = 604800

    def __init__(
        self,
        redis_client: Optional[redis.Redis] = None,
        ttl_seconds: int = DEFAULT_TTL_SECONDS,
    ) -> None:
        self.redis_client = redis_client or redis.from_url(
            settings.REDIS_URL,
            decode_responses=True,
        )
        self.ttl_seconds = ttl_seconds

    # Function Name: get
    # Description:
    # - Attempts to load a MedicationDetail list from Redis.
    # - Cache failures are treated as misses to preserve service availability.
    # Parameters:
    # - drug_name: Search keyword used as cache key suffix.
    # Returns:
    # - Cached MedicationDetail list, or None when missing/unavailable.
    async def get(self, drug_name: str) -> Optional[list[MedicationDetail]]:
        cache_key = self._cache_key(drug_name)
        try:
            cached_data = await self.redis_client.get(cache_key)
            if not cached_data:
                return None

            logger.info("[Redis Cache Hit] '%s' 정보를 cache에서 확인했습니다", drug_name)
            items = json.loads(cached_data)
            return [
                MedicationDetail(**{**item, "source": f"[Cache] {item.get('source', '')}"})
                for item in items
            ]
        except Exception as exc:
            logger.warning("Redis 조회 실패 (캐시 무시하고 진행): %s", exc)
            return None

    # Function Name: set
    # Description:
    # - Stores a MedicationDetail list in Redis.
    # - Cache failures are logged but do not fail the use case.
    # Parameters:
    # - drug_name: Search keyword used as cache key suffix.
    # - medication_details: MedicationDetail list to cache.
    # Returns:
    # - None.
    async def set(
        self,
        drug_name: str,
        medication_details: list[MedicationDetail],
    ) -> None:
        if not medication_details:
            return

        cache_key = self._cache_key(drug_name)
        try:
            payload = [detail.model_dump() for detail in medication_details]
            await self.redis_client.setex(
                cache_key,
                self.ttl_seconds,
                json.dumps(payload),
            )
            logger.info("[Redis Cache Saved] '%s' 정보를 캐시에 저장했습니다.", drug_name)
        except Exception as exc:
            logger.error("Redis 저장 실패: %s", exc)

    # Function Name: _cache_key
    # Description:
    # - Builds the Redis cache key for a medication search keyword.
    # Parameters:
    # - drug_name: Search keyword.
    # Returns:
    # - Redis key string.
    def _cache_key(self, drug_name: str) -> str:
        return f"drug_info:{drug_name}"
