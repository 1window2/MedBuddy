# 파일명: test_rate_limit_redis_configuration.py
# 역할: 요청 제한 Redis의 캐시 분리, 운영 설정 검증과 장애 시 차단 동작을 검증한다.

"""캐시 퇴거가 호출 제한 카운터를 없애지 않도록 설정과 장애 처리를 검증한다."""

from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest
import yaml
from redis.exceptions import ConnectionError, OutOfMemoryError, ResponseError

import main
from core.config import Settings
from core.request_rate_limits import RateLimitRule, RequestRateLimitMiddleware, RequestRateLimitStore
from test_authentication_authorization import _production_api_settings


# 함수이름: test_local_configuration_keeps_legacy_url_fallback
# 함수역할:
# - 개발 환경은 별도 카운터 URL이 없으면 기존 캐시 URL을 쓰고 명시된 주소는 우선하는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_local_configuration_keeps_legacy_url_fallback() -> None:
    settings = Settings(_env_file=None, APP_ENV="development", RATE_LIMIT_REDIS_URL="", REDIS_URL="redis://local-cache:6379/0")
    assert settings.rate_limit_redis_url == settings.REDIS_URL
    configured = settings.model_copy(update={"RATE_LIMIT_REDIS_URL": "redis://local-counter:6380/0"})
    assert configured.rate_limit_redis_url == "redis://local-counter:6380/0"


# 함수이름: test_production_rejects_missing_or_same_server_counter_url
# 함수역할:
# - 운영 환경은 카운터 URL 누락 또는 캐시와 같은 서버를 사용하는 구성을 거부하는지 확인한다.
# 매개변수:
# - url: str; 검사할 요청 제한 Redis URL.
# 반환값:
# - None.
@pytest.mark.parametrize("url", ["", "redis://cache:6379/1", "rediss://user:secret@cache:6379/5"])
def test_production_rejects_missing_or_same_server_counter_url(url: str) -> None:
    with pytest.raises(ValueError, match="RATE_LIMIT_REDIS_URL"):
        _production_api_settings(REDIS_URL="redis://cache:6379/0", RATE_LIMIT_REDIS_URL=url)


# 함수이름: test_counter_url_rejects_invalid_or_overriding_parameters
# 함수역할:
# - 카운터 URL의 잘못된 스킴·호스트·포트와 연결 대상을 덮어쓰는 쿼리를 거부하는지 확인한다.
# 매개변수:
# - url: str; 검사할 요청 제한 Redis URL.
# 반환값:
# - None.
@pytest.mark.parametrize("url", ["https://redis.test", "redis://", "redis://cache:bad", "redis://cache/0?host=other", "redis://cache/#x"])
def test_counter_url_rejects_invalid_or_overriding_parameters(url: str) -> None:
    with pytest.raises(ValueError, match="RATE_LIMIT_REDIS_URL"):
        Settings(_env_file=None, RATE_LIMIT_REDIS_URL=url)


# 함수이름: test_production_accepts_separate_server_and_explicit_port
# 함수역할:
# - 운영 환경은 같은 호스트라도 별도 명시 포트의 카운터 서버를 허용하는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_production_accepts_separate_server_and_explicit_port() -> None:
    assert _production_api_settings(REDIS_URL="redis://cache:6379/0", RATE_LIMIT_REDIS_URL="redis://cache:6380/0").rate_limit_redis_url == "redis://cache:6380/0"


# 함수이름: test_app_uses_counter_url_not_cache_url
# 함수역할:
# - 앱의 요청 제한 저장소가 캐시 주소 대신 별도 카운터 URL을 사용하는지 확인한다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
def test_app_uses_counter_url_not_cache_url(monkeypatch) -> None:
    monkeypatch.setattr(main.settings, "REDIS_URL", "redis://cache:6379/0")
    monkeypatch.setattr(main.settings, "RATE_LIMIT_REDIS_URL", "redis://counters:6379/0")
    application = main.create_app()
    assert application.state.request_rate_limit_store._redis_url == "redis://counters:6379/0"


