import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/recognized_text_region_entity.dart';

// 파일명: recognized_text_region_entity_test.dart
// 역할: OCR 인식 영역 좌표의 변환과 검증 규칙을 확인한다.

void main() {
  test('OCR 영역 좌표를 0부터 1000 사이로 제한한다', () {
    final region = RecognizedTextRegion.fromJson({
      'category': 'medication_row',
      'text': '테스트정 1정',
      'box_2d': [-10, 50, 500, 1200],
    });

    expect(region, isNotNull);
    expect(region!.box2d, [0, 50, 500, 1000]);
  });

  test('순서가 뒤집히거나 누락된 OCR 영역 좌표는 제외한다', () {
    final reversedRegion = RecognizedTextRegion.fromJson({
      'category': 'medication_row',
      'text': '테스트정',
      'box_2d': [500, 50, 100, 900],
    });
    final missingRegion = RecognizedTextRegion.fromJson({
      'category': 'medication_row',
      'text': '테스트정',
      'box_2d': [100, 50, 500],
    });

    expect(reversedRegion, isNull);
    expect(missingRegion, isNull);
  });

  test('민감정보 영역을 화면 마스킹 대상으로 구분한다', () {
    final region = RecognizedTextRegion.fromJson({
      'category': 'sensitive_info',
      'text': '',
      'box_2d': [10, 20, 80, 400],
    });

    expect(region, isNotNull);
    expect(region!.isSensitive, isTrue);
    expect(region.isVisibleInPreview, isTrue);
  });

  test('약품 영역만 일반 OCR 문구와 구분해 미리보기 대상으로 사용한다', () {
    final medicationRegion = RecognizedTextRegion.fromJson({
      'category': 'medication_name',
      'text': '테스트정',
      'box_2d': [100, 50, 200, 500],
    });
    final genericRegion = RecognizedTextRegion.fromJson({
      'category': 'recognized_text',
      'text': '전문가와 상의 없이 복용하지 마세요',
      'box_2d': [220, 50, 300, 700],
    });

    expect(medicationRegion, isNotNull);
    expect(medicationRegion!.isMedication, isTrue);
    expect(medicationRegion.isVisibleInPreview, isTrue);
    expect(genericRegion, isNotNull);
    expect(genericRegion!.isMedication, isFalse);
    expect(genericRegion.isVisibleInPreview, isFalse);
  });
}
