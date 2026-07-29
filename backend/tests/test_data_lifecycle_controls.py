# 파일명: test_data_lifecycle_controls.py
# 역할: 자동 정리, 계정 삭제, 호출 제한의 핵심 수명주기 정책을 검증한다.

from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from controls.manage_account_control import ManageAccount
from core.database import Base
from core.request_rate_limits import RateLimitRule, RequestRateLimitMiddleware
from entities.health_recommendation_cache_entity import _HealthRecommendationCache
from entities.medication_completion_entity import _MedicationCompletion
from entities.patient_caregiver_link_entity import _PatientLinkCode
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import _UserAccount
from services.data_maintenance import DataMaintenanceService


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


# 함수명: test_data_maintenance_removes_expired_and_orphaned_rows
# 역할:
# - 정기 작업이 만료 약, 완료 기록, 연동 코드, AI 캐시를 함께 정리하는지 검증한다.
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

    deleted = DataMaintenanceService().runOnce(db_session)

    assert deleted["saved_medications"] == 1
    assert db_session.query(_SavedMedication).count() == 0
    assert db_session.query(_MedicationCompletion).count() == 0
    assert db_session.query(_PatientLinkCode).count() == 0
    assert db_session.query(_HealthRecommendationCache).count() == 0


# 함수명: test_manage_account_exports_and_deletes_owned_data
# 역할:
# - 계정 관리 Control이 데이터를 직렬화하고 사용자 범위를 완전히 삭제하는지 검증한다.
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


async def _empty_asgi_app(scope, receive, send) -> None:
    return None


# 함수명: test_rate_limiter_blocks_after_memory_limit
# 역할:
# - Redis를 사용할 수 없는 로컬 환경에서도 호출 제한이 동일하게 적용되는지 검증한다.
@pytest.mark.anyio
async def test_rate_limiter_blocks_after_memory_limit() -> None:
    rule = RateLimitRule(max_requests=2, window_seconds=60)
    middleware = RequestRateLimitMiddleware(
        _empty_asgi_app,
        redis_url="redis://localhost:6379",
        rules={},
    )
    middleware._redis_available = False
    try:
        assert (await middleware._consume("test-user", rule))[0] is True
        assert (await middleware._consume("test-user", rule))[0] is True
        assert (await middleware._consume("test-user", rule))[0] is False
    finally:
        await middleware.close()
