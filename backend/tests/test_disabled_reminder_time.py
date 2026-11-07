# 파일명: test_disabled_reminder_time.py
# 역할: 알림 해제 시 시간 보존·변경의 원자성, 환자 범위와 이전 요청 호환성을 검증한다.

from collections.abc import Iterator
from unittest.mock import patch

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from api.dependencies import (
    get_authenticated_principal,
    get_authorization_control,
    get_registered_principal,
    get_set_notification,
    verify_app_check_token,
)
from api.router import router
from controls.authorization_control import AuthorizationControl
from controls.set_notification_control import SetNotification
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.medication_alarm_entity import _MedicationAlarm
from support.db import seed_account


# 함수이름: alarm_api
# 함수역할:
# - 두 환자 계정과 실제 권한·알림 컨트롤을 구성하고 patient-a로 인증된 HTTP 클라이언트를 제공·종료한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# 반환값:
# - Iterator[tuple]; 클라이언트와 알림 컨트롤.
@pytest.fixture
def alarm_api(fk_db: Session) -> Iterator[tuple[TestClient, SetNotification]]:
    seed_account(fk_db, "patient-a", "patient-b")
    principal = AuthenticatedPrincipal(
        subject="patient-a", issuer="test", user_hash="patient-a",
    )
    control = SetNotification(fk_db)
    app = FastAPI()
    app.include_router(router)
    app.dependency_overrides[get_authenticated_principal] = lambda: principal
    app.dependency_overrides[get_registered_principal] = lambda: principal
    app.dependency_overrides[verify_app_check_token] = lambda: None
    app.dependency_overrides[get_authorization_control] = lambda: AuthorizationControl(fk_db)
    app.dependency_overrides[get_set_notification] = lambda: control
    with TestClient(app) as client:
        yield client, control


# 함수이름: test_disable_saves_time_atomically_and_keeps_patient_scope
# 함수역할:
# - 알림 해제와 변경 시간을 한 번에 커밋하고 위조 환자 쿼리와 무관하게 인증된 환자만 수정하는지 확인한다.
# 매개변수:
# - alarm_api: tuple[TestClient, SetNotification]; 인증된 환자의 알림 HTTP 클라이언트와 컨트롤.
# - initially_enabled: bool | None; 기존 활성·비활성 설정 또는 행 없음.
# 반환값:
# - None.
@pytest.mark.parametrize("initially_enabled", [None, False, True])
def test_disable_saves_time_atomically_and_keeps_patient_scope(alarm_api: tuple[TestClient, SetNotification], initially_enabled: bool | None) -> None:
    client, control = alarm_api
    if initially_enabled is not None:
        control.saveNotificationSetting("patient-a", "morning", 18, 55)
        if not initially_enabled:
            control.disableAlarmSetting("patient-a", "morning")
    control.saveNotificationSetting("patient-b", "morning", 8, 15)
    with patch.object(control, "_apply_alarm_state", wraps=control._apply_alarm_state) as apply:
        with patch.object(control.db, "commit", wraps=control.db.commit) as commit:
            response = client.patch(
                "/notification/settings/morning/disable?patient_hash=patient-b",
                json={"hour": 19, "minute": 5},
            )
        assert commit.call_count == 1
    assert response.status_code == 200
    assert apply.call_count == 1
    assert apply.call_args.kwargs == {"enabled": False, "hour": 19, "minute": 5}
    saved = response.json()["data"]
    assert (saved["hour"], saved["minute"], saved["is_enabled"]) == (19, 5, False)
    assert saved["patient_hash"] == "patient-a"
    reloaded = client.get("/notification/settings/morning").json()["data"]
    assert reloaded == saved
    other = control.requestAlarmToggle("patient-b", "morning")["data"]
    assert (other["hour"], other["minute"], other["is_enabled"]) == (8, 15, True)


