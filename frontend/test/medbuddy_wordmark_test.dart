// 파일명: medbuddy_wordmark_test.dart
// 역할: 좁은 폭의 브랜드 로고와 태그라인 정렬·접근성 이름을 검증하며 선택적으로 비교 이미지를 확인한다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/medbuddy_wordmark.dart';

// 함수이름: main
// 함수역할:
// - 선택적 테스트 글꼴 준비와 폭 150·220의 로고 배치 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록한 사례는 테스트 프레임워크에서 실행한다.
void main() {
  // 함수이름: setUpAll
  // 함수역할:
  // - MEDBUDDY_TEST_FONT가 있으면 같은 파일을 Roboto·Arial·Ahem으로 등록하여 글꼴 차이를 줄이고 없으면 기본 글꼴을 유지한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  setUpAll(() async {
    final font = Platform.environment['MEDBUDDY_TEST_FONT'];
    if (font == null) return;
    final bytes = ByteData.sublistView(await File(font).readAsBytes());
    for (final family in ['Roboto', 'Arial', 'Ahem']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  });
  for (final width in [150.0, 220.0]) {
    // 함수이름: testWidgets callback
    // 함수역할:
    // - 로고 두 이미지와 접근성 이름을 확인하고 태그라인 좌우 경계가 워드마크와 맞으며 아래에 배치되는지 검사한다. 캡처 설정이 켜지면 기준 이미지도 비교한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    testWidgets('wordmark fits $width without cropping either brand part', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: MedBuddyColors.pageBackground,
            body: Center(
              child: RepaintBoundary(
                key: const Key('brand-preview'),
                child: ColoredBox(
                  color: MedBuddyColors.pageBackground,
                  child: SizedBox(
                    width: width,
                    child: const MedBuddyWordmark(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('MedBuddy'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
      expect(tester.getSize(find.byType(MedBuddyWordmark)).width, width);
      final tagline = find.byKey(const Key('brand-tagline'));
      final wordmark = find.byKey(const Key('brand-wordmark-image'));
      expect(find.text('SMART MEDICATION CARE'), findsOneWidget);
      expect(
        tester.getTopLeft(tagline).dx,
        closeTo(tester.getTopLeft(wordmark).dx, .1),
      );
      expect(
        tester.getTopRight(tagline).dx,
        closeTo(tester.getTopRight(wordmark).dx, .1),
      );
      expect(
        tester.getTopLeft(tagline).dy,
        greaterThan(tester.getBottomLeft(wordmark).dy),
      );
      expect(tester.takeException(), isNull);
      if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
        await expectLater(
          find.byKey(const Key('brand-preview')),
          matchesGoldenFile('../.dart_tool/result_previews/brand-$width.png'),
        );
      }
    });
  }
}
