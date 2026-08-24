# 파일명: pharmacy_api_boundary.py
# 역할: 국립중앙의료원 전국 약국 정보 조회 서비스 경계를 제공한다.

"""국립중앙의료원 전국 약국 정보 조회 서비스 경계."""

import asyncio
import logging
import xml.etree.ElementTree as ElementTree
from typing import Protocol

import httpx

from core.config import settings
from entities.nearby_pharmacy_entity import PharmacyLocationRecord
from entities.pharmacy_catalog_entity import PharmacyCatalogEntry

logger = logging.getLogger(__name__)

_LOCATION_SEARCH_PATH = "/getParmacyLcinfoInqire"
_FULL_CATALOG_PATH = "/getParmacyFullDown"
_MAX_RESPONSE_BYTES = 4 * 1024 * 1024


class PharmacyApiUnavailableError(RuntimeError):
    """약국 공공데이터 서비스에 일시적으로 접근할 수 없을 때 발생한다."""


class PharmacyApiResponseError(RuntimeError):
    """약국 공공데이터 응답 형식이 계약과 다를 때 발생한다."""


# 프로토콜명: PharmacyLookupBoundary
# 역할:
# - Control이 특정 HTTP 구현을 알지 않고 위치 기반 약국 검색을 요청하게 한다.
class PharmacyLookupBoundary(Protocol):
    async def searchNearby(
        self,
        *,
        latitude: float,
        longitude: float,
        limit: int,
    ) -> list[PharmacyLocationRecord]: ...


