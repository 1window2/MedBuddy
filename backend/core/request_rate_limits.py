# 파일명: request_rate_limits.py
# 역할: 비용이 크거나 반복 대입 위험이 있는 API의 호출 횟수를 제한한다.

import logging
import re
import time
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Protocol

from redis.asyncio import Redis
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send

logger = logging.getLogger(__name__)

_API_PATH_PREFIX = "/api/v1/"
_PATH_PARAMETER_PATTERN = re.compile(r"^\{[^/{}]+\}$")
_INTEGER_PATH_SEGMENT_PATTERN = re.compile(r"^\d+$")

_ATOMIC_INCREMENT_SCRIPT = """
local count = redis.call('INCR', KEYS[1])
if count == 1 then
  redis.call('EXPIRE', KEYS[1], ARGV[1])
end
return count
"""


@dataclass(frozen=True)
class RateLimitRule:
    max_requests: int
    window_seconds: int


# 함수이름: resolve_rate_limit_rule
# 함수역할:
# - 실제 요청 경로를 고정 경로 또는 매개변수 경로 규칙과 연결한다.
# - 별도 규칙이 없는 인증 API에도 읽기·쓰기 기본 제한을 적용한다.
# 매개변수:
# - method: HTTP 메서드
# - path: 실제 또는 FastAPI 정규 경로
# - rules: 우선 적용할 경로별 제한 규칙
# - include_api_default: /api/v1 경로에 기본 제한을 적용할지 여부
# - collapse_default_scope: 기본 제한 카운터를 메서드별 공통 범위로 묶을지 여부
# 반환값: 적용 규칙과 카운터를 공유할 정규 경로 또는 None
def resolve_rate_limit_rule(
    method: str,
    path: str,
    *,
    rules: Mapping[tuple[str, str], RateLimitRule] | None = None,
    include_api_default: bool = True,
    collapse_default_scope: bool = False,
) -> tuple[RateLimitRule, str] | None:
    """요청에 적용할 가장 구체적인 호출 제한 규칙을 반환한다."""
    normalized_method = method.upper()
    normalized_path = path or "/"
    configured_rules = DEFAULT_RATE_LIMIT_RULES if rules is None else rules

    exact_rule = configured_rules.get((normalized_method, normalized_path))
    if exact_rule is not None:
        return exact_rule, normalized_path

    for (rule_method, rule_path), rule in configured_rules.items():
        if rule_method != normalized_method:
            continue
        if _path_matches_template(normalized_path, rule_path):
            return rule, rule_path

    if not include_api_default or not normalized_path.startswith(_API_PATH_PREFIX):
        return None
    default_rule = DEFAULT_AUTHENTICATED_API_RULES.get(normalized_method)
    if default_rule is None:
        return None
    canonical_path = (
        f"{_API_PATH_PREFIX}*"
        if collapse_default_scope
        else _canonicalize_api_path(normalized_path)
    )
    return default_rule, canonical_path


def _path_matches_template(path: str, template: str) -> bool:
    """중괄호 매개변수 한 칸을 임의의 단일 경로 조각과 비교한다."""
    path_segments = path.strip("/").split("/")
    template_segments = template.strip("/").split("/")
    if len(path_segments) != len(template_segments):
        return False
    return all(
        _PATH_PARAMETER_PATTERN.fullmatch(template_segment) is not None
        or path_segment == template_segment
        for path_segment, template_segment in zip(
            path_segments,
            template_segments,
            strict=True,
        )
    )


def _canonicalize_api_path(path: str) -> str:
    """숫자 식별자를 정규 조각으로 바꿔 카운터 키가 무한히 늘지 않게 한다."""
    segments = path.split("/")
    return "/".join(
        "{id}" if _INTEGER_PATH_SEGMENT_PATTERN.fullmatch(segment) else segment
        for segment in segments
    )


