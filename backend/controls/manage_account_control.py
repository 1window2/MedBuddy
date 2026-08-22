# 파일명: manage_account_control.py
# 역할: 사용자 범위 생성, 데이터 내보내기, 계정 데이터 전체 삭제를 담당한다.

import logging
from datetime import date, datetime

from sqlalchemy import inspect as sqlalchemy_inspect, or_
from sqlalchemy.orm import Session

from entities.caregiver_notification_entity import _CaregiverNotification
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


class AccountDeletionPendingError(RuntimeError):
    """Raised when a deleted identity tries to recreate its data scope."""


# 클래스명: ManageAccount
# 역할: 인증 사용자와 연결된 MedBuddy 데이터의 수명주기를 한곳에서 관리한다.
# 주요 책임:
# - 인증 또는 로컬 사용자의 내부 계정 범위를 보장한다.
# - 사용자가 보유한 데이터를 기계 판독 가능한 형태로 내보낸다.
# - 환자 데이터, 보호자 연결, 알림, 캐시를 하나의 트랜잭션으로 삭제한다.
class ManageAccount:
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

    # 함수명: ensureAccount
    # 역할:
    # - FK로 참조할 내부 사용자 row가 없으면 생성한다.
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

    # 함수명: exportAccountData
    # 역할:
    # - 사용자가 소유하거나 보호자로 참여한 데이터를 JSON 응답용으로 묶는다.
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
                "saved_medication_ids": medication_ids,
            },
        }

    # Function Name: deleteAccountData
    # Description:
    # - Purges the authenticated user's MedBuddy data in one database transaction.
    # - In Firebase mode, retains a tombstone before deleting the external identity
    #   so a retry cannot recreate an empty account after a provider outage.
    # Parameters:
    # - user_hash: Server-derived MedBuddy ownership key.
    # - external_subject: Verified Firebase UID; never supplied by the client body.
    # Returns:
    # - Deletion counts and whether the external identity was removed.
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

    def _purge_user_data(
        self,
        normalized_user_hash: str,
        *,
        delete_account: bool,
    ) -> dict[str, int]:
        deleted_counts: dict[str, int] = {}
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
    def _delete(self, model: type[object], criterion: object) -> int:
        return (
            self.db.query(model)
            .filter(criterion)
            .delete(synchronize_session=False)
        )

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
