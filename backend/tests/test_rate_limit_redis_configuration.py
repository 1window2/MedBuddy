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


def test_local_configuration_keeps_legacy_url_fallback() -> None:
    settings = Settings(_env_file=None, APP_ENV="development", RATE_LIMIT_REDIS_URL="", REDIS_URL="redis://local-cache:6379/0")
    assert settings.rate_limit_redis_url == settings.REDIS_URL
    configured = settings.model_copy(update={"RATE_LIMIT_REDIS_URL": "redis://local-counter:6380/0"})
    assert configured.rate_limit_redis_url == "redis://local-counter:6380/0"


@pytest.mark.parametrize("url", ["", "redis://cache:6379/1", "rediss://user:secret@cache:6379/5"])
def test_production_rejects_missing_or_same_server_counter_url(url: str) -> None:
    with pytest.raises(ValueError, match="RATE_LIMIT_REDIS_URL"):
        _production_api_settings(REDIS_URL="redis://cache:6379/0", RATE_LIMIT_REDIS_URL=url)


@pytest.mark.parametrize("url", ["https://redis.test", "redis://", "redis://cache:bad", "redis://cache/0?host=other", "redis://cache/#x"])
def test_counter_url_rejects_invalid_or_overriding_parameters(url: str) -> None:
    with pytest.raises(ValueError, match="RATE_LIMIT_REDIS_URL"):
        Settings(_env_file=None, RATE_LIMIT_REDIS_URL=url)


def test_production_accepts_separate_server_and_explicit_port() -> None:
    assert _production_api_settings(REDIS_URL="redis://cache:6379/0", RATE_LIMIT_REDIS_URL="redis://cache:6380/0").rate_limit_redis_url == "redis://cache:6380/0"


def test_app_uses_counter_url_not_cache_url(monkeypatch) -> None:
    monkeypatch.setattr(main.settings, "REDIS_URL", "redis://cache:6379/0")
    monkeypatch.setattr(main.settings, "RATE_LIMIT_REDIS_URL", "redis://counters:6379/0")
    application = main.create_app()
    assert application.state.request_rate_limit_store._redis_url == "redis://counters:6379/0"


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


@pytest.mark.anyio
async def test_readiness_rejects_unverifiable_policy() -> None:
    redis = SimpleNamespace(ping=AsyncMock(return_value=True), config_get=AsyncMock(side_effect=ResponseError("NOPERM")), aclose=AsyncMock())
    with patch("main.Redis.from_url", return_value=redis):
        with pytest.raises(ResponseError):
            await main._ping_required_redis()
    redis.aclose.assert_awaited_once()


@pytest.mark.anyio
@pytest.mark.parametrize("error", [OutOfMemoryError("OOM"), ConnectionError("unavailable")])
async def test_required_counter_oom_and_outage_return_503_without_fallback(error: Exception) -> None:
    redis = SimpleNamespace(eval=AsyncMock(side_effect=error), aclose=AsyncMock())
    store = RequestRateLimitStore(redis_url="redis://counters", require_redis=True, redis_client=redis)
    downstream = AsyncMock()
    middleware = RequestRateLimitMiddleware(downstream, store=store, rules={("POST", "/limited"): RateLimitRule(max_requests=1, window_seconds=60)})
    responses = []

    async def send(message):
        responses.append(message)

    for _ in range(2):
        await middleware({"type": "http", "method": "POST", "path": "/limited", "client": ("127.0.0.1", 1), "headers": []}, AsyncMock(), send)
    assert [message["status"] for message in responses if message["type"] == "http.response.start"] == [503, 503]
    assert store._memory_counters == {}
    downstream.assert_not_awaited()
    redis.eval.assert_awaited_once()
    await store.close()


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
