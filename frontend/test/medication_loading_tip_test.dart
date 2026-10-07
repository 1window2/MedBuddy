// 파일명: medication_loading_tip_test.dart
// 역할: 분석 팁의 무작위 순환·접근성·생명주기·배치 안정성을 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/widgets/medication_loading_tip.dart';

// 함수이름: _currentTip
// 함수역할: 표시 중인 팁 하나를 읽는다. 매개변수: tester. 반환값: 현재 문구.
String _currentTip(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('analysisMedicationTipText')))
    .data!;

// 함수이름: _screen
// 함수역할: 언어와 접근성 옵션을 조정할 수 있는 테스트 화면을 구성한다.
// 매개변수: language, accessibleNavigation, disableAnimations, active.
// 반환값: 고정 너비의 팁 화면.
Widget _screen({
  String language = 'ko',
  bool accessibleNavigation = false,
  bool disableAnimations = false,
  bool active = true,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      accessibleNavigation: accessibleNavigation,
      disableAnimations: disableAnimations,
    ),
    child: TickerMode(
      enabled: active,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 280,
            child: MedicationLoadingTip(language: language),
          ),
        ),
      ),
    ),
  ),
);

// 함수이름: main
// 함수역할: 팁 표시 회귀 검증을 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  // 함수이름: 무작위 순환 테스트
  // 함수역할: 10초 간격, 순환 내 중복 없음, 새 순환 경계의 연속 중복 방지를 확인한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('8개 팁은 10초마다 중복 없이 표시되고 화면 높이가 유지된다', (tester) async {
    await tester.pumpWidget(_screen());
    final first = _currentTip(tester);
    final region = find.byKey(const ValueKey('analysisMedicationTip'));
    final initialSize = tester.getSize(region);
    final heading = find.text('복약 팁');
    final centerX = tester.getCenter(region).dx;
    expect(tester.widget<Text>(heading).textAlign, TextAlign.center);
    expect(tester.getCenter(heading).dx, closeTo(centerX, 0.01));
    await tester.pump(const Duration(seconds: 9));
    expect(_currentTip(tester), first);
    await tester.pump(const Duration(seconds: 1));
    final seen = <String>{first, _currentTip(tester)};
    expect(seen.length, 2);
    for (var i = 2; i < 8; i++) {
      await tester.pump(MedicationLoadingTip.rotationInterval);
      expect(seen.add(_currentTip(tester)), isTrue);
      expect(tester.getSize(region), initialSize);
      final label = find.byKey(const ValueKey('analysisMedicationTipText'));
      expect(tester.widget<Text>(label).textAlign, TextAlign.center);
      expect(tester.getCenter(label).dx, closeTo(centerX, 0.01));
    }
    final last = _currentTip(tester);
    await tester.pump(MedicationLoadingTip.rotationInterval);
    expect(_currentTip(tester), isNot(last));
    expect(seen, contains(_currentTip(tester)));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 재빌드 유지 테스트
  // 함수역할: 부모 갱신이 순서나 대기 시간을 초기화하지 않는지 확인한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('부모 재빌드에도 현재 팁과 전환 시간이 유지된다', (tester) async {
    await tester.pumpWidget(_screen());
    final first = _currentTip(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(_screen());
    expect(_currentTip(tester), first);
    await tester.pump(const Duration(seconds: 5));
    expect(_currentTip(tester), isNot(first));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 함수이름: 수동 전환 테스트
  // 함수역할: 다음 팁 버튼과 언어 갱신, 수동 전환 후 읽기 시간을 확인한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('다음 팁을 선택하면 읽기 시간이 다시 시작되고 영어도 제공된다', (tester) async {
    await tester.pumpWidget(_screen());
    final first = _currentTip(tester);
    await tester.pump(const Duration(seconds: 9));
    await tester.tap(find.byTooltip('다음 팁'));
    await tester.pump();
    final next = _currentTip(tester);
    expect(next, isNot(first));
    await tester.pump(const Duration(seconds: 1));
    expect(_currentTip(tester), next);
    await tester.pumpWidget(_screen(language: 'en'));
    expect(find.text('Medication tip'), findsOneWidget);
    expect(find.byTooltip('Next tip'), findsOneWidget);
    expect(_currentTip(tester), isNot(next));
    expect(RegExp('[가-힣]').hasMatch(_currentTip(tester)), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final screenReader in [true, false]) {
    // 함수이름: 접근성 자동 전환 제한 테스트
    // 함수역할: 화면 읽기 또는 움직임 감소 설정에서는 수동으로만 전환한다.
    // 매개변수: tester. 반환값: 검증 완료.
    testWidgets('접근성 설정은 자동 전환만 중지한다 $screenReader', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _screen(
            accessibleNavigation: screenReader,
            disableAnimations: !screenReader,
          ),
        );
        final first = _currentTip(tester);
        expect(find.bySemanticsLabel(first), findsOneWidget);
        await tester.pump(const Duration(seconds: 30));
        expect(_currentTip(tester), first);
        await tester.tap(find.byTooltip('다음 팁'));
        await tester.pump();
        expect(_currentTip(tester), isNot(first));
        expect(find.bySemanticsLabel(first), findsNothing);
        expect(find.bySemanticsLabel(_currentTip(tester)), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    });
  }

  // 함수이름: 앱 생명주기 테스트
  // 함수역할: 백그라운드에서는 팁을 유지하고 복귀 후 순환을 재개한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('앱 비활성화와 복귀를 처리하고 제거 후 타이머가 남지 않는다', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(_screen());
    final first = _currentTip(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(_currentTip(tester), first);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(MedicationLoadingTip.rotationInterval);
    expect(_currentTip(tester), isNot(first));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 화면 비활성 테스트
  // 함수역할: 비활성 화면의 자동 전환을 중지하고 다시 활성화하면 재개한다.
  // 매개변수: tester. 반환값: 검증 완료.
  testWidgets('비활성 화면에서는 팁을 자동 전환하지 않는다', (tester) async {
    await tester.pumpWidget(_screen(active: false));
    final first = _currentTip(tester);
    await tester.pump(const Duration(seconds: 30));
    expect(_currentTip(tester), first);
    await tester.pumpWidget(_screen());
    await tester.pump(MedicationLoadingTip.rotationInterval);
    expect(_currentTip(tester), isNot(first));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
