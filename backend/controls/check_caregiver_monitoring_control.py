"""보호자가 관리하는 모든 환자의 알림 감시 자료를 한 번에 조회한다."""

from sqlalchemy.orm import Session

from controls.check_today_medication_info_control import CheckTodayMedicationInfo
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.set_caregiver_notification_control import SetCaregiverNotification
from entities.caregiver_notification_entity import (
    CAREGIVER_NOTIFICATION_MODE_DISABLED,
)
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.patient_hash_entity import normalize_patient_hash
from repositories.patient_caregiver_link_repository import (
    PatientCaregiverLinkRepository,
)


# 클래스명: CheckCaregiverMonitoring
# 역할: 보호자 알림 감시에 필요한 연동, 별칭, 설정, 오늘 일정을 통합한다.
# 주요 책임:
# - 보호자의 활성 환자 연결을 한 번만 조회한다.
# - 환자별 네 시간대 알림 설정을 일괄 조회한다.
# - 알림이 활성화된 환자의 오늘 일정만 응답에 포함한다.
class CheckCaregiverMonitoring:
    def __init__(
        self,
        db: Session,
        link_repository: PatientCaregiverLinkRepository | None = None,
        notification_control: SetCaregiverNotification | None = None,
        today_medication_control: CheckTodayMedicationInfo | None = None,
    ) -> None:
        self.link_repository = (
            link_repository or PatientCaregiverLinkRepository(db)
        )
        self.notification_control = notification_control or (
            SetCaregiverNotification(db)
        )
        self.today_medication_control = today_medication_control or (
            CheckTodayMedicationInfo(db)
        )

    # 함수명: requestMonitoringSnapshot
    # 역할:
    # - 보호자 한 명이 관리하는 모든 환자의 현재 알림 감시 자료를 반환한다.
    def requestMonitoringSnapshot(
        self,
        caregiver_hash: str,
    ) -> dict[str, object]:
        normalized_caregiver_hash = normalize_patient_hash(caregiver_hash)
        links = self.link_repository.list_active_for_caregiver(
            normalized_caregiver_hash
        )
        patient_hashes = [str(link.patient_hash) for link in links]
        settings_by_patient = (
            self.notification_control.loadCaregiverNotificationSettingsForPatients(
                normalized_caregiver_hash,
                patient_hashes,
            )
        )

        patients = [
            self._build_patient_snapshot(
                link,
                settings_by_patient.get(str(link.patient_hash), []),
            )
            for link in links
        ]
        return {
            "success": True,
            "message": "Caregiver monitoring snapshot lookup succeeded.",
            "data": {
                "caregiver_hash": normalized_caregiver_hash,
                "guardian_hash": normalized_caregiver_hash,
                "patients": patients,
            },
        }

    def _build_patient_snapshot(
        self,
        link: _PatientCaregiverLink,
        notification_settings: list[dict[str, object]],
    ) -> dict[str, object]:
        patient_hash = str(link.patient_hash)
        has_active_setting = any(
            setting.get("notification_type")
            != CAREGIVER_NOTIFICATION_MODE_DISABLED
            for setting in notification_settings
        )
        today_medication_info: dict[str, object] = {
            "patient_hash": patient_hash,
            "schedules": [],
        }
        if has_active_setting:
            response = self.today_medication_control.requestTodayMedicationInfo(
                patient_hash
            )
            raw_data = response.get("data")
            if isinstance(raw_data, dict):
                today_medication_info = raw_data

        return {
            "link": LinkPatientCaregiver.toResponseDict(link),
            "patient_hash": patient_hash,
            "patient_alias": str(link.patient_alias or ""),
            "notification_settings": notification_settings,
            "today_medication_info": today_medication_info,
        }
