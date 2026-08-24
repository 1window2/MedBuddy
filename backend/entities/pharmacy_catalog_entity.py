# File Name: pharmacy_catalog_entity.py
# Role: Persistent nationwide pharmacy catalogue and normalized weekly schedules.

from dataclasses import dataclass
from sqlalchemy import Column, DateTime, Float, JSON, String, Text, func

from core.database import Base


@dataclass(frozen=True, slots=True)
class PharmacyCatalogEntry:
    """Normalized National Emergency Medical Center pharmacy record."""

    pharmacy_id: str
    name: str
    address: str
    telephone: str
    latitude: float
    longitude: float
    weekly_hours: dict[str, tuple[str, str]]

    def hours_for(self, *, day_of_week: int, is_public_holiday: bool) -> tuple[str, str]:
        schedule_key = "8" if is_public_holiday else str(day_of_week)
        return self.weekly_hours.get(schedule_key, ("", ""))

    @property
    def has_weekend_or_holiday_hours(self) -> bool:
        return any(
            self.weekly_hours.get(schedule_key, ("", ""))[0]
            for schedule_key in ("6", "7", "8")
        )


class PharmacyCatalogRecord(Base):
    """Replaceable cached copy of the nationwide public pharmacy catalogue."""

    __tablename__ = "pharmacy_catalog_records"

    pharmacy_id = Column(String(length=32), primary_key=True)
    name = Column(String(length=300), index=True, nullable=False)
    address = Column(Text, nullable=False, default="")
    telephone = Column(String(length=80), nullable=False, default="")
    latitude = Column(Float, index=True, nullable=False)
    longitude = Column(Float, index=True, nullable=False)
    weekly_hours = Column(JSON, nullable=False, default=dict)
    source_updated_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )
