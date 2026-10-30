// 파일명: home_no_scroll_test.dart
// 역할: 보호자 안내까지 있는 홈 화면이 흔한 휴대폰 크기의 기본 글씨에서 스크롤 없이 한 화면에 들어가는지 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/input_prescription_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medbuddy_bottom_navigation_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/widgets/home_linked_patient_hint.dart';

import 'support/test_viewport.dart';

// 함수이름: main
// 함수역할: 화면 크기별로 홈 대시보드의 남는 스크롤 길이를 확인한다. 매개변수: 없음. 반환값: 없음.
void main() {
  // 화면 전체 크기(dp), 상태 표시줄·시스템 탐색 영역 높이, 언어. 하단 탭은 앱이 직접 그린다.
  // 테스트 글꼴은 영문 글자를 한 글자 폭으로 그려 실제보다 넓으므로 영어는 가장 흔한 큰 화면만 본다.
  for (final (name, size, top, bottom, language) in [
    ('Pixel 7 gesture', const Size(411, 914), 52.0, 24.0, 'ko'),
    ('Pixel 7 gesture', const Size(411, 914), 52.0, 24.0, 'en'),
    ('Galaxy Note10 buttons', const Size(412, 869), 24.0, 48.0, 'ko'),
  ]) {
    testWidgets('홈은 $name 기본 글씨에서 스크롤 없이 보인다 ($language)', (tester) async {
      // 기본 글씨 전용 검증이므로 전체 테스트의 접근성 배율과 입력을 분리한다.
      setTestViewport(tester, size, textScale: 1);
      tester.view.padding = FakeViewPadding(top: top, bottom: bottom);
      addTearDown(tester.view.resetPadding);
      var searchRequests = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: MedBuddyBottomNavigationUI(
              selectedDestination: MedBuddyDestination.home,
              language: language,
              showChat: true,
              onDestinationSelected: (_) {},
            ),
            body: InputPrescriptionUI(
              userSetting: UserSetting(language: language),
              todayMedicationScheduleList: const [
                MedicationSchedule(
                  medicationID: 'home-1',
                  medicationName: '데파스정1밀리그람(에티졸람)',
                  dosage: '1',
                  intakeTime: '1일 3회',
                  medicationTime: 3,
                ),
              ],
              medicationReminderSettings: const {
                'morning': MedicationAlarm(
                  slotKey: 'morning',
                  hour: 8,
                  minute: 0,
                  enabled: true,
                ),
              },
              todayMedicationCompletedCount: 0,
              todayMedicationTotalCount: 3,
              caregiverScheduleHint: HomeLinkedPatientHint(
                isEnglish: language == 'en',
                onTap: () {},
              ),
              onPrescriptionScanRequested: () {},
              onPrescriptionGalleryRequested: () {},
              onPillIdentificationRequested: (mode) {},
              onTodayScheduleRequested: () {},
              onHealthRecommendationRequested: () {},
              onUserSettingRequested: () {},
              onNotificationsRequested: () {},
              onFeatureSearchRequested: () => searchRequests++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byType(InputPrescriptionUI)),
        ).scale(16),
        16,
      );

      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('homeDashboardScrollView')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scrollable.position.maxScrollExtent, 0);
      expect(
        tester
            .getSize(find.byKey(const Key('caregiver-home-source-hint')))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);

      final search = find.byKey(const ValueKey('homeFeatureSearchButton'));
      final notifications = find.byKey(
        const ValueKey('homeNotificationsButton'),
      );
      final logo = find.byKey(const ValueKey('homeBrandLogo'));
      expect(logo, findsOneWidget);
      expect(find.text('건강한 복약 관리 도우미'), findsNothing);
      expect(find.text('Your medication guide'), findsNothing);
      expect(tester.getRect(logo).right, lessThan(tester.getRect(search).left));
      expect(search.hitTestable(), findsOneWidget);
      expect(notifications.hitTestable(), findsOneWidget);
      await tester.tap(search);
      expect(searchRequests, 1);

      // 큰 글씨에서는 스크롤을 허용하되 새 헤더의 검색·알림은 좁은 화면에서도 겹치지 않는다.
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byType(InputPrescriptionUI)),
        ).scale(16),
        32,
      );
      expect(search.hitTestable(), findsOneWidget);
      expect(notifications.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(search).overlaps(tester.getRect(notifications)),
        isFalse,
      );
      expect(tester.getRect(logo).right, lessThan(tester.getRect(search).left));
      await tester.tap(search);
      expect(searchRequests, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
