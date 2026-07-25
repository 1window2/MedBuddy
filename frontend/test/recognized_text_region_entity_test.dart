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
  });
}
