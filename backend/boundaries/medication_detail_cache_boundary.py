# File Name: medication_detail_cache_boundary.py
# Role: Owns optional Redis medication-detail snapshots and their availability lifecycle.

import json
import logging
import time
from collections.abc import Callable

import redis.asyncio as redis

from boundaries.medication_summary_boundary import FAILED_SUMMARY_TEXT
from core.config import settings
from entities.medication_detail_entity import MedicationDetail

logger = logging.getLogger(__name__)


# Class Name: MedicationDetailCache
# Role:
# - Shared Redis cache boundary for medication detail lookup.
# Responsibilities:
# - Read cached MedicationDetail lists.
# - Save MedicationDetail lists without failing the main use case on Redis errors.
# - Skip Redis for a cool-down after a failed command, then try it again by itself.
# Attributes:
# - redis_client (redis.Redis): Async Redis client used as optional cache storage.
# - _clock (Callable[[], float]): Monotonic clock that times the cool-down.
# - _disabled_until (float): Clock value before which Redis is skipped; 0.0 until the first failure.
class MedicationDetailCache:
    CACHE_TTL_SECONDS = 604800
    # After a failed command Redis is skipped for this long and then tried again.
    RETRY_COOLDOWN_SECONDS = 60.0
    SOCKET_TIMEOUT_SECONDS = 0.3

    # 함수이름: __init__
    # 함수역할:
    # - Redis 약품 상세 캐시 연결을 준비하고 사용 가능 상태로 시작한다.
    # - 직접 만드는 연결에는 접속·응답 제한 시간을 두어 Redis 장애가 요청을 붙잡지 않게 한다.
    # 매개변수:
    # - redis_client (redis.Redis | None): 직렬화된 약품 상세를 저장·조회할 Redis 연결.
    # - clock (Callable[[], float]): 장애 후 재시도 대기 시간을 재는 단조 시계.
    # 반환값:
    # - 없음.
    def __init__(
        self,
        redis_client: redis.Redis | None = None,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.redis_client = redis_client or redis.from_url(
            settings.REDIS_URL,
            decode_responses=True,
            socket_connect_timeout=self.SOCKET_TIMEOUT_SECONDS,
            socket_timeout=self.SOCKET_TIMEOUT_SECONDS,
        )
        self._clock = clock
        self._disabled_until = 0.0

    # Function Name: get
    # Description:
    # - Attempts to load MedicationDetail values from Redis.
    # - Cache failures are treated as misses to preserve service availability.
    # - A failed Redis command starts the cool-down; an entry that cannot be decoded, or that
    #   holds a failed summary, is a miss for that key only and is replaced by the next save.
    # Parameters:
    # - drug_name (str): Search keyword used as cache key suffix.
    # Returns:
    # - Cached MedicationDetail list, or None when missing/unavailable.
    async def get(self, drug_name: str) -> list[MedicationDetail] | None:
        if self._is_cooling_down():
            return None

        try:
            cached_data = await self.redis_client.get(self._cache_key(drug_name))
        except Exception as exc:
            self._start_cooldown("lookup", exc)
            return None
        if not cached_data:
            return None

        try:
            cached_items = json.loads(cached_data)
            if not isinstance(cached_items, list):
                return None

            medication_details = [
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
            logger.warning(
                "Redis medication detail entry is unreadable; treating it as a miss: %s",
                type(exc).__name__,
            )
            return None
        if any(self._holds_failed_summary(detail) for detail in medication_details):
            return None

        logger.info("[Redis] medication detail cache hit.")
        return medication_details

    # Function Name: set
    # Description:
    # - Stores MedicationDetail values in Redis.
    # - Cache failures are logged but do not fail the use case; a failed Redis command starts the cool-down.
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
        if not medication_details or self._is_cooling_down():
            return

        try:
            payload = json.dumps(
                [
                    detail.getMedicationDetail()
                    for detail in medication_details
                ],
                ensure_ascii=False,
            )
        except Exception as exc:
            logger.warning(
                "Medication detail could not be serialized for Redis: %s",
                type(exc).__name__,
            )
            return

        try:
            await self.redis_client.setex(
                self._cache_key(drug_name),
                self.CACHE_TTL_SECONDS,
                payload,
            )
        except Exception as exc:
            self._start_cooldown("save", exc)
            return
        logger.info("[Redis] medication detail cached.")

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

    # Function Name: _is_cooling_down
    # Description:
    # - Tells whether a recent Redis failure still keeps the cache switched off.
    # Parameters:
    # - None.
    # Returns:
    # - True until the cool-down started by the last failed command has passed.
    def _is_cooling_down(self) -> bool:
        return self._clock() < self._disabled_until

    # Function Name: _start_cooldown
    # Description:
    # - Skips Redis for RETRY_COOLDOWN_SECONDS after a failed command and logs only the exception type.
    # - The first call after the cool-down reaches Redis again, so the cache recovers without a restart.
    # Parameters:
    # - operation (str): Cache operation name included in the failure log.
    # - exc (Exception): Caught failure whose type is logged without its payload.
    # Returns:
    # - None.
    def _start_cooldown(self, operation: str, exc: Exception) -> None:
        self._disabled_until = self._clock() + self.RETRY_COOLDOWN_SECONDS
        logger.warning(
            "Redis %s failed; skipping medication cache for %.0f seconds: %s",
            operation,
            self.RETRY_COOLDOWN_SECONDS,
            type(exc).__name__,
        )

    # Function Name: _holds_failed_summary
    # Description:
    # - Recognizes a snapshot stored before failed AI summaries were rejected.
    # Parameters:
    # - medication_detail (MedicationDetail): Detail decoded from a cached entry.
    # Returns:
    # - True when a guidance field holds the failed-summary text instead of a summary.
    @staticmethod
    def _holds_failed_summary(medication_detail: MedicationDetail) -> bool:
        return FAILED_SUMMARY_TEXT in (
            medication_detail.efficacy,
            medication_detail.usage_method,
            medication_detail.warning,
        )
