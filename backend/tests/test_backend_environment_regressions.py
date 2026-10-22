from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest
import httpx
import requests
from redis.asyncio import Redis
from redis.asyncio.connection import Connection
from redis.exceptions import ConnectionError as RedisConnectionError
from sqlalchemy import event

import main
from controls.manage_push_token_control import ManagePushToken
from core.config import settings
from entities.device_push_token_entity import _DevicePushToken
from support.db import make_engine, make_session_factory, seed_account


@pytest.mark.anyio
async def test_default_test_redis_cannot_open_a_network_connection(monkeypatch):
    connect = AsyncMock(side_effect=AssertionError("Unexpected network connection"))
    monkeypatch.setattr(Connection, "_connect", connect)
    client = Redis.from_url("redis://127.0.0.1:6379/0")
    try:
        with pytest.raises(RedisConnectionError, match="disabled in backend tests"):
            await client.ping()
    finally:
        await client.aclose()
    connect.assert_not_awaited()


def test_test_settings_never_inherit_the_developer_redis_url():
    assert settings.REDIS_URL == "redis://127.0.0.1:1/0"
    assert settings.RATE_LIMIT_REDIS_URL == "redis://127.0.0.1:1/0"


def test_default_http_clients_cannot_open_network_connections():
    from urllib.request import urlopen

    with pytest.raises(AssertionError, match="disabled in backend tests"):
        with httpx.Client() as client:
            client.get("https://medbuddy-tests.invalid")
    with pytest.raises(AssertionError, match="disabled in backend tests"):
        requests.get("https://medbuddy-tests.invalid", timeout=1)
    with pytest.raises(AssertionError, match="disabled in backend tests"):
        urlopen("https://medbuddy-tests.invalid", timeout=1)


@pytest.mark.anyio
async def test_async_http_client_blocks_network_but_preserves_fake_transport():
    async with httpx.AsyncClient() as client:
        with pytest.raises(AssertionError, match="disabled in backend tests"):
            await client.get("https://medbuddy-tests.invalid")
    transport = httpx.MockTransport(lambda request: httpx.Response(200, json={"fake": True}))
    async with httpx.AsyncClient(transport=transport) as client:
        assert (await client.get("https://medbuddy-tests.invalid")).json() == {"fake": True}


@pytest.fixture
def lifespan_resources(monkeypatch):
    workers = {}
    for name in (
        "CaregiverAlertOutboxWorker", "ChatNotificationWorker",
        "PeriodicDataMaintenanceRunner",
    ):
        worker = SimpleNamespace(start=Mock(), stop=AsyncMock())
        workers[name] = worker
        monkeypatch.setattr(main, name, Mock(return_value=worker))
    closers = {}
    for name in (
        "close_pill_identification_boundaries", "close_gemini_clients",
        "close_medication_detail_cache", "close_public_drug_boundaries",
        "close_pharmacy_boundary", "close_hospital_boundary",
    ):
        closers[name] = AsyncMock()
        monkeypatch.setattr(main, name, closers[name])
    monkeypatch.setattr(settings, "PERIODIC_MAINTENANCE_ENABLED", True)
    app = SimpleNamespace(state=SimpleNamespace(
        request_rate_limit_store=SimpleNamespace(close=AsyncMock(), consume=AsyncMock()),
        chat_connection_manager=SimpleNamespace(is_user_connected=Mock()),
        readiness_probe_cache=SimpleNamespace(reset=Mock()),
        catalog_readiness_probe_cache=SimpleNamespace(reset=Mock()),
    ))
    return app, workers, closers


@pytest.mark.anyio
@pytest.mark.parametrize("failure", [
    "ChatNotificationWorker", "CaregiverAlertOutboxWorker",
    "PeriodicDataMaintenanceRunner", "redis", "close_pharmacy_boundary",
])
async def test_lifespan_closes_remaining_resources_after_shutdown_failure(
    lifespan_resources, failure,
):
    app, workers, closers = lifespan_resources
    failed_close = (
        workers[failure].stop if failure in workers
        else app.state.request_rate_limit_store.close if failure == "redis"
        else closers[failure]
    )
    failed_close.side_effect = RuntimeError("injected cleanup failure")
    with pytest.raises(RuntimeError, match="injected cleanup failure"):
        async with main.application_lifespan(app):
            pass
    for worker in workers.values():
        worker.stop.assert_awaited_once()
    app.state.request_rate_limit_store.close.assert_awaited_once()
    for close in closers.values():
        close.assert_awaited_once()


@pytest.mark.anyio
@pytest.mark.parametrize("failure", [
    "ChatNotificationWorker", "PeriodicDataMaintenanceRunner",
])
async def test_lifespan_cleans_started_workers_when_later_startup_fails(
    lifespan_resources, monkeypatch, failure,
):
    app, workers, closers = lifespan_resources
    monkeypatch.setattr(main, failure, Mock(side_effect=RuntimeError("startup failed")))
    with pytest.raises(RuntimeError, match="startup failed"):
        async with main.application_lifespan(app):
            pytest.fail("Startup should have failed")
    workers["CaregiverAlertOutboxWorker"].stop.assert_awaited_once()
    if failure == "PeriodicDataMaintenanceRunner":
        workers["ChatNotificationWorker"].stop.assert_awaited_once()
    app.state.request_rate_limit_store.close.assert_awaited_once()
    for close in closers.values():
        close.assert_awaited_once()


@pytest.mark.anyio
@pytest.mark.parametrize("failure", [
    "CaregiverAlertOutboxWorker", "ChatNotificationWorker", "PeriodicDataMaintenanceRunner",
])
async def test_lifespan_cleans_partially_started_worker(lifespan_resources, failure):
    app, workers, closers = lifespan_resources
    workers[failure].start.side_effect = RuntimeError("partial startup failed")
    with pytest.raises(RuntimeError, match="partial startup failed"):
        async with main.application_lifespan(app):
            pytest.fail("Startup should have failed")
    for worker in workers.values():
        if worker.start.called:
            worker.stop.assert_awaited_once()
        else:
            worker.stop.assert_not_awaited()
    app.state.request_rate_limit_store.close.assert_awaited_once()
    for close in closers.values():
        close.assert_awaited_once()


def test_old_account_logout_cannot_disable_a_concurrently_transferred_token(tmp_path):
    engine = make_engine(tmp_path)
    sessions = make_session_factory(engine)
    transferred = False
    try:
        with sessions() as db:
            seed_account(db, "old-owner", "new-owner")
            ManagePushToken(db).registerPushToken("old-owner", "device-token", "android")

        # 해제의 실제 UPDATE 직전에 다른 세션에서 계정 전환을 완료한다.
        @event.listens_for(engine, "before_cursor_execute")
        def transfer_before_revoke(connection, cursor, statement, parameters, context, many):
            nonlocal transferred
            if not transferred and statement.startswith("UPDATE device_push_tokens"):
                transferred = True
                with sessions() as other:
                    ManagePushToken(other).registerPushToken(
                        "new-owner", "device-token", "android",
                    )

        with sessions() as db:
            assert ManagePushToken(db).unregisterPushToken(
                "old-owner", "device-token",
            )["success"]
        with sessions() as db:
            token = db.query(_DevicePushToken).one()
            assert transferred
            assert token.user_hash == "new-owner"
            assert token.enabled is True
            control = ManagePushToken(db)
            control.unregisterPushToken("new-owner", "device-token")
            db.expire_all()
            assert db.query(_DevicePushToken).one().enabled is False
            assert control.unregisterPushToken("new-owner", "device-token")["success"]
    finally:
        engine.dispose()
