# 파일명: test_prescription_analysis_api.py
# 역할: 처방 텍스트 분석 API의 입력 전달과 분석 배치 식별자 보존을 검증한다.

import json
import os
import sys
from pathlib import Path

import httpx
import pytest
from pydantic import ValidationError

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from api.dependencies import (  # noqa: E402
    get_input_prescription,
    get_registered_principal,
)
from api.router import OCRParseRequest  # noqa: E402
from entities.authenticated_principal_entity import (  # noqa: E402
    AuthenticatedPrincipal,
)
from main import create_app  # noqa: E402


# Class Name: _PrescriptionTextAnalysisStub
# Role: Provides a configurable single-medication prescription analysis response.
# Responsibilities:
# - Record submitted text and return fixed institution, date, batch identity, and parse counts with field overrides.
# Attributes:
# - received_text (str): captured input. hospital_name (str): response institution. medication_fields (dict[str, object]): overridden medication fields.
class _PrescriptionTextAnalysisStub:
    # Function Name: __init__
    # Description:
    # - Initialize captured text and configurable institution and medication fields.
    # Parameters:
    # - hospital_name: str; hospital name placed in the response.
    # - medication_fields: object; keyword field overrides collected into the medication mapping.
    # Returns:
    # - None.
    def __init__(
        self,
        hospital_name: str = "테스트 의원",
        **medication_fields: object,
    ) -> None:
        self.received_text = ""
        self.hospital_name = hospital_name
        self.medication_fields = medication_fields

    # Function Name: requestPrescriptionText
    # Description:
    # - Capture submitted text and return one parsed medication with fixed institution, date, batch, and counts.
    # Parameters:
    # - text: str; prescription text to record.
    # Returns:
    # - dict[str, object]; synthetic one-medication analysis result.
    async def requestPrescriptionText(self, text: str) -> dict[str, object]:
        self.received_text = text
        return {
            "hospital_name": self.hospital_name,
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
                    **self.medication_fields,
                }
            ],
            "raw_medication_count": 1,
            "parsed_medication_count": 1,
            "skipped_medication_count": 0,
        }


# Function Name: _analyze
# Description:
# - Request prescription text analysis through the app with an injected analysis control.
# Parameters:
# - control: _PrescriptionTextAnalysisStub; configured analysis result provider.
# - text: str; prescription text in the request body.
# Returns:
# - httpx.Response; analysis endpoint response.
async def _analyze(
    control: _PrescriptionTextAnalysisStub,
    text: str = "테스트정 1정 1일 3회 3일",
) -> httpx.Response:
    app = create_app()
    app.dependency_overrides[get_input_prescription] = lambda: control
    app.dependency_overrides[get_registered_principal] = (
        AuthenticatedPrincipal.development_principal
    )

    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        return await client.post(
            "/api/v1/medication/analyze-prescription-text",
            json={"text": text},
        )


# Function Name: test_analysis_response_preserves_prescription_batch_id
# Description:
# - Pass prescription text unchanged to the control and retain its batch identifier in the successful API response.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_analysis_response_preserves_prescription_batch_id() -> None:
    control = _PrescriptionTextAnalysisStub()

    response = await _analyze(control)

    assert response.status_code == 200
    assert control.received_text == "테스트정 1정 1일 3회 3일"
    assert response.json()["prescription_batch_id"] == "batch_1234567890abcdef"
    medication = response.json()["medications"][0]
    assert response.json()["hospital_name"] == "테스트 의원"
    assert medication["dosage_per_time"] == "1정"
    assert medication["daily_frequency"] == "3회"


