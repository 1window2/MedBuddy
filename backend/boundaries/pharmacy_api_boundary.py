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


# 클래스명: PharmacyApiUnavailableError
# 역할:
# - 약국 공공데이터 조회가 일시적으로 불가능함을 나타낸다.
# 주요 책임:
# - 네트워크 장애, 인증키 부재와 제공자 요청 거부를 응답 형식 오류와 구분한다.
class PharmacyApiUnavailableError(RuntimeError):
    """약국 공공데이터 서비스에 일시적으로 접근할 수 없을 때 발생한다."""


# 클래스명: PharmacyApiResponseError
# 역할:
# - 약국 응답이 기대한 크기 또는 XML 계약을 벗어났음을 나타낸다.
# 주요 책임:
# - 신뢰할 수 없는 제공자 응답을 위치 검색 및 카탈로그 제어 흐름에 전달한다.
class PharmacyApiResponseError(RuntimeError):
    """약국 공공데이터 응답 형식이 계약과 다를 때 발생한다."""


# 클래스명: PharmacyLookupBoundary
# 역할:
# - Control이 HTTP 구현을 알지 않고 위치 기반 약국 검색을 요청하도록 한다.
# 주요 책임:
# - WGS84 좌표와 결과 상한을 받아 약국 위치 레코드 목록을 제공한다.
class PharmacyLookupBoundary(Protocol):
    # 함수이름: searchNearby
    # 함수역할:
    # - 주어진 좌표 주변의 약국을 외부 제공자에서 조회하는 비동기 계약이다.
    # 매개변수:
    # - latitude (float): 검색 중심의 WGS84 위도.
    # - longitude (float): 검색 중심의 WGS84 경도.
    # - limit (int): 반환할 일치 기록의 최대 개수.
    # 반환값:
    # - 주변 약국 위치 레코드 목록.
    async def searchNearby(
        self,
        *,
        latitude: float,
        longitude: float,
        limit: int,
    ) -> list[PharmacyLocationRecord]: ...


# Class Name: NationalEmergencyMedicalCenterPharmacyAPI
# Role:
# - Converts NEMC XML services into pharmacy location and catalog records.
# Responsibilities:
# - Reuse HTTP pooling and bound concurrent provider calls.
# - Keep service keys out of logs and boundary error messages.
# - Validate response sizes and XML status headers before extracting required fields.
# Attributes:
# - _client (AsyncClient | None): Borrowed or lazily created transport.
# - _client_lock (asyncio.Lock): Guards client creation and release.
# - _semaphore (asyncio.Semaphore): Provider concurrency cap.
# - _timeout_seconds (float): Request timeout.
class NationalEmergencyMedicalCenterPharmacyAPI:
    # 함수이름: __init__
    # 함수역할:
    # - HTTP 클라이언트 소유 여부와 생성 잠금, 공공 API 동시 호출 상한 및 제한 시간을 준비한다.
    # 매개변수:
    # - client (httpx.AsyncClient | None): 외부에서 주입한 HTTP 클라이언트; 생략하면 내부에서 생성한다.
    # - timeout_seconds (float | None): 외부 요청 제한 시간(초); None이면 설정값을 사용한다.
    # 반환값:
    # - 없음; 클라이언트 생성은 첫 요청까지 지연한다.
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

    # 함수이름: searchNearby
    # 함수역할:
    # - 현재 좌표에서 가까운 약국을 공공데이터 API에 요청한다.
    # 매개변수:
    # - latitude (float): 검색 중심의 WGS84 위도.
    # - longitude (float): 검색 중심의 WGS84 경도.
    # - limit (int): 공공 API에서 가져올 최대 약국 수
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

    # Function Name: fetchCatalogPage
    # Description:
    # - Validate pagination and fetch one nationwide weekly-hours page under the concurrency and response-size limits.
    # Parameters:
    # - page_no (int): One-based upstream result page number.
    # - page_size (int): Requested rows per page, from 1 through 1,000.
    # Returns:
    # - Normalized catalog entries and provider total count; raises boundary errors on provider failure.
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

    # 함수이름: close
    # 함수역할:
    # - 잠금 안에서 내부 소유 클라이언트를 분리한 뒤 닫고, 주입받은 클라이언트는 유지한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음.
    async def close(self) -> None:
        async with self._client_lock:
            client = self._client
            if self._owns_client:
                self._client = None
        if self._owns_client and client is not None:
            await client.aclose()

    # 함수이름: _get_client
    # 함수역할:
    # - 기존 HTTP 클라이언트를 재사용하거나 잠금으로 중복 생성을 막으며 연결 풀을 준비한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 설정된 제한 시간과 연결 수 상한을 가진 AsyncClient.
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

    # 함수이름: _parse_records
    # 함수역할:
    # - XML과 제공자 상태를 검증한 뒤 이름·ID·좌표가 있는 행만 약국 위치 정보로 변환한다.
    # 매개변수:
    # - payload (bytes): 공공 위치 검색 API의 XML 응답 바이트.
    # 반환값:
    # - 검증된 위치 레코드 목록; 잘못된 XML이나 제공자 실패에는 경계 예외.
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

    # Function Name: _parse_catalog_page
    # Description:
    # - Validate catalog XML, read its total count and normalize valid pharmacy rows with weekday and holiday hours.
    # Parameters:
    # - payload (bytes): Raw nationwide pharmacy-catalog XML response bytes.
    # Returns:
    # - Catalog entries and total count; rows without ID, name or coordinates are skipped.
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

    # 함수이름: _read_text
    # 함수역할:
    # - XML 요소의 텍스트에서 앞뒤 공백을 제거하고 누락값을 빈 문자열로 통일한다.
    # 매개변수:
    # - element (ElementTree.Element | None): 텍스트를 읽을 XML 요소; 없으면 None.
    # 반환값:
    # - 정리한 텍스트 또는 빈 문자열.
    @staticmethod
    def _read_text(element: ElementTree.Element | None) -> str:
        return "" if element is None or element.text is None else element.text.strip()

    # 함수이름: _read_child_text
    # 함수역할:
    # - 약국 항목의 지정 하위 요소에서 정리된 텍스트를 읽는다.
    # 매개변수:
    # - item (ElementTree.Element): 약국 정보를 담은 XML 항목.
    # - field_name (str): 텍스트를 읽을 하위 XML 태그명.
    # 반환값:
    # - 하위 필드 텍스트 또는 요소가 없으면 빈 문자열.
    @classmethod
    def _read_child_text(
        cls,
        item: ElementTree.Element,
        field_name: str,
    ) -> str:
        return cls._read_text(item.find(field_name))

    # 함수이름: _read_float
    # 함수역할:
    # - 지정 하위 필드의 텍스트를 좌표 또는 거리 수치로 파싱한다.
    # 매개변수:
    # - item (ElementTree.Element): 좌표 또는 거리를 담은 XML 항목.
    # - field_name (str): 실수로 읽을 하위 XML 태그명.
    # 반환값:
    # - 파싱한 float 또는 숫자로 변환할 수 없으면 None.
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

    # Function Name: _read_int
    # Description:
    # - Parse the catalog count element, falling back to zero when missing or malformed.
    # Parameters:
    # - element (ElementTree.Element | None): XML count element, or None when absent.
    # Returns:
    # - Integer element value, or 0 if conversion fails.
    @classmethod
    def _read_int(cls, element: ElementTree.Element | None) -> int:
        try:
            return int(cls._read_text(element))
        except (TypeError, ValueError):
            return 0
