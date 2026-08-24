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


class PharmacyCatalogRepository:
    """Database adapter for the replaceable public pharmacy catalogue."""

    def __init__(self, db: Session) -> None:
        self.db = db

    def count(self) -> int:
        return self.db.query(PharmacyCatalogRecord).count()

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

    def latest_updated_at(self) -> datetime | None:
        return self.db.query(
            func.max(PharmacyCatalogRecord.source_updated_at)
        ).scalar()

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
        )

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
