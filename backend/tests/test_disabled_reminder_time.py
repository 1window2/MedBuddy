from unittest.mock import patch

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

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


@pytest.fixture
def alarm_api(fk_db):
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


@pytest.mark.parametrize("initially_enabled", [None, False, True])
def test_disable_saves_time_atomically_and_keeps_patient_scope(alarm_api, initially_enabled):
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


@pytest.mark.parametrize("body", [None, {}, {"hour": None, "minute": None}])
def test_legacy_disable_without_time_preserves_saved_time(alarm_api, body):
    client, control = alarm_api
    control.saveNotificationSetting("patient-a", "morning", 18, 55)
    response = client.patch("/notification/settings/morning/disable", json=body)
    assert response.status_code == 200
    saved = response.json()["data"]
    assert (saved["hour"], saved["minute"], saved["is_enabled"]) == (18, 55, False)


@pytest.mark.parametrize("body", [
    {"hour": -1, "minute": 0},
    {"hour": 24, "minute": 0},
    {"hour": 19, "minute": -1},
    {"hour": 19, "minute": 60},
    {"minute": 5},
    {"hour": None, "minute": 5},
    {"hour": "invalid", "minute": 5},
])
def test_invalid_disabled_time_is_rejected_before_mutation(alarm_api, body):
    client, control = alarm_api
    control.saveNotificationSetting("patient-a", "morning", 18, 55)
    response = client.patch("/notification/settings/morning/disable", json=body)
    assert response.status_code == 422
    saved = control.requestAlarmToggle("patient-a", "morning")["data"]
    assert (saved["hour"], saved["minute"], saved["is_enabled"]) == (18, 55, True)


@pytest.mark.parametrize("time", [(24, 0), (19, 60), (None, 5)])
def test_control_also_validates_disabled_time(alarm_api, time):
    _, control = alarm_api
    with pytest.raises(HTTPException) as error:
        control.disableAlarmSetting("patient-a", "morning", hour=time[0], minute=time[1])
    assert error.value.status_code == 400
    assert control.db.query(_MedicationAlarm).count() == 0


@pytest.mark.parametrize("initially_enabled", [None, False, True])
@pytest.mark.parametrize("body", [{"hour": 19}, {"hour": 19, "minute": None}])
def test_hour_only_disable_defaults_to_zero_minutes(alarm_api, initially_enabled, body):
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


def test_control_hour_only_disable_keeps_upstream_positional_contract(alarm_api):
    _, control = alarm_api
    control.saveNotificationSetting("patient-a", "morning", 18, 55)
    saved = control.disableAlarmSetting("patient-a", "morning", 19)["data"]
    assert (saved["hour"], saved["minute"], saved["is_enabled"]) == (19, 0, False)


def test_disable_conflict_recovery_keeps_new_time(alarm_api):
    _, control = alarm_api
    control.saveNotificationSetting("patient-a", "morning", 18, 55)
    find = control._find_setting
    calls = 0

    def miss_first(patient, slot):
        nonlocal calls
        calls += 1
        return None if calls == 1 else find(patient, slot)

    with patch.object(control, "_find_setting", side_effect=miss_first):
        response = control.disableAlarmSetting("patient-a", "morning", hour=19, minute=5)
    assert calls == 2
    saved = response["data"]
    assert (saved["hour"], saved["minute"], saved["is_enabled"]) == (19, 5, False)
    assert control.db.query(_MedicationAlarm).count() == 1


def test_failed_commit_rolls_back_both_time_and_enabled_state(alarm_api):
    _, control = alarm_api
    control.saveNotificationSetting("patient-a", "morning", 18, 55)
    with patch.object(control.db, "commit", side_effect=RuntimeError("test failure")):
        with pytest.raises(HTTPException) as error:
            control.disableAlarmSetting("patient-a", "morning", hour=19, minute=5)
    assert error.value.status_code == 500
    saved = control.requestAlarmToggle("patient-a", "morning")["data"]
    assert (saved["hour"], saved["minute"], saved["is_enabled"]) == (18, 55, True)
