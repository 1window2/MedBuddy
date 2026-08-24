"""Tests for the exact-date NEMC holiday pharmacy roster boundary."""

import os
import sys
from datetime import date
from pathlib import Path

import httpx
import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from boundaries.holiday_emergency_pharmacy_api_boundary import (  # noqa: E402
    HolidayEmergencyPharmacyAPI,
)


@pytest.mark.anyio
async def test_exact_date_schedule_is_parsed_and_query_is_pharmacy_only() -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        assert request.url.params["QD"] == "H"
        assert request.url.params["QT"] == "20260925"
        return httpx.Response(
            200,
            content=b"""
            <response><header><resultCode>00</resultCode></header><body>
              <totalCount>1</totalCount><items><item>
                <hpid>C1234</hpid>
                <dutyDay1>2026-09-25</dutyDay1>
                <dutyDaytime1>09:00~17:30</dutyDaytime1>
                <dutyDayEtc>Call before visiting</dutyDayEtc>
              </item></items>
            </body></response>
            """,
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(respond))
    boundary = HolidayEmergencyPharmacyAPI(client=client)
    try:
        result = await boundary.fetchSchedules(date(2026, 9, 25))
    finally:
        await client.aclose()

    assert len(result) == 1
    assert result[0].pharmacy_id == "C1234"
    assert result[0].start_time == "0900"
    assert result[0].end_time == "1730"


def test_invalid_time_range_is_not_claimed_as_date_specific() -> None:
    import xml.etree.ElementTree as ElementTree

    item = ElementTree.fromstring(
        "<item><hpid>C1234</hpid><dutyDay1>2026-09-25</dutyDay1>"
        "<dutyDaytime1>contact pharmacy</dutyDaytime1></item>"
    )

    assert (
        HolidayEmergencyPharmacyAPI._parse_item(item, date(2026, 9, 25))
        is None
    )
