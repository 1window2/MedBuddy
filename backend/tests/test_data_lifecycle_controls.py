# File Name: test_data_lifecycle_controls.py
# Role: Regression coverage for retention, account-deletion retries, and memory/Redis
#   request-rate enforcement.

from datetime import UTC, datetime, timedelta
from unittest.mock import patch

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from boundaries.firebase_identity_boundary import IdentityDeletionUnavailableError
from controls.manage_account_control import (
    AccountDeletionPendingError,
    ManageAccount,
)
from core.database import Base
from core.request_rate_limits import (
    DEFAULT_RATE_LIMIT_RULES,
    RateLimitRule,
    RequestRateLimitMiddleware,
    RequestRateLimitStore,
    resolve_rate_limit_rule,
)
from entities.health_recommendation_cache_entity import _HealthRecommendationCache
from entities.chat_message_entity import _ChatMessage
from entities.medication_completion_entity import _MedicationCompletion
from entities.patient_caregiver_link_entity import (
    _PatientCaregiverLink,
    _PatientLinkCode,
)
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import _UserAccount
from services.data_maintenance import DataMaintenanceService
from services.chat_message_retention import ChatMessageRetentionPolicy
from services.saved_medication_retention import SavedMedicationRetentionPolicy


# 함수이름: db_session
# 함수역할:
# - 격리된 인메모리 SQLite 세션을 제공하고 테스트 종료 시 세션과 엔진을 닫는다.
# 매개변수:
# - 없음.
# 반환값:
# - 격리 Session을 제공하며 fixture 정리 시 세션과 엔진을 닫음.
@pytest.fixture
def db_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(bind=engine)
    session_factory = sessionmaker(bind=engine, autoflush=False)
    db = session_factory()
    try:
        yield db
    finally:
        db.close()
        engine.dispose()


# Function Name: test_data_maintenance_removes_expired_and_orphaned_rows
# Description:
# - Requires maintenance to remove expired medication, orphaned completions, link codes, and
#   health-recommendation cache rows together.
# Parameters:
# - db_session (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
def test_data_maintenance_removes_expired_and_orphaned_rows(db_session) -> None:
    patient_hash = "patient-maintenance"
    db_session.add(_UserAccount(user_hash=patient_hash))
    medication = _SavedMedication(
        patient_hash=patient_hash,
        created_date=datetime.now().date() - timedelta(days=50),
        prescription_date=datetime.now().date() - timedelta(days=50),
        item_name="만료 테스트약",
        efficacy="",
        use_method="",
        warning_message="",
        dosage_per_time="1정",
        daily_frequency="1회",
        total_days="1일",
        schedule_slot_keys='["morning"]',
    )
    db_session.add(medication)
    db_session.flush()
    db_session.add_all(
        [
            _MedicationCompletion(
                saved_medication_id=medication.id,
                patient_hash=patient_hash,
                schedule_date=datetime.now().date() - timedelta(days=50),
                slot_key="morning",
            ),
            _PatientLinkCode(
                patient_hash=patient_hash,
                patient_code="OLD12345",
                expires_at=datetime.now(UTC).replace(tzinfo=None)
                - timedelta(minutes=1),
            ),
            _HealthRecommendationCache(
                patient_hash=patient_hash,
                recommendation_key="old-cache",
                payload="{}",
                created_at=datetime.now(UTC).replace(tzinfo=None)
                - timedelta(days=100),
            ),
        ]
    )
    db_session.commit()

    deleted = DataMaintenanceService(
        retention_policy=SavedMedicationRetentionPolicy(
            retention_days_after_end=30,
        )
    ).runOnce(db_session)

    assert deleted["saved_medications"] == 1
    assert db_session.query(_SavedMedication).count() == 0
    assert db_session.query(_MedicationCompletion).count() == 0
    assert db_session.query(_PatientLinkCode).count() == 0
    assert db_session.query(_HealthRecommendationCache).count() == 0


