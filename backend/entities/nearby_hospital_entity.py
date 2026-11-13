# 파일명: nearby_hospital_entity.py
# 역할: 검증된 병원 위치 페이지와 상세 시간표를 불변 데이터로 전달한다.
"""병원 공공데이터의 위치, 진료과와 주간 운영표."""

from dataclasses import dataclass
from datetime import datetime


# 클래스명: HospitalLocationRecord
# 역할: 제공자에서 확인한 병원의 위치·연락 정보를 보관한다.
# 주요 책임: 검색 거리 계산과 공유 문맥에 같은 병원 식별자를 전달한다.
# 속성: hospital_id·name·address·telephone은 str, latitude·longitude는 float, institution_type은 str | None이다.
@dataclass(frozen=True, slots=True)
class HospitalLocationRecord:
    hospital_id: str
    name: str
    address: str
    telephone: str
    latitude: float
    longitude: float
    institution_type: str | None = None


# 클래스명: HospitalLocationPage
# 역할: 유효한 위치 행과 원본 페이지 통계를 함께 보관한다.
# 주요 책임: 잘못된 행을 제외한 뒤에도 페이지 종료·부분 결과 여부를 계산할 근거를 유지한다.
# 속성: records는 HospitalLocationRecord tuple, total_count·row_count·page_size는 전체·원본 행·페이지 크기 int다.
@dataclass(frozen=True, slots=True)
class HospitalLocationPage:
    records: tuple[HospitalLocationRecord, ...]
    total_count: int
    row_count: int
    page_size: int


# 클래스명: HospitalDetails
# 역할: 진료과와 요일별 운영표 및 공유용 검증 위치를 보관한다.
# 주요 책임: 누락 상세를 빈 tuple·None으로 표현하며 운영 상태 자체를 추정하지 않는다.
# 속성: hospital_id는 str, departments·department_codes는 str tuple, weekly_hours는 (요일, 시작, 종료) tuple이다.
#   institution_type·operating_notes는 str | None, location은 HospitalLocationRecord | None, fetched_at은 datetime | None이다.
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
