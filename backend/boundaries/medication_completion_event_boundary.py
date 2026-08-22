# 파일명: medication_completion_event_boundary.py
# 역할: 복약 완료 저장과 후속 알림 처리 사이의 의존성 계약을 정의한다.

from typing import Protocol


# 클래스명: MedicationCompletionEventBoundary
# 역할: 복약 완료 이벤트를 소비하는 후속 처리기의 인터페이스를 정의한다.
class MedicationCompletionEventBoundary(Protocol):
    # 함수명: notifySlotCompleted
    # 역할:
    # - 한 복약 시간대의 모든 약이 새로 완료되었음을 후속 처리기에 전달한다.
    # 매개변수:
    # - patient_hash: 복약한 환자의 소유권 hash
    # - slot_key: 완료된 복약 시간대
    # 반환값:
    # - 후속 처리 결과 객체 또는 결과가 필요 없는 구현의 None
    def notifySlotCompleted(
        self,
        *,
        patient_hash: str,
        slot_key: str,
    ) -> object | None: ...
