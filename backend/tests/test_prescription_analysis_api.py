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
# - hospital_name (str): 결과에 넣을 병원 이름.
# - medication_fields (dict[str, object]): 결과의 약 한 건에서 고정값을 대신할 필드.
class _PrescriptionTextAnalysisStub:
    # 함수이름: __init__
    # 함수역할:
    # - 분석 요청 전 수신 텍스트 기록을 빈 문자열로 준비하고 사례별로 바꿀 결과 값을 보관한다.
    # 매개변수:
    # - hospital_name (str): 결과에 넣을 병원 이름.
    # - medication_fields (object): 결과의 약 한 건에서 고정값을 대신할 필드.
    # 반환값:
    # - 없음 (None).
    def __init__(
        self,
        hospital_name: str = "테스트 의원",
        **medication_fields: object,
    ) -> None:
        self.received_text = ""
        self.hospital_name = hospital_name
        self.medication_fields = medication_fields

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


# 함수이름: _analyze
# 함수역할:
# - 대체 control을 주입한 실제 앱에 처방 텍스트 분석을 요청한다.
# 매개변수:
# - control (_PrescriptionTextAnalysisStub): 분석 결과를 제공할 대체 control.
# - text (str): 요청 본문에 담을 처방 텍스트.
# 반환값:
# - httpx.Response: 분석 API 응답.
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

    response = await _analyze(control)

    assert response.status_code == 200
    assert control.received_text == "테스트정 1정 1일 3회 3일"
    assert response.json()["prescription_batch_id"] == "batch_1234567890abcdef"
    medication = response.json()["medications"][0]
    assert response.json()["hospital_name"] == "테스트 의원"
    assert medication["dosage_per_time"] == "1정"
    assert medication["daily_frequency"] == "3회"


# 함수이름: test_overlong_ai_text_is_truncated_instead_of_failing_the_analysis
# 함수역할:
# - AI가 길이 제한을 넘는 용량·횟수·병원 이름을 돌려줘도 분석이 200으로 끝나고,
#   넘친 값은 제한 길이 이내로 줄어 말줄임표로 끝나며 나머지 결과는 그대로인지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_truncation_never_leaves_part_of_a_number
# 함수역할:
# - 제한 길이가 숫자 중간에 걸리면 끊긴 숫자를 통째로 빼서 남은 앞자리가 다른 용량으로 읽히지 않는지,
#   제한 길이와 정확히 같은 값은 바뀌지 않는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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
