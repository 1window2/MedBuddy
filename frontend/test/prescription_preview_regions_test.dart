// 파일명: prescription_preview_regions_test.dart
// 역할: 처방전 미리보기에 그릴 개인정보 가림 영역과 약 이름 영역의 선택·정렬 규칙을 검증한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_preview_regions.dart';
import 'package:medbuddy_frontend/entities/recognized_text_region_entity.dart';

// 함수이름: region
// 함수역할: 지정한 범주·문구·위치의 인식 영역을 만든다. 매개변수: category, text, top, left. 반환값: 인식 영역.
RecognizedTextRegion region(
  String category,
  String text, {
  double top = 0,
  double left = 0,
}) => RecognizedTextRegion(
  category: category,
  text: text,
  box2d: [top, left, top + 10, left + 10],
);

// 함수이름: main
// 함수역할: 미리보기 영역 선택 테스트를 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  test('sensitive regions stay and matching text becomes a medication', () {
    final regions = resolvePrescriptionPreviewRegions(
      localRegions: [
        region('recognized_text', '엘타인캡슐 300mg', top: 50),
        region('sensitive_info', '홍길동', top: 10),
        region('recognized_text', '1일 3회 식후', top: 60),
      ],
      medicationSchedules: const [MedicationSchedule(medicationName: '엘타인캡슐')],
    );
    expect(regions.map((r) => (r.category, r.text)), [
      ('sensitive_info', '홍길동'),
      ('medication_name', '엘타인캡슐 300mg'),
    ]);
  });

  test('a one-letter OCR error matches only text with a dosage form', () {
    List<String> matched(String text) => resolvePrescriptionPreviewRegions(
      localRegions: [region('recognized_text', text)],
      medicationSchedules: const [MedicationSchedule(medicationName: '타이레놀정')],
    ).map((r) => r.text).toList();
    expect(matched('타이레놀졍'), isEmpty);
    expect(matched('타이레눌정'), ['타이레눌정']);
  });

  test('short names and duplicate boxes are left out', () {
    final regions = resolvePrescriptionPreviewRegions(
      localRegions: [
        region('sensitive_info', '주민번호'),
        region('sensitive_info', '주민번호'),
        region('recognized_text', '정제'),
      ],
      medicationSchedules: const [MedicationSchedule(medicationName: '정제')],
    );
    expect(regions, hasLength(1));
    expect(regions.single.isSensitive, isTrue);
  });
}
