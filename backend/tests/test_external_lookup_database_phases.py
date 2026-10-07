# 파일명: test_external_lookup_database_phases.py
# 역할: 연결 반환과 AI 대기 중 계정·권한·복약 변경에 대한 회귀 테스트.

import asyncio
from collections.abc import Iterator
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
import anyio.to_thread
from fastapi import HTTPException
from sqlalchemy import Engine, create_engine, text
from sqlalchemy.orm import Session, sessionmaker
from starlette.requests import Request

from api import dependencies
from api.router import get_health_recommendation
from controls.authorization_control import AuthorizationControl
from controls.check_health_recommendation_control import CheckHealthRecommendation
from controls.manage_account_control import ManageAccount
from core.account_database_lock import lock_account_operations
from core.application_clock import application_today
from core.database import Base
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.health_recommendation_cache_entity import _HealthRecommendationCache
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import _UserAccount
from services.local_medication_catalog import LocalMedicationCatalog


Database = tuple[Engine, sessionmaker[Session]]


# 함수이름: principal
# 함수역할: 외부 인증 없이 시험 주체를 생성한다.
# 매개변수: owner: 시험 계정. 반환값: 인증 주체.
def principal(owner: str = "caregiver") -> AuthenticatedPrincipal:
    return AuthenticatedPrincipal(subject=owner, issuer="test", user_hash=owner)


# 함수이름: database
# 함수역할: 연결 하나인 임시 DB와 합성 복약·연동 정보를 제공한다.
# 매개변수: tmp_path: pytest 임시 경로. 반환값: engine·세션 factory, 종료 시 연결 회수 확인.
@pytest.fixture
def database(tmp_path: Path) -> Iterator[Database]:
    # 연결이 하나뿐인 환경에서도 AI 대기가 다른 조회를 막지 않아야 한다.
    engine = create_engine(
        f"sqlite:///{(tmp_path / 'phases.db').as_posix()}",
        connect_args={"check_same_thread": False},
        pool_size=1, max_overflow=0, pool_timeout=1,
    )
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine)
    with factory() as db:
        db.add_all([_UserAccount(user_hash="caregiver"), _UserAccount(user_hash="patient")])
        db.add(_PatientCaregiverLink(patient_hash="patient", caregiver_hash="caregiver", linked=True))
        db.add(_SavedMedication(
            patient_hash="patient", item_name="synthetic tablet",
            prescription_date=application_today(), total_days="7",
            dosage_per_time="1", daily_frequency="2",
        ))
        db.commit()
    try:
        yield engine, factory
    finally:
        assert engine.pool.checkedout() == 0
        engine.dispose()


# 클래스명: GatedRecommendation
# 역할 및 주요 책임: 실제 외부 전송 없이 AI 대기 시점을 통제한다.
# 속성: expected/count: 요청 수, ready/release: 대기 진입·해제 신호.
class GatedRecommendation:
    # 함수이름: __init__
    # 함수역할: 대기 신호와 요청 횟수를 초기화한다.
    # 매개변수: expected: 동시 요청 수. 반환값: 없음.
    def __init__(self, expected: int = 1) -> None:
        self.expected = expected
        self.count = 0
        self.ready = asyncio.Event()
        self.release = asyncio.Event()

    # 함수이름: requestHealthRecommendation
    # 함수역할: 지정된 신호까지 기다린 뒤 합성 추천을 반환한다.
    # 매개변수: summaries: 합성 약 목록, language: 언어. 반환값: 시험 추천 payload.
    async def requestHealthRecommendation(self, summaries: list[dict[str, str]], language: str) -> dict[str, object]:
        self.count += 1
        if self.count == self.expected:
            self.ready.set()
        await self.release.wait()
        return {"diet_recommendation": "test", "exercise_recommendation": "test", "caution_items": []}


# 함수이름: request_recommendation
# 함수역할: 실제 route와 권한 control을 요청별 세션으로 실행한다.
# 매개변수: factory: 세션 생성기, gate: 모의 AI. 반환값: route 응답.
async def request_recommendation(factory: sessionmaker[Session], gate: GatedRecommendation) -> dict[str, object]:
    with factory() as db:
        return await get_health_recommendation(
            patient_hash="patient", principal=principal(),
            authorization=AuthorizationControl(db),
            check_health_recommendation=CheckHealthRecommendation(db, llm_service=gate),
        )


