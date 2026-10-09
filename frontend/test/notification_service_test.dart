// File Name: notification_service_test.dart
// Role: Regression coverage for notification routing, cold starts, dose actions, and sign-out cleanup.

import 'package:flutter/material.dart';
import 'package:medbuddy_frontend/entities/caregiver_alert_context_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/linked_chat_entry_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/main.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_controls.dart';
import 'support/fake_notification_service.dart';

// Class Name: _EmptyCheckSchedule
// Role: Empty schedule fixture for notification-driven navigation.
// Responsibilities:
// - Keep the destination schedule empty without accessing the backend.
class _EmptyCheckSchedule extends CheckSchedule {
  // Function Name: requestTodayMedicationSchedule
  // Description:
  // - Keep the destination schedule empty without accessing the backend.
  // Parameters:
  // - None.
  // Returns:
  // - An empty schedule list.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async {
    return const [];
  }
}

// 알림을 연속 선택할 때 실제 스크롤 위치도 바뀌는지 확인할 네 시간대 일정이다.
class _AllSlotsCheckSchedule extends _EmptyCheckSchedule {
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async => const [
    MedicationSchedule(
      medicationID: '1', medicationName: '테스트정', intakeTime: '1정',
      medicationTime: 4, scheduleSlotKeys: ['morning', 'lunch', 'evening', 'bedtime'],
    ),
  ];
}

// Class Name: _RecordingCheckSchedule
// Role: Schedule spy for checking the slot and status sent by a notification action.
// Responsibilities:
// - Record the requested dose slot and completion status without modifying backend data.
class _RecordingCheckSchedule extends _EmptyCheckSchedule {
  String? updatedSlotKey;
  bool? updatedStatus;
  String? updatedScheduleDate;

  // Function Name: updateMedicationSlotStatus
  // Description:
  // - Record the requested dose slot and completion status without modifying backend data.
  // Parameters:
  // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime.
  // - medicationStatus (bool): Requested taken/untaken completion state.
  // Returns:
  // - An empty replacement schedule list.
  @override
  Future<List<MedicationSchedule>> updateMedicationSlotStatus(
    String slotKey,
    bool medicationStatus, {
    String? expectedScheduleDate,
  }) async {
    updatedSlotKey = slotKey;
    updatedStatus = medicationStatus;
    updatedScheduleDate = expectedScheduleDate;
    return const [];
  }
}