class AsyncRateLimitRedis(Protocol):
    async def eval(
        self,
        script: str,
        number_of_keys: int,
        *keys_and_args: object,
    ) -> object: ...

    async def aclose(self) -> None: ...


class RequestRateLimitStore:
    """Owns atomic Redis counters with a bounded local-development fallback."""

    def __init__(
        self,
        *,
        redis_url: str,
        require_redis: bool = False,
        redis_client: AsyncRateLimitRedis | None = None,
    ) -> None:
        self._redis_url = redis_url
        self._injected_redis = redis_client is not None
        self.require_redis = require_redis
        self._redis: AsyncRateLimitRedis | None = redis_client
        self._redis_available = True
        self._redis_retry_at = 0.0
        self._redis_warning_logged = False
        self._memory_counters: dict[str, tuple[int, float]] = {}

    async def consume(
        self,
        *,
        identity: str,
        request_scope: str,
        rule: RateLimitRule,
    ) -> tuple[bool, int]:
        window_number = int(time.time()) // rule.window_seconds
        key = (
            f"medbuddy:rate:{request_scope}:{identity}:{window_number}"
        )
        if (
            self.require_redis
            and not self._redis_available
            and time.monotonic() < self._redis_retry_at
        ):
            raise RuntimeError("Distributed request-rate storage is unavailable.")
        if not self._redis_available and time.monotonic() >= self._redis_retry_at:
            self._redis_available = True
        if self._redis_available:
            try:
                redis = self._get_redis()
                count = int(
                    await redis.eval(
                        _ATOMIC_INCREMENT_SCRIPT,
                        1,
                        key,
                        rule.window_seconds + 1,
                    )
                )
                retry_after = rule.window_seconds - (
                    int(time.time()) % rule.window_seconds
                )
                return count <= rule.max_requests, retry_after
            except Exception as exc:
                self._redis_available = False
                self._redis_retry_at = time.monotonic() + 30.0
                if not self._redis_warning_logged:
                    logger.warning(
                        "Redis rate limiter unavailable: %s",
                        type(exc).__name__,
                    )
                    self._redis_warning_logged = True
                if self.require_redis:
                    raise RuntimeError(
                        "Distributed request-rate storage is unavailable."
                    ) from exc
        return self._consume_memory(key, rule)

    async def close(self) -> None:
        redis = self._redis
        if redis is None:
            return
        await redis.aclose()
        if not self._injected_redis:
            self._redis = None
            self._redis_available = True
            self._redis_retry_at = 0.0

    def _get_redis(self) -> AsyncRateLimitRedis:
        redis = self._redis
        if redis is not None:
            return redis
        redis = Redis.from_url(
            self._redis_url,
            encoding="utf-8",
            decode_responses=True,
            socket_connect_timeout=0.3,
            socket_timeout=0.3,
        )
        self._redis = redis
        return redis

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