# 함수이름: test_pending_ai_releases_connections_and_reuses_cache
# 함수역할: 동시 AI 대기 중 연결 반환과 중복 cache 방지를 검사한다.
# 매개변수: database: 임시 DB. 반환값: 없음, 실패 시 assertion.
def test_pending_ai_releases_connections_and_reuses_cache(database: Database) -> None:
    engine, factory = database

    # 함수이름: scenario
    # 함수역할: worker와 DB 연결을 각각 하나로 제한해 5개 요청을 검증한다.
    # 매개변수: 없음. 반환값: 없음.
    async def scenario() -> None:
        limiter = anyio.to_thread.current_default_thread_limiter()
        old_capacity = limiter.total_tokens
        limiter.total_tokens = 1
        gate = GatedRecommendation(expected=5)
        tasks = [asyncio.create_task(request_recommendation(factory, gate)) for _ in range(5)]
        try:
            await asyncio.wait_for(gate.ready.wait(), 8)
            assert engine.pool.checkedout() == 0
            with engine.connect() as connection:
                assert connection.scalar(text("SELECT 1")) == 1
        finally:
            gate.release.set()
            results = await asyncio.gather(*tasks, return_exceptions=True)
            limiter.total_tokens = old_capacity
        assert all(isinstance(result, dict) and result["success"] for result in results), results
        cached = await request_recommendation(factory, gate)
        assert cached["success"] and gate.count == 5
        with factory() as db:
            assert db.query(_HealthRecommendationCache).count() == 1

    asyncio.run(scenario())


# 함수이름: test_revalidation_rejects_changes_during_ai
# 함수역할: AI 대기 중 삭제·연동 해제·복약 변경 후 응답과 cache를 거부하는지 검사한다.
# 매개변수: database: 임시 DB, change: 변경 종류, status: 기대 상태 코드. 반환값: 없음.
@pytest.mark.parametrize("change,status", [
    ("patient_deleted", 410), ("caller_deleted", 410),
    ("patient_locally_deleted", 410), ("unlinked", 403), ("medication_changed", 409),
])
def test_revalidation_rejects_changes_during_ai(database: Database, change: str, status: int) -> None:
    engine, factory = database

    # 함수이름: scenario
    # 함수역할: AI를 기다리는 동안 데이터 변경 후 권한 재검증을 확인한다.
    # 매개변수: 없음. 반환값: 없음.
    async def scenario() -> None:
        gate = GatedRecommendation()
        task = asyncio.create_task(request_recommendation(factory, gate))
        try:
            await asyncio.wait_for(gate.ready.wait(), 5)
            assert engine.pool.checkedout() == 0
            with factory() as db:
                if change == "patient_locally_deleted":
                    ManageAccount(db).deleteAccountData("patient")
                elif change.endswith("deleted"):
                    owner = "patient" if change == "patient_deleted" else "caregiver"
                    ManageAccount(db)._prepare_firebase_account_deletion(owner)
                elif change == "unlinked":
                    db.query(_PatientCaregiverLink).one().linked = False
                    db.commit()
                else:
                    db.query(_SavedMedication).one().dosage_per_time = "2"
                    db.commit()
        finally:
            gate.release.set()
        with pytest.raises(HTTPException) as rejected:
            await task
        assert rejected.value.status_code == status
        with factory() as db:
            assert db.query(_HealthRecommendationCache).count() == 0
            if change == "patient_locally_deleted":
                assert db.get(_UserAccount, "patient") is None

    asyncio.run(scenario())


# 함수이름: test_cancelled_ai_keeps_no_connection_or_cache
# 함수역할: 취소된 추천이 연결이나 cache를 남기지 않는지 검사한다.
# 매개변수: database: 임시 DB. 반환값: 없음.
def test_cancelled_ai_keeps_no_connection_or_cache(database: Database) -> None:
    engine, factory = database

    # 함수이름: scenario
    # 함수역할: AI 대기 중 취소하고 정리 결과를 검증한다.
    # 매개변수: 없음. 반환값: 없음.
    async def scenario() -> None:
        gate = GatedRecommendation()
        task = asyncio.create_task(request_recommendation(factory, gate))
        await asyncio.wait_for(gate.ready.wait(), 5)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        assert engine.pool.checkedout() == 0
        with factory() as db:
            assert db.query(_HealthRecommendationCache).count() == 0

    asyncio.run(scenario())