# 함수이름: test_manage_account_exports_and_deletes_owned_data
# 함수역할:
# - 계정 내보내기가 요청 사용자 범위를 표시하고 삭제 후 해당 계정과 건강 추천 캐시가 남지 않는지 검증한다.
# 매개변수:
# - db_session (Session): 테스트 fixture가 제공한 격리 SQLAlchemy 세션.
# 반환값:
# - 없음 (None).
def test_manage_account_exports_and_deletes_owned_data(db_session) -> None:
    control = ManageAccount(db_session)
    user_hash = control.ensureAccount("patient-delete", commit=True)
    db_session.add(
        _HealthRecommendationCache(
            patient_hash=user_hash,
            recommendation_key="cache-key",
            payload='{"meal":"test"}',
        )
    )
    db_session.commit()

    exported = control.exportAccountData(user_hash)
    assert exported["data"]["user_hash"] == user_hash

    result = control.deleteAccountData(user_hash)
    assert result["success"] is True
    assert db_session.get(_UserAccount, user_hash) is None
    assert db_session.query(_HealthRecommendationCache).count() == 0


# Class Name: _FailOnceIdentityDeletionBoundary
# Role: Identity-deletion double that fails once and records subjects across the subsequent
#   retry.
# Responsibilities:
# - Records the subject, raises a provider-unavailable error on the first attempt, and allows
#   subsequent retries.
# Attributes:
# - subjects (list[str]): External Firebase subjects recorded across deletion attempts.
class _FailOnceIdentityDeletionBoundary:
    # Function Name: __init__
    # Description:
    # - Starts an empty external-subject history for the fail-once deletion sequence.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.subjects: list[str] = []

    # Function Name: deleteIdentity
    # Description:
    # - Records the subject, raises a provider-unavailable error on the first attempt, and
    #   allows subsequent retries.
    # Parameters:
    # - subject (str): Verified external Firebase user identifier.
    # Returns:
    # - None.
    def deleteIdentity(self, subject: str) -> None:
        self.subjects.append(subject)
        if len(self.subjects) == 1:
            raise IdentityDeletionUnavailableError("provider unavailable")


# Function Name: test_firebase_account_deletion_tombstone_allows_safe_retry
# Description:
# - Persists a deletion tombstone after provider failure, blocks account reuse, and permits a
#   retry that marks the identity deleted without restoring medical data.
# Parameters:
# - db_session (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
def test_firebase_account_deletion_tombstone_allows_safe_retry(db_session) -> None:
    identity_boundary = _FailOnceIdentityDeletionBoundary()
    control = ManageAccount(
        db_session,
        identity_deletion_boundary=identity_boundary,
    )
    user_hash = control.ensureAccount("patient-firebase-delete", commit=True)
    db_session.add(
        _HealthRecommendationCache(
            patient_hash=user_hash,
            recommendation_key="cache-key",
            payload="{}",
        )
    )
    db_session.commit()

    with pytest.raises(IdentityDeletionUnavailableError):
        control.deleteAccountData(user_hash, external_subject="firebase-uid")

    tombstone = db_session.get(_UserAccount, user_hash)
    assert tombstone is not None
    assert tombstone.deletion_requested_at is not None
    assert tombstone.identity_deleted_at is None
    assert db_session.query(_HealthRecommendationCache).count() == 0
    with pytest.raises(AccountDeletionPendingError):
        control.ensureAccount(user_hash)

    result = control.deleteAccountData(
        user_hash,
        external_subject="firebase-uid",
    )

    db_session.refresh(tombstone)
    assert result["identity_deleted"] is True
    assert tombstone.identity_deleted_at is not None
    assert identity_boundary.subjects == ["firebase-uid", "firebase-uid"]


# Function Name: test_zero_day_retention_preserves_ended_medication_history
# Description:
# - Treats zero-day retention as history preservation rather than immediate deletion of ended
#   medication courses.
# Parameters:
# - db_session (Session): Isolated SQLAlchemy session supplied by the test fixture.
# Returns:
# - None.
def test_zero_day_retention_preserves_ended_medication_history(db_session) -> None:
    patient_hash = "patient-history"
    db_session.add(_UserAccount(user_hash=patient_hash))
    medication = _SavedMedication(
        patient_hash=patient_hash,
        created_date=datetime.now().date() - timedelta(days=90),
        prescription_date=datetime.now().date() - timedelta(days=90),
        item_name="종료된 기록약",
        efficacy="",
        use_method="",
        warning_message="",
        dosage_per_time="1정",
        daily_frequency="1회",
        total_days="1일",
        schedule_slot_keys='["morning"]',
    )
    db_session.add(medication)
    db_session.commit()

    deleted = SavedMedicationRetentionPolicy(
        retention_days_after_end=0
    ).cleanup_expired_medications(db_session, patient_hash)

    assert deleted == 0
    assert db_session.get(_SavedMedication, medication.id) is medication


