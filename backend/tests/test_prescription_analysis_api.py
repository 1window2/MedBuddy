# 파일명: test_prescription_analysis_api.py
# 역할: 처방 텍스트 분석 API의 입력 전달과 분석 배치 식별자 보존을 검증한다.

import os
import sys
from pathlib import Path

import httpx
import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from api.dependencies import (  # noqa: E402
    get_input_prescription,
    get_registered_principal,
)
from entities.authenticated_principal_entity import (  # noqa: E402
    AuthenticatedPrincipal,
)
from main import create_app  # noqa: E402


# 클래스명: _PrescriptionTextAnalysisStub
# 역할: 수신 텍스트를 기록하고 배치 ID가 있는 고정 처방 분석 결과를 제공하는 대체 control이다.
# 주요 책임:
# - 전달된 처방 텍스트를 기록하고 단일 약·기관·처방일·배치 및 파싱 건수 결과를 반환한다.
# 속성:
# - received_text (str): 분석 대체 객체가 기록한 처방 텍스트.
class _PrescriptionTextAnalysisStub:
    # 함수이름: __init__
    # 함수역할:
    # - 분석 요청 전 수신 텍스트 기록을 빈 문자열로 준비한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def __init__(self) -> None:
        self.received_text = ""

    # 함수이름: requestPrescriptionText
    # 함수역할:
    # - 전달된 처방 텍스트를 기록하고 단일 약·기관·처방일·배치 및 파싱 건수 결과를 반환한다.
    # 매개변수:
    # - text (str): 응답 또는 처방 분석 대체 객체가 보관할 텍스트.
    # 반환값:
    # - dict[str, object]: 고정 배치 ID와 파싱된 약 한 건을 유지한 처방 결과.
    async def requestPrescriptionText(self, text: str) -> dict[str, object]:
        self.received_text = text
        return {
            "hospital_name": "테스트 의원",
            "prescription_date": "2026-08-22",
            "prescription_batch_id": "batch_1234567890abcdef",
            "medications": [
                {
                    "prescription_date": "2026-08-22",
                    "drug_name": "테스트정",
                    "raw_drug_name": "테스트정",
                    "name_confidence": 0.98,
                    "name_correction_source": "public_data",
                    "dosage_per_time": "1정",
                    "daily_frequency": "3회",
                    "total_days": "3일",
                }
            ],
            "raw_medication_count": 1,
            "parsed_medication_count": 1,
            "skipped_medication_count": 0,
        }


# 함수이름: test_analysis_response_preserves_prescription_batch_id
# 함수역할:
# - 분석 API가 텍스트를 control에 그대로 전달하고 성공 응답에 같은 처방 배치 ID를 유지하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
@pytest.mark.anyio
async def test_analysis_response_preserves_prescription_batch_id() -> None:
    control = _PrescriptionTextAnalysisStub()
    app = create_app()
    app.dependency_overrides[get_input_prescription] = lambda: control
    app.dependency_overrides[get_registered_principal] = (
        AuthenticatedPrincipal.development_principal
    )

    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.post(
            "/api/v1/medication/analyze-prescription-text",
            json={"text": "테스트정 1정 1일 3회 3일"},
        )

    assert response.status_code == 200
    assert control.received_text == "테스트정 1정 1일 3회 3일"
    assert response.json()["prescription_batch_id"] == "batch_1234567890abcdef"
