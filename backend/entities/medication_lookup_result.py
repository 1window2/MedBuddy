# 파일명: medication_lookup_result.py
# 역할: 약 후보 상세와 요약 처리의 완전성 여부를 함께 전달한다.
from dataclasses import dataclass, field

from entities.medication_detail_entity import MedicationDetail


# 후보 요약 누락 여부를 목록과 함께 전달해 부분 성공이 자동 선택 근거가 되지 않게 한다.
# is_complete는 조회된 후보의 요약 성공 여부이며 전체 카탈로그 검색을 보장하지 않는다.
# 클래스명: MedicationLookupResult
# 역할: 후보 목록이 일부 요약 실패를 포함하는지 나타내는 조회 결과다.
# 주요 책임: 부분 성공 목록을 확정적 자동 선택의 근거로 사용하지 않게 한다.
# 속성: details (list[MedicationDetail])는 반환 후보, is_complete (bool)는 조회된 후보들의 요약 완료 여부다.
@dataclass(frozen=True)
class MedicationLookupResult:
    details: list[MedicationDetail] = field(default_factory=list)
    is_complete: bool = True
