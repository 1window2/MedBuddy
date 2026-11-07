# 파일명: test_backend_environment_regressions.py
# 역할: 테스트 네트워크 격리, 앱 수명주기 정리, 토큰 소유권 이전 경합을 검증한다.

from pathlib import Path
from sqlite3 import Cursor
from types import SimpleNamespace
from typing import Any
from unittest.mock import AsyncMock, Mock

import pytest
import httpx
import requests
from redis.asyncio import Redis
from redis.asyncio.connection import Connection
from redis.exceptions import ConnectionError as RedisConnectionError
from sqlalchemy import event
from sqlalchemy.engine import Connection as SQLAlchemyConnection, ExecutionContext

import main
from controls.manage_push_token_control import ManagePushToken
from core.config import settings
from entities.device_push_token_entity import _DevicePushToken
from support.db import make_engine, make_session_factory, seed_account


# 함수이름: test_default_test_redis_cannot_open_a_network_connection
# 함수역할:
# - Redis ping이 격리 오류를 내고 실제 소켓 연결 함수는 호출하지 않는지 확인한다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_default_test_redis_cannot_open_a_network_connection(monkeypatch: pytest.MonkeyPatch) -> None:
    connect = AsyncMock(side_effect=AssertionError("Unexpected network connection"))
    monkeypatch.setattr(Connection, "_connect", connect)
    client = Redis.from_url("redis://127.0.0.1:6379/0")
    try:
        with pytest.raises(RedisConnectionError, match="disabled in backend tests"):
            await client.ping()
    finally:
        await client.aclose()
    connect.assert_not_awaited()


# 함수이름: test_test_settings_never_inherit_the_developer_redis_url
# 함수역할:
# - 캐시와 요청 제한 Redis 주소 모두 개발자 주소 대신 테스트용 닫힌 포트로 고정되는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_test_settings_never_inherit_the_developer_redis_url() -> None:
    assert settings.REDIS_URL == "redis://127.0.0.1:1/0"
    assert settings.RATE_LIMIT_REDIS_URL == "redis://127.0.0.1:1/0"


# 함수이름: test_default_http_clients_cannot_open_network_connections
# 함수역할:
# - httpx·requests·urllib의 기본 전송이 외부 네트워크 접근 전에 AssertionError로 차단되는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_default_http_clients_cannot_open_network_connections() -> None:
    from urllib.request import urlopen

    with pytest.raises(AssertionError, match="disabled in backend tests"):
        with httpx.Client() as client:
            client.get("https://medbuddy-tests.invalid")
    with pytest.raises(AssertionError, match="disabled in backend tests"):
        requests.get("https://medbuddy-tests.invalid", timeout=1)
    with pytest.raises(AssertionError, match="disabled in backend tests"):
        urlopen("https://medbuddy-tests.invalid", timeout=1)


# 함수이름: test_async_http_client_blocks_network_but_preserves_fake_transport
# 함수역할:
# - 비동기 실제 HTTP는 차단하면서 MockTransport 응답은 정상 반환하는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_async_http_client_blocks_network_but_preserves_fake_transport() -> None:
    async with httpx.AsyncClient() as client:
        with pytest.raises(AssertionError, match="disabled in backend tests"):
            await client.get("https://medbuddy-tests.invalid")
    transport = httpx.MockTransport(lambda request: httpx.Response(200, json={"fake": True}))
    async with httpx.AsyncClient(transport=transport) as client:
        assert (await client.get("https://medbuddy-tests.invalid")).json() == {"fake": True}


# 함수이름: lifespan_resources
# 함수역할:
# - 수명주기 작업자와 종료 함수를 기록용 객체로 교체하고 유지보수 실행을 활성화한다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - tuple; 대체 앱, 작업자 매핑, 종료 함수 매핑.
@pytest.fixture
def lifespan_resources(monkeypatch: pytest.MonkeyPatch) -> tuple[SimpleNamespace, dict[str, SimpleNamespace], dict[str, AsyncMock]]:
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


