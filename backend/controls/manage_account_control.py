# 파일명: manage_account_control.py
# 역할: 사용자 범위 생성, 데이터 내보내기, 계정 데이터 전체 삭제를 담당한다.

import logging
from datetime import date, datetime

from sqlalchemy import and_, inspect as sqlalchemy_inspect, or_
from sqlalchemy.orm import Session

from entities.caregiver_notification_entity import _CaregiverNotification
from entities.caregiver_alert_outbox_entity import _CaregiverAlertOutbox
from entities.chat_message_entity import _ChatMessage
from entities.device_push_token_entity import _DevicePushToken
from entities.health_recommendation_cache_entity import _HealthRecommendationCache
from entities.medication_alarm_entity import _MedicationAlarm
from entities.medication_completion_entity import _MedicationCompletion
from entities.patient_caregiver_link_entity import (
    _PatientCaregiverLink,
    _PatientLinkCode,
)
from entities.patient_hash_entity import normalize_patient_hash
from entities.saved_medication_entity import _SavedMedication
from boundaries.firebase_identity_boundary import IdentityDeletionBoundary
from entities.user_account_entity import _UserAccount, utc_now
from entities.user_setting_entity import _UserSetting
from repositories.patient_caregiver_link_repository import (
    PatientCaregiverLinkRepository,
)
from repositories.saved_medication_repository import SavedMedicationRepository

logger = logging.getLogger(__name__)


# Class Name: AccountDeletionPendingError
# Role:
# - Raised when a deleted identity tries to recreate its data scope.
# Responsibilities:
# - Prevent a durable deletion marker from being mistaken for an account that can be recreated.
class AccountDeletionPendingError(RuntimeError):
    """Raised when a deleted identity tries to recreate its data scope."""


