"""주변 병원의 진료과·요일별 운영시간을 검증해 지도 결과를 만든다."""

import asyncio
from collections.abc import Callable
from datetime import date, datetime, timedelta
import re
from zoneinfo import ZoneInfo

from boundaries.holiday_lookup_boundary import HolidayLookupBoundary
from boundaries.hospital_api_boundary import (
    HospitalApiResponseError,
    HospitalApiUnavailableError,
    HospitalLookupBoundary,
)
from boundaries.pharmacy_api_boundary import PharmacyApiUnavailableError
from controls.hospital_department_search import find_department_candidates
from core.config import settings
from entities.nearby_hospital_entity import HospitalDetails, HospitalLocationRecord
from schemas.hospital import HospitalSearchMode, NearbyHospitalItem, NearbyHospitalResponse
from services.nearby_care_policy import (
    format_time,
    haversine_distance,
    is_open_now,
    minutes_until_close,
    normalize_target_datetime,
    parse_minutes,
)


_PAGE_SIZE = 30
# 공공데이터포털 15000736의 공식 활용가이드 코드와 명시적인 명칭 변경만 연결한다.
DEPARTMENT_NAMES: dict[str, tuple[str, ...]] = {
    "D001": ("내과",), "D002": ("소아청소년과",), "D003": ("신경과",),
    "D004": ("정신건강의학과",), "D005": ("피부과",), "D006": ("외과",),
    "D007": ("흉부외과", "심장혈관흉부외과"), "D008": ("정형외과",),
    "D009": ("신경외과",), "D010": ("성형외과",), "D011": ("산부인과",),
    "D012": ("안과",), "D013": ("이비인후과",), "D014": ("비뇨기과", "비뇨의학과"),
    "D016": ("재활의학과",), "D017": ("마취통증의학과",), "D018": ("영상의학과",),
    "D019": ("치료방사선과", "방사선종양학과"),
    "D020": ("임상병리과", "진단검사의학과"), "D021": ("해부병리과", "병리과"),
    "D022": ("가정의학과",), "D023": ("핵의학과",), "D024": ("응급의학과",),
    "D026": (
        "치과", "구강내과", "구강악안면방사선과", "구강안면외과", "구강악안면외과",
        "소아치과", "예방치과", "치과보존과", "치과보철과", "치주과", "치과교정과",
        "구강병리과", "영상치의학과", "통합치의학과",
    ),
    "D034": ("구강악안면외과", "구강안면외과"),
}


