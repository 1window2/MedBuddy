# 파일명: data_maintenance.py
# 역할: 만료 데이터와 관계가 끊긴 데이터를 주기적으로 정리한다.

import asyncio
import logging
from datetime import UTC, datetime, timedelta

from sqlalchemy import exists
from sqlalchemy.orm import Session, sessionmaker

from core.application_clock import application_now
from core.config import settings
from entities.health_recommendation_cache_entity import _HealthRecommendationCache
from entities.caregiver_alert_outbox_entity import (
    CAREGIVER_ALERT_STATUS_SENT,
    _CaregiverAlertOutbox,
)
from entities.medication_completion_entity import _MedicationCompletion
from entities.patient_caregiver_link_entity import _PatientLinkCode
from entities.saved_medication_entity import _SavedMedication
from services.chat_message_retention import ChatMessageRetentionPolicy
from services.saved_medication_retention import SavedMedicationRetentionPolicy

logger = logging.getLogger(__name__)


# 클래스명: DataMaintenanceService
# 역할: 서비스별 보존 정책을 한 트랜잭션으로 실행한다.
# 주요 책임:
# - 복용 종료 후 30일이 지난 저장 약과 완료 기록을 정리한다.
# - 원본 약이 없는 완료 기록과 만료된 연동 코드를 제거한다.
# - 오래된 건강 추천 캐시를 제거한다.
# - 보관 기간이 지난 환자·보호자 채팅을 제거한다.
class DataMaintenanceService:
    def __init__(
        self,
        retention_policy: SavedMedicationRetentionPolicy | None = None,
        chat_retention_policy: ChatMessageRetentionPolicy | None = None,
    ) -> None:
        self.retention_policy = retention_policy or SavedMedicationRetentionPolicy()
        self.chat_retention_policy = (
            chat_retention_policy or ChatMessageRetentionPolicy()
        )

    # 함수명: runOnce
    # 역할:
    # - 현재 시각을 기준으로 모든 데이터 보존 정책을 한 번 실행한다.
    def runOnce(self, db: Session) -> dict[str, int]:
        application_date = application_now().date()
        utc_now = datetime.now(UTC).replace(tzinfo=None)
        cache_cutoff = utc_now - timedelta(
            days=settings.HEALTH_RECOMMENDATION_CACHE_RETENTION_DAYS
        )
        outbox_cutoff = utc_now - timedelta(
            days=settings.CAREGIVER_ALERT_OUTBOX_RETENTION_DAYS
        )
        deleted = {
            "saved_medications": self.retention_policy.cleanup_expired_medications(
                db,
                patient_hash=None,
                today=application_date,
                commit=False,
            ),
            "orphan_completions": (
                db.query(_MedicationCompletion)
                .filter(
                    ~exists().where(
                        _SavedMedication.id
                        == _MedicationCompletion.saved_medication_id
                    )
                )
                .delete(synchronize_session=False)
            ),
            "expired_link_codes": (
                db.query(_PatientLinkCode)
                .filter(
                    (_PatientLinkCode.expires_at <= utc_now)
                    | (_PatientLinkCode.used.is_(True))
                )
                .delete(synchronize_session=False)
            ),
            "health_recommendation_cache": (
                db.query(_HealthRecommendationCache)
                .filter(_HealthRecommendationCache.created_at < cache_cutoff)
                .delete(synchronize_session=False)
            ),
            "sent_caregiver_alerts": (
                db.query(_CaregiverAlertOutbox)
                .filter(
                    _CaregiverAlertOutbox.status == CAREGIVER_ALERT_STATUS_SENT,
                    _CaregiverAlertOutbox.sent_at < outbox_cutoff,
                )
                .delete(synchronize_session=False)
            ),
            "chat_messages": self.chat_retention_policy.cleanup_expired_messages(
                db,
                now=utc_now,
                commit=False,
            ),
        }
        db.commit()
        return deleted


# 클래스명: PeriodicDataMaintenanceRunner
# 역할: 서버가 실행되는 동안 보존 정책을 일정 간격으로 반복 실행한다.
class PeriodicDataMaintenanceRunner:
    def __init__(
        self,
        session_factory: sessionmaker[Session],
        service: DataMaintenanceService | None = None,
    ) -> None:
        self.session_factory = session_factory
        self.service = service or DataMaintenanceService()
        self._stop_event = asyncio.Event()
        self._task: asyncio.Task[None] | None = None

    def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(self._run_loop())

    async def stop(self) -> None:
        self._stop_event.set()
        if self._task is not None:
            await self._task
            self._task = None

    async def _run_loop(self) -> None:
        while not self._stop_event.is_set():
            await asyncio.to_thread(self._run_once)
            try:
                await asyncio.wait_for(
                    self._stop_event.wait(),
                    timeout=settings.PERIODIC_MAINTENANCE_INTERVAL_SECONDS,
                )
            except TimeoutError:
                continue

    def _run_once(self) -> None:
        db = self.session_factory()
        try:
            deleted = self.service.runOnce(db)
            if any(deleted.values()):
                logger.info("Periodic data cleanup completed: %s", deleted)
        except Exception:
            db.rollback()
            logger.exception("Periodic data cleanup failed.")
        finally:
            db.close()
