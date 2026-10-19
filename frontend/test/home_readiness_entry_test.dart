// 파일명: home_readiness_entry_test.dart
// 역할: 홈에 점검 바로가기 없이 기존 기능을 유지하는지 작은 화면·큰 글씨·두 언어에서 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/input_prescription_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 함수역할: 홈의 네 기능 카드와 환경설정 진입을 유지하고 점검 바로가기는 표시하지 않는지 검사한다.
void main() {
  for (final language in ['ko', 'en']) {
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
              onPrescriptionScanRequested: null,
              onPrescriptionGalleryRequested: null,
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
