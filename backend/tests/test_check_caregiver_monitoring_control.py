# 파일명: test_check_caregiver_monitoring_control.py
# 역할: 보호자 모니터링의 일괄 연동·설정 조회와 알림 활성 환자 일정 조회를 검증한다.

from datetime import datetime

from controls.check_caregiver_monitoring_control import CheckCaregiverMonitoring
from entities.patient_caregiver_link_entity import _PatientCaregiverLink


# 클래스명: _LinkRepositoryStub
# 역할: 보호자 조회 이력을 기록하고 미리 지정된 활성 연동 목록을 제공하는 저장소 대체 객체다.
# 주요 책임:
# - 조회한 보호자 해시를 기록하고 설정된 연동 목록을 반환한다.
# 속성:
# - links (list[_PatientCaregiverLink]): 저장소 대체 객체가 반환할 활성 연동 목록.
# - requested_caregiver_hashes (list[str]): 연동 조회에 전달된 보호자 범위 기록.
class _LinkRepositoryStub:
    # 함수이름: __init__
    # 함수역할:
    # - 반환할 연동 목록과 빈 보호자 조회 이력을 보관한다.
    # 매개변수:
    # - links (list[_PatientCaregiverLink]): 저장소 대체 객체가 제공할 활성 환자·보호자 연동.
    # 반환값:
    # - 없음 (None).
    def __init__(self, links: list[_PatientCaregiverLink]) -> None:
        self.links = links
        self.requested_caregiver_hashes: list[str] = []

    # 함수이름: list_active_for_caregiver
    # 함수역할:
    # - 조회한 보호자 해시를 기록하고 설정된 연동 목록을 반환한다.
    # 매개변수:
    # - caregiver_hash (str): 연동 또는 알림 설정 범위를 정할 보호자 해시.
    # 반환값:
    # - list[_PatientCaregiverLink]: 설정된 활성 환자·보호자 연동 목록.
    def list_active_for_caregiver(
        self,
        caregiver_hash: str,
    ) -> list[_PatientCaregiverLink]:
        self.requested_caregiver_hashes.append(caregiver_hash)
        return self.links


# 클래스명: _NotificationControlStub
# 역할: 환자별 알림 일괄 조회를 기록하고 활성·비활성 알림 설정을 제공하는 대체 객체다.
# 주요 책임:
# - 일괄 요청 범위를 기록하고 patient-a의 완료 알림과 patient-b의 비활성 설정을 제공한다.
# 속성:
# - requests (list[tuple[str, list[str]]]): 검증할 보호자·환자 설정 일괄 조회 기록.
class _NotificationControlStub:
    # 함수이름: __init__
    # 함수역할:
    # - 보호자 및 환자 목록별 알림 조회 이력을 빈 목록으로 준비한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def __init__(self) -> None:
        self.requests: list[tuple[str, list[str]]] = []

    # 함수이름: loadCaregiverNotificationSettingsForPatients
    # 함수역할:
    # - 일괄 요청 범위를 기록하고 patient-a의 완료 알림과 patient-b의 비활성 설정을 제공한다.
    # 매개변수:
    # - caregiver_hash (str): 연동 또는 알림 설정 범위를 정할 보호자 해시.
    # - patient_hashes (list[str]): 알림 일괄 조회에 포함할 환자 해시 목록.
    # 반환값:
    # - dict[str, list[dict[str, object]]]: patient-a는 완료 알림, patient-b는 비활성인 환자별 설정 목록.
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


# 클래스명: _TodayMedicationControlStub
# 역할: 일정 조회 대상 환자를 기록하고 환자별 고정 복약 일정을 제공하는 대체 객체다.
# 주요 책임:
# - 조회 환자를 기록하고 해당 환자 해시가 포함된 단일 복약 일정을 반환한다.
# 속성:
# - requested_patient_hashes (list[str]): 일정 조회에 전달된 환자 범위 기록.
class _TodayMedicationControlStub:
    # 함수이름: __init__
    # 함수역할:
    # - 환자별 오늘 일정 조회 이력을 빈 목록으로 준비한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def __init__(self) -> None:
        self.requested_patient_hashes: list[str] = []

    # 함수이름: requestTodayMedicationInfo
    # 함수역할:
    # - 조회 환자를 기록하고 해당 환자 해시가 포함된 단일 복약 일정을 반환한다.
    # 매개변수:
    # - patient_hash (str): 약 또는 연동 데이터 범위를 식별할 환자 소유자 해시.
    # 반환값:
    # - dict[str, object]: 환자의 시험용 단일 일정이 포함된 성공 응답.
    def requestTodayMedicationInfo(self, patient_hash: str) -> dict[str, object]:
        self.requested_patient_hashes.append(patient_hash)
        return {
            "success": True,
            "data": {
                "patient_hash": patient_hash,
                "schedules": [{"medication_id": f"medication-{patient_hash}"}],
            },
        }


# 함수이름: test_monitoring_snapshot_batches_links_settings_and_active_schedules
# 함수역할:
# - 연동·알림 설정을 각각 한 번 조회하고 알림이 활성인 환자만 일정을 조회하며 별칭과 비활성 환자의 빈 일정을 보존하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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