# 클래스명: ManageAccount
# 역할:
# - 인증 사용자와 연결된 MedBuddy 데이터의 수명주기를 한곳에서 관리한다.
# 주요 책임:
# - 인증 또는 로컬 사용자의 내부 계정 범위를 보장한다.
# - 사용자가 보유한 데이터를 기계 판독 가능한 형태로 내보낸다.
# - 환자 데이터, 보호자 연결, 알림, 캐시를 하나의 트랜잭션으로 삭제한다.
# 속성:
# - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
# - medication_repository (SavedMedicationRepository): 환자 소유 저장 약품 스냅샷 저장소.
# - link_repository (PatientCaregiverLinkRepository): 활성 환자·보호자 연동 저장소.
# - identity_deletion_boundary (IdentityDeletionBoundary | None): 외부 인증 계정을 제거하는 선택적 서비스.
class ManageAccount:
    # 함수이름: __init__
    # 함수역할:
    # - 계정 내보내기·삭제에 사용할 저장소와 선택적 외부 인증 계정 삭제 경계를 연결한다.
    # 매개변수:
    # - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
    # - medication_repository (SavedMedicationRepository | None): 환자 소유 저장 약품 스냅샷 저장소.
    # - link_repository (PatientCaregiverLinkRepository | None): 활성 환자·보호자 연동 저장소.
    # - identity_deletion_boundary (IdentityDeletionBoundary | None): 외부 인증 계정을 제거하는 선택적 서비스.
    # 반환값:
    # - 없음.
    def __init__(
        self,
        db: Session,
        medication_repository: SavedMedicationRepository | None = None,
        link_repository: PatientCaregiverLinkRepository | None = None,
        identity_deletion_boundary: IdentityDeletionBoundary | None = None,
    ) -> None:
        self.db = db
        self.medication_repository = (
            medication_repository or SavedMedicationRepository(db)
        )
        self.link_repository = (
            link_repository or PatientCaregiverLinkRepository(db)
        )
        self.identity_deletion_boundary = identity_deletion_boundary

    # Function Name: ensureAccount
    # Description:
    # - Creates the normalized account scope when absent and rejects durable deletion tombstones.
    # Parameters:
    # - user_hash (str): Account ownership scope for the operation.
    # - commit (bool): Whether this operation owns the transaction commit.
    # Returns:
    # - Normalized user hash, or AccountDeletionPendingError for a deleted account.
    def ensureAccount(self, user_hash: str, *, commit: bool = False) -> str:
        normalized_user_hash = normalize_patient_hash(user_hash)
        account = self.db.get(_UserAccount, normalized_user_hash)
        if account is not None and account.deletion_requested_at is not None:
            raise AccountDeletionPendingError(
                "This MedBuddy account has been deleted."
            )
        if account is None:
            self.db.add(_UserAccount(user_hash=normalized_user_hash))
            if commit:
                self.db.commit()
            else:
                self.db.flush()
        return normalized_user_hash

    # 함수이름: exportAccountData
    # 함수역할:
    # - 사용자가 소유하거나 보호자로 참여한 데이터를 JSON 응답용으로 묶는다.
    # 매개변수:
    # - user_hash (str): 작업 대상 계정의 데이터 소유 범위 식별자.
    # 반환값:
    # - 사용자 범위에 속한 복약·연동·채팅·알림·설정의 JSON 호환 내보내기 응답.
    def exportAccountData(self, user_hash: str) -> dict[str, object]:
        normalized_user_hash = self.ensureAccount(user_hash)
        saved_medications = self.medication_repository.list_by_patient(
            normalized_user_hash
        )
        medication_ids = [row.id for row in saved_medications]
        completions = (
            self.db.query(_MedicationCompletion)
            .filter(_MedicationCompletion.patient_hash == normalized_user_hash)
            .all()
        )
        links = self.link_repository.list_for_user(normalized_user_hash)
        caregiver_settings = (
            self.db.query(_CaregiverNotification)
            .filter(
                or_(
                    _CaregiverNotification.patient_hash == normalized_user_hash,
                    _CaregiverNotification.caregiver_hash == normalized_user_hash,
                )
            )
            .all()
        )
        chat_messages = (
            self.db.query(_ChatMessage)
            .join(
                _PatientCaregiverLink,
                _PatientCaregiverLink.id == _ChatMessage.link_id,
            )
            .filter(
                or_(
                    and_(
                        _PatientCaregiverLink.patient_hash == normalized_user_hash,
                        _ChatMessage.patient_deleted_at.is_(None),
                    ),
                    and_(
                        _PatientCaregiverLink.caregiver_hash == normalized_user_hash,
                        _ChatMessage.caregiver_deleted_at.is_(None),
                    ),
                )
            )
            .all()
        )
        return {
            "success": True,
            "data": {
                "user_hash": normalized_user_hash,
                "saved_medications": [
                    self._row_to_dict(row) for row in saved_medications
                ],
                "medication_completions": [
                    self._row_to_dict(row) for row in completions
                ],
                "notification_settings": [
                    self._row_to_dict(row)
                    for row in self.db.query(_MedicationAlarm)
                    .filter(_MedicationAlarm.patient_hash == normalized_user_hash)
                    .all()
                ],
                "caregiver_links": [self._row_to_dict(row) for row in links],
                "caregiver_notification_settings": [
                    self._row_to_dict(row) for row in caregiver_settings
                ],
                "chat_messages": [
                    self._row_to_dict(row) for row in chat_messages
                ],
                "saved_medication_ids": medication_ids,
            },
        }

    # Function Name: deleteAccountData
    # Description:
    # - Purges local data and, when configured, deletes the verified external identity using retry-safe tombstone markers.
    # Parameters:
    # - user_hash (str): Account ownership scope for the operation.
    # - external_subject (str | None): Verified Firebase subject whose external identity is deleted.
    # Returns:
    # - Per-table deletion counts and whether external identity deletion completed.
    def deleteAccountData(
        self,
        user_hash: str,
        external_subject: str | None = None,
    ) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        identity_boundary = self.identity_deletion_boundary
        if identity_boundary is None:
            deleted_counts = self._purge_local_account(normalized_user_hash)
            return self._deletion_result(deleted_counts, identity_deleted=False)

        normalized_subject = (external_subject or "").strip()
        if not normalized_subject:
            raise ValueError("Verified Firebase subject is required.")

        deleted_counts = self._prepare_firebase_account_deletion(
            normalized_user_hash
        )
        identity_boundary.deleteIdentity(normalized_subject)
        self._mark_identity_deleted(normalized_user_hash)
        return self._deletion_result(deleted_counts, identity_deleted=True)

    # Function Name: _prepare_firebase_account_deletion
    # Description:
    # - Commits the deletion-request tombstone and purges user data while retaining the account marker for retries.
    # Parameters:
    # - normalized_user_hash (str): Already-normalized account scope to purge or mark.
    # Returns:
    # - Counts of locally deleted records by data category.
    def _prepare_firebase_account_deletion(
        self,
        normalized_user_hash: str,
    ) -> dict[str, int]:
        try:
            account = self.db.get(_UserAccount, normalized_user_hash)
            if account is None:
                account = _UserAccount(user_hash=normalized_user_hash)
                self.db.add(account)
            if account.deletion_requested_at is None:
                account.deletion_requested_at = utc_now()
            deleted_counts = self._purge_user_data(
                normalized_user_hash,
                delete_account=False,
            )
            self.db.commit()
            return deleted_counts
        except Exception:
            self.db.rollback()
            raise

    # Function Name: _purge_local_account
    # Description:
    # - Commits a complete local account purge, rolling back the transaction on failure.
    # Parameters:
    # - normalized_user_hash (str): Already-normalized account scope to purge or mark.
    # Returns:
    # - Counts of deleted data, including the local account row.
    def _purge_local_account(self, normalized_user_hash: str) -> dict[str, int]:
        try:
            deleted_counts = self._purge_user_data(
                normalized_user_hash,
                delete_account=True,
            )
            self.db.commit()
            return deleted_counts
        except Exception:
            self.db.rollback()
            raise

    # 함수이름: _purge_user_data
    # 함수역할:
    # - 연결 채팅과 복약·알림·설정 데이터를 삭제하고 요청에 따라 계정 기준 행도 제거한다.
    # 매개변수:
    # - normalized_user_hash (str): 삭제 또는 표식 갱신 대상인 정규화된 계정 식별자.
    # - delete_account (bool): 계정 행을 제거할지 삭제 표식을 남길지 여부.
    # 반환값:
    # - 데이터 종류별 삭제 행 수; 커밋은 호출자가 담당한다.
    def _purge_user_data(
        self,
        normalized_user_hash: str,
        *,
        delete_account: bool,
    ) -> dict[str, int]:
        deleted_counts: dict[str, int] = {}
        linked_ids = [
            int(row.id)
            for row in self.db.query(_PatientCaregiverLink.id)
            .filter(
                or_(
                    _PatientCaregiverLink.patient_hash == normalized_user_hash,
                    _PatientCaregiverLink.caregiver_hash == normalized_user_hash,
                )
            )
            .all()
        ]
        deleted_counts["chat_messages"] = (
            self._delete(
                _ChatMessage,
                _ChatMessage.link_id.in_(linked_ids),
            )
            if linked_ids
            else 0
        )
        deleted_counts["caregiver_alerts"] = self._delete(
            _CaregiverAlertOutbox,
            or_(
                _CaregiverAlertOutbox.patient_hash == normalized_user_hash,
                _CaregiverAlertOutbox.caregiver_hash == normalized_user_hash,
            ),
        )
        deleted_counts["medication_completions"] = self._delete(
            _MedicationCompletion,
            _MedicationCompletion.patient_hash == normalized_user_hash,
        )
        deleted_counts["saved_medications"] = self._delete(
            _SavedMedication,
            _SavedMedication.patient_hash == normalized_user_hash,
        )
        deleted_counts["notification_settings"] = self._delete(
            _MedicationAlarm,
            _MedicationAlarm.patient_hash == normalized_user_hash,
        )
        deleted_counts["health_recommendation_cache"] = self._delete(
            _HealthRecommendationCache,
            _HealthRecommendationCache.patient_hash == normalized_user_hash,
        )
        deleted_counts["patient_link_codes"] = self._delete(
            _PatientLinkCode,
            or_(
                _PatientLinkCode.patient_hash == normalized_user_hash,
                _PatientLinkCode.caregiver_hash == normalized_user_hash,
            ),
        )
        deleted_counts["caregiver_notifications"] = self._delete(
            _CaregiverNotification,
            or_(
                _CaregiverNotification.patient_hash == normalized_user_hash,
                _CaregiverNotification.caregiver_hash == normalized_user_hash,
            ),
        )
        deleted_counts["caregiver_links"] = self._delete(
            _PatientCaregiverLink,
            or_(
                _PatientCaregiverLink.patient_hash == normalized_user_hash,
                _PatientCaregiverLink.caregiver_hash == normalized_user_hash,
            ),
        )
        deleted_counts["push_tokens"] = self._delete(
            _DevicePushToken,
            _DevicePushToken.user_hash == normalized_user_hash,
        )
        deleted_counts["user_settings"] = self._delete(
            _UserSetting,
            _UserSetting.user_hash == normalized_user_hash,
        )
        deleted_counts["user_accounts"] = (
            self._delete(
                _UserAccount,
                _UserAccount.user_hash == normalized_user_hash,
            )
            if delete_account
            else 0
        )
        return deleted_counts

    # Function Name: _mark_identity_deleted
    # Description:
    # - Records external identity deletion completion and logs marker failures without undoing the completed identity deletion.
    # Parameters:
    # - normalized_user_hash (str): Already-normalized account scope to purge or mark.
    # Returns:
    # - None.
    def _mark_identity_deleted(self, normalized_user_hash: str) -> None:
        try:
            account = self.db.get(_UserAccount, normalized_user_hash)
            if account is not None:
                account.identity_deleted_at = utc_now()
                self.db.commit()
        except Exception as exc:
            self.db.rollback()
            logger.warning(
                "Firebase identity was deleted but its tombstone marker failed: %s",
                type(exc).__name__,
            )

    # Function Name: _deletion_result
    # Description:
    # - Packages local purge counts and external identity completion into the account-deletion response.
    # Parameters:
    # - deleted_counts (dict[str, int]): Number of purged records grouped by data category.
    # - identity_deleted (bool): Whether external identity deletion completed.
    # Returns:
    # - Successful deletion envelope with counts and identity_deleted flag.
    @staticmethod
    def _deletion_result(
        deleted_counts: dict[str, int],
        *,
        identity_deleted: bool,
    ) -> dict[str, object]:
        return {
            "success": True,
            "message": "MedBuddy account data was deleted.",
            "deleted": deleted_counts,
            "identity_deleted": identity_deleted,
        }
    # 함수이름: _delete
    # 함수역할:
    # - 지정 ORM 모델에서 조건에 일치하는 행을 현재 트랜잭션으로 삭제한다.
    # 매개변수:
    # - model (type[object]): 계정 소유 행을 삭제할 ORM 모델.
    # - criterion (object): 삭제 범위를 제한하는 SQLAlchemy 조건식.
    # 반환값:
    # - 삭제된 행 수.
    def _delete(self, model: type[object], criterion: object) -> int:
        return (
            self.db.query(model)
            .filter(criterion)
            .delete(synchronize_session=False)
        )

    # 함수이름: _row_to_dict
    # 함수역할:
    # - ORM 열 이름을 기준으로 계정 내보내기 값을 수집하고 날짜를 ISO 문자열로 변환한다.
    # 매개변수:
    # - row (object): 내보낼 SQLAlchemy 매핑 행 객체.
    # 반환값:
    # - JSON 직렬화에 사용할 열 이름·값 사전.
    @staticmethod
    def _row_to_dict(row: object) -> dict[str, object]:
        result: dict[str, object] = {}
        mapper = sqlalchemy_inspect(type(row))
        for attribute in mapper.column_attrs:
            column = attribute.columns[0]
            value = getattr(row, attribute.key)
            if isinstance(value, (date, datetime)):
                value = value.isoformat()
            result[column.name] = value
        return result
