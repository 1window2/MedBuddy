"""주변 지역의 진료과별 목록을 모아 상세 조회 전에 거리순 후보를 만든다."""

import asyncio
from collections import deque
from dataclasses import dataclass
import math

from boundaries.hospital_api_boundary import (
    HospitalApiResponseError, HospitalApiUnavailableError, HospitalLookupBoundary,
)
from controls.check_nearby_pharmacy_control import CheckNearbyPharmacy
from core.config import settings
from entities.nearby_hospital_entity import HospitalLocationRecord

_PROVINCES = {
    "서울특별시", "부산광역시", "대구광역시", "인천광역시", "광주광역시",
    "대전광역시", "울산광역시", "세종특별자치시", "경기도", "강원특별자치도",
    "충청북도", "충청남도", "전북특별자치도", "전라남도", "경상북도",
    "경상남도", "제주특별자치도", "강원도", "전라북도",
}
# 제공자 주소에는 정식 시도명과 축약명이 함께 들어온다. 명시된 별칭만 정규화한다.
_PROVINCE_ALIASES = {
    "서울": "서울특별시", "부산": "부산광역시", "대구": "대구광역시",
    "인천": "인천광역시", "광주": "광주광역시", "대전": "대전광역시",
    "울산": "울산광역시", "세종": "세종특별자치시", "경기": "경기도",
    "강원": "강원특별자치도", "충북": "충청북도", "충남": "충청남도",
    "전북": "전북특별자치도", "전남": "전라남도", "경북": "경상북도",
    "경남": "경상남도", "제주": "제주특별자치도",
}
_ERRORS = (HospitalApiUnavailableError, HospitalApiResponseError, TimeoutError)


@dataclass(frozen=True)
class DepartmentCandidates:
    """실제 조회 실패·제한과 주소 표본으로 추정한 지역 범위를 구별한다."""

    records: tuple[HospitalLocationRecord, ...]
    partial: bool
    region_scope_uncertain: bool = False


def _region(address: str) -> tuple[str, str] | None:
    """제공자 주소의 시도·시군구만 사용하고 병원명에서 지역을 추측하지 않는다."""
    parts = address.split()
    if not parts:
        return None
    province = _PROVINCE_ALIASES.get(parts[0], parts[0])
    if province not in _PROVINCES:
        return None
    if province == "세종특별자치시":
        return province, ""
    if len(parts) >= 2 and parts[1].endswith(("시", "군", "구")):
        # 수원시 영통구처럼 일반구가 있는 시는 시 전체를 읽어 경계 누락을 줄인다.
        return province, parts[1]
    return None


async def find_department_candidates(
    boundary: HospitalLookupBoundary, *, latitude: float, longitude: float,
    radius_km: float, department: str, deadline: float,
) -> DepartmentCandidates:
    """지역 파악에는 위치 목록만 쓰고, 상세 후보는 QD로 걸러진 목록에서만 받는다.

    지역 발견은 행정경계 전수 판정이 아니다. 보조 위치 목록의 남은 페이지는
    지역 범위의 불확실성으로 기록하고 진료과 목록의 실제 조회 제한과 구별한다.
    """
    regions: set[tuple[str, str]] = set()
    partial = False
    region_scope_uncertain = False

    def remember(page):
        """주소 누락·유효하지 않은 행은 검색 범위가 불완전함을 나타낸다."""
        nonlocal partial
        partial |= page.row_count != len(page.records)
        for record in page.records:
            region = _region(record.address)
            if region is None:
                partial = True
            else:
                regions.add(region)

    # 무거운 위치 조회를 순차 페이지로 소진하지 않고 중심·네 방향의 첫 페이지만 병합한다.
    dy = radius_km / 111.2
    dx = radius_km / max(1, 111.2 * math.cos(math.radians(latitude)))
    points = [(latitude, longitude), (latitude + dy, longitude),
              (latitude - dy, longitude), (latitude, longitude + dx),
              (latitude, longitude - dx)]

    async def probe(lat, lon):
        """보조 지역 탐색 실패는 이미 찾은 지역을 버리지 않는다."""
        if (asyncio.get_running_loop().time() >= deadline
                or not -90 <= lat <= 90 or not -180 <= lon <= 180):
            return None
        try:
            async with asyncio.timeout_at(deadline):
                return await boundary.fetchNearbyPage(
                    latitude=lat, longitude=lon, page_no=1, page_size=30,
                )
        except _ERRORS:
            return None

    for page in await asyncio.gather(*(probe(lat, lon) for lat, lon in points)):
        if page is None:
            partial = True
        else:
            remember(page)
            # 이 목록은 주소 표본이다. 남은 전체 병원을 진료과 검색 누락으로 세지 않는다.
            region_scope_uncertain |= page.row_count < page.total_count

    if not regions:
        # 지역을 모르는데 해당 진료과가 없다고 응답하지 않는다.
        raise HospitalApiUnavailableError("Hospital search regions are unavailable.")

    pending = deque((province, district, 1, 100) for province, district in sorted(regions))
    candidates: dict[str, tuple[float, HospitalLocationRecord]] = {}
    successful_pages = 0
    first_error = None
    for _ in range(settings.HOSPITAL_DEPARTMENT_MAX_PAGES):
        if not pending:
            break
        # 시간 초과 뒤 캐시 경계의 별도 네트워크 작업을 새로 만들지 않는다.
        if asyncio.get_running_loop().time() >= deadline:
            partial = True
            first_error = first_error or TimeoutError()
            break
        province, district, page_no, size = pending.popleft()
        try:
            async with asyncio.timeout_at(deadline):
                page = await boundary.fetchDepartmentPage(
                    province=province, district=district, department=department,
                    page_no=page_no, page_size=size,
                )
        except _ERRORS as error:
            partial = True
            first_error = first_error or error
            # 이벤트 루프의 시간 정밀도로 시계가 제한 시각보다 약간 앞서도 중단한다.
            if isinstance(error, TimeoutError):
                break
            continue
        successful_pages += 1
        partial |= page.row_count != len(page.records)
        for record in page.records:
            distance = CheckNearbyPharmacy._haversine_distance(
                latitude, longitude, record.latitude, record.longitude,
            )
            if distance <= radius_km:
                candidates.setdefault(record.hospital_id, (distance, record))
        if page_no * page.page_size < page.total_count:
            pending.append((province, district, page_no + 1, page.page_size))
    if first_error is not None and not successful_pages:
        raise first_error
    partial |= bool(pending)
    ordered = sorted(candidates.values(), key=lambda value: (value[0], value[1].hospital_id))
    return DepartmentCandidates(
        tuple(record for _, record in ordered), partial, region_scope_uncertain,
    )
