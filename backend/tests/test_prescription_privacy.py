"""처방전 원문 개인정보가 외부 제공자로 넘어가지 않는지 검증한다."""

from types import SimpleNamespace
from unittest.mock import AsyncMock
import logging

import pytest
from fastapi import HTTPException

from api.router import OCRParseRequest, analyze_masked_prescription_text
from boundaries.prescription_ocr_boundary import OCRServiceBoundary
from controls.input_prescription_control import InputPrescription
from services.prescription_privacy import PrescriptionPrivacyError, deidentify_prescription_text


_MEDICATION = "타이레놀정 500mg 1정 하루 3회 5일분"
_DATE = "조제일자: 2026-10-22"


@pytest.mark.parametrize("header", [
    "환자명: 홍길동\n생년월일: 1990-01-01\n주소: 서울특별시 종로구 사직로 100\n101동 202호",
    "환자 성명\n생년월일\n연령 / 성별\n홍길동\n1990.01.01\n36세 / 남",
    "성 명 / 생년월일 / 전화번호\n홍길동 1990-01-01 010-1234-5678",
    "Patient name: Alice Example\nDate of birth: 1990-01-01\nAddress: 123 Test Street",
    "차트 번호: A123456\n보험번호: B987654\n의무기록번호: C123456",
    "수진자 성명\n홍길동\n주민등록번호\n900101-1234567",
    "환 자 명\n홍 길 동\n생 년 월 일\n1990.01.01\n주 소\n서울특별시 종로구\n101동 202호",
])
def test_removes_entire_private_header_with_multiline_values(header: str) -> None:
    source = f"{header}\n{_DATE}\n약품명\n{_MEDICATION}"
    safe = deidentify_prescription_text(source)
    assert safe == f"{_DATE}\n약품명\n{_MEDICATION}"
    assert deidentify_prescription_text(safe) == safe


@pytest.mark.parametrize("identifier", [
    "900101-1234567", "9001011234567", "900101—1234567", "900101-*******",
    "900101-1******", "010-1234-5678", "01012345678", "02)1234-5678",
    "+82 10 1234 5678", "alice@example.test", "０１０－１２３４－５６７８",
    "010\u200b-1234-5678",
])
def test_removes_inline_identifiers_without_changing_dose(identifier: str) -> None:
    safe = deidentify_prescription_text(f"{_MEDICATION} {identifier}\n{_DATE}")
    assert safe == f"{_MEDICATION} [REDACTED]\n{_DATE}"
    assert deidentify_prescription_text(safe) == safe


@pytest.mark.parametrize("safe", [
    _MEDICATION,
    f"{_DATE}\n{_MEDICATION}",
    f"처방일\n2026-10-22\n{_MEDICATION}",
    "Drug name | Dose\nExample 5mg 1 tablet daily",
    "처방일자 2026년 10월 22일\n서방성 명칭\n테스트서방정 1정 7일분",
    "약품명\n타이레놀\n1정 1일 3회\n총 5일분",
])
def test_preserves_medication_and_explicit_prescription_dates(safe: str) -> None:
    assert deidentify_prescription_text(safe) == safe


@pytest.mark.parametrize(("private_line", "leftover"), [
    ("서울특별시 종로구 사직로 100", None),
    ("서울특별시 종로구", None),
    ("역삼동 123-4", None),
    ("테헤란로 12길 3", None),
    ("홍길동님", None),
    ("홍길동 님", None),
    ("36세 / 남", None),
    ("101동 202호", None),
    ("1990-01-01", "[REDACTED]"),
])
def test_identifying_lines_without_medication_are_left_out(private_line, leftover) -> None:
    # 약 정보가 없는 식별 줄은 요청 전체를 거부하지 않고 그 줄(날짜는 값)만 빼고 보낸다.
    safe = deidentify_prescription_text(f"{_MEDICATION}\n{private_line}")
    assert safe == (_MEDICATION if leftover is None else f"{_MEDICATION}\n{leftover}")
    for private in ("홍길동", "종로구", "사직로", "1990", "36세", "202호"):
        assert private not in safe
    assert deidentify_prescription_text(safe) == safe


