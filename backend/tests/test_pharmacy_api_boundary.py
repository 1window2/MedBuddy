# 파일명: test_pharmacy_api_boundary.py
# 역할: 약국 공공데이터 경계의 응답 검증, 제한과 오류 변환을 확인한다.

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

from boundaries.pharmacy_api_boundary import (  # noqa: E402
    NationalEmergencyMedicalCenterPharmacyAPI,
    PharmacyApiResponseError,
    PharmacyApiUnavailableError,
)


_VALID_XML = b"""<?xml version="1.0" encoding="UTF-8"?>
<response>
  <header><resultCode>00</resultCode><resultMsg>NORMAL SERVICE.</resultMsg></header>
  <body>
    <items>
      <item>
        <hpid>C1234</hpid>
        <dutyName>MedBuddy Pharmacy</dutyName>
        <dutyAddr>Seoul</dutyAddr>
        <dutyTel1>02-123-4567</dutyTel1>
        <latitude>37.5665</latitude>
        <longitude>126.9780</longitude>
        <distance>0.42</distance>
        <startTime>0900</startTime>
        <endTime>2400</endTime>
      </item>
    </items>
  </body>
</response>
"""


def test_parse_records_extracts_only_required_pharmacy_fields() -> None:
    records = NationalEmergencyMedicalCenterPharmacyAPI._parse_records(
        _VALID_XML
    )

    assert len(records) == 1
    assert records[0].pharmacy_id == "C1234"
    assert records[0].name == "MedBuddy Pharmacy"
    assert records[0].distance_km == 0.42
    assert records[0].start_time == "0900"
    assert records[0].end_time == "2400"


def test_parse_records_rejects_public_api_error_header() -> None:
    payload = b"<response><header><resultCode>22</resultCode></header></response>"

    with pytest.raises(PharmacyApiUnavailableError):
        NationalEmergencyMedicalCenterPharmacyAPI._parse_records(payload)


def test_parse_records_rejects_invalid_xml() -> None:
    with pytest.raises(PharmacyApiResponseError):
        NationalEmergencyMedicalCenterPharmacyAPI._parse_records(b"not xml")


@pytest.mark.anyio
async def test_search_nearby_uses_location_api_without_exposing_key() -> None:
    captured_request: httpx.Request | None = None

    def respond(request: httpx.Request) -> httpx.Response:
        nonlocal captured_request
        captured_request = request
        return httpx.Response(200, content=_VALID_XML)

    client = httpx.AsyncClient(transport=httpx.MockTransport(respond))
    boundary = NationalEmergencyMedicalCenterPharmacyAPI(client=client)
    try:
        records = await boundary.searchNearby(
            latitude=37.5665,
            longitude=126.9780,
            limit=10,
        )
    finally:
        await client.aclose()

    assert len(records) == 1
    assert captured_request is not None
    assert captured_request.url.path.endswith("/getParmacyLcinfoInqire")
    assert captured_request.url.params["WGS84_LAT"] == "37.5665000"
    assert captured_request.url.params["WGS84_LON"] == "126.9780000"
    assert captured_request.url.params["numOfRows"] == "10"
