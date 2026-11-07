# 파일명: data_maintenance.py
# 역할: 만료 데이터와 관계가 끊긴 데이터를 주기적으로 정리한다.

import logging
from datetime import UTC, datetime, timedelta

from sqlalchemy import exists, func
from sqlalchemy.orm import Session, sessionmaker

from core.application_clock import application_now
from core.config import settings
from entities.health_recommendation_cache_entity import _HealthRecommendationCache
from entities.caregiver_alert_outbox_entity import (
    CAREGIVER_ALERT_STATUS_DEAD_LETTER,
    CAREGIVER_ALERT_STATUS_SENT,
    _CaregiverAlertOutbox,
)
from entities.medication_completion_entity import _MedicationCompletion
from entities.patient_caregiver_link_entity import _PatientLinkCode
from entities.saved_medication_entity import _SavedMedication
from services.background_loop_runner import BackgroundLoopRunner
from services.chat_message_retention import ChatMessageRetentionPolicy
from services.saved_medication_retention import SavedMedicationRetentionPolicy

logger = logging.getLogger(__name__)


# 클래스명: DataMaintenanceService
# 역할:
# - 서비스별 보존 정책을 한 트랜잭션으로 실행한다.
# 주요 책임:
# - 설정된 보존 기간을 넘긴 저장 약과 해당 완료 기록을 정리한다; 종료 약 보존 설정이 0이면 유지한다.
# - 원본 약이 없는 완료 기록과 만료 또는 사용된 연동 코드를 제거한다.
# - 오래된 추천 캐시, 전송 완료·전송 포기 알림과 보관 기한이 지난 채팅을 제거한다.
# - 모든 정리 결과를 하나의 트랜잭션으로 커밋한다.
# 속성:
# - retention_policy (SavedMedicationRetentionPolicy): 종료 약 보존 정책.
# - chat_retention_policy (ChatMessageRetentionPolicy): 채팅 보존 정책.
class DataMaintenanceService:
    # 함수이름: __init__
    # 함수역할:
    # - 정리 작업에서 함께 사용할 저장 약 및 채팅 보존 정책을 주입받거나 기본 정책으로 준비한다.
    # 매개변수:
    # - retention_policy (SavedMedicationRetentionPolicy | None): 종료 약 보존 정책; None이면 설정 기반 기본 정책.
    # - chat_retention_policy (ChatMessageRetentionPolicy | None): 채팅 보존 정책; None이면 설정 기반 기본 정책.
    # 반환값:
    # - 없음; DB 정리는 아직 실행하지 않는다.
    def __init__(
        self,
        retention_policy: SavedMedicationRetentionPolicy | None = None,
        chat_retention_policy: ChatMessageRetentionPolicy | None = None,
    ) -> None:
        self.retention_policy = retention_policy or SavedMedicationRetentionPolicy()
        self.chat_retention_policy = (
            chat_retention_policy or ChatMessageRetentionPolicy()
        )

    # Function Name: runOnce
    # Description: Applies medication/chat retention, removes orphan completions, expired/used codes, old recommendations and terminal caregiver events in one commit.
    # Parameters: db (Session) is the maintenance transaction; application date and UTC instants are captured internally.
    # Returns: Per-category deletion counts; sent_caregiver_alerts includes dead-letter rows, while pending/failed/processing events remain. Database failures propagate.
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
            # 종료 상태만 지운다. 대기·실패·처리 중인 행은 오래돼도 전송 작업이 계속 소유한다.
            # 전송 포기 행에는 전송 시각이 없으므로 생성 시각으로 보관 기한을 잰다.
            "sent_caregiver_alerts": (
                db.query(_CaregiverAlertOutbox)
                .filter(
                    _CaregiverAlertOutbox.status.in_(
                        (
                            CAREGIVER_ALERT_STATUS_SENT,
                            CAREGIVER_ALERT_STATUS_DEAD_LETTER,
                        )
                    ),
                    func.coalesce(
                        _CaregiverAlertOutbox.sent_at,
                        _CaregiverAlertOutbox.created_at,
                    )
                    < outbox_cutoff,
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


# Class Name: PeriodicDataMaintenanceRunner
# Role: Runs retention cleanup repeatedly during the server lifetime.
# Responsibilities: Executes synchronous cleanup off the event loop using per-cycle sessions and inherited graceful shutdown.
# Attributes: session_factory creates Sessions; service (DataMaintenanceService) applies retention; inherited _task/_stop_event control lifetime.
class PeriodicDataMaintenanceRunner(BackgroundLoopRunner):
    _cycle_logger = logger
    _cycle_failure_message = "Periodic data cleanup cycle failed: %s"

    # Function Name: __init__
    # Description: Stores the session factory and supplied/default maintenance service, then initializes lifecycle state without starting cleanup.
    # Parameters: session_factory (sessionmaker[Session]) opens each cycle; service (DataMaintenanceService | None) overrides default retention behavior.
    # Returns: None; start schedules the loop.
    def __init__(
        self,
        session_factory: sessionmaker[Session],
        service: DataMaintenanceService | None = None,
    ) -> None:
        self.session_factory = session_factory
        self.service = service or DataMaintenanceService()
        super().__init__()

    # Function Name: _cycle_interval_seconds
    # Description: Reads the current maintenance interval after each cycle.
    # Parameters: None.
    # Returns: PERIODIC_MAINTENANCE_INTERVAL_SECONDS in seconds.
    def _cycle_interval_seconds(self) -> float:
        return settings.PERIODIC_MAINTENANCE_INTERVAL_SECONDS

    # 함수이름: _run_once
    # 함수역할:
    # - 독립 세션에서 정리를 실행하고 오류 시 롤백하며 성공·실패를 기록한 뒤 세션을 닫는다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음; 삭제 건수는 로그에 남긴다.
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
