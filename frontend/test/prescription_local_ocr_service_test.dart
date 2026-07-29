import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/prescription_local_ocr_service.dart';

void main() {
  const filter = PrescriptionPrivacyFilter();

  test('개인정보 라벨과 직접 식별자를 민감정보로 판별한다', () {
    expect(filter.containsSensitiveInformation('환자명 홍길동'), isTrue);
    expect(filter.containsSensitiveInformation('주민번호 900101-1234567'), isTrue);
    expect(filter.containsSensitiveInformation('연락처 010-1234-5678'), isTrue);
    expect(filter.containsSensitiveInformation('메일 user@example.com'), isTrue);
    expect(filter.containsSensitiveInformation('조제일자 2026-07-29'), isFalse);
    expect(filter.containsSensitiveInformation('아스피린 1정 1일 2회'), isFalse);
  });

  test('개인정보 라벨만 있는 경우 다음 OCR 줄도 마스킹한다', () {
    expect(filter.shouldMaskFollowingLine('환자명'), isTrue);
    expect(filter.shouldMaskFollowingLine('주소 :'), isTrue);
    expect(filter.shouldMaskFollowingLine('환자명 홍길동'), isFalse);
    expect(filter.shouldMaskFollowingLine('약품명'), isFalse);
  });

  test('복약 문구에 섞인 직접 식별자는 원문을 남기지 않는다', () {
    final masked = filter.maskInlineIdentifiers(
      '문의 010-1234-5678, user@example.com, 900101-1234567',
    );

    expect(masked, isNot(contains('010-1234-5678')));
    expect(masked, isNot(contains('user@example.com')));
    expect(masked, isNot(contains('900101-1234567')));
    expect(masked, contains('[연락처 제거]'));
    expect(masked, contains('[이메일 제거]'));
    expect(masked, contains('[주민번호 제거]'));
  });
}