# 클래스명: CheckNearbyHospital
# 역할: 병원 검색 조건과 서버 검증 채팅 공유 문맥을 구성한다.
# 주요 책임: 진료과·선택일·운영 상태를 함께 판정하고 불확실한 시간표를 숨기지 않는다.
class CheckNearbyHospital:
    # 위치 경계와 공휴일 달력만 연결하며 약국 카탈로그는 사용하지 않는다.
    def __init__(
        self,
        hospital_boundary: HospitalLookupBoundary,
        *,
        holiday_boundary: HolidayLookupBoundary | None = None,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._boundary = hospital_boundary
        self._holiday_boundary = holiday_boundary
        self._timezone = ZoneInfo(settings.APPLICATION_TIME_ZONE)
        self._clock = clock or (lambda: datetime.now(self._timezone))

    # 결과 제한은 진료과·운영 필터 적용 후 계산하고 페이지 탐색은 상한을 둔다.
    async def requestNearbyHospitalSearch(
        self,
        *,
        latitude: float,
        longitude: float,
        search_mode: HospitalSearchMode = HospitalSearchMode.ALL,
        target_datetime: datetime | None = None,
        department: str | None = None,
        limit: int = 20,
        max_distance_km: float = 20.0,
    ) -> NearbyHospitalResponse:
        if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
            raise ValueError("Invalid hospital search coordinates.")
        if not 1 <= limit <= 30 or not 0.1 <= max_distance_km <= 50:
            raise ValueError("Invalid hospital search bounds.")
        if department is not None and department not in DEPARTMENT_NAMES:
            raise ValueError("Unsupported hospital department code.")
        search_mode = HospitalSearchMode(search_mode)
        # 약국 검색과 같은 달력일 범위(오늘 기준 7일 전~366일 후)만 허용해 임의 연도의 달력 조회를 막는다.
        target = normalize_target_datetime(
            target_datetime, now=self._clock(), timezone=self._timezone,
        )
        # 라우터의 전체 제한 전에 부분 결과를 반환할 시간을 남긴다.
        deadline = asyncio.get_running_loop().time() + max(
            0.01, settings.HOSPITAL_SEARCH_TIMEOUT_SECONDS - 1,
        )
        today_holiday, previous_holiday = await asyncio.gather(
            self._is_holiday(target.date()),
            self._is_holiday(target.date() - timedelta(days=1)),
        )
        # 평일인 것이 확인되면 주말·공휴일 검색에 불필요한 병원 호출을 하지 않는다.
        if (search_mode == HospitalSearchMode.WEEKEND_HOLIDAY
                and target.isoweekday() < 6 and today_holiday is False):
            return NearbyHospitalResponse(
                data=[], open_only=False, search_mode=search_mode,
                target_datetime=target, department=department,
                max_distance_km=max_distance_km,
                holiday_schedule_status="not_applicable",
            )
        matches: list[NearbyHospitalItem] = []
        seen: set[str] = set()
        partial = False
        more_pages = False
        first_detail_error = None
        detail_successes = 0
        new_detail_requests = 0
        page_size = _PAGE_SIZE
        department_candidates = None
        if department is not None:
            try:
                department_candidates = await find_department_candidates(
                    self._boundary, latitude=latitude, longitude=longitude,
                    radius_km=max_distance_km, department=department,
                    # 상세 진료시간 조회에 쓸 시간을 남긴다.
                    deadline=max(asyncio.get_running_loop().time(), deadline - 5),
                )
            except TimeoutError:
                raise HospitalApiUnavailableError("Hospital department search timed out.") from None
            partial = department_candidates.partial
        for page_no in range(1, settings.HOSPITAL_SEARCH_MAX_PAGES + 1):
            if department_candidates is not None:
                records = department_candidates.records
                more_pages = False
            else:
                try:
                    async with asyncio.timeout_at(deadline):
                        page = await self._boundary.fetchNearbyPage(
                            latitude=latitude, longitude=longitude,
                            page_no=page_no, page_size=page_size,
                        )
                except TimeoutError:
                    if page_no == 1:
                        raise HospitalApiUnavailableError("Hospital search timed out.") from None
                    partial = True
                    break
                except (HospitalApiUnavailableError, HospitalApiResponseError):
                    if page_no == 1:
                        raise
                    partial = True
                    break
                partial = partial or page.row_count > len(page.records)
                page_size = page.page_size
                more_pages = page_no * page_size < page.total_count
                records = page.records
            candidates: list[tuple[HospitalLocationRecord, float]] = []
            detail_ids: set[str] = set()
            for record in records:
                if record.hospital_id in seen:
                    continue
                seen.add(record.hospital_id)
                distance = haversine_distance(
                    latitude, longitude, record.latitude, record.longitude
                )
                if distance <= max_distance_km:
                    candidates.append((record, distance))
            candidates.sort(key=lambda candidate: candidate[1])
            if search_mode == HospitalSearchMode.ALL and department is None:
                candidates = candidates[:max(0, limit - len(matches))]
            for record, _ in candidates:
                if self._boundary.hasCachedDetails(record.hospital_id):
                    detail_ids.add(record.hospital_id)
                elif new_detail_requests < settings.HOSPITAL_DETAIL_REQUEST_BUDGET:
                    detail_ids.add(record.hospital_id)
                    new_detail_requests += 1
                else:
                    partial = True
            details = await self._load_details_with_deadline(candidates, detail_ids, deadline)
            for (record, distance), detail in zip(candidates, details, strict=True):
                if isinstance(detail, (HospitalApiUnavailableError, HospitalApiResponseError)):
                    first_detail_error = first_detail_error or detail
                    partial = True
                    detail = HospitalDetails(record.hospital_id)
                elif record.hospital_id in detail_ids:
                    detail_successes += 1
                if department is not None and not detail.departments and not detail.department_codes:
                    partial = True
                if department is not None and not self._matches_department(detail, department):
                    continue
                item = self._present(record, detail, distance, target, today_holiday, previous_holiday)
                if search_mode != HospitalSearchMode.ALL and (
                    item.is_open_now is None if search_mode == HospitalSearchMode.OPEN_AT_TIME
                    else item.today_open_time is None
                ):
                    partial = True
                if self._matches_mode(item, search_mode, target):
                    matches.append(item)
            if len(matches) >= limit or not more_pages:
                break
            if asyncio.get_running_loop().time() >= deadline:
                partial = True
                break
        if first_detail_error is not None and not detail_successes:
            raise first_detail_error
        matches.sort(key=lambda item: (item.distance_km, item.name, item.hospital_id))
        return NearbyHospitalResponse(
            data=matches[:limit],
            open_only=search_mode == HospitalSearchMode.OPEN_AT_TIME,
            search_mode=search_mode,
            target_datetime=target,
            department=department,
            max_distance_km=max_distance_km,
            # 달력 확인과 날짜별 병원 운영 확정은 구분한다.
            holiday_schedule_status=(
                "unknown" if today_holiday is None
                else "weekly_report" if today_holiday else "not_applicable"
            ),
            search_truncated=partial or more_pages or len(matches) > limit,
            region_scope_uncertain=(
                department_candidates.region_scope_uncertain
                if department_candidates is not None else False
            ),
        )

    # 공휴일 확인 실패 시 평일로 단정하지 않는다.
    async def _is_holiday(self, value: date) -> bool | None:
        if self._holiday_boundary is None:
            return None
        try:
            async with asyncio.timeout(settings.HOSPITAL_CALENDAR_TIMEOUT_SECONDS):
                return await self._holiday_boundary.isHoliday(value)
        except (PharmacyApiUnavailableError, HospitalApiUnavailableError, TimeoutError):
            return None

    # 검색일의 운영표와 제공자에서 확인한 병원 정보만 채팅 스냅샷으로 만든다.
    async def requestShareContext(self, hospital_id: str, schedule_date: date) -> dict[str, object]:
        """서버 상세 조회의 식별 정보와 선택 날짜 시간표만 채팅에 저장한다."""
        # 검색과 같은 달력일 범위만 받아, 임의 날짜로 공휴일 조회를 반복시키지 못하게 한다.
        target = normalize_target_datetime(
            datetime.combine(schedule_date, datetime.min.time()).replace(hour=12),
            now=self._clock(), timezone=self._timezone,
        )
        detail = await self._boundary.fetchDetails(hospital_id)
        if detail.location is None or detail.fetched_at is None:
            raise ValueError("Hospital information could not be verified.")
        holiday = await self._is_holiday(schedule_date)
        hours = {day: (start, end) for day, start, end in detail.weekly_hours}
        key = "8" if holiday else str(target.isoweekday())
        start, end = self._hours(hours.get(key, ("", ""))) if holiday is not None else (None, None)
        location = detail.location
        return {
            "hospital_id": hospital_id, "name": location.name,
            "address": location.address, "telephone": location.telephone,
            "latitude": location.latitude, "longitude": location.longitude,
            "departments": list(detail.departments),
            "schedule_date": schedule_date.isoformat(),
            "today_hours": (f"{format_time(start)} - {format_time(end)}"
                            if start is not None and end is not None else ""),
            "source_updated_at": detail.fetched_at.isoformat(),
        }

    # 일부 상세 조회 실패는 다른 병원의 확인된 결과와 구분해 유지한다.
    async def _load_details(self, hospital_id: str, allowed: bool):
        if not allowed:
            return HospitalDetails(hospital_id)
        try:
            return await self._boundary.fetchDetails(hospital_id)
        except (HospitalApiUnavailableError, HospitalApiResponseError) as exc:
            return exc

    # 느린 상세 한 건 때문에 먼저 받은 진료시간까지 버리지 않는다.
    async def _load_details_with_deadline(self, candidates, detail_ids, deadline):
        if not candidates:
            return []
        tasks = [asyncio.create_task(
            self._load_details(record.hospital_id, record.hospital_id in detail_ids)
        ) for record, _ in candidates]
        try:
            done, _ = await asyncio.wait(
                tasks, timeout=max(0, deadline - asyncio.get_running_loop().time()),
            )
            return [
                task.result() if task in done
                else HospitalApiUnavailableError("Hospital detail timed out.")
                for task in tasks
            ]
        finally:
            for task in tasks:
                if not task.done():
                    task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

    # 코드가 없으면 명시된 진료과명만 정확히 비교하며 병원 이름은 추측하지 않는다.
    @staticmethod
    def _matches_department(details: HospitalDetails, department: str) -> bool:
        return department in details.department_codes or bool(
            set(DEPARTMENT_NAMES.get(department, ())) & set(details.departments)
        )

    # 불완전하거나 동일한 시작·종료 시각은 휴무나 24시간으로 추정하지 않는다.
    @staticmethod
    def _hours(values: tuple[str, str]) -> tuple[int | None, int | None]:
        if not all(re.fullmatch(r"(?:[0-9]{3,4}|[0-9]{1,2}:[0-9]{2})", value) for value in values):
            return None, None
        start = parse_minutes(values[0])
        end = parse_minutes(values[1], allow_24=True)
        if start is None or end is None or start == end:
            return None, None
        return start, end

    # 선택일과 전날의 공휴일 운영표를 따로 선택해 자정 이월을 계산한다.
    @classmethod
    def _present(
        cls, record: HospitalLocationRecord, details: HospitalDetails,
        distance: float, target: datetime, today_holiday: bool | None,
        previous_holiday: bool | None,
    ) -> NearbyHospitalItem:
        hours = {day: (start, end) for day, start, end in details.weekly_hours}
        today_key = "8" if today_holiday else str(target.isoweekday())
        previous = target.date() - timedelta(days=1)
        previous_key = "8" if previous_holiday else str(previous.isoweekday())
        start, end = cls._hours(hours.get(today_key, ("", ""))) if today_holiday is not None else (None, None)
        prev_start, prev_end = cls._hours(hours.get(previous_key, ("", ""))) if previous_holiday is not None else (None, None)
        opened = is_open_now(
            now=target, start_minutes=start, end_minutes=end,
            previous_start_minutes=prev_start, previous_end_minutes=prev_end,
        )
        # 당일 표가 모호하면 전날 이월 근거만으로 현재 시간을 확정하지 않는다.
        if today_holiday is None:
            opened = None
        elif opened is not True and previous_holiday is None:
            possible_previous = [cls._hours(hours.get(key, ("", ""))) for key in ("8", str(previous.isoweekday()))]
            if any(s is None or e is None or (e < s and target.hour * 60 + target.minute < e)
                   for s, e in possible_previous):
                opened = None
        # 휴게·접수 안내 등 비정형 예외가 있으면 시간표만으로 진료 중을 확정하지 않는다.
        if opened is True and details.operating_notes:
            opened = None
        # 저녁 진료는 선택일의 18시 이후와 겹치는 운영표이며, 18시 정각 종료는 제외한다.
        late = (start is not None and end is not None
                and (end + (1440 if end < start else 0)) > 18 * 60)
        return NearbyHospitalItem(
            hospital_id=record.hospital_id, name=record.name,
            address=record.address, telephone=record.telephone,
            latitude=record.latitude, longitude=record.longitude,
            distance_km=round(distance, 3),
            departments=list(details.departments), institution_type=details.institution_type or record.institution_type,
            operating_notes=details.operating_notes,
            today_open_time=format_time(start),
            today_close_time=format_time(end), is_open_now=opened,
            is_24_hours=start == 0 and end in {1439, 1440}, is_open_late=late,
            has_weekend_or_holiday_hours=any(
                cls._hours(hours.get(day, ("", "")))[0] is not None for day in ("6", "7", "8")
            ),
            is_public_holiday=today_holiday is True, schedule_date=target.date(),
            schedule_source="nemc_hospital_weekly_report" if start is not None or opened is True else "unknown",
            minutes_until_close=minutes_until_close(
                now=target, is_open_now=opened, start_minutes=start, end_minutes=end,
                previous_start_minutes=prev_start, previous_end_minutes=prev_end,
            ),
        )

    # 주말·휴일 필터는 기존 화면처럼 선택한 날짜의 운영표를 기준으로 한다.
    @staticmethod
    def _matches_mode(item: NearbyHospitalItem, mode: HospitalSearchMode, target: datetime) -> bool:
        if mode == HospitalSearchMode.ALL:
            return True
        if mode == HospitalSearchMode.OPEN_AT_TIME:
            return item.is_open_now is True
        if mode == HospitalSearchMode.LATE_HOURS:
            return item.is_open_late
        return (target.isoweekday() >= 6 or item.is_public_holiday) and item.today_open_time is not None