# 함수이름: test_data_maintenance_removes_only_expired_chat_messages
# 함수역할:
# - 보관 기한을 넘은 채팅 메시지만 한 건 삭제하고 최근 메시지는 유지하는지 검증한다.
# 매개변수:
# - db_session (Session): 테스트 fixture가 제공한 격리 SQLAlchemy 세션.
# 반환값:
# - 없음 (None).
def test_data_maintenance_removes_only_expired_chat_messages(db_session) -> None:
    now = datetime.now(UTC).replace(tzinfo=None)
    patient_hash = "patient-chat-retention"
    caregiver_hash = "caregiver-chat-retention"
    db_session.add_all(
        [
            _UserAccount(user_hash=patient_hash),
            _UserAccount(user_hash=caregiver_hash),
        ]
    )
    db_session.flush()
    link = _PatientCaregiverLink(
        patient_hash=patient_hash,
        caregiver_hash=caregiver_hash,
        linked=True,
    )
    db_session.add(link)
    db_session.flush()
    db_session.add_all(
        [
            _ChatMessage(
                link_id=link.id,
                sender_hash=patient_hash,
                client_message_id="expired-message",
                body="보관 기한이 지난 메시지",
                created_at=now - timedelta(days=91),
            ),
            _ChatMessage(
                link_id=link.id,
                sender_hash=caregiver_hash,
                client_message_id="recent-message",
                body="아직 보관할 메시지",
                created_at=now - timedelta(days=89),
            ),
        ]
    )
    db_session.commit()

    deleted = DataMaintenanceService(
        chat_retention_policy=ChatMessageRetentionPolicy(retention_days=90),
    ).runOnce(db_session)

    remaining_messages = db_session.query(_ChatMessage).all()
    assert deleted["chat_messages"] == 1
    assert [row.client_message_id for row in remaining_messages] == [
        "recent-message"
    ]

# 함수이름: _empty_asgi_app
# 함수역할:
# - 호출 제한 미들웨어 테스트에서 추가 응답이나 부작용 없이 종료하는 ASGI 대체 앱이다.
# 매개변수:
# - scope (Scope): 하위 대체 앱에서 사용하지 않는 ASGI 연결·요청 범위.
# - receive (Receive): 요청 본문 이벤트를 제공할 ASGI 수신 함수.
# - send (Send): 응답 이벤트를 받을 ASGI 전송 함수.
# 반환값:
# - 없음 (None).
async def _empty_asgi_app(scope, receive, send) -> None:
    return None


# Class Name: _AtomicRedisStub
# Role: Redis double that records atomic Lua invocations and client closure.
# Responsibilities:
# - Records the Lua script, key count, and arguments and returns the first incremented counter
#   value.
# - Marks the Redis double closed for owned-client cleanup checks.
# Attributes:
# - calls (list[tuple[str, int, tuple[object, ...]]]): Ordered requests captured for later
#   assertions.
# - closed (bool): Whether the simulated client has been closed.
class _AtomicRedisStub:
    # Function Name: __init__
    # Description:
    # - Starts an empty Lua-call history and marks the Redis double as open.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.calls: list[tuple[str, int, tuple[object, ...]]] = []
        self.closed = False

    # Function Name: eval
    # Description:
    # - Records the Lua script, key count, and arguments and returns the first incremented
    #   counter value.
    # Parameters:
    # - script (str): Lua script combining quota increment and expiry.
    # - number_of_keys (int): Number of Redis keys preceding the Lua arguments.
    # - *keys_and_args (object): Redis keys and Lua arguments captured in call order.
    # Returns:
    # - int: 1, the simulated first value of the atomic quota counter.
    async def eval(
        self,
        script: str,
        number_of_keys: int,
        *keys_and_args: object,
    ) -> int:
        self.calls.append((script, number_of_keys, keys_and_args))
        return 1

    # Function Name: aclose
    # Description:
    # - Marks the Redis double closed for owned-client cleanup checks.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def aclose(self) -> None:
        self.closed = True


# Function Name: test_rate_limiter_blocks_after_memory_limit
# Description:
# - Allows the first two requests in a memory-backed quota window and rejects the third when
#   Redis is unavailable.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_rate_limiter_blocks_after_memory_limit() -> None:
    rule = RateLimitRule(max_requests=2, window_seconds=60)
    store = RequestRateLimitStore(
        redis_url="redis://localhost:6379",
    )
    store._redis_available = False
    try:
        assert (
            await store.consume(
                identity="user:test-user",
                request_scope="POST:/limited",
                rule=rule,
            )
        )[0] is True
        assert (
            await store.consume(
                identity="user:test-user",
                request_scope="POST:/limited",
                rule=rule,
            )
        )[0] is True
        assert (
            await store.consume(
                identity="user:test-user",
                request_scope="POST:/limited",
                rule=rule,
            )
        )[0] is False
    finally:
        await store.close()