# 함수이름: test_lifespan_closes_remaining_resources_after_shutdown_failure
# 함수역할:
# - 종료 작업 하나가 실패해도 모든 작업자·Redis·경계를 한 번씩 정리한 뒤 오류를 전파하는지 확인한다.
# 매개변수:
# - lifespan_resources: tuple; 대체 앱·작업자·종료 함수.
# - failure: str; 종료 오류를 주입할 자원 이름.
# 반환값:
# - None.
@pytest.mark.anyio
@pytest.mark.parametrize("failure", [
    "ChatNotificationWorker", "CaregiverAlertOutboxWorker",
    "PeriodicDataMaintenanceRunner", "redis", "close_pharmacy_boundary",
])
async def test_lifespan_closes_remaining_resources_after_shutdown_failure(
    lifespan_resources: tuple[SimpleNamespace, dict[str, SimpleNamespace], dict[str, AsyncMock]], failure: str,
) -> None:
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


# 함수이름: test_lifespan_cleans_started_workers_when_later_startup_fails
# 함수역할:
# - 후속 작업자 생성 실패 시 이미 시작된 작업자와 공유 자원을 정리하고 시작 오류를 전파하는지 확인한다.
# 매개변수:
# - lifespan_resources: tuple; 대체 앱·작업자·종료 함수.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# - failure: str; 생성 실패를 주입할 작업자 이름.
# 반환값:
# - None.
@pytest.mark.anyio
@pytest.mark.parametrize("failure", [
    "ChatNotificationWorker", "PeriodicDataMaintenanceRunner",
])
async def test_lifespan_cleans_started_workers_when_later_startup_fails(
    lifespan_resources: tuple[SimpleNamespace, dict[str, SimpleNamespace], dict[str, AsyncMock]], monkeypatch: pytest.MonkeyPatch, failure: str,
) -> None:
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


# 함수이름: test_lifespan_cleans_partially_started_worker
# 함수역할:
# - 작업자의 start가 중간에 실패해도 시작을 시도한 작업자만 정리하고 공유 자원을 닫는지 확인한다.
# 매개변수:
# - lifespan_resources: tuple; 대체 앱·작업자·종료 함수.
# - failure: str; start 실패를 주입할 작업자 이름.
# 반환값:
# - None.
@pytest.mark.anyio
@pytest.mark.parametrize("failure", [
    "CaregiverAlertOutboxWorker", "ChatNotificationWorker", "PeriodicDataMaintenanceRunner",
])
async def test_lifespan_cleans_partially_started_worker(
    lifespan_resources: tuple[SimpleNamespace, dict[str, SimpleNamespace], dict[str, AsyncMock]], failure: str,
) -> None:
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


# 함수이름: test_old_account_logout_cannot_disable_a_concurrently_transferred_token
# 함수역할:
# - 해제 UPDATE 직전에 다른 계정으로 이전된 토큰은 이전 소유자의 로그아웃으로 비활성화되지 않는지 확인한다.
# 매개변수:
# - tmp_path: Path; 테스트 전용 임시 디렉터리.
# 반환값:
# - None.
def test_old_account_logout_cannot_disable_a_concurrently_transferred_token(tmp_path: Path) -> None:
    engine = make_engine(tmp_path)
    sessions = make_session_factory(engine)
    transferred = False
    try:
        with sessions() as db:
            seed_account(db, "old-owner", "new-owner")
            ManagePushToken(db).registerPushToken("old-owner", "device-token", "android")

        # 해제의 실제 UPDATE 직전에 다른 세션에서 계정 전환을 완료한다.
        # 함수이름: transfer_before_revoke
        # 함수역할:
        # - 최초 토큰 해제 UPDATE 직전에 다른 세션에서 새 소유자 등록을 완료하여 계정 전환 경합을 만든다.
        # 매개변수:
        # - connection: Connection; SQL 실행 연결(사용하지 않음).
        # - cursor: Cursor; DBAPI 커서(사용하지 않음).
        # - statement: str; 토큰 UPDATE 여부를 검사할 SQL.
        # - parameters: object; SQL 매개변수(사용하지 않음).
        # - context: ExecutionContext; 실행 문맥(사용하지 않음).
        # - many: bool; 다중 실행 여부(사용하지 않음).
        # 반환값:
        # - None.
        @event.listens_for(engine, "before_cursor_execute")
        def transfer_before_revoke(
            connection: SQLAlchemyConnection, cursor: Cursor, statement: str,
            parameters: tuple[Any, ...] | list[tuple[Any, ...]], context: ExecutionContext, many: bool,
        ) -> None:
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
