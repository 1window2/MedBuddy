# 파일명: test_pharmacy_api_boundary.py
# 역할: 약국 공공 API의 위치 요청, XML 오류 분류 및 운영시간 추출을 검증한다.

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

_VALID_CATALOG_XML = b"""<?xml version="1.0" encoding="UTF-8"?>
<response>
  <header><resultCode>00</resultCode></header>
  <body>
    <items><item>
      <hpid>C1234</hpid><dutyName>MedBuddy Pharmacy</dutyName>
      <dutyAddr>Seoul</dutyAddr><dutyTel1>02-123-4567</dutyTel1>
      <wgs84Lat>37.5665</wgs84Lat><wgs84Lon>126.9780</wgs84Lon>
      <dutyTime1s>0900</dutyTime1s><dutyTime1c>1800</dutyTime1c>
      <dutyTime8s>2200</dutyTime8s><dutyTime8c>0100</dutyTime8c>
    </item></items><totalCount>1</totalCount>
  </body>
</response>
"""


# 함수이름: test_parse_records_extracts_only_required_pharmacy_fields
# 함수역할:
# - 유효 XML에서 약국 식별자·이름·거리·09시부터 24시까지의 영업시간을 추출하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
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


# 함수이름: test_parse_records_rejects_public_api_error_header
# 함수역할:
# - 공공 API 오류 헤더를 서비스 사용 불가 오류로 처리하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_parse_records_rejects_public_api_error_header() -> None:
    payload = b"<response><header><resultCode>22</resultCode></header></response>"

    with pytest.raises(PharmacyApiUnavailableError):
        NationalEmergencyMedicalCenterPharmacyAPI._parse_records(payload)


# 함수이름: test_parse_records_rejects_invalid_xml
# 함수역할:
# - 잘못된 XML을 약국 응답 형식 오류로 구분하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_parse_records_rejects_invalid_xml() -> None:
    with pytest.raises(PharmacyApiResponseError):
        NationalEmergencyMedicalCenterPharmacyAPI._parse_records(b"not xml")


# 함수이름: test_search_nearby_uses_location_api_without_exposing_key
# 함수역할:
# - 위치 API 경로에 정밀 좌표와 결과 상한을 전달하여 약국 레코드를 얻는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
@pytest.mark.anyio
async def test_search_nearby_uses_location_api_without_exposing_key() -> None:
    captured_request: httpx.Request | None = None

    # 함수이름: respond
    # 함수역할:
    # - 외부 전송 없이 HTTP 요청을 기록하고 검증용 정상 약국 XML을 반환한다.
    # 매개변수:
    # - request (httpx.Request): 대체 응답 선택 또는 검증에 사용할 가로챈 HTTP 요청.
    # 반환값:
    # - httpx.Response: 해당 검증 조건의 XML이 포함된 시험용 HTTP 200 응답.
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


# Function Name: test_parse_catalog_page_preserves_weekly_and_holiday_hours
# Description:
# - Preserves weekday and holiday schedule slots, including a 22:00-01:00 overnight holiday
#   range.
# Parameters:
# - None.
# Returns:
# - None.
def test_parse_catalog_page_preserves_weekly_and_holiday_hours() -> None:
    records, total_count = (
        NationalEmergencyMedicalCenterPharmacyAPI._parse_catalog_page(
            _VALID_CATALOG_XML
        )
    )

    assert total_count == 1
    assert records[0].weekly_hours["1"] == ("0900", "1800")
    assert records[0].weekly_hours["8"] == ("2200", "0100")
