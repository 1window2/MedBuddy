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
_MAX_RESPONSE_BYTES = 1024 * 1024


class HospitalApiUnavailableError(RuntimeError):
    """병원 API의 인증·할당량·통신 장애."""


class HospitalApiResponseError(RuntimeError):
    """병원 API의 XML·페이지 응답 계약 오류."""


# 클래스명: HospitalLookupBoundary
# 역할: 병원 검색 Control이 사용하는 위치·상세 조회 계약.
# 주요 책임: 제공기관 구현을 분리하고 이미 진행 중인 상세 조회를 예산에서 재사용한다.
class HospitalLookupBoundary(Protocol):
    # 좌표 주변의 한 페이지를 가져온다.
    async def fetchNearbyPage(
        self, *, latitude: float, longitude: float, page_no: int, page_size: int
    ) -> HospitalLocationPage: ...

    # 선택한 병원의 주간 운영표와 진료과를 가져온다.
    async def fetchDetails(self, hospital_id: str) -> HospitalDetails: ...

    # 캐시 또는 진행 중 요청은 새 제공자 호출 예산에서 제외한다.
    def hasCachedDetails(self, hospital_id: str) -> bool: ...


@dataclass(frozen=True)
class _CacheEntry:
    expires_at: float
    value: HospitalLocationPage | HospitalDetails | None = None
    error: type[HospitalApiUnavailableError] | type[HospitalApiResponseError] | None = None


# 클래스명: NationalEmergencyMedicalCenterHospitalAPI
# 역할: 국립중앙의료원 병원 API의 제한된 조회·검증·캐시 경계.
# 주요 책임: 동일 요청 병합, 호출 예산 및 응답 크기 제한, 키가 없는 오류 전파.
# 속성: _cache는 TTL 결과, _inflight는 공유 작업, _daily_requests는 프로세스별 호출 수다.
class NationalEmergencyMedicalCenterHospitalAPI:
    # 캐시·진행 요청·연결 풀의 크기를 제한한다.
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
        self._daily_requests = 0
        self._cache: OrderedDict[tuple, _CacheEntry] = OrderedDict()
        self._inflight: dict[tuple, asyncio.Task[_CacheEntry]] = {}
        self._semaphore = asyncio.Semaphore(settings.PUBLIC_API_MAX_CONCURRENCY)

    # 위치 페이지는 날짜·필터와 독립적으로 재사용한다.
    async def fetchNearbyPage(
        self, *, latitude: float, longitude: float, page_no: int, page_size: int
    ) -> HospitalLocationPage:
        if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
            raise ValueError("Invalid hospital search coordinates.")
        if not 1 <= page_no <= settings.HOSPITAL_SEARCH_MAX_PAGES or not 1 <= page_size <= 30:
            raise ValueError("Invalid hospital search pagination.")
        params = {
            "WGS84_LAT": f"{latitude:.7f}",
            "WGS84_LON": f"{longitude:.7f}",
            "pageNo": str(page_no),
            "numOfRows": str(page_size),
        }
        result = await self._cached(
            _LOCATION_PATH, params, settings.HOSPITAL_LOCATION_CACHE_SECONDS
        )
        assert isinstance(result, HospitalLocationPage)
        return result

    # 병원 ID별 상세 결과를 위치 이동과 필터 변경에도 재사용한다.
    async def fetchDetails(self, hospital_id: str) -> HospitalDetails:
        if not re.fullmatch(r"[A-Za-z0-9]{1,32}", hospital_id):
            raise ValueError("Invalid hospital identifier.")
        result = await self._cached(
            _DETAIL_PATH, {"HPID": hospital_id}, settings.HOSPITAL_DETAIL_CACHE_SECONDS
        )
        assert isinstance(result, HospitalDetails)
        return result

    # 실패 캐시와 진행 중 작업도 재사용해 반복 필터의 호출량을 제한한다.
    def hasCachedDetails(self, hospital_id: str) -> bool:
        key = (_DETAIL_PATH, (("HPID", hospital_id),))
        entry = self._cache.get(key)
        return key in self._inflight or (
            entry is not None and entry.expires_at > self._clock()
        )

    # 동일 요청을 합치고 한 호출자의 취소가 공유 작업을 취소하지 않게 한다.
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

    # 검증된 결과와 짧은 실패 캐시만 보관하며 완료 후 진행 표를 비운다.
    async def _load(self, key: tuple, path: str, params: dict[str, str], ttl: int) -> _CacheEntry:
        try:
            try:
                async with asyncio.timeout(settings.HOSPITAL_API_TIMEOUT_SECONDS * 2):
                    root = await self._request(path, params)
                    value = (
                        self._parse_page(root, int(params["pageNo"]), int(params["numOfRows"]))
                        if path == _LOCATION_PATH
                        else self._parse_details(root, params["HPID"])
                    )
                entry = _CacheEntry(self._clock() + ttl, value=value)
            except (HospitalApiUnavailableError, HospitalApiResponseError, TimeoutError) as exc:
                error = (
                    HospitalApiResponseError
                    if isinstance(exc, HospitalApiResponseError)
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

    # 응답을 제한된 크기로 읽고 키나 요청 URL을 예외에 포함하지 않는다.
    async def _request(self, path: str, params: dict[str, str]) -> ET.Element:
        key = settings.HOSPITAL_API_KEY.strip() or settings.PUBLIC_DATA_API_KEY.strip()
        if not key:
            raise HospitalApiUnavailableError("Hospital data credentials are unavailable.")
        try:
            async with self._semaphore:
                budget_date = self._date_clock()
                if self._budget_date != budget_date:
                    self._budget_date = budget_date
                    self._daily_requests = 0
                if self._daily_requests >= settings.HOSPITAL_API_DAILY_REQUEST_BUDGET:
                    raise HospitalApiUnavailableError("Hospital daily request budget exhausted.")
                self._daily_requests += 1
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
        except ET.ParseError:
            raise HospitalApiResponseError("Invalid hospital response XML.") from None
        code = root.findtext(".//resultCode", "").strip()
        if root.find(".//cmmMsgHeader") is not None or code not in {"00", "0000", "03"}:
            if code or root.find(".//cmmMsgHeader") is not None:
                raise HospitalApiUnavailableError("Hospital provider rejected the request.")
            raise HospitalApiResponseError("Hospital response status is missing.")
        if root.find("body") is None:
            raise HospitalApiResponseError("Hospital response body is missing.")
        return root

    # 원본 행 수로 페이지 끝을 계산하고 잘못된 좌표·식별자는 제외한다.
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

    # 응급실 여부를 외래 24시간 진료로 해석하지 않고 주간 시간표만 읽는다.
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

    # 종료 시 진행 중인 공유 작업을 회수하고 내부 소유 연결만 닫는다.
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
