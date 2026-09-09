// File Name: input_prescription_ui_boundary_test.dart
// Role: Regression coverage for home actions, shell navigation, accessibility, and dose-dashboard
//   priorities.

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

// Class Name: _CountingCheckSchedule
// Role: Schedule stub that counts destination-triggered refreshes.
// Responsibilities:
// - Count each schedule read while keeping the destination empty.
// Attributes:
// - requestCount (int): Number of intercepted control requests.
class _CountingCheckSchedule extends CheckSchedule {
  int requestCount = 0;

  // Function Name: requestTodayMedicationSchedule
  // Description:
  // - Count each schedule read while keeping the destination empty.
  // Parameters:
  // - None.
  // Returns:
  // - An empty schedule list.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    requestCount += 1;
    return const [];
  }
}

// Class Name: _CountingCheckSavedMedication
// Role: Saved-medication stub that counts cabinet revisits.
// Responsibilities:
// - Count saved-list reads without returning any medication rows.
// Attributes:
// - requestCount (int): Number of intercepted control requests.
class _CountingCheckSavedMedication extends CheckSavedMedication {
  int requestCount = 0;

  // Function Name: requestSavedMedicationInfo
  // Description:
  // - Count saved-list reads without returning any medication rows.
  // Parameters:
  // - None.
  // Returns:
  // - An empty saved-medication list.
  @override
  Future<List<MedicationDetail>> requestSavedMedicationInfo() async {
    requestCount += 1;
    return const [];
  }
}

