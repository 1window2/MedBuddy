// 파일명: input_prescription_ui_boundary_test.dart
// 역할: 처방전, 낱알약과 직접 등록 입력 방식 선택 화면을 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/input_prescription_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medbuddy_bottom_navigation_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/pill_identification_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/views/home_screen.dart';
import 'package:provider/provider.dart';

class _CountingCheckSchedule extends CheckSchedule {
  int requestCount = 0;

  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    requestCount += 1;
    return const [];
  }
}

class _CountingCheckSavedMedication extends CheckSavedMedication {
  int requestCount = 0;

  @override
  Future<List<MedicationDetail>> requestSavedMedicationInfo() async {
    requestCount += 1;
    return const [];
  }
}

void main() {
  testWidgets('home keeps v0.1.1 actions and exposes v0.2 direct entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var pillTaskRequested = false;
    var manualTaskRequested = false;
    await tester.pumpWidget(
      MaterialApp(
        home: InputPrescriptionUI(
          statusMessage: '',
          userSetting: const UserSetting(language: 'ko'),
          onPrescriptionScanRequested: () {},
          onPrescriptionGalleryRequested: () {},
          onPillIdentificationRequested: () {
            pillTaskRequested = true;
          },
          onManualMedicationRequested: () {
            manualTaskRequested = true;
          },
          onTodayScheduleRequested: () {},
          onHealthRecommendationRequested: () {},
          onMedicationReminderRequested: () {},
          onUserSettingRequested: () {},
        ),
      ),
    );

    await tester.tap(find.text('처방전 분석'));
    await tester.pumpAndSettle();

    expect(find.text('직접 등록'), findsOneWidget);
    await tester.tap(find.text('직접 등록'));
    await tester.pumpAndSettle();
    expect(manualTaskRequested, isTrue);

    await tester.tap(find.text('낱알약 식별'));
    await tester.pump();
    expect(pillTaskRequested, isTrue);
  });

  testWidgets('home owns navigation into loose-pill identification', (
    tester,
  ) async {
    final viewModel = MedBuddyViewModel();
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    final inputBoundary = tester.widget<InputPrescriptionUI>(
      find.byType(InputPrescriptionUI),
    );
    inputBoundary.onPillIdentificationRequested?.call();
    await tester.pumpAndSettle();

    expect(find.byType(PillIdentificationUI), findsOneWidget);
  });

  testWidgets('application shell separates destinations from home actions', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    final viewModel = MedBuddyViewModel();
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    expect(find.byType(MedBuddyBottomNavigationUI), findsOneWidget);
    expect(find.text('홈'), findsOneWidget);
    expect(find.text('일정'), findsOneWidget);
    expect(find.text('복약함'), findsOneWidget);
    expect(find.text('내 정보'), findsOneWidget);
    expect(find.text('처방전 분석'), findsOneWidget);
    expect(find.text('낱알약 식별'), findsOneWidget);
    expect(find.text('건강 관리 추천'), findsOneWidget);
    expect(find.text('복약 알림 설정'), findsOneWidget);
    expect(find.byKey(const ValueKey('homeMedicationTipCard')), findsOneWidget);
    expect(find.text('환자/보호자 연동'), findsNothing);
    expect(find.byKey(const ValueKey('homeSettingsButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('schedule destination refreshes whenever it is revisited', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    final checkSchedule = _CountingCheckSchedule();
    final viewModel = MedBuddyViewModel(checkSchedule: checkSchedule);
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('bottomNavigation-schedule')));
    await tester.pumpAndSettle();
    expect(checkSchedule.requestCount, 1);

    await tester.tap(find.byKey(const ValueKey('bottomNavigation-home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bottomNavigation-schedule')));
    await tester.pumpAndSettle();

    expect(checkSchedule.requestCount, 2);
  });

  testWidgets('medication cabinet refreshes whenever it is revisited', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    final checkSavedMedication = _CountingCheckSavedMedication();
    final viewModel = MedBuddyViewModel(
      checkSavedMedication: checkSavedMedication,
    );
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('bottomNavigation-medicationCabinet')),
    );
    await tester.pumpAndSettle();
    expect(checkSavedMedication.requestCount, 1);

    await tester.tap(find.byKey(const ValueKey('bottomNavigation-home')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bottomNavigation-medicationCabinet')),
    );
    await tester.pumpAndSettle();

    expect(checkSavedMedication.requestCount, 2);
  });

  testWidgets('bottom navigation exposes four labelled destinations', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 200));
    var selected = MedBuddyDestination.home;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: MedBuddyBottomNavigationUI(
            selectedDestination: selected,
            language: 'ko',
            onDestinationSelected: (destination) {
              selected = destination;
            },
          ),
        ),
      ),
    );

    expect(find.text('홈'), findsOneWidget);
    expect(find.text('일정'), findsOneWidget);
    expect(find.text('복약함'), findsOneWidget);
    expect(find.text('내 정보'), findsOneWidget);
    expect(find.text('처방전 분석'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('bottomNavigation-schedule')));
    expect(selected, MedBuddyDestination.schedule);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('bottomNavigation-schedule')))
          .height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('bottom navigation follows accessible text scaling', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 240));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            bottomNavigationBar: MedBuddyBottomNavigationUI(
              selectedDestination: MedBuddyDestination.home,
              language: 'ko',
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(MedBuddyBottomNavigationUI)).height,
      greaterThan(80),
    );
    expect(tester.widget<Text>(find.text('홈')).textScaler, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('빠른 기능 카드는 서로 같은 높이와 고유한 아이콘을 제공한다', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: InputPrescriptionUI(
          statusMessage: '',
          userSetting: const UserSetting(language: 'ko'),
          onPrescriptionScanRequested: () {},
          onPrescriptionGalleryRequested: () {},
          onPillIdentificationRequested: () {},
          onTodayScheduleRequested: () {},
          onHealthRecommendationRequested: () {},
          onMedicationReminderRequested: () {},
          onUserSettingRequested: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final healthCard = find.byKey(
      const ValueKey('homeHealthRecommendationCard'),
    );
    final reminderCard = find.byKey(
      const ValueKey('homeMedicationReminderCard'),
    );
    expect(
      tester.getSize(reminderCard).height,
      tester.getSize(healthCard).height,
    );
    expect(find.byIcon(Icons.monitor_heart_outlined), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('근처 운영 약국 카드는 실험실 기능을 켠 경우에만 표시한다', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget buildHome({VoidCallback? onNearbyPharmacyRequested}) {
      return MaterialApp(
        home: InputPrescriptionUI(
          statusMessage: '',
          userSetting: const UserSetting(language: 'ko'),
          onPrescriptionScanRequested: () {},
          onPrescriptionGalleryRequested: () {},
          onPillIdentificationRequested: () {},
          onTodayScheduleRequested: () {},
          onNearbyPharmacyRequested: onNearbyPharmacyRequested,
          onHealthRecommendationRequested: () {},
          onMedicationReminderRequested: () {},
          onUserSettingRequested: () {},
        ),
      );
    }

    await tester.pumpWidget(buildHome());
    expect(find.byKey(const ValueKey('homeNearbyPharmacyCard')), findsNothing);

    await tester.pumpWidget(buildHome(onNearbyPharmacyRequested: () {}));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('homeNearbyPharmacyCard')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('영어 설정은 메인 화면 제목과 설명에 함께 반영된다', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: InputPrescriptionUI(
          statusMessage: '',
          userSetting: const UserSetting(language: 'en'),
          onPrescriptionScanRequested: () {},
          onPrescriptionGalleryRequested: () {},
          onPillIdentificationRequested: () {},
          onTodayScheduleRequested: () {},
          onHealthRecommendationRequested: () {},
          onMedicationReminderRequested: () {},
          onUserSettingRequested: () {},
        ),
      ),
    );

    expect(find.text('Start your medication plan with ease'), findsOneWidget);
    expect(find.text('빠른 기능'), findsNothing);
    expect(find.text('Quick Actions'), findsNothing);
    expect(find.text('Prescription Analysis'), findsOneWidget);
  });

  testWidgets('large grid preserves inherited scale and action wording', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 1100));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: _home(userSetting: const UserSetting(fontSize: 20)),
      ),
    );
    await tester.pumpAndSettle();

    final prescriptionTitle = tester.widget<Text>(find.text('처방전\n분석'));
    final pillTitle = tester.widget<Text>(find.text('낱알약\n식별'));
    expect(prescriptionTitle.textScaler, isNull);
    expect(pillTitle.textScaler, isNull);
    expect(find.text('건강 관리\n추천'), findsOneWidget);
    expect(find.text('복약 알림\n설정'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact subtitles wrap without shrinking inside FittedBox', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 1000));

    await tester.pumpWidget(
      MaterialApp(
        home: _home(userSetting: const UserSetting(language: 'en')),
      ),
    );

    final subtitleFinder = find.text(
      'Review food and activity guidance for your medications',
    );
    final subtitle = tester.widget<Text>(subtitleFinder);
    expect(subtitle.maxLines, 2);
    expect(subtitle.style?.fontSize, 11);
    expect(
      find.ancestor(of: subtitleFinder, matching: find.byType(FittedBox)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard chooses the earliest alarm and localizes its slot', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 1000));

    await tester.pumpWidget(
      MaterialApp(
        home: _home(
          userSetting: const UserSetting(language: 'en'),
          schedules: const [
            MedicationSchedule(
              medicationName: 'MorningMed',
              scheduleSlotKeys: ['morning'],
            ),
            MedicationSchedule(
              medicationName: 'LunchMed',
              scheduleSlotKeys: ['lunch'],
            ),
          ],
          alarms: const {
            'morning': MedicationAlarm(
              slotKey: 'morning',
              hour: 20,
              minute: 0,
              enabled: true,
            ),
            'lunch': MedicationAlarm(
              slotKey: 'lunch',
              hour: 12,
              minute: 0,
              enabled: true,
            ),
          },
          totalCount: 2,
          nowProvider: () => DateTime(2026, 1, 1, 10),
        ),
      ),
    );

    expect(find.textContaining('Lunch 12:00 · LunchMed'), findsOneWidget);
    expect(find.textContaining('점심 12:00'), findsNothing);
  });

  testWidgets('dashboard represents every due medication and disabled alarm', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 1000));

    await tester.pumpWidget(
      MaterialApp(
        home: _home(
          schedules: const [
            MedicationSchedule(
              medicationName: '약A',
              scheduleSlotKeys: ['lunch'],
            ),
            MedicationSchedule(
              medicationName: '약B',
              scheduleSlotKeys: ['lunch'],
            ),
          ],
          alarms: const {
            'lunch': MedicationAlarm(
              slotKey: 'lunch',
              hour: 12,
              minute: 0,
              enabled: false,
            ),
          },
          totalCount: 2,
          nowProvider: () => DateTime(2026, 1, 1, 10),
        ),
      ),
    );

    expect(find.text('다음 복약 일정'), findsOneWidget);
    expect(find.text('다음 복약 알림'), findsNothing);
    expect(find.textContaining('점심 12:00 · 약A 외 1개'), findsOneWidget);
  });

  testWidgets('dashboard uses an overdue-specific status message', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 1000));

    await tester.pumpWidget(
      MaterialApp(
        home: _home(
          schedules: const [
            MedicationSchedule(
              medicationName: '아침약',
              scheduleSlotKeys: ['morning'],
            ),
          ],
          alarms: const {
            'morning': MedicationAlarm(
              slotKey: 'morning',
              hour: 8,
              minute: 0,
              enabled: true,
            ),
          },
          totalCount: 1,
          nowProvider: () => DateTime(2026, 1, 1, 23),
        ),
      ),
    );

    expect(find.text('미복용한 약을 확인해주세요'), findsOneWidget);
    expect(find.text('미복용 확인'), findsOneWidget);
    expect(find.textContaining('임의로 추가 복용하지 말고'), findsOneWidget);
    expect(find.textContaining('늦지 않게 복용하세요.'), findsNothing);
    expect(find.text('오늘도 복약을 꾸준히 이어가고 있어요'), findsNothing);
  });

  testWidgets('dashboard prioritizes a future dose over an overdue dose', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 1000));

    await tester.pumpWidget(
      MaterialApp(
        home: _home(
          schedules: const [
            MedicationSchedule(
              medicationName: '아침약',
              scheduleSlotKeys: ['morning'],
            ),
            MedicationSchedule(
              medicationName: '점심약',
              scheduleSlotKeys: ['lunch'],
            ),
          ],
          alarms: const {
            'morning': MedicationAlarm(
              slotKey: 'morning',
              hour: 8,
              minute: 0,
              enabled: true,
            ),
            'lunch': MedicationAlarm(
              slotKey: 'lunch',
              hour: 12,
              minute: 0,
              enabled: true,
            ),
          },
          totalCount: 2,
          nowProvider: () => DateTime(2026, 1, 1, 10),
        ),
      ),
    );

    expect(find.text('다음 복약 알림'), findsOneWidget);
    expect(find.textContaining('점심 12:00 · 점심약'), findsOneWidget);
    expect(find.textContaining('아침 08:00 · 아침약'), findsNothing);
    expect(find.textContaining('임의로 추가 복용하지 말고'), findsNothing);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

InputPrescriptionUI _home({
  UserSetting userSetting = const UserSetting(),
  List<MedicationSchedule> schedules = const [],
  Map<String, MedicationAlarm> alarms = const {},
  int completedCount = 0,
  int totalCount = 0,
  DateTime Function()? nowProvider,
}) {
  return InputPrescriptionUI(
    statusMessage: '',
    userSetting: userSetting,
    todayMedicationScheduleList: schedules,
    medicationReminderSettings: alarms,
    todayMedicationCompletedCount: completedCount,
    todayMedicationTotalCount: totalCount,
    nowProvider: nowProvider,
    onPrescriptionScanRequested: () {},
    onPrescriptionGalleryRequested: () {},
    onPillIdentificationRequested: () {},
    onTodayScheduleRequested: () {},
    onHealthRecommendationRequested: () {},
    onMedicationReminderRequested: () {},
    onUserSettingRequested: () {},
  );
}