# 함수이름: test_legacy_disable_without_time_preserves_saved_time
# 함수역할:
# - 시간을 생략한 이전 형식의 해제 요청은 저장된 시·분을 유지하는지 확인한다.
# 매개변수:
# - alarm_api: tuple[TestClient, SetNotification]; 인증된 환자의 알림 HTTP 클라이언트와 컨트롤.
# - body: dict | None; 비활성화 요청의 시간 필드.
# 반환값:
# - None.
@pytest.mark.parametrize("body", [None, {}, {"hour": None, "minute": None}])
def test_legacy_disable_without_time_preserves_saved_time(alarm_api: tuple[TestClient, SetNotification], body: dict[str, int | None] | None) -> None:
    client, control = alarm_api
    control.saveNotificationSetting("patient-a", "morning", 18, 55)
    response = client.patch("/notification/settings/morning/disable", json=body)
    assert response.status_code == 200
    saved = response.json()["data"]
    assert (saved["hour"], saved["minute"], saved["is_enabled"]) == (18, 55, False)


# 함수이름: test_invalid_disabled_time_is_rejected_before_mutation
# 함수역할:
# - 잘못된 해제 시간은 HTTP 422로 거부하고 기존 시간과 활성 상태는 유지하는지 확인한다.
# 매개변수:
# - alarm_api: tuple[TestClient, SetNotification]; 인증된 환자의 알림 HTTP 클라이언트와 컨트롤.
# - body: dict | None; 비활성화 요청의 시간 필드.
# 반환값:
# - None.
@pytest.mark.parametrize("body", [
    {"hour": -1, "minute": 0},
    {"hour": 24, "minute": 0},
    {"hour": 19, "minute": -1},
    {"hour": 19, "minute": 60},
    {"minute": 5},
    {"hour": None, "minute": 5},
    {"hour": "invalid", "minute": 5},
])
def test_invalid_disabled_time_is_rejected_before_mutation(alarm_api: tuple[TestClient, SetNotification], body: dict[str, int | str | None]) -> None:
    client, control = alarm_api
    control.saveNotificationSetting("patient-a", "morning", 18, 55)
    response = client.patch("/notification/settings/morning/disable", json=body)
    assert response.status_code == 422
    saved = control.requestAlarmToggle("patient-a", "morning")["data"]
    assert (saved["hour"], saved["minute"], saved["is_enabled"]) == (18, 55, True)


# 함수이름: test_control_also_validates_disabled_time
# 함수역할:
# - 내부 컨트롤도 잘못된 시간을 400으로 거부하고 설정 행을 생성하지 않는지 확인한다.
# 매개변수:
# - alarm_api: tuple[TestClient, SetNotification]; 인증된 환자의 알림 HTTP 클라이언트와 컨트롤.
# - time: tuple; 내부 컨트롤에 전달할 잘못된 시·분.
# 반환값:
# - None.
@pytest.mark.parametrize("time", [(24, 0), (19, 60), (None, 5)])
def test_control_also_validates_disabled_time(alarm_api: tuple[TestClient, SetNotification], time: tuple[int | None, int]) -> None:
    _, control = alarm_api
    with pytest.raises(HTTPException) as error:
        control.disableAlarmSetting("patient-a", "morning", hour=time[0], minute=time[1])
    assert error.value.status_code == 400
    assert control.db.query(_MedicationAlarm).count() == 0


# 함수이름: test_hour_only_disable_defaults_to_zero_minutes
# 함수역할:
# - 시만 지정한 해제는 기존 설정 유무와 무관하게 분을 0으로 저장하는지 확인한다.
# 매개변수:
# - alarm_api: tuple[TestClient, SetNotification]; 인증된 환자의 알림 HTTP 클라이언트와 컨트롤.
# - initially_enabled: bool | None; 기존 활성·비활성 설정 또는 행 없음.
# - body: dict | None; 비활성화 요청의 시간 필드.
# 반환값:
# - None.
@pytest.mark.parametrize("initially_enabled", [None, False, True])
@pytest.mark.parametrize("body", [{"hour": 19}, {"hour": 19, "minute": None}])
def test_hour_only_disable_defaults_to_zero_minutes(alarm_api: tuple[TestClient, SetNotification], initially_enabled: bool | None, body: dict[str, int | None]) -> None:
    client, control = alarm_api
    if initially_enabled is not None:
        control.saveNotificationSetting("patient-a", "morning", 18, 55)
        if not initially_enabled:
            control.disableAlarmSetting("patient-a", "morning")
    response = client.patch("/notification/settings/morning/disable", json=body)
    assert response.status_code == 200
    saved = response.json()["data"]
    assert (saved["hour"], saved["minute"], saved["is_enabled"]) == (19, 0, False)
    assert client.get("/notification/settings/morning").json()["data"] == saved