// Function Name: main
// Description:
// - Register regression cases for home actions, shell navigation, accessibility, and dose-dashboard
//   priorities.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: home keeps v0.1.1 actions and exposes v0.2 direct entry.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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
          // Function Name: onPrescriptionScanRequested callback
          // Description:
          // - Keep prescription camera navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onPrescriptionScanRequested: () {},
          // Function Name: onPrescriptionGalleryRequested callback
          // Description:
          // - Keep prescription gallery navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onPrescriptionGalleryRequested: () {},
          // Function Name: onPillIdentificationRequested callback
          // Description:
          // - Record pill-identification navigation so the test can assert the action was dispatched.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the callback completes after its recorded side effects.
          onPillIdentificationRequested: () {
            pillTaskRequested = true;
          },
          // 함수이름: onManualMedicationRequested 콜백
          // 함수역할:
          // - 약 직접 등록 요청을 기록해 해당 사용자 명령의 전달 여부를 검사한다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 기록 또는 상태 변경을 마친다.
          onManualMedicationRequested: () {
            manualTaskRequested = true;
          },
          // Function Name: onTodayScheduleRequested callback
          // Description:
          // - Keep today-schedule navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onTodayScheduleRequested: () {},
          // Function Name: onHealthRecommendationRequested callback
          // Description:
          // - Keep health-recommendation navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onHealthRecommendationRequested: () {},
          // Function Name: onMedicationReminderRequested callback
          // Description:
          // - Keep reminder-settings navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onMedicationReminderRequested: () {},
          // Function Name: onUserSettingRequested callback
          // Description:
          // - Keep user-settings navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
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

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: home owns navigation into loose-pill identification.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: application shell separates destinations from home actions.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: schedule destination refreshes whenever it is revisited.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: medication cabinet refreshes whenever it is revisited.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: bottom navigation exposes four labelled destinations.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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
            // Function Name: onDestinationSelected callback
            // Description:
            // - Capture the selected bottom-navigation destination for label/action assertions.
            // Parameters:
            // - destination (MedBuddyDestination): Destination selected in bottom navigation.
            // Returns:
            // - No value; stores the chosen destination.
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

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: bottom navigation follows accessible text scaling.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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
              // Function Name: onDestinationSelected callback
              // Description:
              // - Keep bottom-navigation destination selection available in the fixture without performing the
              //   action.
              // Parameters:
              // - _ (MedBuddyDestination): Unused argument retained for the callback contract.
              // Returns:
              // - No value; the action is intentionally inert.
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

  // Function Name: testWidgets callback
  // Description:
  // - Verify that quick-action cards have equal heights and distinct icons.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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
          // Function Name: onPrescriptionScanRequested callback
          // Description:
          // - Keep prescription camera navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onPrescriptionScanRequested: () {},
          // Function Name: onPrescriptionGalleryRequested callback
          // Description:
          // - Keep prescription gallery navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onPrescriptionGalleryRequested: () {},
          // 함수이름: onPillIdentificationRequested 콜백
          // 함수역할:
          // - 알약 식별 화면 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onPillIdentificationRequested: () {},
          // Function Name: onTodayScheduleRequested callback
          // Description:
          // - Keep today-schedule navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onTodayScheduleRequested: () {},
          // Function Name: onHealthRecommendationRequested callback
          // Description:
          // - Keep health-recommendation navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onHealthRecommendationRequested: () {},
          // Function Name: onMedicationReminderRequested callback
          // Description:
          // - Keep reminder-settings navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onMedicationReminderRequested: () {},
          // Function Name: onUserSettingRequested callback
          // Description:
          // - Keep user-settings navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
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

  // Function Name: testWidgets callback
  // Description:
  // - Verify that the nearby-open-pharmacy action is visible only when its experiment is enabled.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('근처 운영 약국 카드는 실험실 기능을 켠 경우에만 표시한다', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Function Name: buildHome
    // Description:
    // - Build a home screen whose optional pharmacy action controls experiment visibility.
    // Parameters:
    // - onNearbyPharmacyRequested (VoidCallback?): Optional pharmacy action; absence hides the experiment
    //   entry.
    // Returns:
    // - A MaterialApp containing the configured home actions.
    Widget buildHome({VoidCallback? onNearbyPharmacyRequested}) {
      return MaterialApp(
        home: InputPrescriptionUI(
          statusMessage: '',
          userSetting: const UserSetting(language: 'ko'),
          // Function Name: onPrescriptionScanRequested callback
          // Description:
          // - Keep prescription camera navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onPrescriptionScanRequested: () {},
          // Function Name: onPrescriptionGalleryRequested callback
          // Description:
          // - Keep prescription gallery navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onPrescriptionGalleryRequested: () {},
          // 함수이름: onPillIdentificationRequested 콜백
          // 함수역할:
          // - 알약 식별 화면 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onPillIdentificationRequested: () {},
          // Function Name: onTodayScheduleRequested callback
          // Description:
          // - Keep today-schedule navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onTodayScheduleRequested: () {},
          onNearbyPharmacyRequested: onNearbyPharmacyRequested,
          // Function Name: onHealthRecommendationRequested callback
          // Description:
          // - Keep health-recommendation navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onHealthRecommendationRequested: () {},
          // Function Name: onMedicationReminderRequested callback
          // Description:
          // - Keep reminder-settings navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onMedicationReminderRequested: () {},
          // Function Name: onUserSettingRequested callback
          // Description:
          // - Keep user-settings navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onUserSettingRequested: () {},
        ),
      );
    }

    await tester.pumpWidget(buildHome());
    expect(find.byKey(const ValueKey('homeNearbyPharmacyCard')), findsNothing);

    // 함수이름: onNearbyPharmacyRequested 콜백
    // 함수역할:
    // - 근처 약국 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 없음; 외부 동작을 수행하지 않는다.
    await tester.pumpWidget(buildHome(onNearbyPharmacyRequested: () {}));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('homeNearbyPharmacyCard')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Verify that English settings localize home titles and supporting text together.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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
          // Function Name: onPrescriptionScanRequested callback
          // Description:
          // - Keep prescription camera navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onPrescriptionScanRequested: () {},
          // Function Name: onPrescriptionGalleryRequested callback
          // Description:
          // - Keep prescription gallery navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onPrescriptionGalleryRequested: () {},
          // 함수이름: onPillIdentificationRequested 콜백
          // 함수역할:
          // - 알약 식별 화면 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
          // 매개변수:
          // - 없음.
          // 반환값:
          // - 없음; 외부 동작을 수행하지 않는다.
          onPillIdentificationRequested: () {},
          // Function Name: onTodayScheduleRequested callback
          // Description:
          // - Keep today-schedule navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onTodayScheduleRequested: () {},
          // Function Name: onHealthRecommendationRequested callback
          // Description:
          // - Keep health-recommendation navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onHealthRecommendationRequested: () {},
          // Function Name: onMedicationReminderRequested callback
          // Description:
          // - Keep reminder-settings navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onMedicationReminderRequested: () {},
          // Function Name: onUserSettingRequested callback
          // Description:
          // - Keep user-settings navigation available in the fixture without performing the action.
          // Parameters:
          // - None.
          // Returns:
          // - No value; the action is intentionally inert.
          onUserSettingRequested: () {},
        ),
      ),
    );

    expect(find.text('Start your medication plan with ease'), findsOneWidget);
    expect(find.text('빠른 기능'), findsNothing);
    expect(find.text('Quick Actions'), findsNothing);
    expect(find.text('Prescription Analysis'), findsOneWidget);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: large grid preserves inherited scale and action wording.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('large grid preserves inherited scale and action wording', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 1100));

    await tester.pumpWidget(
      MaterialApp(
        // Function Name: builder callback
        // Description:
        // - Apply text scale 2 to the existing child for accessibility layout checks.
        // Parameters:
        // - context (BuildContext): Widget context used for inherited settings or navigation.
        // - child (Widget?): Existing subtree whose media settings are overridden.
        // Returns:
        // - A MediaQuery wrapping the original child with the override.
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

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: compact subtitles wrap without shrinking inside FittedBox.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: dashboard chooses the earliest alarm and localizes its slot.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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
          // Function Name: nowProvider callback
          // Description:
          // - Supply a controllable clock so dose deadlines and reminder windows do not depend on wall time.
          // Parameters:
          // - None.
          // Returns:
          // - DateTime from DateTime(2026, 1, 1, 10).
          nowProvider: () => DateTime(2026, 1, 1, 10),
        ),
      ),
    );

    expect(find.textContaining('Lunch 12:00 · LunchMed'), findsOneWidget);
    expect(find.textContaining('점심 12:00'), findsNothing);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: dashboard represents every due medication and disabled alarm.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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
          // Function Name: nowProvider callback
          // Description:
          // - Supply a controllable clock so dose deadlines and reminder windows do not depend on wall time.
          // Parameters:
          // - None.
          // Returns:
          // - DateTime from DateTime(2026, 1, 1, 10).
          nowProvider: () => DateTime(2026, 1, 1, 10),
        ),
      ),
    );

    expect(find.text('다음 복약 일정'), findsOneWidget);
    expect(find.text('다음 복약 알림'), findsNothing);
    expect(find.textContaining('점심 12:00 · 약A 외 1개'), findsOneWidget);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: dashboard uses an overdue-specific status message.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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
          // Function Name: nowProvider callback
          // Description:
          // - Supply a controllable clock so dose deadlines and reminder windows do not depend on wall time.
          // Parameters:
          // - None.
          // Returns:
          // - DateTime from DateTime(2026, 1, 1, 23).
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

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: dashboard marks the next medication slot from one large action.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('dashboard marks the next medication slot from one large action', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 1000));
    String? completedSlotKey;

    await tester.pumpWidget(
      MaterialApp(
        home: _home(
          schedules: const [
            MedicationSchedule(
              medicationName: '점심약A',
              scheduleSlotKeys: ['lunch'],
            ),
            MedicationSchedule(
              medicationName: '점심약B',
              scheduleSlotKeys: ['lunch'],
            ),
          ],
          alarms: const {
            'lunch': MedicationAlarm(
              slotKey: 'lunch',
              hour: 12,
              minute: 30,
              enabled: true,
            ),
          },
          totalCount: 2,
          // Function Name: nowProvider callback
          // Description:
          // - Supply a controllable clock so dose deadlines and reminder windows do not depend on wall time.
          // Parameters:
          // - None.
          // Returns:
          // - DateTime from DateTime(2026, 1, 1, 10).
          nowProvider: () => DateTime(2026, 1, 1, 10),
          // Function Name: onNextMedicationCompleteRequested callback
          // Description:
          // - Capture the slot completed by the dashboard's large next-dose action.
          // Parameters:
          // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime.
          // Returns:
          // - Future<void>; stores the completed slot key.
          onNextMedicationCompleteRequested: (slotKey) async {
            completedSlotKey = slotKey;
          },
        ),
      ),
    );

    final completionButton = find.byKey(
      const ValueKey('homeNextSlotCompletionButton'),
    );
    expect(completionButton, findsOneWidget);
    expect(find.text('복용했어요'), findsOneWidget);

    await tester.tap(completionButton);
    await tester.pump();

    expect(completedSlotKey, 'lunch');
    expect(tester.takeException(), isNull);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: dashboard prioritizes a future dose over an overdue dose.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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
          // Function Name: nowProvider callback
          // Description:
          // - Supply a controllable clock so dose deadlines and reminder windows do not depend on wall time.
          // Parameters:
          // - None.
          // Returns:
          // - DateTime from DateTime(2026, 1, 1, 10).
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

