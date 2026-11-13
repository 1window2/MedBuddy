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
from entities.medication_lookup_result import MedicationLookupResult

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

    # Function Name: __init__
    # Description: Uses an injected Redis client or creates one with bounded socket timeouts, and initializes the outage cooldown.
    # Parameters: redis_client (Redis | None) overrides the configured endpoint; clock (Callable) measures cooldown time monotonically.
    # Returns: None; no cache lookup or write is performed.
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

    # 함수이름: get
    # 함수역할: 냉각 중 조회를 생략하고 캐시 JSON을 약 상세로 검증한 뒤 실패 요약이 섞인 항목은 미스로 취급한다.
    # 매개변수: drug_name (str)은 v2 캐시 키에 사용할 약명이다.
    # 반환값: MedicationDetail 목록 또는 미스·잘못된 값·Redis 장애 시 None. Redis 오류는 냉각을 시작하고 내용은 로그에 남기지 않는다.
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
            if not isinstance(cached_items, list) or any(
                not isinstance(item, dict) for item in cached_items
            ):
                return None

            medication_details = [
                MedicationDetail(
                    **{
                        **item,
                        "source": f"[Cache] {item.get('source', '')}",
                    }
                )
                for item in cached_items
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

    # 함수이름: set
    # 함수역할: 완전하고 비어 있지 않은 결과만 직렬화해 만료 시간을 지정해 저장하며 냉각 중에는 건너뛴다.
    # 매개변수: drug_name (str)은 키용 약명, result (MedicationLookupResult)는 후보와 완전성 판정이다.
    # 반환값: None. 직렬화 실패는 기록 후 생략하고 Redis 실패는 냉각을 시작하며 호출자에게 예외를 전파하지 않는다.
    async def set(
        self,
        drug_name: str,
        result: MedicationLookupResult,
    ) -> None:
        if not result.is_complete or not result.details or self._is_cooling_down():
            return

        try:
            payload = json.dumps(
                [
                    detail.getMedicationDetail()
                    for detail in result.details
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

    # 함수이름: _cache_key
    # 함수역할: 이전 캐시 형식과 섞이지 않도록 약명 앞에 v2 네임스페이스를 붙인다.
    # 매개변수: drug_name (str)은 호출자가 정한 조회 이름이다.
    # 반환값: drug_info:v2: 접두사와 원본 약명을 합친 str. 이름 정규화는 수행하지 않는다.
    def _cache_key(self, drug_name: str) -> str:
        return f"drug_info:v2:{drug_name}"

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
