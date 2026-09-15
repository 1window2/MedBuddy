// File Name: input_prescription_ui_boundary_test.dart
// Role: Regression coverage for home actions, shell navigation, accessibility, and dose-dashboard
//   priorities.

import 'package:flutter/material.dart';
import 'package:medbuddy_frontend/boundaries/medication_capture_options_ui_boundary.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/input_prescription_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medbuddy_bottom_navigation_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/notification_inbox_ui_boundary.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

// Class Name: _CountingCheckSchedule
// Role: Schedule stub that counts destination-triggered refreshes.
// Responsibilities:
// - Count each schedule read while keeping the destination empty.
// Attributes:
// - requestCount (int): Number of intercepted control requests.
class _CountingCheckSchedule extends CheckSchedule {
  int requestCount = 0;
  final List<bool> slotWrites = [];

  // Record whole-slot writes so navigation can be checked for accidental resets.
  @override
  Future<List<MedicationSchedule>> updateMedicationSlotStatus(
    String slotKey,
    bool medicationStatus, {
    String? expectedScheduleDate,
  }) async {
    slotWrites.add(medicationStatus);
    return const [];
  }

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
  testWidgets('home bulk completion offers review without resetting the slot', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    final schedule = _CountingCheckSchedule();
    final viewModel = MedBuddyViewModel(checkSchedule: schedule);
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    tester
        .widget<InputPrescriptionUI>(find.byType(InputPrescriptionUI))
        .onNextMedicationCompleteRequested!('morning');
    await tester.pumpAndSettle();
    expect(schedule.slotWrites, [true]);
    expect(find.text('실행 취소'), findsNothing);
    await tester.tap(find.text('일정 확인'));
    await tester.pumpAndSettle();
    expect(schedule.requestCount, 1);
    expect(schedule.slotWrites, [true]);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 약 등록·식별 진입 테스트
  // 함수역할: 중복 카드 없이 공통 메뉴에서 처방전·알약 식별·직접 등록에 접근하는지 확인한다.
  // 매개변수: tester: 위젯 테스트 도구. 반환값: 진입 동작 검증 완료.
  testWidgets('home groups medication input and identification in one entry', (
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
          onPillIdentificationRequested: (mode) {
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

    expect(find.text('낱알약 식별'), findsNothing);
    expect(
      find.byKey(const ValueKey('homePillIdentificationCard')),
      findsNothing,
    );
    await tester.tap(find.text('약 등록·식별'));
    await tester.pumpAndSettle();

    expect(find.text('처방전 분석'), findsOneWidget);
    expect(find.text('직접 등록'), findsOneWidget);
    await tester.tap(find.text('직접 등록'));
    await tester.pumpAndSettle();
    expect(manualTaskRequested, isTrue);

    await tester.tap(find.text('약 등록·식별'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('낱알약 식별'));
    await tester.pumpAndSettle();
    expect(pillTaskRequested, isFalse);
    await tester.tap(find.text('여러 알약 한 번에 찾기'));
    await tester.pump();
    expect(pillTaskRequested, isTrue);
  });

  // 함수이름: 홈 알림함 진입 테스트
  // 함수역할: 상단 종 버튼이 알림함을 열고 돌아온 뒤에도 홈 메뉴가 유지되는지 확인한다.
  // 매개변수: tester: 위젯 테스트 도구. 반환값: 실제 화면 이동 검증 완료.
  testWidgets('home bell opens notification inbox', (tester) async {
    SharedPreferences.setMockInitialValues({});
    _setViewport(tester, const Size(390, 844));
    final viewModel = MedBuddyViewModel();
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    final reminder = find.byKey(const ValueKey('homeNotificationsButton'));
    await tester.ensureVisible(reminder);
    await tester.tap(reminder);
    await tester.pumpAndSettle();
    expect(find.byType(NotificationInboxUI), findsOneWidget);
    final settingsContext = tester.element(find.byType(NotificationInboxUI));
    Navigator.of(settingsContext).pop();
    await tester.pumpAndSettle();
    expect(reminder, findsOneWidget);
    expect(
      find.byKey(const ValueKey('homeNearbyPharmacyCard')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 20));
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
    inputBoundary.onPillIdentificationRequested?.call(
      PillCaptureMode.singlePhoto,
    );
    await tester.pumpAndSettle();

    expect(find.byType(PillIdentificationUI), findsOneWidget);
    expect(
      tester
          .widget<PillIdentificationUI>(find.byType(PillIdentificationUI))
          .captureMode,
      PillCaptureMode.singlePhoto,
    );
  });

  // 함수이름: 홈 기본 기능 테스트
  // 함수역할: 실험실 설정 없이 약국을 포함한 홈 바로가기와 하단 탐색을 분리해 표시하는지 확인한다.
  // 매개변수: tester: 화면 테스트 도구. 반환값: 검증 완료.
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
    expect(find.text('약 등록·식별'), findsOneWidget);
    expect(find.text('낱알약 식별'), findsNothing);
    expect(find.text('건강 관리 추천'), findsOneWidget);
    expect(find.text('근처 운영 약국'), findsOneWidget);
    expect(find.text('환경설정'), findsOneWidget);
    expect(find.byKey(const ValueKey('homeMedicationTipCard')), findsNothing);
    expect(find.text('복약 팁'), findsNothing);
    expect(find.text('환자/보호자 연동'), findsNothing);
    expect(
      find.byKey(const ValueKey('homeNotificationsButton')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 20));
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
          onPillIdentificationRequested: (mode) {},
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
    final pharmacyCard = find.byKey(const ValueKey('homeNearbyPharmacyCard'));
    expect(
      tester.getSize(pharmacyCard).height,
      tester.getSize(healthCard).height,
    );
    expect(find.byIcon(Icons.monitor_heart_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 약국·알림 독립 배치 테스트
  // 함수역할: 약국 콜백 유무와 관계없이 두 카드의 자리를 유지하고 알림 카드가 중복되지 않는지 확인한다.
  // 매개변수: tester: 위젯 테스트 도구. 반환값: 네 카드 배치 검증 완료.
  testWidgets('약국과 복약 알림 카드는 서로 다른 자리를 유지한다', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 함수이름: buildHome
    // 함수역할: 약국 동작 연결 유무별 홈 화면을 만든다.
    // 매개변수: onNearbyPharmacyRequested: 선택적 약국 콜백. 반환값: 홈 테스트 앱.
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
          onPillIdentificationRequested: (mode) {},
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
    expect(
      find.byKey(const ValueKey('homeNearbyPharmacyCard')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('homeUserSettingsCard')), findsOneWidget);

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

  // 함수이름: 홈 영어 표시 테스트
  // 함수역할: 변경한 약 등록·식별과 알림 설정 카드의 제목·설명에 영어 설정이 적용되는지 확인한다.
  // 매개변수: tester: 위젯 테스트 도구. 반환값: 번역 검증 완료.
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
          onPillIdentificationRequested: (mode) {},
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
    expect(find.text('Add or Identify Medication'), findsOneWidget);
    expect(
      find.text('Use a prescription, pill photo, or manual entry'),
      findsOneWidget,
    );
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Nearby Pharmacy'), findsOneWidget);
  });

  // 함수이름: 큰 글씨 카드 회귀 테스트
  // 함수역할: 두 배 확대에서도 제목을 강제로 분리하거나 설명을 숨기지 않는지 검사한다.
  // 매개변수: tester (WidgetTester): 홈 화면을 구성하는 테스트 도구.
  // 반환값: 모든 접근성 검증이 완료되는 Future<void>.
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

    final prescriptionTitle = tester.widget<Text>(find.text('약 등록·식별'));
    final reminderTitle = tester.widget<Text>(find.text('환경설정'));
    expect(prescriptionTitle.textScaler, isNull);
    expect(reminderTitle.textScaler, isNull);
    expect(find.text('건강 관리 추천'), findsOneWidget);
    expect(find.text('환경설정'), findsOneWidget);
    expect(find.text('처방전·알약 사진 또는 직접 입력으로 등록해요'), findsOneWidget);
    expect(find.text('글씨 크기·언어·알림을 설정해요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in const [
    Size(320, 640),
    Size(350, 800),
    Size(390, 844),
    Size(430, 932),
    Size(800, 600),
  ]) {
    for (final scale in const [1.3, 2.0]) {
      for (final language in const ['ko', 'en']) {
        // 함수이름: 화면 크기·언어별 큰 글씨 테스트
        // 함수역할: 제목·설명·화살표가 유지되고, 카드 안에서 글씨가 잘리지 않는지 확인한다.
        // 매개변수: tester (WidgetTester): 화면 배치와 실제 텍스트 영역을 검사하는 도구.
        // 반환값: 선택한 화면·배율·언어 조합의 검증을 마치는 Future<void>.
        testWidgets(
          'large home retains full content $viewport $scale $language',
          (tester) async {
            _setViewport(tester, viewport);
            await tester.pumpWidget(
              MaterialApp(
                // 함수이름: builder 콜백
                // 함수역할: 운영체제와 앱에서 이미 결정한 접근성 배율을 홈 화면에 전달한다.
                // 매개변수: context (BuildContext), child (Widget?): 기존 앱 위젯과 문맥.
                // 반환값: 요청된 확대 배율을 상속하는 위젯.
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: _home(
                  userSetting: UserSetting(fontSize: 20, language: language),
                ),
              ),
            );
            await tester.pumpAndSettle();
            const keys = [
              'homePrescriptionAnalysisCard',
              'homeUserSettingsCard',
              'homeHealthRecommendationCard',
              'homeNearbyPharmacyCard',
            ];
            for (final key in keys) {
              final card = find.byKey(ValueKey(key));
              final labels = find.descendant(
                of: card,
                matching: find.byType(Text),
              );
              expect(labels, findsNWidgets(2));
              expect(
                find.descendant(
                  of: card,
                  matching: find.byIcon(Icons.arrow_forward_rounded),
                ),
                findsOneWidget,
              );
              final cardRect = tester.getRect(card);
              for (final element in labels.evaluate()) {
                final label = element.widget as Text;
                expect(label.maxLines, isNull);
                expect(label.textScaler, isNull);
                expect(
                  MediaQuery.textScalerOf(element).scale(16),
                  closeTo(16 * scale, 0.01),
                );
                final paragraph =
                    element.findRenderObject()! as RenderParagraph;
                expect(paragraph.didExceedMaxLines, isFalse);
                final origin = paragraph.localToGlobal(Offset.zero);
                expect(origin.dx, greaterThanOrEqualTo(cardRect.left));
                expect(origin.dy, greaterThanOrEqualTo(cardRect.top));
                expect(
                  origin.dx + paragraph.size.width,
                  lessThanOrEqualTo(cardRect.right + 0.01),
                );
                expect(
                  origin.dy + paragraph.size.height,
                  lessThanOrEqualTo(cardRect.bottom + 0.01),
                );
              }
            }
            if (viewport.width >= 350) {
              final first = tester.getRect(
                find.byKey(const ValueKey('homePrescriptionAnalysisCard')),
              );
              final second = tester.getRect(
                find.byKey(const ValueKey('homeHealthRecommendationCard')),
              );
              expect(first.top, second.top);
              expect(first.height, second.height);
              expect(first.right, lessThan(second.left));
              // 기본 큰 글씨의 카드가 불필요한 세로 고정 비율로 늘어나지 않게 한다.
              if (scale == 1.3 && language == 'ko' && viewport.width == 390) {
                expect(first.height, lessThan(first.width * 1.25));
                expect(
                  tester
                      .getSize(
                        find.byKey(const ValueKey('homeEncouragementPanel')),
                      )
                      .height,
                  lessThan(260),
                );
              }
            }
            await tester.ensureVisible(
              find.byKey(const ValueKey('homeNearbyPharmacyCard')),
            );
            await tester.pumpAndSettle();
            expect(
              find
                  .byKey(const ValueKey('homeNearbyPharmacyCard'))
                  .hitTestable(),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

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

  for (final viewport in const [Size(320, 640), Size(390, 844)]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      for (final language in const ['ko', 'en']) {
        // 함수이름: 미복용 안내 줄바꿈 테스트
        // 함수역할: 긴 약 이름과 주의 문구가 큰 글씨에서도 잘리지 않고 완료 버튼 위에 배치되는지 확인한다.
        // 매개변수: tester (WidgetTester): 화면 배치와 상호작용 검증 도구.
        // 반환값: 화면 크기·배율·언어별 검증을 마치는 Future<void>.
        testWidgets('overdue guidance wraps fully $viewport $scale $language', (
          tester,
        ) async {
          _setViewport(tester, viewport);
          String? completedSlot;
          await tester.pumpWidget(
            MaterialApp(
              // 함수이름: builder 콜백
              // 함수역할: 테스트할 접근성 글씨 배율을 홈 화면에 전달한다.
              // 매개변수: context (BuildContext), child (Widget?): 앱의 문맥과 화면.
              // 반환값: 설정한 글씨 배율을 상속하는 화면.
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: _home(
                userSetting: UserSetting(language: language),
                schedules: const [
                  MedicationSchedule(
                    medicationName: '아침 복용 테스트 약 Long medication name 100mg',
                    scheduleSlotKeys: ['morning'],
                  ),
                  MedicationSchedule(
                    medicationName: 'Second medication',
                    scheduleSlotKeys: ['morning'],
                  ),
                ],
                totalCount: 2,
                // 함수이름: nowProvider 콜백
                // 함수역할: 아침 복약 시간이 지난 상황을 고정한다.
                // 매개변수: 없음. 반환값: 테스트 기준 시각.
                nowProvider: () => DateTime(2026, 1, 1, 23),
                // 함수이름: onNextMedicationCompleteRequested 콜백
                // 함수역할: 안내 아래 완료 버튼으로 전달되는 시간대를 기록한다.
                // 매개변수: slotKey (String): 완료할 복약 시간대. 반환값: 기록 완료.
                onNextMedicationCompleteRequested: (slotKey) async {
                  completedSlot = slotKey;
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          final guidance = language == 'ko'
              ? '놓친 복약은 임의로 추가 복용하지 말고 처방·복약지도를 확인하세요.'
              : 'Check your prescription guidance before taking a missed dose.';
          final guide = find.textContaining(guidance);
          expect(guide, findsOneWidget);
          final label = tester.widget<Text>(guide);
          expect(label.maxLines, isNull);
          expect(label.overflow, isNot(TextOverflow.ellipsis));
          expect(label.textScaler, isNull);
          final paragraph = tester.renderObject<RenderParagraph>(guide);
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(paragraph.textScaler.scale(12), closeTo(12 * scale, 0.01));
          final panel = tester.getRect(
            find.byKey(const ValueKey('homeEncouragementPanel')),
          );
          final guideRect = tester.getRect(guide);
          expect(guideRect.left, greaterThanOrEqualTo(panel.left));
          expect(guideRect.right, lessThanOrEqualTo(panel.right));
          expect(guideRect.bottom, lessThanOrEqualTo(panel.bottom));
          final completion = find.byKey(
            const ValueKey('homeNextSlotCompletionButton'),
          );
          expect(tester.getRect(completion).top, greaterThan(guideRect.bottom));
          await tester.ensureVisible(completion);
          await tester.pumpAndSettle();
          expect(completion.hitTestable(), findsOneWidget);
          await tester.tap(completion);
          await tester.pump();
          expect(completedSlot, 'morning');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

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
  Future<void> Function(String slotKey)? onNextMedicationCompleteRequested,
}) {
  return InputPrescriptionUI(
    statusMessage: '',
    userSetting: userSetting,
    todayMedicationScheduleList: schedules,
    medicationReminderSettings: alarms,
    todayMedicationCompletedCount: completedCount,
    todayMedicationTotalCount: totalCount,
    nowProvider: nowProvider,
    onNextMedicationCompleteRequested: onNextMedicationCompleteRequested,
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
    onPillIdentificationRequested: (mode) {},
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
