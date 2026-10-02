import 'medication_detail_entity.dart';

// 불확실한 검색 결과를 자동 연결하지 않고 사용자 확인 단계로 전달한다.
class MedicationMatchReview implements Exception {
  final List<MedicationDetail> candidates;
  final String reason;

  MedicationMatchReview(
    List<MedicationDetail> candidates, {
    this.reason = 'ambiguous_product',
  }) : candidates = List.unmodifiable(candidates);
}
