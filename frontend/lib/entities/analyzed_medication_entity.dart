import 'medication_detail_entity.dart';
import 'medication_schedule_entity.dart';

// 파일명: analyzed_medication_entity.dart
// 역할: 처방전 OCR 결과와 공공데이터 분석 결과를 하나로 묶는 모델을 정의한다.

// 클래스명: AnalyzedMedication
// 역할: 사용자가 분석 결과를 확인하고 저장할 때 필요한 스케줄 정보와 약 상세 정보를 함께 보관한다.
// 주요 책임:
// - OCR에서 추출한 복약 스케줄을 유지한다.
// - 공공데이터 API로 보강한 약 상세 정보를 유지한다.
// - 화면 표시용 약 이름을 안정적으로 제공한다.
class AnalyzedMedication {
  final MedicationSchedule schedule;
  final MedicationDetail detail;

  const AnalyzedMedication({
    required this.schedule,
    required this.detail,
  });

  // 함수명: displayName
  // 함수역할:
  // - 상세 정보의 약 이름을 우선 사용하고, 없으면 OCR에서 추출한 이름을 사용한다.
  // 반환값:
  // - 화면에 표시할 약 이름
  String get displayName {
    if (detail.itemName.trim().isNotEmpty) {
      return detail.itemName.trim();
    }
    return schedule.displayName;
  }
}