# 함수이름: test_only_explicit_external_lookups_release_postgres_registration
# 함수역할: 외부 조회 허용 목록만 등록 단계에서 commit하는지 검사한다.
# 매개변수: method/path: route, detached: 연결 반환 기대 여부. 반환값: 없음.
@pytest.mark.parametrize("method,path,detached", [
    (method, path, True) for method, path in sorted(dependencies._DETACHED_LOOKUP_ROUTES)
] + [
    ("POST", "/api/v1/medication/save", False),
    ("POST", "/api/v1/chat/links/1/messages", False),
    ("DELETE", "/api/v1/auth/account-data", False),
])
def test_only_explicit_external_lookups_release_postgres_registration(method: str, path: str, detached: bool) -> None:
    # PostgreSQL 분기 자체의 호출 계약을 검사한다. 실제 서버 잠금 검증을 대체하지 않는다.
    db = MagicMock()
    db.get_bind.return_value.dialect.name = "postgresql"
    request = Request({"type": "http", "method": method, "path": path, "headers": []})

    # 함수이름: scenario
    # 함수역할: 인증 dependency의 등록·commit 호출 계약을 검사한다.
    # 매개변수: 없음. 반환값: 없음.
    async def scenario() -> None:
        with patch.object(dependencies.settings, "RATE_LIMIT_ENABLED", False), patch.object(
            dependencies, "_register_account_scope",
        ) as register:
            dependency = dependencies.get_registered_principal(request, principal(), db)
            try:
                assert await anext(dependency) == principal()
                register.assert_called_once_with(db, "caregiver")
                assert db.commit.call_count == int(detached)
            finally:
                await dependency.aclose()

    asyncio.run(scenario())


# 함수이름: test_catalog_worker_uses_the_released_connection
# 함수역할: 등록 후 반환한 연결을 독립 카탈로그 worker가 사용하는지 검사한다.
# 매개변수: database: 임시 DB. 반환값: 없음.
def test_catalog_worker_uses_the_released_connection(database: Database) -> None:
    engine, factory = database

    # 함수이름: scenario
    # 함수역할: 등록과 실제 카탈로그 검색을 연결 하나로 순차 실행한다.
    # 매개변수: 없음. 반환값: 없음.
    async def scenario() -> None:
        with factory() as db:
            dependencies._register_detached_lookup_scope(db, "caregiver")
            assert not db.in_transaction()
            catalog = LocalMedicationCatalog(db, summary_generator=object())
            assert await catalog._search_catalog("no-such-test-drug") == ([], [])
            assert engine.pool.checkedout() == 0

    asyncio.run(scenario())


# 함수이름: test_sqlite_external_lookup_does_not_hold_request_lifetime_lock
# 함수역할: SQLite 외부 조회가 같은 계정의 다음 요청을 막지 않는지 검사한다.
# 매개변수: database: 임시 DB. 반환값: 없음.
def test_sqlite_external_lookup_does_not_hold_request_lifetime_lock(database: Database) -> None:
    _, factory = database

    # 함수이름: scenario
    # 함수역할: 같은 계정의 dependency 두 개가 동시에 열릴 수 있는지 검사한다.
    # 매개변수: 없음. 반환값: 없음.
    async def scenario() -> None:
        request = Request({
            "type": "http", "method": "GET",
            "path": "/api/v1/medication/health/recommendation", "headers": [],
        })
        with factory() as first, factory() as second, patch.object(
            dependencies.settings, "RATE_LIMIT_ENABLED", False,
        ):
            scopes = [dependencies.get_registered_principal(request, principal(), db)
                      for db in (first, second)]
            try:
                for scope in scopes:
                    assert await asyncio.wait_for(anext(scope), 1) == principal()
                assert dependencies._sqlite_account_lock_registry.active_scope_count == 0
            finally:
                for scope in scopes:
                    await scope.aclose()

    asyncio.run(scenario())


# 함수이름: test_account_lock_orders_owners_and_rejects_nested_transaction
# 함수역할: PostgreSQL 계정 잠금 순서와 중복 제거·중첩 거부를 검사한다.
# 매개변수: 없음. 반환값: 없음.
def test_account_lock_orders_owners_and_rejects_nested_transaction() -> None:
    db = MagicMock()
    db.in_transaction.return_value = False
    db.get_bind.return_value.dialect.name = "postgresql"
    lock_account_operations(db, ["z", "a", "z"])
    assert [call.args[1] for call in db.execute.call_args_list] == [
        {"timeout": "5s"}, {"user_hash": "a"}, {"user_hash": "z"},
    ]
    db.in_transaction.return_value = True
    with pytest.raises(RuntimeError, match="fresh transaction"):
        lock_account_operations(db, ["a"])
