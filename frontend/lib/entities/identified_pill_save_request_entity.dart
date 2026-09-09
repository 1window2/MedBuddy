import 'medication_schedule_entity.dart';
import 'pill_identification_entity.dart';

// 파일명: identified_pill_save_request_entity.dart
// 역할: 사용자가 확인한 낱알약 후보와 복약 일정을 하나의 저장 요청으로 묶는다.

// 클래스명: IdentifiedPillSaveRequest
// 역할: 확인한 알약 후보와 해당 복약 일정을 한 저장 단위로 묶는다.
// 주요 책임:
// - 다중 식별 결과 저장 시 후보와 일정의 대응이 섞이지 않도록 유지한다.
// 속성:
// - candidate (PillIdentificationCandidate): 사용자가 선택하거나 동일성을 비교할 알약 후보
// - medicationSchedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
class IdentifiedPillSaveRequest {
  final PillIdentificationCandidate candidate;
  final MedicationSchedule medicationSchedule;

  // 함수이름: IdentifiedPillSaveRequest
  // 함수역할: 사용자가 확인한 알약 후보와 검토한 복약 일정을 함께 묶어 중복 병합과 저장에 전달한다.
  // 매개변수:
  // - candidate (PillIdentificationCandidate): 사용자가 선택하거나 동일성을 비교할 알약 후보
  // - medicationSchedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
  // 반환값:
  // - IdentifiedPillSaveRequest: 초기화된 인스턴스.
  const IdentifiedPillSaveRequest({
    required this.candidate,
    required this.medicationSchedule,
  });
}
