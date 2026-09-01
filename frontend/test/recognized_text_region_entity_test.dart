import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/recognized_text_region_entity.dart';

// 파일명: recognized_text_region_entity_test.dart
// 역할: OCR 인식 영역 좌표의 변환과 검증 규칙을 확인한다.

void main() {
  test('순서가 올바른 네 개의 OCR 좌표만 유효하다', () {
    const validRegion = RecognizedTextRegion(
      category: 'medication_row',
      text: '테스트정',
      box2d: [100, 50, 500, 900],
    );
    const reversedRegion = RecognizedTextRegion(
      category: 'medication_row',
      text: '테스트정',
      box2d: [500, 50, 100, 900],
    );
    const missingRegion = RecognizedTextRegion(
      category: 'medication_row',
      text: '테스트정',
      box2d: [100, 50, 500],
    );

    expect(validRegion.isValid, isTrue);
    expect(reversedRegion.isValid, isFalse);
    expect(missingRegion.isValid, isFalse);
  });

  test('민감정보 영역을 화면 마스킹 대상으로 구분한다', () {
    const region = RecognizedTextRegion(
      category: 'sensitive_info',
      text: '',
      box2d: [10, 20, 80, 400],
    );

    expect(region.isSensitive, isTrue);
    expect(region.isVisibleInPreview, isTrue);
  });

  test('약품 영역만 일반 OCR 문구와 구분해 미리보기 대상으로 사용한다', () {
    const medicationRegion = RecognizedTextRegion(
      category: 'medication_name',
      text: '테스트정',
      box2d: [100, 50, 200, 500],
    );
    const genericRegion = RecognizedTextRegion(
      category: 'recognized_text',
      text: '전문가와 상의 없이 복용하지 마세요',
      box2d: [220, 50, 300, 700],
    );

    expect(medicationRegion.isMedication, isTrue);
    expect(medicationRegion.isVisibleInPreview, isTrue);
    expect(genericRegion.isMedication, isFalse);
    expect(genericRegion.isVisibleInPreview, isFalse);
  });
}
