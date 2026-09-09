# File Name: pharmacy_catalog_repository.py
# Role: Stores and searches the normalized nationwide pharmacy catalogue.

import math
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import func
from sqlalchemy.orm import Session

from entities.pharmacy_catalog_entity import (
    KoreanHolidayMonthFetchRecord,
    KoreanHolidayRecord,
    PharmacyCatalogEntry,
    PharmacyCatalogRecord,
    PharmacyHolidayFetchRecord,
    PharmacyHolidaySchedule,
    PharmacyHolidayScheduleRecord,
)


# 클래스명: PharmacyCatalogRepository
# 역할:
# - 전국 약국 카탈로그와 날짜별 영업·공휴일 캐시의 DB 접근을 맡는다.
# 주요 책임:
# - 근접 후보를 좌표 사각형으로 추리고 카탈로그 및 공식 지정 정보를 갱신한다.
# - 공휴일 캐시는 조회 시각을 별도로 기록하여 빈 결과와 캐시 부재를 구분한다.
# 속성:
# - db (Session): 카탈로그 조회와 교체에 사용할 SQLAlchemy 세션.
class PharmacyCatalogRepository:
    """Database adapter for the replaceable public pharmacy catalogue."""

    # Function Name: __init__
    # Description:
    # - Bind the caller's database session for pharmacy catalog and holiday-cache operations.
    # Parameters:
    # - db (Session): Caller-provided SQLAlchemy session for persisted records.
    # Returns:
    # - None; session lifetime remains with the caller.
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: count
    # Description:
    # - Count all persisted nationwide pharmacy records without loading catalog entries.
    # Parameters:
    # - None.
    # Returns:
    # - Number of pharmacy catalog rows.
    def count(self) -> int:
        return self.db.query(PharmacyCatalogRecord).count()

    # 함수이름: find_by_id
    # 함수역할:
    # - 공유 메시지에 사용할 약국 행을 기본키로 찾고 경계용 엔트리로 변환한다.
    # 매개변수:
    # - pharmacy_id (str): 조회할 공공 약국 식별자.
    # 반환값:
    # - 약국 카탈로그 엔트리 또는 ID가 없으면 None.
    def find_by_id(self, pharmacy_id: str) -> PharmacyCatalogEntry | None:
        """공유 메시지에 사용할 약국 한 건을 식별자로 조회한다."""
        row = self.db.get(PharmacyCatalogRecord, pharmacy_id)
        return self._to_entry(row) if row is not None else None

    # 함수이름: latest_source_updated_at
    # 함수역할:
    # - 현재 카탈로그 행의 공공데이터 갱신 시각 중 최댓값을 조회한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 가장 최근 갱신 시각 또는 카탈로그가 비어 있으면 None.
    def latest_source_updated_at(self) -> datetime | None:
        """현재 카탈로그에서 가장 최근의 공공데이터 갱신 시각을 반환한다."""
        return self.db.query(
            func.max(PharmacyCatalogRecord.source_updated_at)
        ).scalar()

    # Function Name: is_fresh
    # Description:
    # - Require the minimum catalog size and compare the newest source timestamp with the allowed age.
    # Parameters:
    # - minimum_rows (int): Minimum row count required for a usable nationwide snapshot.
    # - max_age (timedelta): Maximum permitted age of the cached snapshot.
    # Returns:
    # - True when enough rows exist and the newest source timestamp meets the cutoff.
    def is_fresh(self, *, minimum_rows: int, max_age: timedelta) -> bool:
        if self.count() < minimum_rows:
            return False
        newest_update = self.db.query(
            func.max(PharmacyCatalogRecord.source_updated_at)
        ).scalar()
        if newest_update is None:
            return False
        cutoff = datetime.now(UTC).replace(tzinfo=None) - max_age
        return newest_update >= cutoff

    # Function Name: latest_updated_at
    # Description:
    # - Read the maximum source-update timestamp without materializing pharmacy entries.
    # Parameters:
    # - None.
    # Returns:
    # - Newest catalog source timestamp, or None when no timestamp exists.
    def latest_updated_at(self) -> datetime | None:
        return self.db.query(
            func.max(PharmacyCatalogRecord.source_updated_at)
        ).scalar()

    # Function Name: search_nearby_candidates
    # Description:
    # - Select a latitude/longitude bounding box covering the search radius, adjusting longitude span for latitude.
    # Parameters:
    # - latitude (float): WGS84 latitude of the search center.
    # - longitude (float): WGS84 longitude of the search center.
    # - max_distance_km (float): Radius in kilometers used to construct the bounding box.
    # Returns:
    # - Candidate entries in the box; exact radial distance filtering remains with the caller.
    def search_nearby_candidates(
        self,
        *,
        latitude: float,
        longitude: float,
        max_distance_km: float,
    ) -> list[PharmacyCatalogEntry]:
        latitude_delta = max_distance_km / 110.574
        longitude_scale = max(abs(math.cos(math.radians(latitude))), 0.01)
        longitude_delta = max_distance_km / (111.320 * longitude_scale)
        rows = (
            self.db.query(PharmacyCatalogRecord)
            .filter(
                PharmacyCatalogRecord.latitude.between(
                    latitude - latitude_delta,
                    latitude + latitude_delta,
                ),
                PharmacyCatalogRecord.longitude.between(
                    longitude - longitude_delta,
                    longitude + longitude_delta,
                ),
            )
            .all()
        )
        return [self._to_entry(row) for row in rows]

    # Function Name: replace_all
    # Description:
    # - Replace the full catalog using bulk mappings; commit here or flush into the caller's transaction.
    # Parameters:
    # - entries (list[PharmacyCatalogEntry]): Complete normalized pharmacy snapshot to persist.
    # - commit (bool): Whether to commit and own rollback, or only flush for the caller.
    # Returns:
    # - None; rolls back on failure only when this operation owns the commit.
    def replace_all(
        self,
        entries: list[PharmacyCatalogEntry],
        *,
        commit: bool = True,
    ) -> None:
        mappings = [
            {
                "pharmacy_id": entry.pharmacy_id,
                "name": entry.name,
                "address": entry.address,
                "telephone": entry.telephone,
                "latitude": entry.latitude,
                "longitude": entry.longitude,
                "weekly_hours": {
                    key: [hours[0], hours[1]]
                    for key, hours in entry.weekly_hours.items()
                },
                "official_designations": entry.official_designations,
            }
            for entry in entries
        ]
        try:
            self.db.query(PharmacyCatalogRecord).delete(synchronize_session=False)
            self.db.bulk_insert_mappings(PharmacyCatalogRecord, mappings)
            if commit:
                self.db.commit()
            else:
                self.db.flush()
        except Exception:
            if commit:
                self.db.rollback()
            raise

    # Function Name: apply_official_designations_by_phone
    # Description:
    # - Match designation overlays by digit-only phone and normalized name, clearing unmatched overlays without changing source timestamps.
    # Parameters:
    # - designations_by_phone (dict[str, dict[str, object]]): Official late-night designations keyed by normalized telephone digits.
    # Returns:
    # - Number of matched pharmacy designations; commits updates or rolls back on failure.
    def apply_official_designations_by_phone(
        self,
        designations_by_phone: dict[str, dict[str, object]],
    ) -> int:
        """Updates designation overlays without downloading the full catalogue."""

        matched = 0
        mappings: list[dict[str, object]] = []
        try:
            for row in self.db.query(PharmacyCatalogRecord).all():
                normalized_phone = "".join(
                    character for character in (row.telephone or "")
                    if character.isdigit()
                )
                designation = designations_by_phone.get(normalized_phone)
                if designation is not None:
                    expected_name = "".join(
                        character
                        for character in str(designation.get("name", ""))
                        if character.isalnum()
                    ).casefold()
                    actual_name = "".join(
                        character for character in row.name if character.isalnum()
                    ).casefold()
                    if expected_name != actual_name:
                        designation = None
                next_value = (
                    {"public_late_night": designation}
                    if designation is not None
                    else {}
                )
                if designation is not None:
                    matched += 1
                mappings.append(
                    {
                        "pharmacy_id": row.pharmacy_id,
                        "official_designations": next_value,
                        "source_updated_at": row.source_updated_at,
                    }
                )
            self.db.bulk_update_mappings(PharmacyCatalogRecord, mappings)
            self.db.commit()
        except Exception:
            self.db.rollback()
            raise
        return matched

    # 함수이름: _to_entry
    # 함수역할:
    # - 저장된 영업시간 JSON을 요일별 시간 쌍으로 바꾸고 누락된 선택 필드를 안전한 기본값으로 채운다.
    # 매개변수:
    # - row (PharmacyCatalogRecord): 변환할 영속 약국 카탈로그 행.
    # 반환값:
    # - DB 행에서 구성한 PharmacyCatalogEntry.
    @staticmethod
    def _to_entry(row: PharmacyCatalogRecord) -> PharmacyCatalogEntry:
        raw_hours = row.weekly_hours if isinstance(row.weekly_hours, dict) else {}
        weekly_hours: dict[str, tuple[str, str]] = {}
        for key, value in raw_hours.items():
            if isinstance(value, (list, tuple)) and len(value) == 2:
                weekly_hours[str(key)] = (str(value[0]), str(value[1]))
        return PharmacyCatalogEntry(
            pharmacy_id=row.pharmacy_id,
            name=row.name,
            address=row.address or "",
            telephone=row.telephone or "",
            latitude=row.latitude,
            longitude=row.longitude,
            weekly_hours=weekly_hours,
            official_designations=(
                dict(row.official_designations)
                if isinstance(row.official_designations, dict)
                else {}
            ),
            source_updated_at=row.source_updated_at,
        )

    # Function Name: get_cached_holiday_schedules
    # Description:
    # - Require a fresh date-fetch marker before reading the pharmacy holiday schedules for that date.
    # Parameters:
    # - value (date): Exact date whose pharmacy schedules are requested.
    # - max_age (timedelta): Maximum permitted age of the cached snapshot.
    # Returns:
    # - Schedules keyed by pharmacy ID, an empty dict for a known empty roster, or None for missing/stale cache.
    def get_cached_holiday_schedules(
        self,
        value: date,
        *,
        max_age: timedelta,
    ) -> dict[str, PharmacyHolidaySchedule] | None:
        fetch = self.db.get(PharmacyHolidayFetchRecord, value)
        if fetch is None:
            return None
        cutoff = datetime.now(UTC).replace(tzinfo=None) - max_age
        if fetch.fetched_at < cutoff:
            return None
        rows = (
            self.db.query(PharmacyHolidayScheduleRecord)
            .filter(PharmacyHolidayScheduleRecord.schedule_date == value)
            .all()
        )
        return {
            row.pharmacy_id: PharmacyHolidaySchedule(
                pharmacy_id=row.pharmacy_id,
                schedule_date=row.schedule_date,
                start_time=row.start_time,
                end_time=row.end_time,
                note=row.note or "",
            )
            for row in rows
        }

    # Function Name: replace_holiday_schedules
    # Description:
    # - Replace one date's holiday roster and commit a fetch marker even when the schedule list is empty.
    # Parameters:
    # - value (date): Date whose existing schedule rows are replaced.
    # - schedules (list[PharmacyHolidaySchedule]): Complete holiday schedule snapshot for that date.
    # Returns:
    # - None; rolls back and re-raises on failure.
    def replace_holiday_schedules(
        self,
        value: date,
        schedules: list[PharmacyHolidaySchedule],
    ) -> None:
        try:
            (
                self.db.query(PharmacyHolidayScheduleRecord)
                .filter(PharmacyHolidayScheduleRecord.schedule_date == value)
                .delete(synchronize_session=False)
            )
            for schedule in schedules:
                self.db.add(
                    PharmacyHolidayScheduleRecord(
                        schedule_date=value,
                        pharmacy_id=schedule.pharmacy_id,
                        start_time=schedule.start_time,
                        end_time=schedule.end_time,
                        note=schedule.note,
                    )
                )
            fetch = self.db.get(PharmacyHolidayFetchRecord, value)
            if fetch is None:
                fetch = PharmacyHolidayFetchRecord(schedule_date=value)
                self.db.add(fetch)
            fetch.row_count = len(schedules)
            fetch.fetched_at = datetime.now(UTC).replace(tzinfo=None)
            self.db.commit()
        except Exception:
            self.db.rollback()
            raise

    # Function Name: get_cached_korean_holidays
    # Description:
    # - Validate the monthly fetch timestamp and read legal-holiday dates within the month's exclusive upper bound.
    # Parameters:
    # - year (int): Calendar year of the requested holiday month.
    # - month (int): Calendar month, from 1 through 12.
    # - max_age (timedelta): Maximum permitted age of the cached snapshot.
    # Returns:
    # - Immutable cached dates, including an empty set, or None for a missing or expired fetch marker.
    def get_cached_korean_holidays(
        self,
        year: int,
        month: int,
        *,
        max_age: timedelta,
    ) -> frozenset[date] | None:
        month_key = f"{year:04d}-{month:02d}"
        fetch = self.db.get(KoreanHolidayMonthFetchRecord, month_key)
        if fetch is None:
            return None
        cutoff = datetime.now(UTC).replace(tzinfo=None) - max_age
        if fetch.fetched_at < cutoff:
            return None
        start = date(year, month, 1)
        end = date(year + (month == 12), 1 if month == 12 else month + 1, 1)
        rows = (
            self.db.query(KoreanHolidayRecord)
            .filter(
                KoreanHolidayRecord.holiday_date >= start,
                KoreanHolidayRecord.holiday_date < end,
            )
            .all()
        )
        return frozenset(row.holiday_date for row in rows)

    # Function Name: replace_korean_holidays
    # Description:
    # - Replace one month's legal-holiday rows and update its fetch count and timestamp in one transaction.
    # Parameters:
    # - year (int): Calendar year of the requested holiday month.
    # - month (int): Calendar month, from 1 through 12.
    # - holidays (frozenset[date]): Complete set of legal holiday dates for the month.
    # Returns:
    # - None; commits the snapshot or rolls back and re-raises on failure.
    def replace_korean_holidays(
        self,
        year: int,
        month: int,
        holidays: frozenset[date],
    ) -> None:
        month_key = f"{year:04d}-{month:02d}"
        start = date(year, month, 1)
        end = date(year + (month == 12), 1 if month == 12 else month + 1, 1)
        try:
            (
                self.db.query(KoreanHolidayRecord)
                .filter(
                    KoreanHolidayRecord.holiday_date >= start,
                    KoreanHolidayRecord.holiday_date < end,
                )
                .delete(synchronize_session=False)
            )
            for holiday in holidays:
                self.db.add(KoreanHolidayRecord(holiday_date=holiday))
            fetch = self.db.get(KoreanHolidayMonthFetchRecord, month_key)
            if fetch is None:
                fetch = KoreanHolidayMonthFetchRecord(month_key=month_key)
                self.db.add(fetch)
            fetch.row_count = len(holidays)
            fetch.fetched_at = datetime.now(UTC).replace(tzinfo=None)
            self.db.commit()
        except Exception:
            self.db.rollback()
            raise
