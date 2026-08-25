# 파일명: test_check_caregiver_monitoring_control.py
# 역할: 보호자 통합 감시 조회가 여러 환자의 자료를 한 요청으로 구성하는지 검증한다.

from datetime import datetime

from controls.check_caregiver_monitoring_control import CheckCaregiverMonitoring
from entities.patient_caregiver_link_entity import _PatientCaregiverLink


class _LinkRepositoryStub:
    def __init__(self, links: list[_PatientCaregiverLink]) -> None:
        self.links = links
        self.requested_caregiver_hashes: list[str] = []

    def list_active_for_caregiver(
        self,
        caregiver_hash: str,
    ) -> list[_PatientCaregiverLink]:
        self.requested_caregiver_hashes.append(caregiver_hash)
        return self.links


class _NotificationControlStub:
    def __init__(self) -> None:
        self.requests: list[tuple[str, list[str]]] = []

    def loadCaregiverNotificationSettingsForPatients(
        self,
        caregiver_hash: str,
        patient_hashes: list[str],
    ) -> dict[str, list[dict[str, object]]]:
        self.requests.append((caregiver_hash, patient_hashes))
        return {
            "patient-a": [
                {
                    "patient_hash": "patient-a",
                    "caregiver_hash": caregiver_hash,
                    "slot_key": "morning",
                    "notification_type": "dose_completed",
                }
            ],
            "patient-b": [
                {
                    "patient_hash": "patient-b",
                    "caregiver_hash": caregiver_hash,
                    "slot_key": "morning",
                    "notification_type": "disabled",
                }
            ],
        }


class _TodayMedicationControlStub:
    def __init__(self) -> None:
        self.requested_patient_hashes: list[str] = []

    def requestTodayMedicationInfo(self, patient_hash: str) -> dict[str, object]:
        self.requested_patient_hashes.append(patient_hash)
        return {
            "success": True,
            "data": {
                "patient_hash": patient_hash,
                "schedules": [{"medication_id": f"medication-{patient_hash}"}],
            },
        }


def test_monitoring_snapshot_batches_links_settings_and_active_schedules() -> None:
    """활성 환자 전체를 한 번 조회하고 필요한 일정만 포함하는지 검증한다."""
    links = [
        _PatientCaregiverLink(
            id=1,
            patient_hash="patient-a",
            caregiver_hash="caregiver-a",
            patient_alias="어머니",
            linked=True,
            created_at=datetime(2026, 8, 25),
        ),
        _PatientCaregiverLink(
            id=2,
            patient_hash="patient-b",
            caregiver_hash="caregiver-a",
            patient_alias="아버지",
            linked=True,
            created_at=datetime(2026, 8, 25),
        ),
    ]
    link_repository = _LinkRepositoryStub(links)
    notification_control = _NotificationControlStub()
    today_control = _TodayMedicationControlStub()
    control = CheckCaregiverMonitoring(
        db=None,  # type: ignore[arg-type]
        link_repository=link_repository,  # type: ignore[arg-type]
        notification_control=notification_control,  # type: ignore[arg-type]
        today_medication_control=today_control,  # type: ignore[arg-type]
    )

    response = control.requestMonitoringSnapshot("caregiver-a")

    assert link_repository.requested_caregiver_hashes == ["caregiver-a"]
    assert notification_control.requests == [
        ("caregiver-a", ["patient-a", "patient-b"])
    ]
    assert today_control.requested_patient_hashes == ["patient-a"]
    patients = response["data"]["patients"]  # type: ignore[index]
    assert [patient["patient_alias"] for patient in patients] == [
        "어머니",
        "아버지",
    ]
    assert patients[0]["today_medication_info"]["schedules"]
    assert patients[1]["today_medication_info"]["schedules"] == []
