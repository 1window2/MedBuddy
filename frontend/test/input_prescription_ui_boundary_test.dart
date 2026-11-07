// File Name: input_prescription_ui_boundary_test.dart
// Role: Regression coverage for home actions, shell navigation, accessibility, and dose-dashboard
//   priorities.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medbuddy_frontend/boundaries/medication_capture_options_ui_boundary.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/input_prescription_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_nearby_pharmacy_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medbuddy_bottom_navigation_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/notification_inbox_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/pill_identification_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/views/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notification_service.dart';

// 클래스명: _CountingCheckSchedule
// 역할: 홈·일정 화면의 조회 횟수와 시간대 복용 기록 저장을 관찰하는 일정 대역.
// 주요 책임: 빈 일정으로 조회를 계수하고 시간대·상태 쓰기를 기록하며 저장 실패 또는 지연을 재현한다.
// 속성: requestCount: 일정 조회 횟수; slotWrites/writtenSlots: 요청 상태·시간대 기록; failWrites: 저장 실패 여부; writeGate: 저장 완료 대기 신호.
class _CountingCheckSchedule extends CheckSchedule {
  int requestCount = 0;
  final List<bool> slotWrites = [];
  final List<String> writtenSlots = [];
  bool failWrites = false;
  Completer<void>? writeGate;

