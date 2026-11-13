// 파일명: medication_match_review_entity.dart
// 역할: 자동 확정할 수 없는 약 검색 후보를 사용자 검토 단계로 전달한다.
import 'medication_detail_entity.dart';

// 불확실한 검색 결과를 자동 연결하지 않고 사용자 확인 단계로 전달한다.
// 클래스명: MedicationMatchReview
// 역할: 약 검색 결과의 모호성을 검토 가능한 예외로 전달한다.
// 주요 책임: 후보 목록을 수정 불가능하게 보관하고 검토 사유를 전달한다.
// 속성: candidates (List<MedicationDetail>): 후보 목록; reason (String): 검토 사유 코드.
class MedicationMatchReview implements Exception {
  final List<MedicationDetail> candidates;
  final String reason;

  // 함수이름: MedicationMatchReview
  // 함수역할: 검색 후보를 변경 불가능한 목록으로 복사해 예외에 보관한다.
  // 매개변수: candidates (List<MedicationDetail>): 검토할 후보; reason (String): 기본 ambiguous_product인 사유.
  // 반환값: 후보와 사유를 가진 예외. 후보가 비어 있어도 허용한다.
  MedicationMatchReview(
    List<MedicationDetail> candidates, {
    this.reason = 'ambiguous_product',
  }) : candidates = List.unmodifiable(candidates);
}
