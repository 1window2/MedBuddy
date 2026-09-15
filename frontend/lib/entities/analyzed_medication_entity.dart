import 'medication_detail_entity.dart';
import 'medication_schedule_entity.dart';

// 파일명: analyzed_medication_entity.dart
// 역할: 처방전 OCR 결과와 공공데이터 분석 결과를 하나로 묶는 모델을 정의한다.

// 클래스명: AnalyzedMedication
// 역할: 사용자가 분석 결과를 확인하고 저장할 때 필요한 스케줄 정보와 약 상세 정보를 함께 보관한다.
// 주요 책임:
// - OCR에서 추출한 복약 스케줄을 유지한다.
// - 공공데이터 API로 보강한 약 상세 정보를 유지한다.
// - 사용자 OCR 수정명과 공공데이터 약 이름의 우선순위를 적용한다.
// 속성:
// - schedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
// - detail (MedicationDetail): 복약 일정과 연결할 약 상세 정보
class AnalyzedMedication {
  final MedicationSchedule schedule;
  final MedicationDetail detail;

  // 함수이름: AnalyzedMedication
  // 함수역할: 처방전에서 인식한 일정과 조회한 약 상세정보를 같은 분석 항목으로 묶어 이름 선택과 저장에 사용한다.
  // 매개변수:
  // - schedule (MedicationSchedule): 처리할 약 이름·복용량·기간·시간대 일정
  // - detail (MedicationDetail): 복약 일정과 연결할 약 상세 정보
  // 반환값:
  // - AnalyzedMedication: 초기화된 인스턴스.
  const AnalyzedMedication({required this.schedule, required this.detail});

  // 함수이름: displayName
  // 함수역할: 사용자가 OCR 약명을 수정한 경우 수정명을 가장 먼저 사용한다. 그 외에는 상세 정보의 약 이름을 우선하고 없으면 OCR 약명을 사용한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 화면에 표시할 약 이름
  String get displayName {
    if (schedule.nameCorrectionSource == 'user_edit' &&
        schedule.medicationName.trim().isNotEmpty) {
      return schedule.medicationName.trim();
    }
    if (detail.itemName.trim().isNotEmpty) {
      return detail.itemName.trim();
    }
    return schedule.displayName;
  }

  // 함수이름: displayNameForLanguage
  // 함수역할: 사용자 수정명과 공공데이터 약품명 우선순위는 유지한다. 두 이름이 모두 비어 있을 때만 현재 언어에 맞는 대체 문구를 사용한다.
  // 매개변수:
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - String: 사용자 수정명과 공공데이터 약품명 우선순위는 유지한다. 두 이름이 모두 비어 있을 때만 현재 언어에 맞는 대체 문구를 사용한다.
  String displayNameForLanguage(String language) {
    if (schedule.nameCorrectionSource == 'user_edit' &&
        schedule.medicationName.trim().isNotEmpty) {
      return schedule.medicationName.trim();
    }
    if (detail.itemName.trim().isNotEmpty) {
      return detail.itemName.trim();
    }
    return schedule.displayNameForLanguage(language);
  }
}