@pytest.mark.parametrize(("source", "expected"), [
    # 약봉투: 환자 이름 줄, 약국 주소·전화, 필요시 용법.
    (
        "홍길동 님\n행복약국\n서울특별시 강남구 테헤란로 123\n02-123-4567\n"
        "타이레놀정500mg 1정 1일 3회 3일분\n아프면 1정씩 복용",
        "행복약국\n[REDACTED]\n타이레놀정500mg 1정 1일 3회 3일분\n아프면 1정씩 복용",
    ),
    # 처방전 양식의 교부 연월일과 투약 기간.
    (
        "교부 연월일 및 번호 2026년 10월 22일 제 00123 호\n"
        "아목시실린캡슐 1캡슐 12시간 간격으로 1캡슐\n투약기간 2026.10.22~2026.10.28",
        "교부 연월일 및 번호 2026년 10월 22일 제 00123 호\n"
        "아목시실린캡슐 1캡슐 12시간 간격으로 1캡슐\n투약기간 2026.10.22~2026.10.28",
    ),
    ("알렌드론산정 70mg 1주 1회 4주 소요", "알렌드론산정 70mg 1주 1회 4주 소요"),
    ("세티리진정 1정 아침저녁으로 1정씩", "세티리진정 1정 아침저녁으로 1정씩"),
    ("이부프로펜정 필요하면 1정, 통증이 심하면 2정", "이부프로펜정 필요하면 1정, 통증이 심하면 2정"),
    ("다음 진료일 2026-11-01\n" + _MEDICATION, "다음 진료일 2026-11-01\n" + _MEDICATION),
    # 두 자리 이상 숫자도 끝까지 읽고 단위를 본다(번지로 오인하면 거부되거나 용법 줄이 빠졌다).
    ("타이레놀정 500mg\n아프면 12시간 간격으로 1정씩 복용", "타이레놀정 500mg\n아프면 12시간 간격으로 1정씩 복용"),
    ("챔프시럽\n열나면 10ml씩 복용", "챔프시럽\n열나면 10ml씩 복용"),
    ("세티리진정 10mg 1일 1회 자기전\n가려우면 24시간에 1정까지", "세티리진정 10mg 1일 1회 자기전\n가려우면 24시간에 1정까지"),
    # OCR이 띄운 "4 주"와 다음 줄의 "소…" 약 이름은 주소 라벨이 아니다.
    ("복용기간 4 주\n소론도정 5mg 1일 1회", "복용기간 4 주\n소론도정 5mg 1일 1회"),
    ("4 주 소론도정 5mg", "4 주 소론도정 5mg"),
])
def test_realistic_prescription_and_bag_text_is_analysed(source: str, expected: str) -> None:
    assert deidentify_prescription_text(source) == expected


_UNSAFE = [
    f"환자명 홍길동 {_MEDICATION}",
    f"환자명 홍길동 {_DATE}\n{_MEDICATION}",
    f"홍길동님 {_MEDICATION}",
    f"서울특별시 종로구 사직로 100 {_MEDICATION}",
    f"36세 / 남 {_MEDICATION}",
    f"{_MEDICATION}\x00",
    "환자명\n홍길동\n생년월일\n1990-01-01",
    "환자명 홍길동\n타이레놀\n1정 1일 3회",
    "900101-1234567",
]


@pytest.mark.parametrize("source", _UNSAFE)
def test_rejects_ambiguous_or_residual_high_risk_text(source: str) -> None:
    with pytest.raises(PrescriptionPrivacyError) as failure:
        deidentify_prescription_text(source)
    assert "홍길동" not in str(failure.value)
    assert "1990" not in str(failure.value)
    assert "900101" not in str(failure.value)


@pytest.mark.anyio
@pytest.mark.parametrize("source", _UNSAFE)
async def test_unsafe_text_never_calls_provider_or_control_boundary(source: str) -> None:
    generate = AsyncMock()
    boundary = OCRServiceBoundary(
        client=object(), model_name="test", response_schema={},
        gemini_text_client=SimpleNamespace(generate_text_content=generate),
    )
    with pytest.raises(PrescriptionPrivacyError):
        await boundary.extractPrescriptionTextData(source)
    generate.assert_not_awaited()

    extract = AsyncMock()
    control = InputPrescription(
        client=object(), ocr_service_boundary=SimpleNamespace(extractPrescriptionTextData=extract),
        medication_name_verifier=object(),
    )
    with pytest.raises(PrescriptionPrivacyError):
        await control.requestPrescriptionText(source)
    extract.assert_not_awaited()


