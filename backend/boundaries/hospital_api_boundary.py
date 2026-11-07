# 파일명: hospital_api_boundary.py
# 역할: 병원 공공 API의 위치·진료과·상세 조회를 호출 제한과 공유 캐시로 보호한다.
"""국립중앙의료원 병원 위치·상세 조회와 제한된 공유 캐시."""

import asyncio
from collections import OrderedDict
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime
import math
import re
import time
from typing import Protocol
from urllib.parse import unquote
import xml.etree.ElementTree as ET
from zoneinfo import ZoneInfo

import httpx

from core.config import settings
from entities.nearby_hospital_entity import (
    HospitalDetails,
    HospitalLocationPage,
    HospitalLocationRecord,
)

_LOCATION_PATH = "/getHsptlMdcncLcinfoInqire"
_DETAIL_PATH = "/getHsptlBassInfoInqire"
_DEPARTMENT_PATH = "/getHsptlMdcncListInfoInqire"
_MAX_RESPONSE_BYTES = 1024 * 1024
# 제공자에 보내는 검색 좌표의 소수 자릿수(약 100 m 격자).
_QUERY_COORDINATE_DECIMALS = 3


# 클래스명: HospitalApiUnavailableError
# 역할: 병원 제공자에 일시적으로 접근할 수 없음을 알린다.
# 주요 책임: 인증·통신·할당량 장애를 응답 형식 오류와 구분한다.
# 속성: RuntimeError의 오류 메시지 외 추가 상태 없음.
class HospitalApiUnavailableError(RuntimeError):
    """병원 API의 인증·할당량·통신 장애."""


# Class Name: HospitalApiBudgetExhaustedError
# Role: Signals exhaustion of an operation's daily hospital API budget.
# Responsibilities: Distinguish a budget that resets at local midnight from transient failures.
# Attributes: Inherited exception arguments; no additional state.
class HospitalApiBudgetExhaustedError(HospitalApiUnavailableError):
    """오늘 사용할 수 있는 병원 API 호출 예산을 모두 썼다. 서비스 시간대의 자정에 초기화된다."""


# 클래스명: HospitalApiResponseError
# 역할: 제공자 응답을 안전한 병원 데이터로 해석할 수 없음을 알린다.
# 주요 책임: XML·식별자·페이지 계약 위반을 통신 장애와 구분한다.
# 속성: RuntimeError의 오류 메시지 외 추가 상태 없음.
class HospitalApiResponseError(RuntimeError):
    """병원 API의 XML·페이지 응답 계약 오류."""


# 클래스명: HospitalLookupBoundary
# 역할: 병원 검색 Control이 사용하는 위치·상세 조회 계약.
# 주요 책임: 제공기관 구현을 분리하고 이미 진행 중인 상세 조회를 예산에서 재사용한다.
# 속성: 없음. 구현체의 캐시·연결 상태는 이 계약에 노출하지 않는다.
class HospitalLookupBoundary(Protocol):
    # 함수이름: fetchNearbyPage
    # 함수역할: 좌표 주변의 제공자 위치 목록 한 페이지를 요청하는 계약이다.
    # 매개변수: latitude, longitude (float)는 좌표, page_no, page_size (int)는 페이지 조건이다.
    # 반환값: HospitalLocationPage. 구현체의 입력 검증·제공자 오류는 호출자에게 전달한다.
    async def fetchNearbyPage(
        self, *, latitude: float, longitude: float, page_no: int, page_size: int
    ) -> HospitalLocationPage: ...

    # 함수이름: fetchDepartmentPage
    # 함수역할: 지역과 진료과로 먼저 걸러진 병원 목록을 요청하는 계약이다.
    # 매개변수: province, district, department (str)는 지역·진료과, page_no, page_size (int)는 페이지 조건이다.
    # 반환값: HospitalLocationPage. 조회 실패는 구현체의 예외로 전달한다.
    async def fetchDepartmentPage(
        self, *, province: str, district: str, department: str,
        page_no: int, page_size: int,
    ) -> HospitalLocationPage: ...

    # 함수이름: fetchDetails
    # 함수역할: 선택한 병원의 진료과·주간 운영표를 조회하는 계약이다.
    # 매개변수: hospital_id (str)는 제공자 병원 식별자다.
    # 반환값: HospitalDetails. 입력 검증·제공자 오류는 구현체에서 전달한다.
    async def fetchDetails(self, hospital_id: str) -> HospitalDetails: ...

    # 함수이름: hasCachedDetails
    # 함수역할: 상세 요청을 새 호출 예산 없이 재사용할 수 있는지 확인한다.
    # 매개변수: hospital_id (str)는 확인할 병원 식별자다.
    # 반환값: bool. 유효한 성공·실패 캐시 또는 진행 중 작업이 있으면 True다.
    def hasCachedDetails(self, hospital_id: str) -> bool: ...


