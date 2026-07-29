# 파일명: request_rate_limits.py
# 역할: 비용이 크거나 반복 대입 위험이 있는 API의 호출 횟수를 제한한다.

import hashlib
import logging
import time
from collections.abc import Mapping
from dataclasses import dataclass

from redis.asyncio import Redis
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class RateLimitRule:
    max_requests: int
    window_seconds: int


# 클래스명: RequestRateLimitMiddleware
# 역할: 경로별 고정 시간창 제한을 사용자 토큰과 IP에 각각 적용한다.
# 주요 책임:
# - Redis가 연결된 환경에서는 여러 서버 인스턴스가 같은 카운터를 공유한다.
# - 로컬 개발에서 Redis를 사용할 수 없으면 프로세스 메모리 카운터로 대체한다.
# - 인증 토큰 원문은 저장하지 않고 SHA-256 지문만 제한 키에 사용한다.
class RequestRateLimitMiddleware:
    _instances: set["RequestRateLimitMiddleware"] = set()

    def __init__(
        self,
        app: ASGIApp,
        *,
        redis_url: str,
        rules: Mapping[tuple[str, str], RateLimitRule],
        enabled: bool = True,
    ) -> None:
        self.app = app
        self.enabled = enabled
        self.rules = dict(rules)
        self._redis = Redis.from_url(
            redis_url,
            encoding="utf-8",
            decode_responses=True,
            socket_connect_timeout=0.3,
            socket_timeout=0.3,
        )
        self._redis_available = True
        self._redis_retry_at = 0.0
        self._redis_warning_logged = False
        self._memory_counters: dict[str, tuple[int, float]] = {}
        self._instances.add(self)

    async def __call__(
        self,
        scope: Scope,
        receive: Receive,
        send: Send,
    ) -> None:
        if not self.enabled or scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        rule = self.rules.get(
            (
                str(scope.get("method", "")).upper(),
                str(scope.get("path", "")),
            )
        )
        if rule is None:
            await self.app(scope, receive, send)
            return

        retry_after = 0
        for identity in self._request_identities(scope):
            allowed, identity_retry_after = await self._consume(identity, rule)
            retry_after = max(retry_after, identity_retry_after)
            if not allowed:
                response = JSONResponse(
                    status_code=429,
                    content={
                        "detail": (
                            "요청이 너무 많습니다. 잠시 후 다시 시도해주세요."
                        )
                    },
                    headers={"Retry-After": str(max(1, retry_after))},
                )
                await response(scope, receive, send)
                return

        await self.app(scope, receive, send)

    async def close(self) -> None:
        await self._redis.aclose()
        self._instances.discard(self)

    @classmethod
    async def close_all(cls) -> None:
        for instance in tuple(cls._instances):
            await instance.close()

    async def _consume(
        self,
        identity: str,
        rule: RateLimitRule,
    ) -> tuple[bool, int]:
        window_number = int(time.time()) // rule.window_seconds
        key = f"medbuddy:rate:{identity}:{window_number}"
        if not self._redis_available and time.monotonic() >= self._redis_retry_at:
            self._redis_available = True
        if self._redis_available:
            try:
                count = await self._redis.incr(key)
                if count == 1:
                    await self._redis.expire(key, rule.window_seconds + 1)
                retry_after = rule.window_seconds - (
                    int(time.time()) % rule.window_seconds
                )
                return count <= rule.max_requests, retry_after
            except Exception as exc:
                self._redis_available = False
                self._redis_retry_at = time.monotonic() + 30.0
                if not self._redis_warning_logged:
                    logger.warning(
                        "Redis rate limiter unavailable; using process memory: %s",
                        type(exc).__name__,
                    )
                    self._redis_warning_logged = True
        return self._consume_memory(key, rule)

    def _consume_memory(
        self,
        key: str,
        rule: RateLimitRule,
    ) -> tuple[bool, int]:
        now = time.monotonic()
        count, expires_at = self._memory_counters.get(
            key,
            (0, now + rule.window_seconds),
        )
        if expires_at <= now:
            count = 0
            expires_at = now + rule.window_seconds
        count += 1
        self._memory_counters[key] = (count, expires_at)
        if len(self._memory_counters) > 10_000:
            self._memory_counters = {
                existing_key: value
                for existing_key, value in self._memory_counters.items()
                if value[1] > now
            }
        retry_after = max(1, int(expires_at - now))
        return count <= rule.max_requests, retry_after

    @staticmethod
    def _request_identities(scope: Scope) -> tuple[str, ...]:
        client = scope.get("client")
        client_host = str(client[0]) if client else "unknown"
        identities = [f"ip:{client_host}"]
        for name, value in scope.get("headers", ()):
            if name.lower() != b"authorization":
                continue
            token_hash = hashlib.sha256(value).hexdigest()
            identities.append(f"user:{token_hash}")
            break
        return tuple(identities)


DEFAULT_RATE_LIMIT_RULES: dict[tuple[str, str], RateLimitRule] = {
    ("POST", "/api/v1/medication/upload-prescription"): RateLimitRule(6, 60),
    ("POST", "/api/v1/medication/analyze-prescription-text"): RateLimitRule(
        12,
        60,
    ),
    ("POST", "/api/v1/medication/pill-identification/candidates"): RateLimitRule(
        6,
        60,
    ),
    ("POST", "/api/v1/medication/identify"): RateLimitRule(30, 60),
    ("GET", "/api/v1/medication/health/recommendation"): RateLimitRule(12, 60),
    ("POST", "/api/v1/medication/link/code"): RateLimitRule(10, 3_600),
    ("POST", "/api/v1/medication/link/register"): RateLimitRule(5, 300),
}