# Function Name: test_rate_limiter_fails_closed_when_redis_is_required
# Description:
# - Fails closed with an explicit distributed-storage error when Redis is mandatory but
#   unavailable.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_rate_limiter_fails_closed_when_redis_is_required() -> None:
    store = RequestRateLimitStore(
        redis_url="redis://localhost:6379",
        require_redis=True,
    )
    store._redis_available = False
    try:
        with pytest.raises(RuntimeError, match="Distributed request-rate storage"):
            await store.consume(
                identity="user:test-user",
                request_scope="POST:/limited",
                rule=RateLimitRule(max_requests=2, window_seconds=60),
            )
    finally:
        await store.close()


# Function Name: test_rate_limiter_keeps_failing_closed_during_redis_retry_delay
# Description:
# - Requires successive requests during Redis retry backoff to remain 503 responses with
#   five-second retry hints.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_rate_limiter_keeps_failing_closed_during_redis_retry_delay() -> None:
    responses: list[dict[str, object]] = []

    # Function Name: send
    # Description:
    # - Collects ASGI response messages so status and retry headers can be inspected.
    # Parameters:
    # - message (dict[str, object]): ASGI response event captured for status and header
    #   assertions.
    # Returns:
    # - None.
    async def send(message: dict[str, object]) -> None:
        responses.append(message)

    store = RequestRateLimitStore(
        redis_url="redis://localhost:6379",
        require_redis=True,
    )
    middleware = RequestRateLimitMiddleware(
        _empty_asgi_app,
        store=store,
        rules={
            ("POST", "/limited"): RateLimitRule(
                max_requests=2,
                window_seconds=60,
            )
        },
    )
    store._redis_available = False
    store._redis_retry_at = float("inf")
    scope = {
        "type": "http",
        "method": "POST",
        "path": "/limited",
        "client": ("127.0.0.1", 12345),
        "headers": [],
    }

    # Function Name: receive
    # Description:
    # - Supplies one empty completed ASGI request body to the rate-limit middleware.
    # Parameters:
    # - None.
    # Returns:
    # - dict[str, object]: Empty final ASGI request-body event.
    async def receive() -> dict[str, object]:
        return {"type": "http.request", "body": b"", "more_body": False}

    try:
        await middleware(scope, receive, send)  # type: ignore[arg-type]
        await middleware(scope, receive, send)  # type: ignore[arg-type]
    finally:
        await store.close()

    response_starts = [
        message
        for message in responses
        if message.get("type") == "http.response.start"
    ]
    assert [message["status"] for message in response_starts] == [503, 503]
    assert all(
        (b"retry-after", b"5") in message["headers"]
        for message in response_starts
    )


# Function Name: test_rate_limiter_uses_ip_identity_and_route_specific_scope
# Description:
# - Builds the quota identity from the request IP and its scope from the HTTP method and route.
# Parameters:
# - None.
# Returns:
# - None.
def test_rate_limiter_uses_ip_identity_and_route_specific_scope() -> None:
    scope = {
        "client": ("203.0.113.5", 12345),
        "headers": [(b"authorization", b"Bearer private-token")],
    }

    assert (
        RequestRateLimitMiddleware._request_ip_identity(scope)  # type: ignore[arg-type]
        == "ip:203.0.113.5"
    )
    assert (
        RequestRateLimitMiddleware._request_scope(  # type: ignore[arg-type]
            {**scope, "method": "POST", "path": "/limited"}
        )
        == "POST:/limited"
    )


# 함수이름: test_pill_identification_limit_accepts_a_full_client_batch
# 함수역할:
# - 알약 단건 식별 제한이 정상 클라이언트 최대 일괄 등록인 10회를 허용하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_pill_identification_limit_accepts_a_full_client_batch() -> None:
    rule = DEFAULT_RATE_LIMIT_RULES[
        ("POST", "/api/v1/medication/pill-identification/candidates")
    ]

    assert rule.max_requests >= 10


