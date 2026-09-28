"""병원 공공데이터의 위치, 진료과와 주간 운영표."""

from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True, slots=True)
class HospitalLocationRecord:
    hospital_id: str
    name: str
    address: str
    telephone: str
    latitude: float
    longitude: float
    institution_type: str | None = None


@dataclass(frozen=True, slots=True)
class HospitalLocationPage:
    records: tuple[HospitalLocationRecord, ...]
    total_count: int
    row_count: int
    page_size: int


@dataclass(frozen=True, slots=True)
class HospitalDetails:
    hospital_id: str
    departments: tuple[str, ...] = ()
    department_codes: tuple[str, ...] = ()
    institution_type: str | None = None
    weekly_hours: tuple[tuple[str, str, str], ...] = ()
    operating_notes: str | None = None
    location: HospitalLocationRecord | None = None
    fetched_at: datetime | None = None