# 함수이름: test_readiness_verifies_counter_policy_and_always_closes
# 함수역할:
# - 준비 상태 검사가 noeviction 정책만 허용하고 성공·실패 모두 Redis 연결을 닫는지 확인한다.
# 매개변수:
# - policy: str; Redis maxmemory-policy 응답.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
@pytest.mark.parametrize("policy", ["noeviction", "allkeys-lru", "volatile-lru", ""])
async def test_readiness_verifies_counter_policy_and_always_closes(policy: str, monkeypatch) -> None:
    monkeypatch.setattr(main.settings, "RATE_LIMIT_REDIS_URL", "redis://counters:6379/0")
    redis = SimpleNamespace(ping=AsyncMock(return_value=True), config_get=AsyncMock(return_value={"maxmemory-policy": policy}), aclose=AsyncMock())
    with patch("main.Redis.from_url", return_value=redis) as factory:
        if policy == "noeviction":
            await main._ping_required_redis()
        else:
            with pytest.raises(RuntimeError, match="noeviction"):
                await main._ping_required_redis()
    assert factory.call_args.args[0] == "redis://counters:6379/0"
    redis.config_get.assert_awaited_once_with("maxmemory-policy")
    redis.aclose.assert_awaited_once()


# 함수이름: test_readiness_rejects_unverifiable_policy
# 함수역할:
# - 정책 조회 권한이 없으면 준비 검사를 실패시키되 Redis 연결은 닫는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_readiness_rejects_unverifiable_policy() -> None:
    redis = SimpleNamespace(ping=AsyncMock(return_value=True), config_get=AsyncMock(side_effect=ResponseError("NOPERM")), aclose=AsyncMock())
    with patch("main.Redis.from_url", return_value=redis):
        with pytest.raises(ResponseError):
            await main._ping_required_redis()
    redis.aclose.assert_awaited_once()


# 함수이름: test_required_counter_oom_and_outage_return_503_without_fallback
# 함수역할:
# - 필수 Redis 메모리 부족·장애는 로컬 카운터로 우회하지 않고 연속 요청을 503으로 차단하는지 확인한다.
# 매개변수:
# - error: Exception; 필수 카운터의 메모리 부족 또는 연결 실패.
# 반환값:
# - None.
@pytest.mark.anyio
@pytest.mark.parametrize("error", [OutOfMemoryError("OOM"), ConnectionError("unavailable")])
async def test_required_counter_oom_and_outage_return_503_without_fallback(error: Exception) -> None:
    redis = SimpleNamespace(eval=AsyncMock(side_effect=error), aclose=AsyncMock())
    store = RequestRateLimitStore(redis_url="redis://counters", require_redis=True, redis_client=redis)
    downstream = AsyncMock()
    middleware = RequestRateLimitMiddleware(downstream, store=store, rules={("POST", "/limited"): RateLimitRule(max_requests=1, window_seconds=60)})
    responses = []

    # 함수이름: send
    # 함수역할:
    # - 미들웨어의 ASGI 응답 이벤트를 수집해 반복 요청의 상태를 검사한다.
    # 매개변수:
    # - message: dict; 미들웨어가 보낸 ASGI 응답 이벤트.
    # 반환값:
    # - None.
    async def send(message):
        responses.append(message)

    for _ in range(2):
        await middleware({"type": "http", "method": "POST", "path": "/limited", "client": ("127.0.0.1", 1), "headers": []}, AsyncMock(), send)
    assert [message["status"] for message in responses if message["type"] == "http.response.start"] == [503, 503]
    assert store._memory_counters == {}
    downstream.assert_not_awaited()
    redis.eval.assert_awaited_once()
    await store.close()


# 함수이름: test_compose_separates_cache_and_persistent_noeviction_counters
# 함수역할:
# - 배포 구성의 캐시와 영속 noeviction 카운터가 저장 공간·주소를 분리하고 카운터 준비 상태를 기다리는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_compose_separates_cache_and_persistent_noeviction_counters() -> None:
    source = Path(__file__).resolve().parents[2] / "compose.self-hosted.yml"
    configuration = yaml.safe_load(source.read_text(encoding="utf-8"))
    services = configuration["services"]
    cache, counters = services["redis"], services["rate-limit-redis"]
    assert "allkeys-lru" in cache["command"]
    assert "noeviction" in counters["command"]
    assert counters["command"][counters["command"].index("--appendonly") + 1] == "yes"
    assert counters["volumes"] != cache["volumes"]
    assert "ports" not in counters
    assert "rate_limit_redis_data" in configuration["volumes"]
    assert services["backend"]["environment"]["RATE_LIMIT_REDIS_URL"] == "redis://rate-limit-redis:6379/0"
    assert services["backend"]["depends_on"]["rate-limit-redis"]["condition"] == "service_healthy"