# 함수이름: test_control_hour_only_disable_keeps_upstream_positional_contract
# 함수역할:
# - 기존 위치 인수로 시만 넘겨도 분 0의 비활성 설정을 저장하는지 확인한다.
# 매개변수:
# - alarm_api: tuple[TestClient, SetNotification]; 인증된 환자의 알림 HTTP 클라이언트와 컨트롤.
# 반환값:
# - None.
def test_control_hour_only_disable_keeps_upstream_positional_contract(alarm_api: tuple[TestClient, SetNotification]) -> None:
    _, control = alarm_api
    control.saveNotificationSetting("patient-a", "morning", 18, 55)
    saved = control.disableAlarmSetting("patient-a", "morning", 19)["data"]
    assert (saved["hour"], saved["minute"], saved["is_enabled"]) == (19, 0, False)


# 함수이름: test_disable_conflict_recovery_keeps_new_time
# 함수역할:
# - 설정 삽입 경합을 복구할 때도 새 시·분과 비활성 상태를 한 행에 저장하는지 확인한다.
# 매개변수:
# - alarm_api: tuple[TestClient, SetNotification]; 인증된 환자의 알림 HTTP 클라이언트와 컨트롤.
# 반환값:
# - None.
def test_disable_conflict_recovery_keeps_new_time(alarm_api: tuple[TestClient, SetNotification]) -> None:
    _, control = alarm_api
    control.saveNotificationSetting("patient-a", "morning", 18, 55)
    find = control._find_setting
    calls = 0

    # 함수이름: miss_first
    # 함수역할:
    # - 첫 설정 조회만 누락으로 반환하여 기존 행 삽입 충돌 후 재조회 경로를 재현한다.
    # 매개변수:
    # - patient: str; 설정 소유 환자.
    # - slot: str; 알림 시간대 키.
    # 반환값:
    # - 첫 호출은 None, 이후에는 실제 설정 조회 결과.
    def miss_first(patient: str, slot: str) -> _MedicationAlarm | None:
        nonlocal calls
        calls += 1
        return None if calls == 1 else find(patient, slot)

    with patch.object(control, "_find_setting", side_effect=miss_first):
        response = control.disableAlarmSetting("patient-a", "morning", hour=19, minute=5)
    assert calls == 2
    saved = response["data"]
    assert (saved["hour"], saved["minute"], saved["is_enabled"]) == (19, 5, False)
    assert control.db.query(_MedicationAlarm).count() == 1


# 함수이름: test_failed_commit_rolls_back_both_time_and_enabled_state
# 함수역할:
# - 커밋 실패는 500으로 반환하고 시간 변경과 알림 해제를 함께 롤백하는지 확인한다.
# 매개변수:
# - alarm_api: tuple[TestClient, SetNotification]; 인증된 환자의 알림 HTTP 클라이언트와 컨트롤.
# 반환값:
# - None.
def test_failed_commit_rolls_back_both_time_and_enabled_state(alarm_api: tuple[TestClient, SetNotification]) -> None:
    _, control = alarm_api
    control.saveNotificationSetting("patient-a", "morning", 18, 55)
    with patch.object(control.db, "commit", side_effect=RuntimeError("test failure")):
        with pytest.raises(HTTPException) as error:
            control.disableAlarmSetting("patient-a", "morning", hour=19, minute=5)
    assert error.value.status_code == 500
    saved = control.requestAlarmToggle("patient-a", "morning")["data"]
    assert (saved["hour"], saved["minute"], saved["is_enabled"]) == (18, 55, True)
