# 파일명: test_user_setting_revision_api.py
# 역할: 설정 HTTP 경로의 인증 계정 범위, 개정 전달과 충돌 후 최신 값 보존을 검증한다.

"""설정 API의 버전 전달, 충돌 응답, 인증된 계정 범위를 검증한다."""

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from api.dependencies import (
    get_authenticated_principal, get_authorization_control, get_manage_user_setting,
)
from api.router import get_user_setting, save_user_setting
from controls.authorization_control import AuthorizationControl
from controls.manage_user_setting_control import ManageUserSetting
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.user_setting_entity import _UserSetting
from support.db import seed_account


# 함수이름: test_setting_http_revision_check_preserves_owner_and_latest_value
# 함수역할:
# - 설정 HTTP 요청은 인증된 계정만 수정하고 개정 충돌을 409로 반환하여 최신 알림 값을 보존하는지 확인한다.
# 매개변수:
# - fk_db: Session; 외래 키가 활성화된 격리 데이터베이스.
# 반환값:
# - None.
def test_setting_http_revision_check_preserves_owner_and_latest_value(fk_db: Session) -> None:
    principal = AuthenticatedPrincipal(
        subject="synthetic-owner", issuer="test", user_hash="owner",
    )
    seed_account(fk_db, "owner", "other")
    app = FastAPI()
    app.add_api_route("/settings/user", get_user_setting, methods=["GET"])
    app.add_api_route("/settings/user", save_user_setting, methods=["PUT"])
    app.dependency_overrides[get_authenticated_principal] = lambda: principal
    app.dependency_overrides[get_authorization_control] = lambda: AuthorizationControl(fk_db)
    app.dependency_overrides[get_manage_user_setting] = lambda: ManageUserSetting(fk_db)
    payload = {
        "font_size": 16, "reading_speed": 1.0, "language": "ko",
        "medication_notifications_enabled": False, "expected_revision": 0,
    }
    with TestClient(app) as client:
        initial = client.get("/settings/user?user_hash=other")
        assert initial.json()["revision"] == 0
        assert initial.json()["data"]["user_hash"] == "owner"
        saved = client.put("/settings/user?user_hash=other", json=payload)
        assert saved.status_code == 200
        assert saved.json()["revision"] == 1
        late = client.put("/settings/user", json={
            **payload, "medication_notifications_enabled": True,
        })
        assert late.status_code == 409
        assert late.json()["detail"] == {
            "code": "settings_revision_conflict", "revision": 1,
        }
        assert client.get("/settings/user").json()["data"]["medication_notifications_enabled"] is False
    assert fk_db.query(_UserSetting).filter_by(user_hash="other").count() == 0
