"""Tests for legal-holiday lookup and fail-closed behavior."""

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

from boundaries.korean_holiday_api_boundary import KoreanHolidayAPI  # noqa: E402
from boundaries.pharmacy_api_boundary import (  # noqa: E402
    PharmacyApiUnavailableError,
)


@pytest.mark.anyio
async def test_holiday_month_is_parsed_and_cached() -> None:
    request_count = 0

    def respond(_: httpx.Request) -> httpx.Response:
        nonlocal request_count
        request_count += 1
        return httpx.Response(
            200,
            content=(
                b"<response><header><resultCode>00</resultCode></header>"
                b"<body><items><item><locdate>20260817</locdate></item>"
                b"</items></body></response>"
            ),
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(respond))
    boundary = KoreanHolidayAPI(client=client)
    try:
        assert await boundary.isHoliday(date(2026, 8, 17)) is True
        assert await boundary.isHoliday(date(2026, 8, 18)) is False
    finally:
        await client.aclose()

    assert request_count == 1


@pytest.mark.anyio
async def test_holiday_lookup_fails_closed_on_service_error() -> None:
    client = httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _: httpx.Response(503))
    )
    boundary = KoreanHolidayAPI(client=client)
    try:
        with pytest.raises(PharmacyApiUnavailableError):
            await boundary.isHoliday(date(2026, 8, 17))
    finally:
        await client.aclose()