# Function Name: test_multiple_pill_identification_has_a_dedicated_cost_limit
# Description:
# - Requires multi-pill identification to have its own bounded one-to-ten-request cost quota.
# Parameters:
# - None.
# Returns:
# - None.
def test_multiple_pill_identification_has_a_dedicated_cost_limit() -> None:
    rule = DEFAULT_RATE_LIMIT_RULES[
        ("POST", "/api/v1/medication/pill-identification/multiple-candidates")
    ]

    assert 1 <= rule.max_requests <= 10


# 함수이름: test_rate_limit_resolver_matches_dynamic_chat_route
# 함수역할:
# - 숫자 연동 ID가 있는 채팅 경로를 정규 경로와 분당 20회 규칙에 연결하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_rate_limit_resolver_matches_dynamic_chat_route() -> None:
    resolved = resolve_rate_limit_rule(
        "POST",
        "/api/v1/chat/links/27/messages",
    )

    assert resolved is not None
    rule, canonical_path = resolved
    assert rule == RateLimitRule(max_requests=20, window_seconds=60)
    assert canonical_path == "/api/v1/chat/links/{link_id}/messages"


# 함수이름: test_rate_limit_resolver_applies_default_to_unlisted_api
# 함수역할:
# - 별도 규칙이 없는 약 항목 경로도 정규화하여 분당 60회 기본 제한을 적용하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_rate_limit_resolver_applies_default_to_unlisted_api() -> None:
    resolved = resolve_rate_limit_rule(
        "PATCH",
        "/api/v1/medication/items/123",
    )

    assert resolved is not None
    rule, canonical_path = resolved
    assert rule == RateLimitRule(max_requests=60, window_seconds=60)
    assert canonical_path == "/api/v1/medication/items/{id}"


# Function Name: test_rate_limiter_separates_endpoint_buckets
# Description:
# - Keeps two endpoint quota buckets independent for the same identity.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_rate_limiter_separates_endpoint_buckets() -> None:
    rule = RateLimitRule(max_requests=1, window_seconds=60)
    store = RequestRateLimitStore(redis_url="redis://localhost:6379")
    store._redis_available = False
    try:
        first_route = await store.consume(
            identity="user:test-user",
            request_scope="POST:/first",
            rule=rule,
        )
        second_route = await store.consume(
            identity="user:test-user",
            request_scope="POST:/second",
            rule=rule,
        )
    finally:
        await store.close()

    assert first_route[0] is True
    assert second_route[0] is True


# Function Name: test_rate_limiter_sets_counter_and_expiry_atomically
# Description:
# - Uses one Redis Lua call to increment and set expiry atomically, passes the expected TTL, and
#   closes the owned client.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_rate_limiter_sets_counter_and_expiry_atomically() -> None:
    redis = _AtomicRedisStub()
    store = RequestRateLimitStore(
        redis_url="redis://unused",
        redis_client=redis,
    )
    try:
        allowed, _ = await store.consume(
            identity="user:test-user",
            request_scope="POST:/limited",
            rule=RateLimitRule(max_requests=2, window_seconds=60),
        )
    finally:
        await store.close()

    assert allowed is True
    assert len(redis.calls) == 1
    script, number_of_keys, keys_and_args = redis.calls[0]
    assert "INCR" in script and "EXPIRE" in script
    assert number_of_keys == 1
    assert keys_and_args[-1] == 61
    assert redis.closed is True


# Function Name: test_rate_limiter_recreates_owned_redis_after_repeated_close
# Description:
# - Allows repeated cleanup and recreates the owned Redis client for later requests, closing
#   both client generations.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_rate_limiter_recreates_owned_redis_after_repeated_close() -> None:
    first_redis = _AtomicRedisStub()
    second_redis = _AtomicRedisStub()
    store = RequestRateLimitStore(redis_url="redis://unused")
    rule = RateLimitRule(max_requests=2, window_seconds=60)

    with patch(
        "core.request_rate_limits.Redis.from_url",
        side_effect=[first_redis, second_redis],
    ) as redis_factory:
        await store.consume(
            identity="user:test-user",
            request_scope="POST:/limited",
            rule=rule,
        )
        await store.close()
        await store.consume(
            identity="user:test-user",
            request_scope="POST:/limited",
            rule=rule,
        )
        await store.close()

    assert redis_factory.call_count == 2
    assert len(first_redis.calls) == 1
    assert len(second_redis.calls) == 1
    assert first_redis.closed is True
    assert second_redis.closed is True
