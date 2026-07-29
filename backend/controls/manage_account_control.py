# 파일명: manage_account_control.py
# 역할: 사용자 범위 생성, 데이터 내보내기, 계정 데이터 전체 삭제를 담당한다.

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
from entities.user_account_entity import _UserAccount
from entities.user_setting_entity import _UserSetting


# 클래스명: ManageAccount
# 역할: 인증 사용자와 연결된 MedBuddy 데이터의 수명주기를 한곳에서 관리한다.
# 주요 책임:
# - 인증 또는 로컬 사용자의 내부 계정 범위를 보장한다.
# - 사용자가 보유한 데이터를 기계 판독 가능한 형태로 내보낸다.
# - 환자 데이터, 보호자 연결, 알림, 캐시를 하나의 트랜잭션으로 삭제한다.
class ManageAccount:
    def __init__(self, db: Session) -> None:
        self.db = db

    # 함수명: ensureAccount
    # 역할:
    # - FK로 참조할 내부 사용자 row가 없으면 생성한다.
    def ensureAccount(self, user_hash: str, *, commit: bool = False) -> str:
        normalized_user_hash = normalize_patient_hash(user_hash)
        account = self.db.get(_UserAccount, normalized_user_hash)
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
        saved_medications = (
            self.db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == normalized_user_hash)
            .all()
        )
        medication_ids = [row.id for row in saved_medications]
        completions = (
            self.db.query(_MedicationCompletion)
            .filter(_MedicationCompletion.patient_hash == normalized_user_hash)
            .all()
        )
        links = (
            self.db.query(_PatientCaregiverLink)
            .filter(
                or_(
                    _PatientCaregiverLink.patient_hash == normalized_user_hash,
                    _PatientCaregiverLink.caregiver_hash == normalized_user_hash,
                )
            )
            .all()
        )
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

    # 함수명: deleteAccountData
    # 역할:
    # - 사용자 소유 데이터와 보호자 접근 관계를 트랜잭션으로 모두 삭제한다.
    # - Firebase 인증 계정 삭제는 클라이언트의 재인증 흐름에서 별도로 수행한다.
    def deleteAccountData(self, user_hash: str) -> dict[str, object]:
        normalized_user_hash = normalize_patient_hash(user_hash)
        deleted_counts: dict[str, int] = {}
        try:
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
            deleted_counts["user_accounts"] = self._delete(
                _UserAccount,
                _UserAccount.user_hash == normalized_user_hash,
            )
            self.db.commit()
        except Exception:
            self.db.rollback()
            raise

        return {
            "success": True,
            "message": "MedBuddy account data was deleted.",
            "deleted": deleted_counts,
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