# Function Name: test_overlong_ai_text_is_truncated_instead_of_failing_the_analysis
# Description:
# - Return HTTP 200 when AI text exceeds field limits, truncating affected values with an ellipsis while retaining other results.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_overlong_ai_text_is_truncated_instead_of_failing_the_analysis() -> None:
    dosage = ("1정씩 식후 30분에 물과 함께 " * 9)[:150]
    frequency = "하루 세 번 " * 20
    assert len(dosage) == 150 and len(frequency) == 140
    control = _PrescriptionTextAnalysisStub(
        hospital_name="가" * 600,
        dosage_per_time=dosage,
        daily_frequency=frequency,
    )

    response = await _analyze(control)

    assert response.status_code == 200, response.text
    body = response.json()
    medication = body["medications"][0]
    assert medication["dosage_per_time"] == dosage[:99] + "…"
    assert medication["daily_frequency"] == frequency[:99] + "…"
    assert body["hospital_name"] == "가" * 499 + "…"
    assert medication["drug_name"] == "테스트정"
    assert medication["total_days"] == "3일"
    assert body["prescription_batch_id"] == "batch_1234567890abcdef"
    assert body["parsed_medication_count"] == 1


# Function Name: test_truncation_never_leaves_part_of_a_number
# Description:
# - Remove a whole number crossed by the truncation boundary and preserve values exactly at the length limit.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_truncation_never_leaves_part_of_a_number() -> None:
    split_number = "가" * 97 + "1250mg"
    split_decimal = "나" * 96 + "0.25정 추가"
    exact_limit = "다" * 99 + "3"
    control = _PrescriptionTextAnalysisStub(
        dosage_per_time=split_number,
        daily_frequency=split_decimal,
        total_days=exact_limit,
    )

    response = await _analyze(control)

    assert response.status_code == 200, response.text
    medication = response.json()["medications"][0]
    assert medication["dosage_per_time"] == "가" * 97 + "…"
    assert medication["daily_frequency"] == "나" * 96 + "…"
    assert medication["total_days"] == exact_limit


# Class Name: _FailingAnalysis
# Role: Analysis control double that raises a prepared error.
# Responsibilities:
# - Stands in for the control so the route's error mapping can be checked.
# Attributes:
# - error (Exception): Error raised by the analysis.
class _FailingAnalysis:
    # Function Name: __init__
    # Description: Stores the error to raise.
    # Parameters: error (Exception) - Error raised by the analysis.
    # Returns: None.
    def __init__(self, error: Exception) -> None:
        self.error = error

    # Function Name: requestPrescriptionText
    # Description: Raises the prepared error instead of analysing the text.
    # Parameters: text (str) - Ignored prescription text.
    # Returns: Never returns.
    async def requestPrescriptionText(self, text: str) -> dict[str, object]:
        raise self.error


# Function Name: test_invalid_ai_reply_is_an_upstream_error
# Description:
# - An AI reply that is not the agreed JSON object is answered with 502 and a retry hint, not
#   with 400: the request itself was valid.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_invalid_ai_reply_is_an_upstream_error() -> None:
    from services.prescription_parser import PrescriptionAnalysisFormatError

    response = await _analyze(
        _FailingAnalysis(PrescriptionAnalysisFormatError("AI returned an invalid JSON response."))
    )

    assert response.status_code == 502
    assert response.json()["detail"] == "처방전 분석 결과를 해석하지 못했습니다. 다시 시도해주세요."


# Function Name: test_parser_errors_are_not_returned_to_the_client
# Description:
# - A message a control raises on purpose is returned with HTTP 400, while a JSON or validation
#   error raised by a parsing library, whose text quotes positions and input values, becomes
#   the generic HTTP 500 answer.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_parser_errors_are_not_returned_to_the_client() -> None:
    intended = await _analyze(_FailingAnalysis(ValueError("Masked prescription text is empty.")))
    assert intended.status_code == 400
    assert intended.json()["detail"] == "Masked prescription text is empty."

    try:
        json.loads('{"drug_name": "비밀약", ')
    except json.JSONDecodeError as exc:
        decode_error = exc
    leaked = await _analyze(_FailingAnalysis(decode_error))
    assert leaked.status_code == 500
    assert "Expecting" not in leaked.text and "char" not in leaked.text

    try:
        OCRParseRequest.model_validate({"text": {"secret": "비밀약"}})
    except ValidationError as exc:
        validation_error = exc
    leaked = await _analyze(_FailingAnalysis(validation_error))
    assert leaked.status_code == 500
    assert "비밀약" not in leaked.text and "input" not in leaked.text
