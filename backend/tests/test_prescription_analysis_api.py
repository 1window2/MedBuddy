# 파일명: test_prescription_analysis_api.py
# 역할: 처방전 텍스트 분석 API의 외부 응답 계약을 검증한다.

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


class _PrescriptionTextAnalysisStub:
    def __init__(self) -> None:
        self.received_text = ""

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
