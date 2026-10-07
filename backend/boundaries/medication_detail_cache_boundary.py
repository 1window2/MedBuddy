# File Name: medication_detail_cache_boundary.py
# Role: Owns optional Redis medication-detail snapshots and their availability lifecycle.

import json
import logging

import redis.asyncio as redis

from core.config import settings
from entities.medication_detail_entity import MedicationDetail

logger = logging.getLogger(__name__)


# Class Name: MedicationDetailCache
# Role:
# - Shared Redis cache boundary for medication detail lookup.
# Responsibilities:
# - Read cached MedicationDetail lists.
# - Save MedicationDetail lists without failing the main use case on Redis errors.
# Attributes:
# - redis_client (redis.Redis): Async Redis client used as optional cache storage.
class MedicationDetailCache:
    CACHE_TTL_SECONDS = 604800

    # 함수이름: __init__
    # 함수역할:
    # - Redis 약품 상세 캐시 연결을 준비하고 사용 가능 상태로 시작한다.
    # 매개변수:
    # - redis_client (redis.Redis | None): 직렬화된 약품 상세를 저장·조회할 Redis 연결.
    # 반환값:
    # - 없음.
    def __init__(self, redis_client: redis.Redis | None = None) -> None:
        self.redis_client = redis_client or redis.from_url(
            settings.REDIS_URL,
            decode_responses=True,
        )
        self._is_available = True

    # Function Name: get
    # Description:
    # - Attempts to load MedicationDetail values from Redis.
    # - Cache failures are treated as misses to preserve service availability.
    # Parameters:
    # - drug_name (str): Search keyword used as cache key suffix.
    # Returns:
    # - Cached MedicationDetail list, or None when missing/unavailable.
    async def get(self, drug_name: str) -> list[MedicationDetail] | None:
        if not self._is_available:
            return None

        try:
            cached_data = await self.redis_client.get(self._cache_key(drug_name))
            if not cached_data:
                return None

            logger.info("[Redis] medication detail cache hit.")
            cached_items = json.loads(cached_data)
            if not isinstance(cached_items, list):
                return None

            return [
                MedicationDetail(
                    **{
                        **item,
                        "source": f"[Cache] {item.get('source', '')}",
                    }
                )
                for item in cached_items
                if isinstance(item, dict)
            ]
        except Exception as exc:
            self._disable_cache("lookup", exc)
            return None

    # Function Name: set
    # Description:
    # - Stores MedicationDetail values in Redis.
    # - Cache failures are logged but do not fail the use case.
    # Parameters:
    # - drug_name (str): Search keyword used as cache key suffix.
    # - medication_details (list[MedicationDetail]): MedicationDetail list to cache.
    # Returns:
    # - None.
    async def set(
        self,
        drug_name: str,
        medication_details: list[MedicationDetail],
    ) -> None:
        if not self._is_available or not medication_details:
            return

        try:
            payload = [
                detail.getMedicationDetail()
                for detail in medication_details
            ]
            await self.redis_client.setex(
                self._cache_key(drug_name),
                self.CACHE_TTL_SECONDS,
                json.dumps(payload, ensure_ascii=False),
            )
            logger.info("[Redis] medication detail cached.")
        except Exception as exc:
            self._disable_cache("save", exc)

    # Function Name: close
    # Description:
    # - Closes the Redis client and its reusable connections.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def close(self) -> None:
        await self.redis_client.aclose()

    # Function Name: _cache_key
    # Description:
    # - Places a medication query in the drug_info Redis namespace.
    # Parameters:
    # - drug_name (str): Medication name to search or serialize.
    # Returns:
    # - Redis key for the supplied drug name.
    def _cache_key(self, drug_name: str) -> str:
        return f"drug_info:{drug_name}"

    # Function Name: _disable_cache
    # Description:
    # - Disables Redis use for this process after an operation failure and logs only the exception type.
    # Parameters:
    # - operation (str): Cache operation name included in the failure log.
    # - exc (Exception): Caught failure whose type is logged without its payload.
    # Returns:
    # - None.
    def _disable_cache(self, operation: str, exc: Exception) -> None:
        self._is_available = False
        logger.warning(
            "Redis %s failed; disabling medication cache for this process: %s",
            operation,
            type(exc).__name__,
        )