// Function Name: _setViewport
// Description:
// - Set the logical viewport with unit pixel ratio and register automatic restoration.
// Parameters:
// - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
// - size (Size): Logical viewport dimensions used for layout checks.
// Returns:
// - No value; the test viewport is configured.
void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// Function Name: _home
// Description:
// - Build the home dashboard from supplied schedules, alarms, progress, and a controllable clock.
// Parameters:
// - userSetting (UserSetting): Language, text-size, and speech preferences for the scenario.
// - schedules (List<MedicationSchedule>): Recognized or current dose schedules for the scenario.
// - alarms (Map<String, MedicationAlarm>): Alarm settings indexed by dose slot.
// - completedCount (int): Completed-dose count displayed in the dashboard.
// - totalCount (int): Total scheduled dose count shown in the dashboard.
// - nowProvider (DateTime Function()?): Dashboard clock override for due-dose ordering.
// - onNextMedicationCompleteRequested (Future<void> Function(String slotKey)?): Optional callback for
//   completing the next due slot.
// Returns:
// - The configured InputPrescriptionUI with inert unrelated navigation callbacks.
InputPrescriptionUI _home({
  UserSetting userSetting = const UserSetting(),
  List<MedicationSchedule> schedules = const [],
  Map<String, MedicationAlarm> alarms = const {},
  int completedCount = 0,
  int totalCount = 0,
  DateTime Function()? nowProvider,
  Future<void> Function(String slotKey)?
      onNextMedicationCompleteRequested,
}) {
  return InputPrescriptionUI(
    statusMessage: '',
    userSetting: userSetting,
    todayMedicationScheduleList: schedules,
    medicationReminderSettings: alarms,
    todayMedicationCompletedCount: completedCount,
    todayMedicationTotalCount: totalCount,
    nowProvider: nowProvider,
    onNextMedicationCompleteRequested:
        onNextMedicationCompleteRequested,
    // Function Name: onPrescriptionScanRequested callback
    // Description:
    // - Keep prescription camera navigation available in the fixture without performing the action.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the action is intentionally inert.
    onPrescriptionScanRequested: () {},
    // Function Name: onPrescriptionGalleryRequested callback
    // Description:
    // - Keep prescription gallery navigation available in the fixture without performing the action.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the action is intentionally inert.
    onPrescriptionGalleryRequested: () {},
    // 함수이름: onPillIdentificationRequested 콜백
    // 함수역할:
    // - 알약 식별 화면 이동 명령을 테스트 화면에 유지하되 실제 동작은 수행하지 않는다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - 없음; 외부 동작을 수행하지 않는다.
    onPillIdentificationRequested: () {},
    // Function Name: onTodayScheduleRequested callback
    // Description:
    // - Keep today-schedule navigation available in the fixture without performing the action.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the action is intentionally inert.
    onTodayScheduleRequested: () {},
    // Function Name: onHealthRecommendationRequested callback
    // Description:
    // - Keep health-recommendation navigation available in the fixture without performing the action.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the action is intentionally inert.
    onHealthRecommendationRequested: () {},
    // Function Name: onMedicationReminderRequested callback
    // Description:
    // - Keep reminder-settings navigation available in the fixture without performing the action.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the action is intentionally inert.
    onMedicationReminderRequested: () {},
    // Function Name: onUserSettingRequested callback
    // Description:
    // - Keep user-settings navigation available in the fixture without performing the action.
    // Parameters:
    // - None.
    // Returns:
    // - No value; the action is intentionally inert.
    onUserSettingRequested: () {},
  );
}