@pytest.mark.anyio
async def test_provider_receives_only_redacted_content_and_logs_no_pii(caplog) -> None:
    caplog.set_level(logging.INFO)
    generate = AsyncMock(return_value=SimpleNamespace(text="{}"))
    client = SimpleNamespace(aio=SimpleNamespace(models=SimpleNamespace(generate_content=generate)))
    boundary = OCRServiceBoundary(client=client, model_name="test", response_schema={})
    source = f"환자명 홍길동\n생년월일 1990-01-01\n{_DATE}\n{_MEDICATION} 010-1234-5678"
    assert await boundary.extractPrescriptionTextData(source) == "{}"
    sent = generate.await_args.kwargs["contents"][1]
    assert sent == f"{_DATE}\n{_MEDICATION} [REDACTED]"
    assert "input_characters=" in caplog.text
    for private in ("홍길동", "1990", "010-1234-5678"):
        assert private not in caplog.text
        assert private not in sent


@pytest.mark.anyio
async def test_control_sanitizes_before_injected_ocr_boundary() -> None:
    extract = AsyncMock(return_value='{"medications": []}')
    verifier = SimpleNamespace(verify_many=AsyncMock(return_value=[]))
    control = InputPrescription(
        client=object(), medication_name_verifier=verifier,
        ocr_service_boundary=SimpleNamespace(extractPrescriptionTextData=extract),
    )
    await control.requestPrescriptionText(f"환자명 홍길동\n{_DATE}\n{_MEDICATION}")
    extract.assert_awaited_once_with(f"{_DATE}\n{_MEDICATION}")


def test_existing_secondary_response_masking_is_preserved() -> None:
    control = InputPrescription(client=object(), medication_name_verifier=object(), ocr_service_boundary=object())
    assert control._apply_secondary_masking({"hospital_name": "900101-1234567"}) == {
        "hospital_name": "900101-*******",
    }


def test_existing_device_redaction_markers_and_ocr_spacing_are_safe() -> None:
    safe = deidentify_prescription_text(f"Drug  name | Dose\n{_MEDICATION} [연락처 제거] [주민번호 제거] [이메일 제거]")
    assert safe == f"Drug name | Dose\n{_MEDICATION} [REDACTED] [REDACTED] [REDACTED]"


@pytest.mark.parametrize("row", [
    "씨잘정5밀리그램 1정 1일 1회 7일분",
    "크레스토정10밀리그램 1정 1일 1회 30일분",
    "트라젠타듀오정2.5/500밀리그램 1정 1일 2회 30일분",
    "엘도스캡슐 1캡슐 1일 3회 5일분",
    "듀파락이지시럽 15ml 1일 1회 7일분",
    "메트포르민",
    "아모잘탄정5/50밀리그램",
    "라식스정 0.5정 주 1회 28일분",
])
def test_legitimate_korean_medication_rows_are_not_treated_as_patient_names(row: str) -> None:
    assert deidentify_prescription_text(row) == row
    assert deidentify_prescription_text(f"환자명 홍길동\n약품명\n{row}") == f"약품명\n{row}"


def test_unicode_ocr_unit_normalization_preserves_medication_meaning() -> None:
    assert deidentify_prescription_text("타이레놀정 500㎎ 1정") == "타이레놀정 500mg 1정"


def test_bare_words_are_not_silently_guessed_to_be_patient_names() -> None:
    # 약명과 이름을 낱말 길이만으로 구분할 수 없어 미탐지 한계를 명시적으로 남긴다.
    assert deidentify_prescription_text("홍길동") == "홍길동"


@pytest.mark.anyio
async def test_privacy_rejection_returns_safe_400_without_external_call(caplog) -> None:
    caplog.set_level(logging.DEBUG)
    extract = AsyncMock()
    control = InputPrescription(
        client=object(), medication_name_verifier=object(),
        ocr_service_boundary=SimpleNamespace(extractPrescriptionTextData=extract),
    )
    with pytest.raises(HTTPException) as failure:
        await analyze_masked_prescription_text(
            OCRParseRequest(text=f"환자명 홍길동 {_MEDICATION}"), control,
        )
    assert failure.value.status_code == 400
    assert "개인정보" in failure.value.detail
    assert "홍길동" not in failure.value.detail
    assert "홍길동" not in caplog.text
    extract.assert_not_awaited()
