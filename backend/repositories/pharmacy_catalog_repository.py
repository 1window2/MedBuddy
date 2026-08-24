# File Name: pharmacy_catalog_repository.py
# Role: Stores and searches the normalized nationwide pharmacy catalogue.

import math
from datetime import UTC, datetime, timedelta

from sqlalchemy import func
from sqlalchemy.orm import Session

from entities.pharmacy_catalog_entity import PharmacyCatalogEntry, PharmacyCatalogRecord


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
        )

