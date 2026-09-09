# 파일명: test_api_contract.py
# 역할: 프론트엔드와 백엔드의 API 계약 버전 협상 및 불일치 응답을 검증한다.

from fastapi import FastAPI
from fastapi.testclient import TestClient

from core.api_contract import API_CONTRACT_HEADER, ApiContractMiddleware


# 함수이름: _create_test_app
# 함수역할:
# - 계약 버전 미들웨어와 ping 경로만 등록한 FastAPI 앱을 구성한다.
# 매개변수:
# - 없음.
# 반환값:
# - FastAPI: 계약 미들웨어와 ping 경로가 등록된 FastAPI 앱.
def _create_test_app() -> FastAPI:
    app = FastAPI()
    app.add_middleware(
        ApiContractMiddleware,
        contract_version="medbuddy-api-v1",
    )

    # 함수이름: ping
    # 함수역할:
    # - 계약 버전 헤더 검증에 사용할 고정 성공 본문을 제공한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - dict[str, str]: status가 ok인 응답 사전.
    @app.get("/api/v1/ping")
    def ping() -> dict[str, str]:
        return {"status": "ok"}

    return app


# 함수이름: test_api_response_includes_contract_version
# 함수역할:
# - 정상 ping 응답이 200과 서버의 medbuddy-api-v1 계약 헤더를 포함하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_api_response_includes_contract_version() -> None:
    with TestClient(_create_test_app()) as client:
        response = client.get("/api/v1/ping")

    assert response.status_code == 200
    assert response.headers[API_CONTRACT_HEADER] == "medbuddy-api-v1"


# 함수이름: test_mismatched_api_contract_is_rejected
# 함수역할:
# - 다른 계약 버전 요청이 426으로 거절되고 본문과 헤더에 기대 버전이 안내되는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_mismatched_api_contract_is_rejected() -> None:
    with TestClient(_create_test_app()) as client:
        response = client.get(
            "/api/v1/ping",
            headers={API_CONTRACT_HEADER: "medbuddy-api-v2"},
        )

    assert response.status_code == 426
    assert response.json() == {
        "detail": "MedBuddy API contract version is incompatible.",
        "expected_contract": "medbuddy-api-v1",
    }
    assert response.headers[API_CONTRACT_HEADER] == "medbuddy-api-v1"