  // 함수이름: updateMedicationSlotStatus
  // 함수역할: 시간대와 상태를 기록한 후 실패를 주입하거나 완료 신호를 기다려 홈 저장 흐름을 재현한다.
  // 매개변수: slotKey (String): 저장할 시간대; medicationStatus (bool): 완료 여부; expectedScheduleDate (String?): 인터페이스 호환용 날짜이며 대역에서는 사용하지 않는다.
  // 반환값: Future<List<MedicationSchedule>>: 빈 일정 목록; failWrites이면 StateError, 대기 신호가 실패하면 해당 오류를 전파한다.
  @override
  Future<List<MedicationSchedule>> updateMedicationSlotStatus(
    String slotKey,
    bool medicationStatus, {
    String? expectedScheduleDate,
  }) async {
    slotWrites.add(medicationStatus);
    writtenSlots.add(slotKey);
    if (failWrites) throw StateError('test update failure');
    if (writeGate != null) await writeGate!.future;
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

// 클래스명: _SelectableCheckSavedMedication
// 역할: 홈 셸의 복약함 선택 모드에 사용할 활성 약 한 개를 제공한다.
// 주요 책임: 실제 서버 조회 없이 오늘 시작하는 7일 약을 반환해 뒤로가기 단계를 검증한다.
// 속성: 자체 속성 없음; 조회마다 고정 ID 1의 약을 만든다.
class _SelectableCheckSavedMedication extends CheckSavedMedication {
  // 함수이름: requestSavedMedicationInfo
  // 함수역할: 현재 시각부터 7일간 복용하는 선택용 약 한 개를 새로 만든다.
  // 매개변수: 없음.
  // 반환값: Future<List<MedicationDetail>>: ID 1의 선택 테스트 약을 담은 목록.
  @override
  Future<List<MedicationDetail>> requestSavedMedicationInfo() async => [
    MedicationDetail(
      id: 1,
      itemName: '선택 테스트 약',
      efficacy: '',
      usageMethod: '',
      warning: '',
      prescriptionDate: DateTime.now(),
      totalDays: '7',
    ),
  ];
}

// 클래스명: _HomeReminderViewModel
// 역할: 홈 기록 안내가 사용하는 사용자 기본 시각과 개별 알림 시각을 고정한다.
// 주요 책임: 저장소를 조회하지 않고 테스트별 일정 시각을 제공한다.
// 속성: setting: 사용자 기본 설정, reminders: 시간대별 실제 알림 설정.
class _HomeReminderViewModel extends MedBuddyViewModel {
  final UserSetting setting;
  final Map<String, MedicationAlarm> reminders;

  // 함수이름: _HomeReminderViewModel
  // 함수역할: 저장 대역과 예정 시각을 주입해 안내 조건을 재현한다.
  // 매개변수: checkSchedule: 저장 대역, setting/reminders: 비교할 예정 시각.
  // 반환값: 시각 설정을 고정한 테스트용 ViewModel.
  _HomeReminderViewModel({
    required super.checkSchedule,
    this.setting = const UserSetting(),
    this.reminders = const {},
  });

  // 함수이름: userSetting
  // 함수역할: 기본 시각 및 언어를 테스트 설정으로 고정한다.
  // 매개변수: 없음. 반환값: 주입한 사용자 설정.
  @override
  UserSetting get userSetting => setting;

  // 함수이름: medicationReminderSettings
  // 함수역할: 기본 시각보다 우선하는 시간대별 알림 설정을 제공한다.
  // 매개변수: 없음. 반환값: 주입한 알림 설정 맵.
  @override
  Map<String, MedicationAlarm> get medicationReminderSettings => reminders;
}

// 함수이름: main
// 함수역할: 홈 작업 메뉴, 하단 탐색, 복용 기록 저장·안내 시각, 큰 글씨와 다음 복약 우선순위 회귀 테스트를 등록한다.
// 매개변수: 없음.
// 반환값: void: 각 위젯 검증을 테스트 프레임워크에 등록한다.
void main() {
  for (final width in [280.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      // Function Name: linked-patient guidance layout test
      // Description: Keep guidance below all four cards and reachable at large text sizes.
      // Parameters: tester - widget rendering and interaction harness.
      // Returns: Completion of layout and tap assertions; mismatches fail the test.
      testWidgets('linked-patient guidance follows cards at $width/$scale', (
        tester,
      ) async {
        _setViewport(tester, Size(width, 844));
        var taps = 0;
        const hintKey = Key('linkedPatientGuidance');
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: _home(
                caregiverScheduleHint: TextButton(
                  key: hintKey,
                  // Function Name: guidance tap callback
                  // Description: Record activation without navigating outside the fixture.
                  // Parameters: None.
                  // Returns: No value; increments the activation count.
                  onPressed: () => taps++,
                  child: const Text(
                    'View your linked patient’s medication schedule',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final hint = find.byKey(hintKey);
        for (final cardKey in [
          'homePrescriptionAnalysisCard',
          'homeHealthRecommendationCard',
          'homeNearbyPharmacyCard',
          'homeUserSettingsCard',
        ]) {
          expect(
            tester.getTopLeft(hint).dy,
            greaterThanOrEqualTo(
              tester.getBottomLeft(find.byKey(Key(cardKey))).dy,
            ),
          );
        }
        await tester.ensureVisible(hint);
        await tester.pumpAndSettle();
        await tester.tap(hint);
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  // 함수이름: testWidgets: 'home bulk completion offers review without resetting the slot'
  // 함수역할: 홈에서 아침 복용 완료를 저장한 뒤 안내의 일정 확인을 누른다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; true 저장은 한 번 유지되고 실행 취소는 없으며 일정 조회만 한 번 추가되어 완료 기록을 되돌리지 않는다.
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
        .onMedicationSlotStatusRequested!('morning', true);
    await tester.pumpAndSettle();
    expect(schedule.slotWrites, [true]);
    expect(find.text('실행 취소'), findsNothing);
    await tester.tap(find.text('일정 확인'));
    await tester.pumpAndSettle();
    expect(schedule.requestCount, 1);
    expect(schedule.slotWrites, [true]);
    expect(tester.takeException(), isNull);
  });

  for (final fail in [false, true]) {
    // Function Name: testWidgets: '홈 복용 취소는 선택 시간대만 기존 저장 경로에 전달한다: $fail'
    // Description: Request an evening-only completion cancellation with either a successful or failing write stub.
    // Parameters: tester (WidgetTester): widget rendering, input and frame control.
    // Returns: No value; only evening/false is written, the returned boolean and notice match success/failure, notices last at least five seconds, and loading always clears.
    testWidgets('홈 복용 취소는 선택 시간대만 기존 저장 경로에 전달한다: $fail', (tester) async {
      _setViewport(tester, const Size(390, 844));
      final schedule = _CountingCheckSchedule()..failWrites = fail;
      final viewModel = MedBuddyViewModel(checkSchedule: schedule);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<MedBuddyViewModel>.value(
          value: viewModel,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      final saved = await tester
          .widget<InputPrescriptionUI>(find.byType(InputPrescriptionUI))
          .onMedicationSlotStatusRequested!('evening', false);
      await tester.pumpAndSettle();
      expect(saved, !fail);
      expect(schedule.slotWrites, [false]);
      expect(schedule.writtenSlots, ['evening']);
      expect(
        find.text(fail ? '복약 상태를 저장하지 못했습니다.' : '해당 시간대의 복용 기록을 취소했습니다.'),
        findsOneWidget,
      );
      // 실패 안내는 일반 성공 안내(5초)보다 먼저 사라지지 않는다.
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        greaterThanOrEqualTo(const Duration(seconds: 5)),
      );
      expect(
        tester
            .widget<InputPrescriptionUI>(find.byType(InputPrescriptionUI))
            .isNextMedicationCompletionLoading,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final scenario in [
    (
      name: '예정 시각 두 시간 초과 전',
      minute: 15 * 60 + 59,
      defaultTime: '18:00',
      alarmHour: null,
      completed: true,
      fail: false,
      warning: true,
    ),
    (
      name: '예정 시각 정확히 두 시간 전',
      minute: 16 * 60,
      defaultTime: '18:00',
      alarmHour: null,
      completed: true,
      fail: false,
      warning: false,
    ),
    (
      name: '예정 시각 두 시간 이내 전',
      minute: 16 * 60 + 1,
      defaultTime: '18:00',
      alarmHour: null,
      completed: true,
      fail: false,
      warning: false,
    ),
    (
      name: '변경한 기본 시각보다 두 시간 초과 전',
      minute: 17 * 60 + 29,
      defaultTime: '19:30',
      alarmHour: null,
      completed: true,
      fail: false,
      warning: true,
    ),
    (
      name: '조기 안내도 개별 알림 시각 우선',
      minute: 17 * 60,
      defaultTime: '20:00',
      alarmHour: 18,
      completed: true,
      fail: false,
      warning: false,
    ),
    (
      name: '꺼진 개별 알림 시각보다 두 시간 초과 전',
      minute: 17 * 60 + 59,
      defaultTime: '18:00',
      alarmHour: 20,
      completed: true,
      fail: false,
      warning: true,
    ),
    (
      name: '이른 기록 저장 실패',
      minute: 15 * 60 + 59,
      defaultTime: '18:00',
      alarmHour: null,
      completed: true,
      fail: true,
      warning: false,
    ),
    (
      name: '이른 복용 취소',
      minute: 15 * 60 + 59,
      defaultTime: '18:00',
      alarmHour: null,
      completed: false,
      fail: false,
      warning: false,
    ),
    (
      name: '예정 시각 전',
      minute: 17 * 60 + 59,
      defaultTime: '18:00',
      alarmHour: null,
      completed: true,
      fail: false,
      warning: false,
    ),
    (
      name: '예정 시각 정각',
      minute: 18 * 60,
      defaultTime: '18:00',
      alarmHour: null,
      completed: true,
      fail: false,
      warning: false,
    ),
    (
      name: '예정 시각 직후는 제때 복용',
      minute: 18 * 60 + 1,
      defaultTime: '18:00',
      alarmHour: null,
      completed: true,
      fail: false,
      warning: false,
    ),
    (
      name: '유예 시간 직전',
      minute: 18 * 60 + missedDoseGraceMinutes - 1,
      defaultTime: '18:00',
      alarmHour: null,
      completed: true,
      fail: false,
      warning: false,
    ),
    (
      name: '유예 시간이 지난 기록',
      minute: 18 * 60 + missedDoseGraceMinutes,
      defaultTime: '18:00',
      alarmHour: null,
      completed: true,
      fail: false,
      warning: true,
    ),
    (
      name: '변경한 기본 시각 이전',
      minute: 18 * 60 + 30,
      defaultTime: '19:00',
      alarmHour: null,
      completed: true,
      fail: false,
      warning: false,
    ),
    (
      name: '변경한 기본 시각 이후',
      minute: 19 * 60 + missedDoseGraceMinutes,
      defaultTime: '19:00',
      alarmHour: null,
      completed: true,
      fail: false,
      warning: true,
    ),
    (
      name: '개별 알림 시각 우선',
      minute: 19 * 60,
      defaultTime: '18:00',
      alarmHour: 20,
      completed: true,
      fail: false,
      warning: false,
    ),
    (
      name: '알림 꺼짐에도 복약 시각 적용',
      minute: 17 * 60 + missedDoseGraceMinutes,
      defaultTime: '18:00',
      alarmHour: 17,
      completed: true,
      fail: false,
      warning: true,
    ),
    (
      name: '늦은 기록 저장 실패',
      minute: 20 * 60,
      defaultTime: '18:00',
      alarmHour: null,
      completed: true,
      fail: true,
      warning: false,
    ),
    (
      name: '늦은 복용 취소',
      minute: 20 * 60,
      defaultTime: '18:00',
      alarmHour: null,
      completed: false,
      fail: false,
      warning: false,
    ),
  ]) {
    // 함수이름: 기록 시각별 안내 테스트
    // 함수역할: 실제 알림 시각의 우선순위와 두 시간 경계를 확인하며 취소·실패에는 주의 문구가 없는지 검증한다.
    // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
    testWidgets('저장 완료 알림의 놓친 복약 안내: ${scenario.name}', (tester) async {
      _setViewport(tester, const Size(390, 844));
      final schedule = _CountingCheckSchedule()..failWrites = scenario.fail;
      final viewModel = _HomeReminderViewModel(
        checkSchedule: schedule,
        setting: UserSetting(defaultEveningTime: scenario.defaultTime),
        reminders: scenario.alarmHour == null
            ? const {}
            : {
                'evening': MedicationAlarm(
                  slotKey: 'evening',
                  hour: scenario.alarmHour!,
                  minute: 0,
                  enabled: false,
                ),
              },
      );
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<MedBuddyViewModel>.value(
          value: viewModel,
          child: MaterialApp(
            home: HomeScreen(
              nowProvider: () => DateTime(
                2026,
                9,
                22,
                scenario.minute ~/ 60,
                scenario.minute % 60,
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('놓친 복약은'), findsNothing);
      final saved = await tester
          .widget<InputPrescriptionUI>(find.byType(InputPrescriptionUI))
          .onMedicationSlotStatusRequested!('evening', scenario.completed);
      await tester.pumpAndSettle();
      expect(saved, !scenario.fail);
      final snackbar = tester.widget<SnackBar>(find.byType(SnackBar));
      final message = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('home-dose-record-notice')),
              matching: find.byType(Text),
            ),
          )
          .data!;
      expect(message.contains('놓친 복약은'), scenario.warning);
      if (scenario.warning) {
        expect(
          message,
          '예정된 약을 모두 복용 완료로 기록했습니다.\n'
          '놓친 복약은 임의로 추가 복용하지 말고 처방·복약지도를 확인하세요.',
        );
        expect(snackbar.duration, const Duration(seconds: 8));
      }
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: 늦은 응답의 안내 기준 테스트
  // 함수역할: 저장 중 예정 시각을 지나도 정상 시각에 누른 기록을 늦은 기록으로 바꾸지 않는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
  testWidgets('응답이 늦어져도 버튼을 누른 시각으로 주의 문구를 판단한다', (tester) async {
    final gate = Completer<void>();
    final schedule = _CountingCheckSchedule()..writeGate = gate;
    final viewModel = _HomeReminderViewModel(checkSchedule: schedule);
    addTearDown(viewModel.dispose);
    var now = DateTime(2026, 9, 22, 17, 59);
    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: MaterialApp(home: HomeScreen(nowProvider: () => now)),
      ),
    );
    final saving = tester
        .widget<InputPrescriptionUI>(find.byType(InputPrescriptionUI))
        .onMedicationSlotStatusRequested!('evening', true);
    await tester.pump();
    now = DateTime(2026, 9, 22, 18, 1);
    gate.complete();
    await saving;
    await tester.pumpAndSettle();
    expect(find.textContaining('놓친 복약은'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 조기 기록의 지연 응답 테스트
  // 함수역할: 저장 중 조기 안내 경계를 지나더라도 버튼을 누를 때 필요했던 안내를 유지하는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
  testWidgets('이른 기록도 저장 응답이 아닌 버튼을 누른 시각으로 안내한다', (tester) async {
    final gate = Completer<void>();
    final schedule = _CountingCheckSchedule()..writeGate = gate;
    final viewModel = _HomeReminderViewModel(checkSchedule: schedule);
    addTearDown(viewModel.dispose);
    var now = DateTime(2026, 9, 22, 15, 59);
    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: MaterialApp(home: HomeScreen(nowProvider: () => now)),
      ),
    );
    final saving = tester
        .widget<InputPrescriptionUI>(find.byType(InputPrescriptionUI))
        .onMedicationSlotStatusRequested!('evening', true);
    await tester.pump();
    now = DateTime(2026, 9, 22, 16, 1);
    gate.complete();
    expect(await saving, isTrue);
    await tester.pumpAndSettle();
    expect(find.textContaining('놓친 복약은'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    // Function Name: testWidgets: '큰 글씨에서도 저장 알림의 주의 문구가 잘리지 않는다: $language'
    // Description: Record an evening dose on a 320-by-700 viewport at double text scale in Korean and English, then scroll the safety notice.
    // Parameters: tester (WidgetTester): widget rendering, input and frame control.
    // Returns: No value; the notice is not line-truncated, occupies more than 240 pixels of width within the viewport, and its View action sits below the readable text without exceptions.
    testWidgets('큰 글씨에서도 저장 알림의 주의 문구가 잘리지 않는다: $language', (tester) async {
      _setViewport(tester, const Size(320, 700));
      final viewModel = _HomeReminderViewModel(
        checkSchedule: _CountingCheckSchedule(),
        setting: UserSetting(language: language),
      );
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<MedBuddyViewModel>.value(
          value: viewModel,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: HomeScreen(nowProvider: () => DateTime(2026, 9, 22, 19)),
          ),
        ),
      );
      await tester
          .widget<InputPrescriptionUI>(find.byType(InputPrescriptionUI))
          .onMedicationSlotStatusRequested!('evening', true);
      await tester.pumpAndSettle();
      final text = find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining(
          language == 'ko' ? '놓친 복약은' : 'Do not take an extra dose on your own',
        ),
      );
      expect(text, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
        isFalse,
      );
      final notice = find.byKey(const Key('home-dose-record-notice'));
      // 일정 확인 버튼이 본문 옆 폭을 차지하지 않아, 주의 문구가 화면 폭 대부분(여백 제외)을 쓴다.
      expect(tester.getRect(notice).width, greaterThan(240));
      expect(
        tester.getRect(find.text(language == 'ko' ? '일정 확인' : 'View')).top,
        greaterThanOrEqualTo(tester.getRect(notice).bottom),
      );
      expect(tester.getRect(notice).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(notice).bottom, lessThanOrEqualTo(700));
      await tester.drag(notice, const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(text).bottom,
        lessThanOrEqualTo(tester.getRect(notice).bottom + 1),
      );
      expect(tester.takeException(), isNull);
    });
  }

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
          userSetting: const UserSetting(language: 'ko'),
          // 함수이름: onPillIdentificationRequested 콜백
          // 함수역할: 선택한 촬영 모드는 사용하지 않고 낱알약 식별 요청 여부를 기록한다.
          // 매개변수: mode (PillCaptureMode): 요청된 촬영 모드이며 이 대역에서는 소비하지 않는다.
          // 반환값: void: pillTaskRequested를 true로 바꾼다.

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
    await tester.tap(find.text('약 등록·관리'));
    await tester.pumpAndSettle();
    expect(find.text('약 관리'), findsOneWidget);
    expect(find.text('약봉투·처방전 등록'), findsNothing);
    await tester.tap(find.text('약 등록'));
    await tester.pumpAndSettle();

    expect(find.text('약봉투·처방전 등록'), findsOneWidget);
    expect(find.text('직접 등록'), findsOneWidget);
    await tester.tap(find.text('직접 등록'));
    await tester.pumpAndSettle();
    expect(manualTaskRequested, isTrue);

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

  // 함수이름: testWidgets: 'home owns navigation into loose-pill identification'
  // 함수역할: 실제 HomeScreen이 제공한 낱알약 식별 콜백을 singlePhoto 모드로 호출한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 식별 화면이 열리고 전달한 촬영 모드가 유지된다.
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

  // 홈 선택창에서 고른 병원·약국만 해당 지도 화면으로 연결한다.
  for (final hospitals in [true, false]) {
    // 함수이름: testWidgets: 'home selects nearby care hospitals=$hospitals'
    // 함수역할: 홈의 주변 의료시설 동작을 호출한 뒤 병원 또는 약국 선택지를 누르고 화면을 종료한다.
    // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
    // 반환값: 반환값 없음; 선택 전에는 시설 화면이 없고 선택한 hospitals 값의 일반 조회 화면이 열리며 종료 후 지연 예외가 없다.
    testWidgets('home selects nearby care hospitals=$hospitals', (
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
      tester
          .widget<InputPrescriptionUI>(find.byType(InputPrescriptionUI))
          .onNearbyPharmacyRequested
          ?.call();
      await tester.pumpAndSettle();
      expect(find.byType(CheckNearbyPharmacyUI), findsNothing);
      await tester.tap(find.text(hospitals ? '근처 병원' : '근처 약국'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final screen = tester.widget<CheckNearbyPharmacyUI>(
        find.byType(CheckNearbyPharmacyUI),
      );
      expect(screen.hospitals, hospitals);
      expect(screen.selectionMode, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
      expect(tester.takeException(), isNull);
    });
  }

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
    expect(find.text('복약 기록'), findsOneWidget);
    expect(find.text('내 정보'), findsOneWidget);
    expect(find.text('약 등록·관리'), findsOneWidget);
    expect(find.text('낱알약 식별'), findsNothing);
    expect(find.text('건강 관리 추천'), findsOneWidget);
    expect(find.text('근처 운영 병원·약국'), findsOneWidget);
    expect(find.text('가까운 병원·약국의 운영시간을 확인해요'), findsOneWidget);
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

  // 함수이름: testWidgets: 'schedule destination requests cache-aware refresh on revisit'
  // 함수역할: 일정 탭에 재방문하고 확정된 일정 변경을 적용한 뒤 다시 방문한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 최근 조회는 첫 두 방문에 한 번만 수행하고 변경으로 캐시가 무효화된 다음 방문에서는 두 번째 조회를 수행한다.
  testWidgets('schedule destination requests cache-aware refresh on revisit', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    // 앞선 테스트의 기기 설정이나 알림 조회 실패에 따라 캐시 조건이 달라지지 않게 한다.
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((_) async => http.Response('{"data":[]}', 200));
    final checkSchedule = _CountingCheckSchedule();
    final viewModel = MedBuddyViewModel(
      checkSchedule: checkSchedule,
      setNotification: SetNotification(client: client),
      notificationService: RecordingNotificationService(),
    );
    addTearDown(client.close);
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

    expect(checkSchedule.requestCount, 1);

    // 확정된 일정 변경은 최근 조회를 무효화하므로 다음 재방문에서 다시 읽어야 한다.
    viewModel.applyConfirmedTodaySchedules([]);
    await tester.tap(find.byKey(const ValueKey('bottomNavigation-home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bottomNavigation-schedule')));
    await tester.pumpAndSettle();
    expect(checkSchedule.requestCount, 2);
  });

  // 함수이름: testWidgets: 'medication cabinet refreshes whenever it is revisited'
  // 함수역할: 홈의 약 등록·관리 메뉴에서 복약함에 진입하고 뒤로 나온 뒤 다시 진입한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 저장 약 조회 횟수가 첫 진입 1회에서 재진입 2회로 늘어난다.
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

    await tester.tap(find.text('약 등록·관리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('약 관리'));
    await tester.pumpAndSettle();
    expect(checkSavedMedication.requestCount, 1);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('약 등록·관리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('약 관리'));
    await tester.pumpAndSettle();

    expect(checkSavedMedication.requestCount, 2);
  });

  // 함수이름: testWidgets: '복약함 뒤로가기는 선택만 취소하고 두 번째에 홈으로 이동한다'
  // 함수역할: 실제 홈 셸의 복약함에서 선택 모드를 켜고 시스템 뒤로가기를 두 번 보낸다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 첫 뒤로가기는 선택 표시를 없애고 두 번 모두 홈 탭 선택을 유지하며 화면 종료 후에도 예외가 없다.
  testWidgets('복약함 뒤로가기는 선택만 취소하고 두 번째에 홈으로 이동한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    _setViewport(tester, const Size(390, 844));
    final viewModel = MedBuddyViewModel(
      checkSavedMedication: _SelectableCheckSavedMedication(),
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.tap(find.text('약 등록·관리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('약 관리'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saved-medication-select')));
    await tester.pumpAndSettle();
    expect(find.text('복약 선택'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('복약 선택'), findsNothing);
    expect(
      tester
          .widget<MedBuddyBottomNavigationUI>(
            find.byType(MedBuddyBottomNavigationUI, skipOffstage: false),
          )
          .selectedDestination,
      MedBuddyDestination.home,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MedBuddyBottomNavigationUI>(
            find.byType(MedBuddyBottomNavigationUI, skipOffstage: false),
          )
          .selectedDestination,
      MedBuddyDestination.home,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 20));
  });

  // 함수이름: testWidgets: 'bottom navigation exposes four labelled destinations'
  // 함수역할: 한국어 하단 탐색의 네 목적지와 일정 버튼을 검사하고 일정을 누른다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 홈·일정·복약 기록·내 정보만 보이고 등록 동작은 없으며 일정 콜백과 높이 48 이상 터치 영역을 제공한다.
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
    expect(find.text('복약 기록'), findsOneWidget);
    expect(find.text('내 정보'), findsOneWidget);
    expect(find.text('약봉투·처방전 등록'), findsNothing);

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
  for (final language in ['ko', 'en']) {
    for (final scale in [1.0, 1.7]) {
      // 함수이름: testWidgets: 'bottom navigation aligns icons and labels $language $scale'
      // 함수역할: 언어·글자 배율별로 채팅을 포함한 모든 하단 목적지의 아이콘과 문구 위치를 비교한다.
      // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
      // 반환값: 반환값 없음; 아이콘 중심과 문구 상단이 각각 0.01 오차 안에서 정렬되고 문구는 줄바꿈 없는 한 줄이며 렌더링 예외가 없다.
      testWidgets(
        'bottom navigation aligns icons and labels $language $scale',
        (tester) async {
          _setViewport(tester, const Size(390, 300));
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  bottomNavigationBar: MedBuddyBottomNavigationUI(
                    selectedDestination: MedBuddyDestination.home,
                    language: language,
                    showChat: true,
                    onDestinationSelected: (_) {},
                  ),
                ),
              ),
            ),
          );
          final icons = <double>[];
          final labels = <double>[];
          for (final destination in MedBuddyDestination.values) {
            final button = find.byKey(
              ValueKey('bottomNavigation-${destination.name}'),
            );
            icons.add(
              tester
                  .getCenter(
                    find.descendant(of: button, matching: find.byType(Icon)),
                  )
                  .dy,
            );
            labels.add(
              tester
                  .getTopLeft(
                    find.descendant(of: button, matching: find.byType(Text)),
                  )
                  .dy,
            );
          }
          for (final top in icons) {
            expect(top, closeTo(icons.first, 0.01));
          }
          for (final top in labels) {
            expect(top, closeTo(labels.first, 0.01));
          }
          for (final destination in MedBuddyDestination.values) {
            final button = find.byKey(
              ValueKey('bottomNavigation-${destination.name}'),
            );
            final label = tester.widget<Text>(
              find.descendant(of: button, matching: find.byType(Text)),
            );
            expect(label.maxLines, 1);
            expect(label.softWrap, isFalse);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  // Function Name: testWidgets: 'bottom navigation follows accessible text scaling'
  // Description: Render bottom navigation with inherited double text scaling in a short viewport.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; navigation grows beyond 80 pixels, the Home label does not override the text scaler, and layout raises no exception.
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

  // 함수이름: testWidgets: '빠른 기능 카드는 서로 같은 높이와 고유한 아이콘을 제공한다'
  // 함수역할: 390 너비 홈에서 주변 약국·건강 정보 카드 높이와 건강·설정 아이콘을 확인한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 두 카드 높이가 같고 각 기능 아이콘이 하나씩 있으며 렌더링 예외가 없다.
  testWidgets('빠른 기능 카드는 서로 같은 높이와 고유한 아이콘을 제공한다', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: InputPrescriptionUI(
          userSetting: const UserSetting(language: 'ko'),
          // 함수이름: onPillIdentificationRequested 콜백
          // 함수역할: 홈 카드 배치를 검사할 수 있도록 식별 진입 콜백을 제공하되 이동은 실행하지 않는다.
          // 매개변수: mode (PillCaptureMode): 요청된 촬영 모드이며 이 대역에서는 소비하지 않는다.
          // 반환값: void: 외부 동작 없이 종료한다.

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

  // 함수이름: testWidgets: '약국과 복약 알림 카드는 서로 다른 자리를 유지한다'
  // 함수역할: 주변 의료시설 콜백이 없는 홈을 만든 뒤 콜백을 연결해 다시 렌더링한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 첫 화면에 주변 시설·환경설정 카드가 각각 있고 콜백 연결 후에도 주변 시설 카드가 하나만 남으며 예외가 없다.
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
          userSetting: const UserSetting(language: 'ko'),
          // 함수이름: onPillIdentificationRequested 콜백
          // 함수역할: 홈 카드 배치를 검사할 수 있도록 식별 진입 콜백을 제공하되 이동은 실행하지 않는다.
          // 매개변수: mode (PillCaptureMode): 요청된 촬영 모드이며 이 대역에서는 소비하지 않는다.
          // 반환값: void: 외부 동작 없이 종료한다.

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

  // 함수이름: testWidgets: '영어 설정은 메인 화면 제목과 설명에 함께 반영된다'
  // 함수역할: 영어 설정의 홈에서 약 등록·관리, 환경설정, 주변 병원·약국 제목과 소개 문구를 확인한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 지정한 영어 제목·설명은 표시되고 한글·영문 빠른 기능 제목은 표시되지 않는다.
  testWidgets('영어 설정은 메인 화면 제목과 설명에 함께 반영된다', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: InputPrescriptionUI(
          userSetting: const UserSetting(language: 'en'),
          // 함수이름: onPillIdentificationRequested 콜백
          // 함수역할: 홈 카드 배치를 검사할 수 있도록 식별 진입 콜백을 제공하되 이동은 실행하지 않는다.
          // 매개변수: mode (PillCaptureMode): 요청된 촬영 모드이며 이 대역에서는 소비하지 않는다.
          // 반환값: void: 외부 동작 없이 종료한다.

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
    expect(find.text('Add or manage medication'), findsOneWidget);
    expect(find.text('Add or manage your medications'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Nearby Hospitals & Pharmacies'), findsOneWidget);
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

    final prescriptionTitle = tester.widget<Text>(find.text('약 등록·관리'));
    final reminderTitle = tester.widget<Text>(find.text('환경설정'));
    expect(prescriptionTitle.textScaler, isNull);
    expect(reminderTitle.textScaler, isNull);
    expect(find.text('건강 관리 추천'), findsOneWidget);
    expect(find.text('환경설정'), findsOneWidget);
    expect(find.text('약을 등록하고 저장한 약을 관리해요'), findsOneWidget);
    expect(find.text('글자 크기·언어·알림을 설정해요'), findsOneWidget);
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
                  // 시간대를 넘겨도 기존의 작은 홈 미리보기 크기를 유지한다.
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

  // Function Name: testWidgets: 'compact subtitles wrap without shrinking inside FittedBox'
  // Description: Render the compact English home and inspect its food/activity guidance subtitle.
  // Parameters: tester (WidgetTester): widget rendering, input and frame control.
  // Returns: No value; the subtitle allows two lines at font size 11, has no FittedBox ancestor, and renders without exception.
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

  // 함수이름: testWidgets: 'dashboard chooses the earliest alarm and localizes its slot'
  // 함수역할: 영어 홈에서 아침 알림은 20시, 점심 알림은 12시로 설정하고 현재 시각을 10시로 고정한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 이름 순서보다 실제 알림 시각이 빠른 점심 약을 영어 상태·시각 문구로 표시한다.
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

    expect(find.text('Lunch · Not taken'), findsOneWidget);
    expect(find.text('12:00 · LunchMed'), findsOneWidget);
    expect(find.textContaining('점심 12:00'), findsNothing);
  });

  // 함수이름: testWidgets: 'dashboard represents every due medication and disabled alarm'
  // 함수역할: 같은 점심 시간대의 약 두 개와 꺼진 알림을 오전 10시 홈에 제공한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 복약 요약은 점심 미복용과 첫 약 외 1개를 표시하되 다음 알림 제목이나 두 번째 약명을 따로 표시하지 않는다.
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

    expect(find.text('점심 · 미복용'), findsOneWidget);
    expect(find.text('다음 복약 알림'), findsNothing);
    expect(find.text('12:00 · 약A 외 1개'), findsOneWidget);
    expect(find.text('약B'), findsNothing);
  });

  for (final viewport in const [Size(320, 640), Size(390, 844)]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      for (final language in const ['ko', 'en']) {
        // 함수이름: 시간대 요약 배치 테스트
        // 함수역할: 긴 약 이름을 두 줄 안에 요약하고 큰 글씨에서도 완료 버튼과 겹치지 않는지 확인한다.
        // 매개변수: tester (WidgetTester): 화면 배치와 상호작용 검증 도구.
        // 반환값: 화면 크기·배율·언어별 검증을 마치는 Future<void>.
        testWidgets('slot summary stays compact $viewport $scale $language', (
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
                // 함수이름: onMedicationSlotStatusRequested 콜백
                // 함수역할: 안내 아래 완료 버튼으로 전달되는 시간대를 기록한다.
                // 매개변수: slotKey, completed: 저장할 시간대와 완료 상태. 반환값: 저장 성공.
                onMedicationSlotStatusRequested: (slotKey, completed) async {
                  completedSlot = slotKey;
                  expect(completed, isTrue);
                  return true;
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          final guide = find.textContaining('Long medication name 100mg');
          expect(guide, findsOneWidget);
          final label = tester.widget<Text>(guide);
          expect(label.maxLines, 2);
          expect(label.overflow, TextOverflow.ellipsis);
          expect(label.textScaler, isNull);
          final paragraph = tester.renderObject<RenderParagraph>(guide);
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

  // 함수이름: testWidgets: 'dashboard uses an overdue-specific status message'
  // 함수역할: 오전 8시 미복용 약만 있는 홈의 현재 시각을 밤 11시로 고정한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 미복용 확인과 시간대·약명은 보이고 제때 복용하거나 꾸준히 복용 중이라는 일반 안내는 보이지 않는다.
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
    expect(find.text('아침 · 미복용'), findsOneWidget);
    expect(find.text('08:00 · 아침약'), findsOneWidget);
    expect(find.textContaining('늦지 않게 복용하세요.'), findsNothing);
    expect(find.text('오늘도 복약을 꾸준히 이어가고 있어요'), findsNothing);
  });

  // 함수이름: testWidgets: 'dashboard marks the next medication slot from one large action'
  // 함수역할: 점심 12:30 약 두 개를 오전 10시 홈에 제공한 뒤 큰 복용 완료 버튼을 누른다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 선택한 시간대는 lunch이고 저장 콜백에 완료 true를 전달하며 위젯 예외가 없다.
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
          // Function Name: onMedicationSlotStatusRequested callback
          // Description:
          // - Capture the slot completed by the dashboard's large next-dose action.
          // Parameters:
          // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime.
          // - completed (bool): Requested completion state.
          // Returns:
          // - Future<bool>; stores the selected slot and reports success.
          onMedicationSlotStatusRequested: (slotKey, completed) async {
            completedSlotKey = slotKey;
            expect(completed, isTrue);
            return true;
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

  // 함수이름: testWidgets: 'dashboard prioritizes a future dose over an overdue dose'
  // 함수역할: 오전 10시에 지난 아침 8시 약과 예정된 점심 12시 약을 함께 제공한다.
  // 매개변수: tester (WidgetTester): 화면 생성·입력·프레임 제어.
  // 반환값: 반환값 없음; 점심 페이지·미복용 상태·약명부터 표시하고 지나간 아침 요약이나 추가 복용 경고는 첫 요약에 나타나지 않는다.
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

    expect(find.byKey(const Key('home-slot-page-lunch')), findsOneWidget);
    expect(find.text('점심 · 미복용'), findsOneWidget);
    expect(find.text('12:00 · 점심약'), findsOneWidget);
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
// - caregiverScheduleHint (Widget?): Optional linked-patient guidance below the action cards.
// - schedules (List<MedicationSchedule>): Recognized or current dose schedules for the scenario.
// - alarms (Map<String, MedicationAlarm>): Alarm settings indexed by dose slot.
// - completedCount (int): Completed-dose count displayed in the dashboard.
// - totalCount (int): Total scheduled dose count shown in the dashboard.
// - nowProvider (DateTime Function()?): Dashboard clock override for due-dose ordering.
// - onMedicationSlotStatusRequested (Future<bool> Function(String, bool)?): Optional callback for
//   completing the next due slot.
// Returns:
// - The configured InputPrescriptionUI with inert unrelated navigation callbacks.
InputPrescriptionUI _home({
  UserSetting userSetting = const UserSetting(),
  Widget? caregiverScheduleHint,
  List<MedicationSchedule> schedules = const [],
  Map<String, MedicationAlarm> alarms = const {},
  int completedCount = 0,
  int totalCount = 0,
  DateTime Function()? nowProvider,
  Future<bool> Function(String slotKey, bool completed)?
  onMedicationSlotStatusRequested,
}) {
  return InputPrescriptionUI(
    userSetting: userSetting,
    caregiverScheduleHint: caregiverScheduleHint,
    todayMedicationScheduleList: schedules,
    medicationReminderSettings: alarms,
    todayMedicationCompletedCount: completedCount,
    todayMedicationTotalCount: totalCount,
    nowProvider: nowProvider,
    onMedicationSlotStatusRequested: onMedicationSlotStatusRequested,
    // 함수이름: onPillIdentificationRequested 콜백
    // 함수역할: 홈 카드 배치를 검사할 수 있도록 식별 진입 콜백을 제공하되 이동은 실행하지 않는다.
    // 매개변수: mode (PillCaptureMode): 요청된 촬영 모드이며 이 대역에서는 소비하지 않는다.
    // 반환값: void: 외부 동작 없이 종료한다.

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
