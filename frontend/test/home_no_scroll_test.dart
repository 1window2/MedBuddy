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
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(top: top, bottom: bottom);
      addTearDown(tester.view.reset);
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
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

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
        tester.getSize(find.byKey(const Key('caregiver-home-source-hint'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
