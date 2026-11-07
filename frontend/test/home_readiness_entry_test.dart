// 파일명: home_readiness_entry_test.dart
// 역할: 홈에 점검 바로가기 없이 기존 기능을 유지하는지 작은 화면·큰 글씨·두 언어에서 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/input_prescription_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 함수역할: 홈의 네 기능 카드와 환경설정 진입을 유지하고 점검 바로가기는 표시하지 않는지 검사한다.
// 함수이름: main
// 함수역할:
// - 한국어·영어 홈의 작은 화면 회귀 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 검증을 테스트 프레임워크가 실행한다.
void main() {
  for (final language in ['ko', 'en']) {
    // 함수이름: testWidgets callback
    // 함수역할:
    // - 320px·두 배 글씨에서 점검 진입은 숨기고 네 기능 카드를 유지하며 환경설정 콜백을 한 번 실행하고 렌더링 오류가 없는지 확인한다.
    // 매개변수:
    // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    testWidgets('홈 점검 바로가기 제거: $language 320px 2배 글씨', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var requests = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: InputPrescriptionUI(
              userSetting: UserSetting(language: language),
              onPillIdentificationRequested: null,
              onTodayScheduleRequested: null,
              onHealthRecommendationRequested: null,
              onUserSettingRequested: () => requests++,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('home-readiness')), findsNothing);
      expect(
        find.text(language == 'en' ? 'Setup check' : '사용 준비 점검'),
        findsNothing,
      );
      for (final key in [
        'homePrescriptionAnalysisCard',
        'homeHealthRecommendationCard',
        'homeNearbyPharmacyCard',
        'homeUserSettingsCard',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      final button = find.byKey(const ValueKey('homeUserSettingsCard'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      expect(requests, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
