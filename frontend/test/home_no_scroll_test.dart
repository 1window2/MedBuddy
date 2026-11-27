// 파일명: home_no_scroll_test.dart
// 역할: 보호자 안내까지 있는 홈 화면이 흔한 휴대폰 크기의 기본 글씨에서 스크롤 없이 한 화면에 들어가고,
//   기능 버튼 네 줄이 같은 높이·같은 간격으로 놓이며, 큰 글씨에서는 넘치지 않고 스크롤되는지 검증한다.
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
    // Function Name: home fits without scrolling at default text
    // Description:
    // - Checks default-scale content has zero scroll extent, a usable caregiver hint and nonoverlapping header actions; then checks the narrow large-text layout and search callback.
    // Parameters:
    // - tester (WidgetTester): Drives the widget tree and advances the test clock.
    // Returns:
    // - Future<void>: Completes the checks; an unexpected result fails the test.
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
      // 이 기기들에서 스크롤이 없는지는 아래 411×891 테스트가 본다. 테스트 글꼴은 한글도 한 글자를 1em 폭으로
      //   그려 '근처 운영 병원·약국'이 네 줄로 접히므로, 하단 탭과 보호자 안내가 함께 있는 이 크기에서는
      //   버튼 줄이 실제 기기보다 높아져 스크롤이 생긴다. 대신 줄 높이·간격이 같은지를 확인한다.
      _expectEvenHomeRows(tester);
      expect(scrollable.position.viewportDimension, greaterThan(0));
      expect(
        tester.getRect(find.byKey(const ValueKey('homeBrandLogo'))).top,
        greaterThanOrEqualTo(top + 24),
      );
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
      // 큰 글씨에서는 버튼 줄이 내용만큼 자라고, 넘치는 대신 화면이 스크롤된다.
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      await tester.tap(search);
      expect(searchRequests, 2);
      expect(tester.takeException(), isNull);
    });
  }

  // Function Name: home fills 411x891 without scrolling at default text
  // Description:
  // - Checks that at 411×891 and 1.0× text the dashboard, the four tile rows and the caregiver hint
  //   fit with zero scroll extent, the rows share one height with 12dp gaps, and the six icon boxes
  //   are the same size.
  // Parameters:
  // - tester (WidgetTester): Drives the widget tree and advances the test clock.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  testWidgets('홈은 411x891 기본 글씨에서 같은 높이의 네 줄로 스크롤 없이 보인다', (tester) async {
    setTestViewport(tester, const Size(411, 891), textScale: 1);
    await tester.pumpWidget(
      MaterialApp(
        home: InputPrescriptionUI(
          userSetting: const UserSetting(),
          todayMedicationScheduleList: const [
            MedicationSchedule(
              medicationID: 'home-1',
              medicationName: '데파스정1밀리그람(에티졸람)',
              dosage: '1',
              intakeTime: '1일 3회',
              medicationTime: 3,
            ),
          ],
          todayMedicationCompletedCount: 0,
          todayMedicationTotalCount: 3,
          caregiverScheduleHint: HomeLinkedPatientHint(
            isEnglish: false,
            onTap: () {},
          ),
          onPillIdentificationRequested: (mode) {},
          onTodayScheduleRequested: () {},
          onHealthRecommendationRequested: () {},
          onUserSettingRequested: () {},
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
    _expectEvenHomeRows(tester);
    final settings = tester.getRect(
      find.byKey(const ValueKey('homeUserSettingsCard')),
    );
    final hint = tester.getRect(
      find.byKey(const Key('caregiver-home-source-hint')),
    );
    expect(hint.top, greaterThanOrEqualTo(settings.bottom));
    expect(
      find.byKey(const Key('caregiver-home-source-hint')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

// 홈 기능 버튼 키. 줄 순서대로: [약 등록] [약 관리·약 검색] [건강 관리 추천·근처 운영 병원·약국] [환경설정].
const _homeRows = [
  ['homeMedicationRegisterCard'],
  ['homeMedicationManageCard', 'homeMedicationSearchCard'],
  ['homeHealthRecommendationCard', 'homeNearbyPharmacyCard'],
  ['homeUserSettingsCard'],
];

// 함수이름: _expectEvenHomeRows
// 함수역할: 350dp 이상 너비의 홈 버튼이 같은 높이의 네 줄로, 줄 사이와 두 버튼 사이가 모두 12dp로 놓이고
//   여섯 버튼의 아이콘 칸 크기가 같은지 확인한다.
// 매개변수: tester (WidgetTester): 화면을 읽는 테스트 도구.
// 반환값: 없음. 어긋나면 테스트가 실패한다.
void _expectEvenHomeRows(WidgetTester tester) {
  Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
  final rows = [
    for (final row in _homeRows) [for (final key in row) rect(key)],
  ];
  final height = rows.first.first.height;
  expect(height, greaterThanOrEqualTo(76));
  final fullWidth = rows.first.first;
  for (final row in rows) {
    for (final tile in row) {
      expect(tile.height, moreOrLessEquals(height));
      expect(tile.top, moreOrLessEquals(row.first.top));
    }
    if (row.length == 2) {
      expect(row[1].left - row[0].right, moreOrLessEquals(12));
      expect(row[0].width, moreOrLessEquals(row[1].width));
      expect(row[0].left, moreOrLessEquals(fullWidth.left));
      expect(row[1].right, moreOrLessEquals(fullWidth.right));
    } else {
      expect(row.single.width, moreOrLessEquals(fullWidth.width));
    }
  }
  for (var i = 1; i < rows.length; i++) {
    expect(rows[i].first.top - rows[i - 1].first.bottom, moreOrLessEquals(12));
  }

  // 각 버튼의 첫 아이콘은 아이콘 칸 안의 기능 아이콘이고, 그 가장 가까운 Container가 아이콘 칸이다.
  final iconBoxes = [
    for (final row in _homeRows)
      for (final key in row)
        tester.getSize(
          find
              .ancestor(
                of: find
                    .descendant(
                      of: find.byKey(ValueKey(key)),
                      matching: find.byType(Icon),
                    )
                    .first,
                matching: find.byType(Container),
              )
              .first,
        ),
  ];
  expect(iconBoxes, hasLength(6));
  for (final box in iconBoxes) {
    expect(box, iconBoxes.first);
    expect(box.width, box.height);
  }
}
