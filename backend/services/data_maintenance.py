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
# 역할:
# - 서비스별 보존 정책을 한 트랜잭션으로 실행한다.
# 주요 책임:
# - 설정된 보존 기간을 넘긴 저장 약과 해당 완료 기록을 정리한다; 종료 약 보존 설정이 0이면 유지한다.
# - 원본 약이 없는 완료 기록과 만료 또는 사용된 연동 코드를 제거한다.
# - 오래된 추천 캐시, 전송 완료 알림과 보관 기한이 지난 채팅을 제거한다.
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

    # 함수이름: runOnce
    # 함수역할:
    # - 현재 시각을 기준으로 모든 데이터 보존 정책을 한 번 실행한다.
    # 매개변수:
    # - db (Session): 영속 기록에 접근할 호출자의 SQLAlchemy 세션.
    # 반환값:
    # - 저장 약, 고아 완료 기록, 연동 코드, 추천 캐시, 전송 알림과 채팅별 삭제 건수.
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
# 역할:
# - 서버가 실행되는 동안 보존 정책을 일정 간격으로 반복 실행한다.
# 주요 책임:
# - 동기 정리 서비스를 별도 스레드에서 반복 실행하고 종료 대기와 주기별 세션 수명을 관리한다.
# 속성:
# - session_factory (sessionmaker[Session]): 작업별 세션 생성기.
# - service (DataMaintenanceService): 일괄 정리 서비스.
# - _task / _stop_event: 반복 태스크와 종료 신호.
class PeriodicDataMaintenanceRunner:
    # 함수이름: __init__
    # 함수역할:
    # - 정리 세션 생성기와 서비스를 저장하고 반복 태스크의 종료 이벤트를 준비한다.
    # 매개변수:
    # - session_factory (sessionmaker[Session]): 작업 주기마다 독립 SQLAlchemy 세션을 여는 팩터리.
    # - service (DataMaintenanceService | None): 실행할 정리 서비스; None이면 기본 DataMaintenanceService.
    # 반환값:
    # - 없음; 반복 실행은 start에서 시작한다.
    def __init__(
        self,
        session_factory: sessionmaker[Session],
        service: DataMaintenanceService | None = None,
    ) -> None:
        self.session_factory = session_factory
        self.service = service or DataMaintenanceService()
        self._stop_event = asyncio.Event()
        self._task: asyncio.Task[None] | None = None

    # 함수이름: start
    # 함수역할:
    # - 등록된 태스크가 없을 때만 주기적 데이터 정리 작업을 시작한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음; 중복 태스크를 생성하지 않는다.
    def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(self._run_loop())

    # 함수이름: stop
    # 함수역할:
    # - 종료 신호를 설정하고 진행 중인 정리가 끝날 때까지 기다린 후 태스크를 해제한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음; 반복 태스크 종료 후 반환한다.
    async def stop(self) -> None:
        self._stop_event.set()
        if self._task is not None:
            await self._task
            self._task = None

    # 함수이름: _run_loop
    # 함수역할:
    # - 정리를 별도 스레드에서 한 번 실행한 뒤 설정된 간격이나 종료 신호까지 기다린다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음; 종료 이벤트가 설정되면 반복을 마친다.
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