// Function Name: main
// Description:
// - Register regression cases for notification routing, cold starts, dose actions, and sign-out
//   cleanup.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: dated payload regression
  // Description: Strict dates prevent rollover and undated legacy quick actions.
  // Parameters: None.
  // Returns: Parser assertions for valid, malformed, stale, and legacy payloads.
  test('quick actions require a valid matching reminder date', () {
    final selection = NotificationService.selectionFromPayload(
      'schedule:morning:17:2026-09-10',
      actionId: NotificationService.markSlotTakenActionId,
    );
    expect(selection?.isForDate(DateTime(2026, 9, 10)), isTrue);
    expect(selection?.isForDate(DateTime(2026, 9, 11)), isFalse);
    expect(NotificationService.selectionFromPayload(
      'schedule:morning:17',
    )?.isForDate(DateTime(2026, 9, 10)), isFalse);
    for (final invalid in ['2026-02-30', '2026-09-10T12', 'invalid']) {
      expect(NotificationService.selectionFromPayload(
        'schedule:morning:17:$invalid',
      ), isNull);
    }
  });

  // Function Name: tearDown callback
  // Description:
  // - Remove the global notification-selection handler after every test.
  // Parameters:
  // - None.
  // Returns:
  // - No value; later tests cannot receive the previous callback.
  tearDown(() {
    NotificationService.setNotificationSelectionHandler(null);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: schedule payload resolves to the dose screen destination.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('schedule payload resolves to the dose screen destination', () {
    expect(
      NotificationService.destinationFromPayload('schedule:morning:17'),
      MedicationNotificationDestination.schedule,
    );
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: malformed notification payloads cannot trigger navigation.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('malformed notification payloads cannot trigger navigation', () {
    expect(NotificationService.destinationFromPayload(null), isNull);
    expect(NotificationService.destinationFromPayload('schedule::17'), isNull);
    expect(
      NotificationService.destinationFromPayload('schedule:morning:not-an-id'),
      isNull,
    );
    expect(NotificationService.destinationFromPayload('settings:17'), isNull);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 선택한 일정 알림이 등록된 선택 처리기로 전달되는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('a selected schedule notification reaches the registered handler', () {
    final selections = <MedicationNotificationSelection>[];
    NotificationService.setNotificationSelectionHandler(selections.add);

    NotificationService.handleNotificationPayload('schedule:evening:29');

    expect(
      selections.single.destination,
      MedicationNotificationDestination.schedule,
    );
    expect(selections.single.slotKey, 'evening');
    expect(selections.single.patientHash, isNull);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: schedule notification actions retain the slot and notification id.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('schedule notification actions retain the slot and notification id', () {
    final taken = NotificationService.selectionFromPayload(
      'schedule:evening:29',
      actionId: NotificationService.markSlotTakenActionId,
      notificationId: 900,
    );
    final snoozed = NotificationService.selectionFromPayload(
      'schedule:bedtime:31',
      actionId: NotificationService.snoozeTenMinutesActionId,
    );

    expect(taken?.action, MedicationNotificationAction.markSlotTaken);
    expect(taken?.slotKey, 'evening');
    expect(taken?.notificationId, 900);
    expect(snoozed?.action, MedicationNotificationAction.snoozeTenMinutes);
    expect(snoozed?.slotKey, 'bedtime');
    expect(snoozed?.notificationId, 31);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: unknown notification actions retain normal open behavior.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('unknown notification actions retain normal open behavior', () {
    final selection = NotificationService.selectionFromPayload(
      'schedule:morning:17',
      actionId: 'untrusted-action',
    );

    expect(selection?.action, MedicationNotificationAction.open);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 앱 초기 실행 알림을 처리기 등록 뒤에 전달하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('a cold-start notification is delivered after handler registration', () {
    NotificationService.handleNotificationPayload('schedule:morning:31');

    final selections = <MedicationNotificationSelection>[];
    NotificationService.setNotificationSelectionHandler(selections.add);

    expect(
      selections.single.destination,
      MedicationNotificationDestination.schedule,
    );
    expect(selections.single.slotKey, 'morning');
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 보호자 알림 데이터가 선택 환자 식별자를 보존하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('caregiver payload keeps the selected patient hash', () {
    final selection = NotificationService.selectionFromPayload(
      'caregiver:patient_test',
    );

    expect(
      selection?.destination,
      MedicationNotificationDestination.caregiverSchedule,
    );
    expect(selection?.patientHash, 'patient_test');
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 채팅 알림 데이터에는 연동 대화 식별자만 유지되는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('chat payload keeps only the linked conversation identifier', () {
    final selection = NotificationService.selectionFromPayload('chat:37');

    expect(
      selection?.destination,
      MedicationNotificationDestination.linkedChat,
    );
    expect(selection?.linkId, 37);
    expect(selection?.patientHash, isNull);
    expect(NotificationService.selectionFromPayload('chat:not-an-id'), isNull);
    expect(NotificationService.selectionFromPayload('chat:0'), isNull);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 세션 정리 대상 알림을 일정, 보호자와 채팅 유형으로 구별하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test(
    'session cleanup classifies schedule, caregiver, and chat notifications',
    () {
      expect(
        NotificationService.isSessionNotificationPayload('schedule:morning:17'),
        isTrue,
      );
      expect(
        NotificationService.isSessionNotificationPayload(
          'caregiver:patient_test',
        ),
        isTrue,
      );
      expect(
        NotificationService.isSessionNotificationPayload('chat:37'),
        isTrue,
      );
      expect(
        NotificationService.isSessionNotificationPayload('settings:17'),
        isFalse,
      );
    },
  );

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 일정 알림 선택 처리기가 해당 시간대 복약 화면을 여는지 검증한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('the notification selection handler opens the dose screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final navigatorKey = GlobalKey<NavigatorState>();
    MedicationNotificationSelectionHandler? selectionHandler;

    await tester.pumpWidget(
      MedBuddyApp(
        navigatorKey: navigatorKey,
        // Function Name: notificationSelectionRegistrar callback
        // Description:
        // - Capture the registered selection handler for synthetic notification taps.
        // Parameters:
        // - handler (MedicationNotificationSelectionHandler?): Selection handler registered by the
        //   application.
        // Returns:
        // - No value; the callback completes after its recorded side effects.
        notificationSelectionRegistrar: (handler) {
          selectionHandler = handler;
        },
        // Function Name: viewModelFactory callback
        // Description:
        // - Build a view model using local settings and injected schedule/alarm/notification fixtures.
        // Parameters:
        // - None.
        // Returns:
        // - A MedBuddyViewModel isolated from real notification plugins.
        viewModelFactory: () => MedBuddyViewModel(
          checkSchedule: _EmptyCheckSchedule(),
          setNotification: EmptySetNotification(),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: RecordingNotificationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(selectionHandler, isNotNull);
    // 이전 계정용 보호자 알림은 현재 계정의 화면이나 액션을 실행하지 않는다.
    final otherAccountAlert = CaregiverAlertContext(
      alertId: 1, sourceAlertId: 1, linkId: 17,
      eventId: 'a' * 64, sourceEventId: 'a' * 64,
      patientHash: 'patient-other', recipientHash: 'another-account',
      slotKey: 'morning', scheduleDate: '2026-09-28',
    );
    for (final action in [MedicationNotificationAction.open,
      MedicationNotificationAction.caregiverSnooze,
      MedicationNotificationAction.caregiverRequestCheck]) {
      selectionHandler!(MedicationNotificationSelection(
        destination: MedicationNotificationDestination.caregiverSchedule,
        caregiverAlert: otherAccountAlert, patientHash: 'patient-other', action: action,
      ));
      await tester.pumpAndSettle();
      expect(navigatorKey.currentState?.canPop(), isFalse);
    }
    selectionHandler!(
      const MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(navigatorKey.currentState?.canPop(), isTrue);
    expect(find.byType(CheckScheduleUI), findsOneWidget);
    final scheduleState = tester.state(find.byType(CheckScheduleUI));
    // 다른 시간대 알림을 연속으로 눌러도 같은 화면에 새 목적지가 전달된다.
    for (final slot in ['morning', 'evening', 'bedtime', 'lunch']) {
      selectionHandler!(MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule,
        slotKey: slot,
      ));
      await tester.pumpAndSettle();
      expect(tester.widget<CheckScheduleUI>(find.byType(CheckScheduleUI)).initialSlotKey, slot);
      expect(tester.state(find.byType(CheckScheduleUI)), same(scheduleState));
    }
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(navigatorKey.currentState!.canPop(), isFalse);
  });

  // 같은 일정 화면에서 알림의 새 시간대까지 스크롤하며 중복 경로를 쌓지 않는다.
  testWidgets('successive notification slots reveal their schedule cards', (tester) async {
    SharedPreferences.setMockInitialValues({});
    MedicationNotificationSelectionHandler? handler;
    await tester.pumpWidget(MedBuddyApp(
      notificationSelectionRegistrar: (value) => handler = value,
      viewModelFactory: () => MedBuddyViewModel(
        checkSchedule: _AllSlotsCheckSchedule(),
        setNotification: EmptySetNotification(),
        manageUserSetting: ManageUserSetting(useRemotePersistence: false),
        notificationService: RecordingNotificationService(),
      ),
    ));
    await tester.pumpAndSettle();
    double? bedtimeOffset;
    for (final slot in ['bedtime', 'morning']) {
      handler!(MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule, slotKey: slot,
      ));
      await tester.pumpAndSettle();
      final target = find.byKey(ValueKey('schedule-entire-slot-toggle-$slot'));
      expect(target, findsOneWidget);
      final offset = Scrollable.of(tester.element(target)).position.pixels;
      if (slot == 'bedtime') {
        expect(offset, greaterThan(0));
        bedtimeOffset = offset;
      } else {
        expect(offset, lessThan(bedtimeOffset!));
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });

  // 채팅 알림은 역할 정보가 없는 채팅 화면을 직접 열지 않고 연동 확인 경로를 거친다.
  testWidgets('chat notification resolves the link before opening the room', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    MedicationNotificationSelectionHandler? selectionHandler;
    await tester.pumpWidget(
      MedBuddyApp(
        notificationSelectionRegistrar: (handler) => selectionHandler = handler,
        viewModelFactory: () => MedBuddyViewModel(
          checkSchedule: _EmptyCheckSchedule(),
          setNotification: EmptySetNotification(),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: RecordingNotificationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    selectionHandler!(
      const MedicationNotificationSelection(
        destination: MedicationNotificationDestination.linkedChat,
        linkId: 17,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final entry = tester.widget<LinkedChatEntryUI>(find.byType(LinkedChatEntryUI));
    expect(entry.linkId, 17);
    expect(entry.currentUserHash, isNotEmpty);
    expect(entry.userSetting.userHash, entry.currentUserHash);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: the notification action marks the whole dose slot as taken.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('the notification action marks the whole dose slot as taken', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final schedule = _RecordingCheckSchedule();
    MedicationNotificationSelectionHandler? selectionHandler;

    await tester.pumpWidget(
      MedBuddyApp(
        // Function Name: notificationSelectionRegistrar callback
        // Description:
        // - Capture the registered selection handler for synthetic notification taps.
        // Parameters:
        // - handler (MedicationNotificationSelectionHandler?): Selection handler registered by the
        //   application.
        // Returns:
        // - No value; the callback completes after its recorded side effects.
        notificationSelectionRegistrar: (handler) {
          selectionHandler = handler;
        },
        // Function Name: viewModelFactory callback
        // Description:
        // - Build a view model using local settings and injected schedule/alarm/notification fixtures.
        // Parameters:
        // - None.
        // Returns:
        // - A MedBuddyViewModel isolated from real notification plugins.
        viewModelFactory: () => MedBuddyViewModel(
          checkSchedule: schedule,
          setNotification: EmptySetNotification(),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: RecordingNotificationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    selectionHandler!(
      MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule,
        slotKey: 'evening',
        notificationId: 29,
        action: MedicationNotificationAction.markSlotTaken,
        scheduleDate: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();

    expect(schedule.updatedSlotKey, 'evening');
    expect(schedule.updatedStatus, isTrue);
    expect(schedule.updatedScheduleDate,
        DateTime.now().toIso8601String().split('T').first);
    expect(find.byType(CheckScheduleUI), findsNothing);

    expect(find.text('실행 취소'), findsNothing);
    schedule.updatedSlotKey = null;
    await tester.tap(find.text('일정 확인'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckScheduleUI), findsOneWidget);
    expect(schedule.updatedSlotKey, isNull);

    // Old, future, and undated reminders may never mutate today's dose.
    for (final date in <DateTime?>[
      DateTime.now().subtract(const Duration(days: 1)),
      DateTime.now().add(const Duration(days: 1)),
      null,
    ]) {
      schedule.updatedSlotKey = null;
      selectionHandler!(MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule,
        slotKey: 'evening',
        notificationId: 29,
        action: MedicationNotificationAction.markSlotTaken,
        scheduleDate: date,
      ));
      await tester.pumpAndSettle();
      expect(schedule.updatedSlotKey, isNull);
    }
  });

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: the notification action snoozes the same dose for ten minutes.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('the notification action snoozes the same dose for ten minutes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final notifications = RecordingNotificationService();
    MedicationNotificationSelectionHandler? selectionHandler;

    await tester.pumpWidget(
      MedBuddyApp(
        // Function Name: notificationSelectionRegistrar callback
        // Description:
        // - Capture the registered selection handler for synthetic notification taps.
        // Parameters:
        // - handler (MedicationNotificationSelectionHandler?): Selection handler registered by the
        //   application.
        // Returns:
        // - No value; the callback completes after its recorded side effects.
        notificationSelectionRegistrar: (handler) {
          selectionHandler = handler;
        },
        // Function Name: viewModelFactory callback
        // Description:
        // - Build a view model using local settings and injected schedule/alarm/notification fixtures.
        // Parameters:
        // - None.
        // Returns:
        // - A MedBuddyViewModel isolated from real notification plugins.
        viewModelFactory: () => MedBuddyViewModel(
          checkSchedule: _EmptyCheckSchedule(),
          setNotification: EmptySetNotification(),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: notifications,
        ),
      ),
    );
    await tester.pumpAndSettle();

    selectionHandler!(
      MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule,
        slotKey: 'bedtime',
        notificationId: 31,
        action: MedicationNotificationAction.snoozeTenMinutes,
        scheduleDate: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();

    expect(notifications.snoozes.single.id, 31);
    expect(notifications.snoozes.single.slotKey, 'bedtime');
    expect(notifications.snoozes.single.slotTitle, '취침 전');
    expect(notifications.snoozes.single.delay, const Duration(minutes: 10));
    expect(notifications.snoozes.single.scheduleDate?.toIso8601String().split('T').first,
        DateTime.now().toIso8601String().split('T').first);

    // A delayed or legacy action cannot reschedule a different day's dose.
    for (final date in <DateTime?>[
      DateTime.now().subtract(const Duration(days: 1)),
      DateTime.now().add(const Duration(days: 1)),
      null,
    ]) {
      notifications.snoozes.clear();
      selectionHandler!(MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule,
        slotKey: 'bedtime',
        notificationId: 31,
        action: MedicationNotificationAction.snoozeTenMinutes,
        scheduleDate: date,
      ));
      await tester.pumpAndSettle();
      expect(notifications.snoozes, isEmpty);
    }
  });

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: sign-out cancels local medication reminders first.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('sign-out cancels local medication reminders first', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final events = <String>[];
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MedBuddyApp(
        authenticationControl: authenticationControl,
        // Function Name: sessionReminderCleanup callback
        // Description:
        // - Append reminder cancellation to the session event log before provider sign-out.
        // Parameters:
        // - None.
        // Returns:
        // - Future<void>; records reminder cleanup.
        sessionReminderCleanup: () async {
          events.add('reminders-canceled');
        },
        // Function Name: viewModelFactory callback
        // Description:
        // - Build a view model using local settings and injected schedule/alarm/notification fixtures.
        // Parameters:
        // - None.
        // Returns:
        // - A MedBuddyViewModel isolated from real notification plugins.
        viewModelFactory: () => MedBuddyViewModel(
          checkSchedule: _EmptyCheckSchedule(),
          setNotification: EmptySetNotification(),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: RecordingNotificationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Function Name: signOutForTest callback
    // Description:
    // - Append provider sign-out after reminder cleanup to verify the session teardown order.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; records provider sign-out.
    await authenticationControl.signOutForTest(() async {
      events.add('provider-sign-out');
    });

    // 세션이 끝난 뒤에도 한 번 더 취소한다(서버가 끊은 세션과 같은 경로).
    expect(events, [
      'reminders-canceled',
      'provider-sign-out',
      'reminders-canceled',
    ]);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: when the server ended the session, the sign-out preparation stops at its
  //   first step (the push token cannot be unregistered with the rejected credential), yet the
  //   ended account's local medication reminders are still canceled once the session is cleared.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('a session ended by the server cancels local medication reminders', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final events = <String>[];
    var cleanupCalls = 0;
    final authenticationControl = AuthenticationControl.development();
    addTearDown(authenticationControl.dispose);

    await tester.pumpWidget(
      MedBuddyApp(
        authenticationControl: authenticationControl,
        // Function Name: sessionReminderCleanup callback
        // Description:
        // - Fails on the first call, standing in for a preparation that could not finish, and
        //   records reminder cancellation afterwards.
        // Parameters:
        // - None.
        // Returns:
        // - Future<void>; records reminder cleanup or throws on the first call.
        sessionReminderCleanup: () async {
          cleanupCalls += 1;
          if (cleanupCalls == 1) {
            events.add('preparation-failed');
            throw StateError('The device push token could not be unregistered.');
          }
          events.add('reminders-canceled');
        },
        // Function Name: viewModelFactory callback
        // Description:
        // - Build a view model using local settings and injected schedule/alarm/notification fixtures.
        // Parameters:
        // - None.
        // Returns:
        // - A MedBuddyViewModel isolated from real notification plugins.
        viewModelFactory: () => MedBuddyViewModel(
          checkSchedule: _EmptyCheckSchedule(),
          setNotification: EmptySetNotification(),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: RecordingNotificationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(events, isEmpty);

    // Function Name: invalidateUnauthorizedSessionForTest callback
    // Description:
    // - Append provider sign-out, which runs after the session was cleared.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; records provider sign-out.
    await authenticationControl.invalidateUnauthorizedSessionForTest(() async {
      events.add('provider-sign-out');
    });
    await tester.pumpAndSettle();

    expect(events, [
      'preparation-failed',
      'reminders-canceled',
      'provider-sign-out',
    ]);
  });
}
