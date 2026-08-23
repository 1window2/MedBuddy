import 'medication_schedule_entity.dart';
import 'pill_identification_entity.dart';

// 파일명: identified_pill_save_request_entity.dart
// 역할: 사용자가 확인한 낱알약 후보와 복약 일정을 하나의 저장 요청으로 묶는다.

// 클래스명: IdentifiedPillSaveRequest
// 역할: 다중 낱알약 저장 과정에서 후보와 해당 일정을 같은 순서로 안전하게 전달한다.
class IdentifiedPillSaveRequest {
  final PillIdentificationCandidate candidate;
  final MedicationSchedule medicationSchedule;

  const IdentifiedPillSaveRequest({
    required this.candidate,
    required this.medicationSchedule,
  });
}