# 클래스명: _CacheEntry
# 역할: 병원 조회 결과 또는 재발생시킬 오류 종류를 만료 시각과 함께 보관한다.
# 주요 책임: 실패도 짧게 공유하여 동일 요청의 반복 호출을 줄인다.
# 속성: expires_at (float)는 단조 시각, value는 위치·상세 결과, error는 예외 타입 또는 None이다.
@dataclass(frozen=True)
class _CacheEntry:
    expires_at: float
    value: HospitalLocationPage | HospitalDetails | None = None
    error: type[HospitalApiUnavailableError] | type[HospitalApiResponseError] | None = None


# 클래스명: NationalEmergencyMedicalCenterHospitalAPI
# 역할: 국립중앙의료원 병원 API의 제한된 조회·검증·캐시 경계.
# 주요 책임: 동일 요청 병합, 호출 예산 및 응답 크기 제한, 키가 없는 오류 전파.
# 속성: _cache는 TTL 결과, _inflight는 공유 작업, _daily_requests는 프로세스별·오퍼레이션별 호출 수다.
class NationalEmergencyMedicalCenterHospitalAPI:
    # Function Name: __init__
    # Description: Initializes bounded caches, shared requests and per-operation daily counters without opening a connection.
    # Parameters: client (AsyncClient | None) is borrowed when supplied; clock measures TTLs; date_clock selects the budget day.
    # Returns: None. An omitted date_clock uses the configured application time zone.
    def __init__(
        self,
        *,
        client: httpx.AsyncClient | None = None,
        clock: Callable[[], float] = time.monotonic,
        date_clock: Callable[[], date] | None = None,
    ) -> None:
        self._client = client
        self._owns_client = client is None
        self._clock = clock
        self._date_clock = date_clock or (lambda: datetime.now(ZoneInfo(settings.APPLICATION_TIME_ZONE)).date())
        self._budget_date: date | None = None
        # 제공기관의 하루 할당량은 오퍼레이션마다 따로 매겨지므로 호출 수도 오퍼레이션별로 센다.
        self._daily_requests: dict[str, int] = {}
        self._cache: OrderedDict[tuple, _CacheEntry] = OrderedDict()
        self._inflight: dict[tuple, asyncio.Task[_CacheEntry]] = {}
        self._semaphore = asyncio.Semaphore(settings.PUBLIC_API_MAX_CONCURRENCY)

    # Function Name: fetchNearbyPage
    # Description: Validates pagination and coarsens coordinates before requesting a date-independent cached location page.
    # Parameters: latitude, longitude (float) are geographic coordinates; page_no, page_size (int) select the bounded page.
    # Returns: HospitalLocationPage; raises ValueError for invalid bounds and propagates provider/cache failures.
    async def fetchNearbyPage(
        self, *, latitude: float, longitude: float, page_no: int, page_size: int
    ) -> HospitalLocationPage:
        if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
            raise ValueError("Invalid hospital search coordinates.")
        if not 1 <= page_no <= settings.HOSPITAL_SEARCH_MAX_PAGES or not 1 <= page_size <= 30:
            raise ValueError("Invalid hospital search pagination.")
        # 거리는 호출자가 실제 좌표로 다시 계산한다. 제공자에는 약 100 m 격자로 낮춘 좌표만 보내
        # 정밀 위치를 넘기지 않고, 좌표를 조금씩 바꿔 캐시를 피해 일일 호출 예산을 쓰는 것도 막는다.
        params = {
            "WGS84_LAT": f"{latitude:.{_QUERY_COORDINATE_DECIMALS}f}",
            "WGS84_LON": f"{longitude:.{_QUERY_COORDINATE_DECIMALS}f}",
            "pageNo": str(page_no),
            "numOfRows": str(page_size),
        }
        result = await self._cached(
            _LOCATION_PATH, params, settings.HOSPITAL_LOCATION_CACHE_SECONDS
        )
        assert isinstance(result, HospitalLocationPage)
        return result

    # 함수이름: fetchDetails
    # 함수역할: 병원 ID별 상세 캐시를 위치·필터 변경과 무관하게 재사용한다.
    # 매개변수: hospital_id (str)는 1~32자의 영문·숫자 식별자다.
    # 반환값: HospitalDetails. 식별자가 잘못되면 ValueError, 조회 실패 시 제공자 예외를 전달한다.
    async def fetchDetails(self, hospital_id: str) -> HospitalDetails:
        if not re.fullmatch(r"[A-Za-z0-9]{1,32}", hospital_id):
            raise ValueError("Invalid hospital identifier.")
        result = await self._cached(
            _DETAIL_PATH, {"HPID": hospital_id}, settings.HOSPITAL_DETAIL_CACHE_SECONDS
        )
        assert isinstance(result, HospitalDetails)
        return result

    # 함수이름: fetchDepartmentPage
    # 함수역할: 지역·진료과·페이지 조합을 검증해 좌표 조회와 별도로 캐시한다.
    # 매개변수: province, district, department (str)는 지역과 D형 진료과 코드, page_no, page_size (int)는 페이지 조건이다.
    # 반환값: HospitalLocationPage. 잘못된 조건은 ValueError, 제공자 실패는 해당 예외를 전달한다.
    async def fetchDepartmentPage(
        self, *, province: str, district: str, department: str,
        page_no: int, page_size: int,
    ) -> HospitalLocationPage:
        if (not re.fullmatch(r"[가-힣]{2,20}", province)
                or (district and not re.fullmatch(r"[가-힣]{1,20}[시군구]", district))
                or not re.fullmatch(r"D[0-9]{3}", department)
                or not 1 <= page_no <= settings.HOSPITAL_DEPARTMENT_MAX_PAGES
                or not 1 <= page_size <= 100):
            raise ValueError("Invalid hospital department search.")
        params = {"Q0": province, "QD": department,
                  "pageNo": str(page_no), "numOfRows": str(page_size)}
        if district:
            params["Q1"] = district
        result = await self._cached(
            _DEPARTMENT_PATH, params, settings.HOSPITAL_LOCATION_CACHE_SECONDS,
        )
        assert isinstance(result, HospitalLocationPage)
        return result

    # 함수이름: hasCachedDetails
    # 함수역할: 실패 캐시와 진행 중 작업까지 포함해 상세 조회의 재사용 가능성을 판정한다.
    # 매개변수: hospital_id (str)는 확인할 병원 식별자다.
    # 반환값: bool. 만료 전 캐시나 진행 중 작업이 있으면 True이며 조회 자체는 실행하지 않는다.
    def hasCachedDetails(self, hospital_id: str) -> bool:
        key = (_DETAIL_PATH, (("HPID", hospital_id),))
        entry = self._cache.get(key)
        return key in self._inflight or (
            entry is not None and entry.expires_at > self._clock()
        )

    # 함수이름: _cached
    # 함수역할: 동일 요청을 합치고 호출자의 취소로 공유 작업이 취소되지 않게 보호한다.
    # 매개변수: path (str)는 API 경로, params (dict[str, str])는 캐시 키 재료, ttl (int)은 성공 보관 초다.
    # 반환값: 위치·상세 결과. 용량 초과나 저장된 실패는 해당 병원 API 예외로 발생시킨다.
    async def _cached(self, path: str, params: dict[str, str], ttl: int):
        key = (path, tuple(sorted(params.items())))
        entry = self._cache.get(key)
        if entry is not None and entry.expires_at > self._clock():
            self._cache.move_to_end(key)
        else:
            self._cache.pop(key, None)
            task = self._inflight.get(key)
            if task is None:
                if len(self._inflight) >= settings.PUBLIC_API_MAX_CONCURRENCY * 8:
                    raise HospitalApiUnavailableError("Hospital lookup capacity exceeded.")
                task = asyncio.create_task(self._load(key, path, params, ttl))
                self._inflight[key] = task
            entry = await asyncio.shield(task)
        if entry.error is not None:
            raise entry.error("Hospital data is temporarily unavailable.")
        return entry.value

    # Function Name: _load
    # Description: Fetches and parses under a timeout, caches success or a sanitized failure, and always removes the inflight entry.
    # Parameters: key (tuple) identifies the shared request; path (str), params (dict[str, str]) select it; ttl (int) is success lifetime in seconds.
    # Returns: _CacheEntry. Budget exhaustion retains its distinct error type; cancellation and unexpected errors propagate.
    async def _load(self, key: tuple, path: str, params: dict[str, str], ttl: int) -> _CacheEntry:
        try:
            try:
                async with asyncio.timeout(settings.HOSPITAL_API_TIMEOUT_SECONDS * 2):
                    root = await self._request(path, params)
                    value = (
                        self._parse_page(root, int(params["pageNo"]), int(params["numOfRows"]))
                        if path in {_LOCATION_PATH, _DEPARTMENT_PATH}
                        else self._parse_details(root, params["HPID"])
                    )
                entry = _CacheEntry(self._clock() + ttl, value=value)
            except (HospitalApiUnavailableError, HospitalApiResponseError, TimeoutError) as exc:
                # 예산 소진은 자정까지 풀리지 않으므로 일시 장애와 구분해 그대로 전한다.
                error = (
                    HospitalApiResponseError
                    if isinstance(exc, HospitalApiResponseError)
                    else HospitalApiBudgetExhaustedError
                    if isinstance(exc, HospitalApiBudgetExhaustedError)
                    else HospitalApiUnavailableError
                )
                entry = _CacheEntry(
                    self._clock() + settings.PUBLIC_API_FAILURE_CACHE_SECONDS, error=error
                )
            self._cache[key] = entry
            self._cache.move_to_end(key)
            while len(self._cache) > settings.HOSPITAL_CACHE_MAX_ENTRIES:
                self._cache.popitem(last=False)
            return entry
        finally:
            self._inflight.pop(key, None)

    # Function Name: _request
    # Description: Charges the operation's daily budget, bounds streaming response size, and validates XML without exposing credentials.
    # Parameters: path (str) is the provider operation; params (dict[str, str]) excludes the service key added internally.
    # Returns: Parsed XML Element; raises budget, availability or response errors for quota, transport or contract failures.
    async def _request(self, path: str, params: dict[str, str]) -> ET.Element:
        key = settings.HOSPITAL_API_KEY.strip() or settings.PUBLIC_DATA_API_KEY.strip()
        if not key:
            raise HospitalApiUnavailableError("Hospital data credentials are unavailable.")
        try:
            async with self._semaphore:
                budget_date = self._date_clock()
                if self._budget_date != budget_date:
                    self._budget_date = budget_date
                    self._daily_requests = {}
                used = self._daily_requests.get(path, 0)
                if used >= settings.HOSPITAL_API_DAILY_REQUEST_BUDGET:
                    raise HospitalApiBudgetExhaustedError(
                        "Hospital daily request budget exhausted."
                    )
                self._daily_requests[path] = used + 1
                if self._client is None:
                    self._client = httpx.AsyncClient(
                        timeout=settings.HOSPITAL_API_TIMEOUT_SECONDS,
                        follow_redirects=False,
                        limits=httpx.Limits(max_connections=settings.PUBLIC_API_MAX_CONCURRENCY),
                    )
                async with self._client.stream(
                    "GET", settings.HOSPITAL_API_BASE_URL.rstrip("/") + path,
                    params={**params, "serviceKey": unquote(key)},
                    timeout=settings.HOSPITAL_API_TIMEOUT_SECONDS,
                ) as response:
                    if response.status_code != 200:
                        raise HospitalApiUnavailableError("Hospital provider request failed.")
                    payload = bytearray()
                    async for chunk in response.aiter_bytes():
                        payload.extend(chunk)
                        if len(payload) > _MAX_RESPONSE_BYTES:
                            raise HospitalApiResponseError("Hospital response is too large.")
        except (httpx.HTTPError, OSError, TimeoutError):
            raise HospitalApiUnavailableError("Hospital provider request failed.") from None
        if b"<!DOCTYPE" in payload.upper() or b"<!ENTITY" in payload.upper():
            raise HospitalApiResponseError("Hospital response contains unsupported XML.")
        try:
            root = ET.fromstring(payload)
        except (ET.ParseError, ValueError, LookupError):
            raise HospitalApiResponseError("Invalid hospital response XML.") from None
        code = root.findtext(".//resultCode", "").strip()
        if root.find(".//cmmMsgHeader") is not None or code not in {"00", "0000", "03"}:
            if code or root.find(".//cmmMsgHeader") is not None:
                raise HospitalApiUnavailableError("Hospital provider rejected the request.")
            raise HospitalApiResponseError("Hospital response status is missing.")
        if root.find("body") is None:
            raise HospitalApiResponseError("Hospital response body is missing.")
        return root

    # 함수이름: _parse_page
    # 함수역할: 페이지 메타데이터를 검증하고 잘못된 좌표·식별자 행은 제외하되 원본 행 수는 유지한다.
    # 매개변수: root (Element)는 XML, page_no, page_size (int)는 요청한 페이지와 최대 크기다.
    # 반환값: HospitalLocationPage. 페이지 계약 불일치·예상치 못한 빈 페이지는 HospitalApiResponseError다.
    @staticmethod
    def _parse_page(root: ET.Element, page_no: int, page_size: int) -> HospitalLocationPage:
        try:
            total = int(root.findtext("body/totalCount", ""))
            actual_page = int(root.findtext("body/pageNo", ""))
            actual_size = int(root.findtext("body/numOfRows", ""))
        except ValueError:
            raise HospitalApiResponseError("Invalid hospital pagination.") from None
        items = root.findall("body/items/item")
        if total < 0 or actual_page != page_no or not 1 <= actual_size <= page_size or len(items) > actual_size:
            raise HospitalApiResponseError("Unexpected hospital pagination.")
        if not items and (page_no - 1) * actual_size < total:
            raise HospitalApiResponseError("Hospital result page is unexpectedly empty.")
        records = []
        for item in items:
            identifier = item.findtext("hpid", "").strip()
            name = item.findtext("dutyName", "").strip()
            try:
                latitude = float(item.findtext("latitude") or item.findtext("wgs84Lat", ""))
                longitude = float(item.findtext("longitude") or item.findtext("wgs84Lon", ""))
            except ValueError:
                continue
            if (
                not re.fullmatch(r"[A-Za-z0-9]{1,32}", identifier) or not name
                or not math.isfinite(latitude) or not math.isfinite(longitude)
                or not -90 <= latitude <= 90 or not -180 <= longitude <= 180
                or (latitude == 0 and longitude == 0)
            ):
                continue
            records.append(HospitalLocationRecord(
                hospital_id=identifier, name=name,
                address=item.findtext("dutyAddr", "").strip(),
                telephone=item.findtext("dutyTel1", "").strip(),
                latitude=latitude, longitude=longitude,
                institution_type=(item.findtext("dutyDivName", "").strip()
                                  or item.findtext("dutyDivNam", "").strip() or None),
            ))
        return HospitalLocationPage(tuple(records), total, len(items), actual_size)

    # 함수이름: _parse_details
    # 함수역할: 식별자를 검증하고 진료과·주간 시간표·공유용 위치를 읽으며 응급실을 24시간 외래로 해석하지 않는다.
    # 매개변수: root (Element)는 XML, hospital_id (str)는 요청한 식별자다.
    # 반환값: HospitalDetails. 0건은 빈 상세, 개수·ID 불일치는 HospitalApiResponseError이며 잘못된 위치만 제외한다.
    @staticmethod
    def _parse_details(root: ET.Element, hospital_id: str) -> HospitalDetails:
        items = root.findall("body/items/item")
        try:
            total = int(root.findtext("body/totalCount", ""))
        except ValueError:
            raise HospitalApiResponseError("Hospital detail count is missing.") from None
        if total not in {0, 1} or len(items) != total:
            raise HospitalApiResponseError("Invalid hospital detail count.")
        if not items:
            return HospitalDetails(hospital_id)
        if len(items) != 1 or items[0].findtext("hpid", "").strip() != hospital_id:
            raise HospitalApiResponseError("Hospital detail identifier mismatch.")
        item = items[0]
        departments = tuple(dict.fromkeys(
            value.strip() for value in re.split(r"[,;|]", item.findtext("dgidIdName", ""))
            if value.strip()
        ))
        codes = tuple(dict.fromkeys(re.findall(r"\bD[0-9]{3}\b", item.findtext("dgidId", ""))))
        # 채팅 공유용 이름·전화·좌표도 클라이언트가 아닌 제공자 응답에서 읽는다.
        location = None
        try:
            latitude = float(item.findtext("wgs84Lat", ""))
            longitude = float(item.findtext("wgs84Lon", ""))
            name = item.findtext("dutyName", "").strip()
            if (name and math.isfinite(latitude) and math.isfinite(longitude)
                    and -90 <= latitude <= 90 and -180 <= longitude <= 180
                    and (latitude != 0 or longitude != 0)):
                location = HospitalLocationRecord(
                    hospital_id=hospital_id, name=name[:300],
                    address=item.findtext("dutyAddr", "").strip()[:600],
                    telephone=item.findtext("dutyTel1", "").strip()[:40],
                    latitude=latitude, longitude=longitude,
                )
        except ValueError:
            pass
        return HospitalDetails(
            hospital_id=hospital_id,
            departments=departments,
            department_codes=codes,
            institution_type=item.findtext("dutyDivNam", "").strip() or None,
            operating_notes="\n".join(dict.fromkeys(
                text for tag in ("dutyEtc", "dutyInf")
                if (text := item.findtext(tag, "").strip())
            )) or None,
            weekly_hours=tuple(
                (str(day), item.findtext(f"dutyTime{day}s", "").strip(),
                 item.findtext(f"dutyTime{day}c", "").strip())
                for day in range(1, 9)
            ),
            location=location,
            fetched_at=datetime.now(UTC),
        )

    # 함수이름: close
    # 함수역할: 진행 중 작업을 취소·회수하고 캐시를 비운 뒤 내부 소유 연결만 닫는다.
    # 매개변수: 없음.
    # 반환값: None. 외부에서 주입한 HTTP 클라이언트는 닫지 않으며 연결 종료 오류는 전달한다.
    async def close(self) -> None:
        tasks = tuple(self._inflight.values())
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        self._inflight.clear()
        self._cache.clear()
        if self._owns_client and self._client is not None:
            await self._client.aclose()
            self._client = None
