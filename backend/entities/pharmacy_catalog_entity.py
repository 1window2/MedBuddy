# 파일명: pharmacy_catalog_entity.py
# 역할: 전국 약국 카탈로그와 정규화된 요일별 운영시간을 저장한다.

from dataclasses import dataclass, field
from datetime import date, datetime

from sqlalchemy import Column, Date, DateTime, Float, Integer, JSON, String, Text, func

from core.database import Base


@dataclass(frozen=True, slots=True)
class PharmacyCatalogEntry:
    """국립중앙의료원 약국 데이터를 조회용 불변 값으로 표현한다."""

    pharmacy_id: str
    name: str
    address: str
    telephone: str
    latitude: float
    longitude: float
    weekly_hours: dict[str, tuple[str, str]]
    official_designations: dict[str, object] = field(default_factory=dict)
    source_updated_at: datetime | None = None

    def hours_for(self, *, day_of_week: int, is_public_holiday: bool) -> tuple[str, str]:
        """요일 또는 공휴일에 해당하는 운영시간을 반환한다."""
        schedule_key = "8" if is_public_holiday else str(day_of_week)
        return self.weekly_hours.get(schedule_key, ("", ""))

    @property
    def has_weekend_or_holiday_hours(self) -> bool:
        """주말이나 공휴일 운영시간이 하나라도 등록되었는지 확인한다."""
        return any(
            self.weekly_hours.get(schedule_key, ("", ""))[0]
            for schedule_key in ("6", "7", "8")
        )


class PharmacyCatalogRecord(Base):
    """전국 공공 약국 카탈로그의 교체 가능한 로컬 사본을 저장한다."""

    __tablename__ = "pharmacy_catalog_records"

    pharmacy_id = Column(String(length=32), primary_key=True)
    name = Column(String(length=300), index=True, nullable=False)
    address = Column(Text, nullable=False, default="")
    telephone = Column(String(length=80), nullable=False, default="")
    latitude = Column(Float, index=True, nullable=False)
    longitude = Column(Float, index=True, nullable=False)
    weekly_hours = Column(JSON, nullable=False, default=dict)
    official_designations = Column(JSON, nullable=False, default=dict)
    source_updated_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


@dataclass(frozen=True, slots=True)
class PharmacyHolidaySchedule:
    """Date-specific pharmacy schedule reported by the NEMC holiday roster."""

    pharmacy_id: str
    schedule_date: date
    start_time: str
    end_time: str
    note: str = ""


class PharmacyHolidayScheduleRecord(Base):
    """Persistent, bounded cache of date-specific NEMC holiday schedules."""

    __tablename__ = "pharmacy_holiday_schedules"

    schedule_date = Column(Date, primary_key=True)
    pharmacy_id = Column(String(length=32), primary_key=True)
    start_time = Column(String(length=8), nullable=False, default="")
    end_time = Column(String(length=8), nullable=False, default="")
    note = Column(Text, nullable=False, default="")
    fetched_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


class PharmacyHolidayFetchRecord(Base):
    """Records successful fetches, including dates with zero roster entries."""

    __tablename__ = "pharmacy_holiday_fetches"

    schedule_date = Column(Date, primary_key=True)
    row_count = Column(Integer, nullable=False, default=0)
    fetched_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


class KoreanHolidayRecord(Base):
    """Persistent legal-holiday date returned by the government calendar API."""

    __tablename__ = "korean_holidays"

    holiday_date = Column(Date, primary_key=True)
    fetched_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


class KoreanHolidayMonthFetchRecord(Base):
    """Records fetched months so an empty month is also cached safely."""

    __tablename__ = "korean_holiday_month_fetches"

    month_key = Column(String(length=7), primary_key=True)
    row_count = Column(Integer, nullable=False, default=0)
    fetched_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )
