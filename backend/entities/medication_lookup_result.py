from dataclasses import dataclass, field

from entities.medication_detail_entity import MedicationDetail


# 후보 요약 누락 여부를 목록과 함께 전달해 부분 성공이 자동 선택 근거가 되지 않게 한다.
# is_complete는 조회된 후보의 요약 성공 여부이며 전체 카탈로그 검색을 보장하지 않는다.
@dataclass(frozen=True)
class MedicationLookupResult:
    details: list[MedicationDetail] = field(default_factory=list)
    is_complete: bool = True
