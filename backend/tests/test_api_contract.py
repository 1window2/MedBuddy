# 파일명: test_api_contract.py
# 역할: 프론트엔드와 백엔드의 API 계약 버전 협상 규칙을 검증한다.

from fastapi import FastAPI
from fastapi.testclient import TestClient

from core.api_contract import API_CONTRACT_HEADER, ApiContractMiddleware


def _create_test_app() -> FastAPI:
    app = FastAPI()
    app.add_middleware(
        ApiContractMiddleware,
        contract_version="medbuddy-api-v1",
    )

    @app.get("/api/v1/ping")
    def ping() -> dict[str, str]:
        return {"status": "ok"}

    return app


def test_api_response_includes_contract_version() -> None:
    with TestClient(_create_test_app()) as client:
        response = client.get("/api/v1/ping")

    assert response.status_code == 200
    assert response.headers[API_CONTRACT_HEADER] == "medbuddy-api-v1"


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