# 클래스명: NationalEmergencyMedicalCenterPharmacyAPI
# 역할:
# - 국립중앙의료원 XML API를 호출하고 안전한 약국 위치 레코드로 변환한다.
# 주요 책임:
# - HTTP 연결 풀과 동시 호출 제한을 재사용한다.
# - 인증키가 로그나 예외 메시지에 포함되지 않게 한다.
# - XML 헤더와 응답 크기를 검증한 뒤 필요한 필드만 추출한다.
class NationalEmergencyMedicalCenterPharmacyAPI:
    def __init__(
        self,
        *,
        client: httpx.AsyncClient | None = None,
        timeout_seconds: float | None = None,
    ) -> None:
        self._client = client
        self._owns_client = client is None
        self._client_lock = asyncio.Lock()
        self._semaphore = asyncio.Semaphore(settings.PUBLIC_API_MAX_CONCURRENCY)
        self._timeout_seconds = (
            timeout_seconds
            if timeout_seconds is not None
            else settings.PHARMACY_API_TIMEOUT_SECONDS
        )

    # 함수명: searchNearby
    # 역할:
    # - 현재 좌표에서 가까운 약국을 공공데이터 API에 요청한다.
    # 매개변수:
    # - latitude, longitude: WGS84 기준 사용자 좌표
    # - limit: 공공 API에서 가져올 최대 약국 수
    # 반환값:
    # - 검증된 PharmacyLocationRecord 목록
    async def searchNearby(
        self,
        *,
        latitude: float,
        longitude: float,
        limit: int,
    ) -> list[PharmacyLocationRecord]:
        if not settings.PUBLIC_DATA_API_KEY.strip():
            raise PharmacyApiUnavailableError(
                "Public pharmacy data credentials are unavailable."
            )

        endpoint = (
            settings.PHARMACY_API_BASE_URL.rstrip("/") + _LOCATION_SEARCH_PATH
        )
        params = {
            "serviceKey": settings.PUBLIC_DATA_API_KEY,
            "WGS84_LAT": f"{latitude:.7f}",
            "WGS84_LON": f"{longitude:.7f}",
            "pageNo": 1,
            "numOfRows": limit,
        }

        try:
            async with self._semaphore:
                client = await self._get_client()
                response = await client.get(endpoint, params=params)
        except (httpx.HTTPError, OSError, TimeoutError) as exc:
            logger.warning(
                "Pharmacy public API request failed: %s",
                type(exc).__name__,
            )
            raise PharmacyApiUnavailableError(
                "The pharmacy data service is temporarily unavailable."
            ) from exc

        if response.status_code != 200:
            logger.warning(
                "Pharmacy public API returned status %s.",
                response.status_code,
            )
            raise PharmacyApiUnavailableError(
                "The pharmacy data service did not respond successfully."
            )
        if len(response.content) > _MAX_RESPONSE_BYTES:
            raise PharmacyApiResponseError(
                "The pharmacy data response exceeded the allowed size."
            )

        return self._parse_records(response.content)

    async def fetchCatalogPage(
        self,
        *,
        page_no: int,
        page_size: int,
    ) -> tuple[list[PharmacyCatalogEntry], int]:
        """Fetches one page of nationwide weekly pharmacy schedules."""

        if not settings.PUBLIC_DATA_API_KEY.strip():
            raise PharmacyApiUnavailableError(
                "Public pharmacy data credentials are unavailable."
            )
        if page_no < 1 or not 1 <= page_size <= 1_000:
            raise ValueError("Pharmacy catalogue pagination is invalid.")

        endpoint = settings.PHARMACY_API_BASE_URL.rstrip("/") + _FULL_CATALOG_PATH
        params = {
            "serviceKey": settings.PUBLIC_DATA_API_KEY,
            "pageNo": page_no,
            "numOfRows": page_size,
        }
        try:
            async with self._semaphore:
                client = await self._get_client()
                response = await client.get(endpoint, params=params)
        except (httpx.HTTPError, OSError, TimeoutError) as exc:
            logger.warning(
                "Pharmacy catalogue request failed: %s",
                type(exc).__name__,
            )
            raise PharmacyApiUnavailableError(
                "The pharmacy data service is temporarily unavailable."
            ) from exc

        if response.status_code != 200:
            raise PharmacyApiUnavailableError(
                "The pharmacy data service did not respond successfully."
            )
        if len(response.content) > _MAX_RESPONSE_BYTES:
            raise PharmacyApiResponseError(
                "The pharmacy catalogue response exceeded the allowed size."
            )
        return self._parse_catalog_page(response.content)

    async def close(self) -> None:
        async with self._client_lock:
            client = self._client
            if self._owns_client:
                self._client = None
        if self._owns_client and client is not None:
            await client.aclose()

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is not None:
            return self._client
        async with self._client_lock:
            if self._client is None:
                self._client = httpx.AsyncClient(
                    timeout=self._timeout_seconds,
                    follow_redirects=False,
                    limits=httpx.Limits(
                        max_connections=settings.PUBLIC_API_MAX_CONCURRENCY,
                        max_keepalive_connections=(
                            settings.PUBLIC_API_MAX_CONCURRENCY
                        ),
                    ),
                )
        return self._client

    @classmethod
    def _parse_records(cls, payload: bytes) -> list[PharmacyLocationRecord]:
        try:
            root = ElementTree.fromstring(payload)
        except ElementTree.ParseError as exc:
            raise PharmacyApiResponseError(
                "The pharmacy data service returned invalid XML."
            ) from exc

        result_code = cls._read_text(root.find(".//resultCode"))
        if result_code not in {"", "00", "0000"}:
            raise PharmacyApiUnavailableError(
                "The pharmacy data service rejected the request."
            )

        records: list[PharmacyLocationRecord] = []
        for item in root.findall(".//item"):
            name = cls._read_child_text(item, "dutyName")
            pharmacy_id = cls._read_child_text(item, "hpid")
            latitude = cls._read_float(item, "latitude")
            longitude = cls._read_float(item, "longitude")
            if not name or not pharmacy_id or latitude is None or longitude is None:
                continue
            records.append(
                PharmacyLocationRecord(
                    pharmacy_id=pharmacy_id,
                    name=name,
                    address=cls._read_child_text(item, "dutyAddr"),
                    telephone=cls._read_child_text(item, "dutyTel1"),
                    latitude=latitude,
                    longitude=longitude,
                    distance_km=cls._read_float(item, "distance"),
                    start_time=cls._read_child_text(item, "startTime"),
                    end_time=cls._read_child_text(item, "endTime"),
                )
            )
        return records

    @classmethod
    def _parse_catalog_page(
        cls,
        payload: bytes,
    ) -> tuple[list[PharmacyCatalogEntry], int]:
        try:
            root = ElementTree.fromstring(payload)
        except ElementTree.ParseError as exc:
            raise PharmacyApiResponseError(
                "The pharmacy catalogue service returned invalid XML."
            ) from exc

        result_code = cls._read_text(root.find(".//resultCode"))
        if result_code not in {"", "00", "0000"}:
            raise PharmacyApiUnavailableError(
                "The pharmacy catalogue service rejected the request."
            )
        total_count = cls._read_int(root.find(".//totalCount"))
        records: list[PharmacyCatalogEntry] = []
        for item in root.findall(".//item"):
            pharmacy_id = cls._read_child_text(item, "hpid")
            name = cls._read_child_text(item, "dutyName")
            latitude = cls._read_float(item, "wgs84Lat")
            longitude = cls._read_float(item, "wgs84Lon")
            if not pharmacy_id or not name or latitude is None or longitude is None:
                continue
            weekly_hours: dict[str, tuple[str, str]] = {}
            for day_index in range(1, 9):
                start_time = cls._read_child_text(item, f"dutyTime{day_index}s")
                close_time = cls._read_child_text(item, f"dutyTime{day_index}c")
                if start_time or close_time:
                    weekly_hours[str(day_index)] = (start_time, close_time)
            records.append(
                PharmacyCatalogEntry(
                    pharmacy_id=pharmacy_id,
                    name=name,
                    address=cls._read_child_text(item, "dutyAddr"),
                    telephone=cls._read_child_text(item, "dutyTel1"),
                    latitude=latitude,
                    longitude=longitude,
                    weekly_hours=weekly_hours,
                )
            )
        return records, total_count

    @staticmethod
    def _read_text(element: ElementTree.Element | None) -> str:
        return "" if element is None or element.text is None else element.text.strip()

    @classmethod
    def _read_child_text(
        cls,
        item: ElementTree.Element,
        field_name: str,
    ) -> str:
        return cls._read_text(item.find(field_name))

    @classmethod
    def _read_float(
        cls,
        item: ElementTree.Element,
        field_name: str,
    ) -> float | None:
        value = cls._read_child_text(item, field_name)
        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    @classmethod
    def _read_int(cls, element: ElementTree.Element | None) -> int:
        try:
            return int(cls._read_text(element))
        except (TypeError, ValueError):
            return 0
