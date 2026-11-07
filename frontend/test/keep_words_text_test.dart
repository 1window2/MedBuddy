// 파일명: keep_words_text_test.dart
// 역할: 한국어 단어 단위 줄바꿈 문자열과 위젯의 표시·검색·낭독 동작을 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/widgets/keep_words_text.dart';

const _joiner = '⁠';

// 함수이름: main
// 함수역할: 단어 단위 줄바꿈 테스트를 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  // Function Name: test callback
  // Description:
  // - Check exact joiner placement inside Hangul words and mixed numeric units while preserving spaces and explicit line breaks.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('Hangul words are joined and spaces stay breakable', () {
    expect(
      keepKoreanWords('관리해요 확인'),
      '관$_joiner리$_joiner해$_joiner요 확$_joiner인',
    );
    expect(
      keepKoreanWords('500밀리그램'),
      ['500', '밀', '리', '그', '램'].join(_joiner),
    );
    expect(keepKoreanWords('식후 30분'), '식$_joiner후 30$_joiner분');
    expect(keepKoreanWords('line one\n두 줄'), 'line one\n두 줄');
  });

  // Function Name: test callback
  // Description:
  // - Keep ordinary Latin text and empty input unchanged, but replace range-boundary spaces with nonbreaking spaces.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('text without Hangul is unchanged except ranges', () {
    expect(keepKoreanWords('Morning 08:00'), 'Morning 08:00');
    expect(keepKoreanWords(''), '');
    expect(
      keepKoreanWords('2026-11-04 ~ 11-17'),
      '2026-11-04 ~ 11-17',
    );
  });

  // 함수이름: 원문 노출 테스트
  // 함수역할: 그리는 문자열과 달리 검색·화면 낭독은 원문을 쓰는지 확인한다. 매개변수: tester. 반환값: 검증 완료.
  testWidgets('finders and screen readers see the original text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: KeepWordsText('약을 관리해요'))),
    );
    expect(find.text('약을 관리해요'), findsOneWidget);
    expect(find.bySemanticsLabel('약을 관리해요'), findsOneWidget);
    final rich = tester.widget<Text>(find.byType(Text));
    expect(
      rich.textSpan!.toPlainText(includeSemanticsLabels: false),
      keepKoreanWords('약을 관리해요'),
    );
    semantics.dispose();
  });
}