# 클래스명: RequestRateLimitMiddleware
# 역할: 경로별 고정 시간창의 광범위한 요청 IP 제한을 적용한다.
# 주요 책임:
# - Redis가 연결된 환경에서는 여러 서버 인스턴스가 같은 카운터를 공유한다.
# - 로컬 개발에서 Redis를 사용할 수 없으면 프로세스 메모리 카운터로 대체한다.
# - 운영에서 Redis가 필수이면 저장소 장애를 재시도 가능한 503으로 변환한다.
# - 검증된 사용자별 제한은 인증 의존성이 같은 저장소에 별도로 적용한다.
class RequestRateLimitMiddleware:
    _IP_LIMIT_MULTIPLIER = 20

    def __init__(
        self,
        app: ASGIApp,
        *,
        store: RequestRateLimitStore,
        rules: Mapping[tuple[str, str], RateLimitRule],
        enabled: bool = True,
    ) -> None:
        self.app = app
        self.enabled = enabled
        self.rules = dict(rules)
        self.store = store

    async def __call__(
        self,
        scope: Scope,
        receive: Receive,
        send: Send,
    ) -> None:
        if not self.enabled or scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        resolved_rule = resolve_rate_limit_rule(
            str(scope.get("method", "")),
            str(scope.get("path", "")),
            rules=self.rules,
            collapse_default_scope=True,
        )
        if resolved_rule is None:
            await self.app(scope, receive, send)
            return
        rule, canonical_path = resolved_rule

        retry_after = 0
        try:
            identity_rule = RateLimitRule(
                max_requests=rule.max_requests * self._IP_LIMIT_MULTIPLIER,
                window_seconds=rule.window_seconds,
            )
            allowed, retry_after = await self.store.consume(
                identity=self._request_ip_identity(scope),
                request_scope=self._request_scope(
                    scope,
                    canonical_path=canonical_path,
                ),
                rule=identity_rule,
            )
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
        except RuntimeError:
            response = JSONResponse(
                status_code=503,
                content={
                    "detail": "Request quota storage is temporarily unavailable."
                },
                headers={"Retry-After": "5"},
            )
            await response(scope, receive, send)
            return

        await self.app(scope, receive, send)

    @staticmethod
    def _request_ip_identity(scope: Scope) -> str:
        client = scope.get("client")
        client_host = str(client[0]) if client else "unknown"
        return f"ip:{client_host}"

    @staticmethod
    def _request_scope(
        scope: Scope,
        *,
        canonical_path: str | None = None,
    ) -> str:
        return (
            f"{str(scope.get('method', '')).upper()}:"
            f"{canonical_path or str(scope.get('path', ''))}"
        )


DEFAULT_RATE_LIMIT_RULES: dict[tuple[str, str], RateLimitRule] = {
    ("GET", "/ready"): RateLimitRule(6, 60),
    ("POST", "/api/v1/medication/analyze-prescription-text"): RateLimitRule(
        12,
        60,
    ),
    # 프론트 최대 10개 일괄 작업과 제한 응답 재시도 여유를 정상 사용 범위로 허용한다.
    ("POST", "/api/v1/medication/pill-identification/candidates"): RateLimitRule(
        12,
        60,
    ),
    ("POST", "/api/v1/medication/identify"): RateLimitRule(30, 60),
    ("GET", "/api/v1/medication/health/recommendation"): RateLimitRule(12, 60),
    ("GET", "/api/v1/pharmacy/nearby"): RateLimitRule(30, 60),
    ("POST", "/api/v1/medication/link/code"): RateLimitRule(10, 3_600),
    ("POST", "/api/v1/medication/link/register"): RateLimitRule(5, 300),
    ("GET", "/api/v1/chat/links/{link_id}/messages"): RateLimitRule(60, 60),
    ("GET", "/api/v1/chat/links/{link_id}/medications"): RateLimitRule(60, 60),
    ("GET", "/api/v1/chat/links/{link_id}/schedule-contexts"): RateLimitRule(
        60,
        60,
    ),
    (
        "GET",
        "/api/v1/chat/links/{link_id}/medications/{medication_id}",
    ): RateLimitRule(60, 60),
    ("POST", "/api/v1/chat/links/{link_id}/messages"): RateLimitRule(20, 60),
    ("POST", "/api/v1/chat/links/{link_id}/read"): RateLimitRule(60, 60),
    ("GET", "/api/v1/chat/links/{link_id}/unread-count"): RateLimitRule(
        60,
        60,
    ),
}


# 목록에 별도 제한이 없는 인증 API도 무제한으로 남지 않도록 보수적인
# 기본값을 적용한다. 비용이 큰 API는 위의 더 엄격한 규칙이 우선한다.
DEFAULT_AUTHENTICATED_API_RULES: dict[str, RateLimitRule] = {
    "GET": RateLimitRule(180, 60),
    "POST": RateLimitRule(60, 60),
    "PUT": RateLimitRule(60, 60),
    "PATCH": RateLimitRule(60, 60),
    "DELETE": RateLimitRule(30, 60),
}
