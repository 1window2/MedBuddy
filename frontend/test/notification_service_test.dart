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
import 'package:medbuddy_frontend/entities/patient_hash_entity.dart';
import 'package:medbuddy_frontend/services/auth_config.dart';
import 'package:medbuddy_frontend/services/medication_reminder_action_tag.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_controls.dart';
import 'support/fake_notification_service.dart';

// Class Name: _EmptyCheckSchedule
// Role: Empty schedule fixture for notification-driven navigation.
// Responsibilities: Avoid backend reads while the destination screen loads.
// Attributes: No additional fields.
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
// 클래스명: _AllSlotsCheckSchedule
// 역할: 연속 알림 선택 시 스크롤 이동을 확인할 네 시간대 일정 대역.
// 주요 책임: 아침·점심·저녁·취침 전을 모두 포함한 고정 약 하나를 서버 조회 없이 제공한다.
// 속성: 추가 필드 없음.
class _AllSlotsCheckSchedule extends _EmptyCheckSchedule {
  // 함수이름: requestTodayMedicationSchedule
  // 함수역할: 네 시간대 카드가 모두 만들어지도록 고정 약 하나의 일정을 반환한다.
  // 매개변수: 없음.
  // 반환값: Future<List<MedicationSchedule>>; 네 시간대 키를 가진 테스트 약 한 건.
  @override
  Future<List<MedicationSchedule>> requestTodayMedicationSchedule() async => const [
    MedicationSchedule(
      medicationID: '1', medicationName: '테스트정', intakeTime: '1정',
      medicationTime: 4, scheduleSlotKeys: ['morning', 'lunch', 'evening', 'bedtime'],
    ),
  ];
}

// Class Name: _RecordingCheckSchedule
// Role: Schedule spy for notification-driven dose updates.
// Responsibilities: Capture the requested slot, completion status, and date without writing to the backend.
// Attributes: updatedSlotKey, updatedStatus, updatedScheduleDate store the latest request; initially null.
class _RecordingCheckSchedule extends _EmptyCheckSchedule {
  String? updatedSlotKey;
  bool? updatedStatus;
  String? updatedScheduleDate;

  // Function Name: updateMedicationSlotStatus
  // Description: Records the slot, completion flag, and expected date without validating or persisting the dose.
  // Parameters:
  // - slotKey (String): Slot whose requested update is recorded.
  // - medicationStatus (bool): Requested taken/untaken state.
  // - expectedScheduleDate (String?): Optional date constraint captured without validation.
  // Returns: Future<List<MedicationSchedule>>; an empty replacement schedule.
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
  // Description: Verifies exact-date matching, rejects malformed dates, and prevents undated legacy reminders from matching a dose date.
  // Parameters: None.
  // Returns: void; fails if date parsing or matching accepts an invalid or mismatched date.
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

  // Function Name: notification selection routing test
  // Description: Rejects another account's caregiver actions, opens the schedule for a valid selection, and reuses the same screen for successive slot selections.
  // Parameters: tester (WidgetTester) - renders the app, dispatches selections, and checks navigation state.
  // Returns: Future<void>; fails if an unrelated account opens a route or repeated selections replace the schedule state or stack routes.
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
  // Function Name: successive slot scroll test
  // Description: Verifies that bedtime selection scrolls down and a subsequent morning selection moves back toward the top of the same schedule.
  // Parameters: tester (WidgetTester) - dispatches selections and reads each target card's scroll position.
  // Returns: Future<void>; fails if a target card is missing or the scroll positions do not change as expected.
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
  // Function Name: chat link resolution test
  // Description: Verifies that a chat selection opens LinkedChatEntryUI with the selected link and matching current-user settings before entering a room.
  // Parameters: tester (WidgetTester) - renders the app and inspects the link-resolution screen.
  // Returns: Future<void>; fails if the link or account context is missing or inconsistent.
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

  // Function Name: signed taken-action test
  // Description: Verifies that a signed current-day action records the whole slot without opening the schedule, while stale, future, and undated actions make no update.
  // Parameters: tester (WidgetTester) - dispatches reminder actions and checks recorded updates and subsequent schedule navigation.
  // Returns: Future<void>; fails if the slot/date/status differs or an invalid-date action records a dose.
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
      await _signedSelection(tester, slotKey: 'evening', notificationId: 29, action: MedicationNotificationAction.markSlotTaken),
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

  // Function Name: signed snooze-action test
  // Description: Verifies that a signed current-day action snoozes the same reminder for ten minutes and stale, future, or undated actions schedule nothing.
  // Parameters: tester (WidgetTester) - dispatches reminder actions and inspects captured snooze requests.
  // Returns: Future<void>; fails if the reminder ID, slot, date, delay, or invalid-date behavior differs.
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
      await _signedSelection(tester, slotKey: 'bedtime', notificationId: 31, action: MedicationNotificationAction.snoozeTenMinutes),
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

  // Function Name: sign-out reminder cleanup order test
  // Description: Verifies that explicit sign-out cancels reminders before provider sign-out and repeats local cleanup after the session is cleared.
  // Parameters: tester (WidgetTester) - mounts the app so its session listeners record cleanup.
  // Returns: Future<void>; fails if cleanup and provider sign-out events occur in a different order.
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

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: a schedule notification delivered while the app is still starting, before
  //   the root navigator exists, opens the dose screen once the first frame is built.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('a cold-start schedule notification opens the dose screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final navigatorKey = GlobalKey<NavigatorState>();
    NavigatorState? navigatorAtDelivery;
    var delivered = false;

    await tester.pumpWidget(
      MedBuddyApp(
        navigatorKey: navigatorKey,
        // Function Name: notificationSelectionRegistrar callback
        // Description:
        // - Deliver the launch notification as soon as the application registers its handler.
        // Parameters:
        // - handler (MedicationNotificationSelectionHandler?): Selection handler registered by the
        //   application; null when it is removed.
        // Returns:
        // - No value; the callback completes after delivering the selection once.
        notificationSelectionRegistrar: (handler) {
          if (handler == null || delivered) return;
          delivered = true;
          navigatorAtDelivery = navigatorKey.currentState;
          handler(
            const MedicationNotificationSelection(
              destination: MedicationNotificationDestination.schedule,
              slotKey: 'morning',
            ),
          );
        },
        viewModelFactory: () => MedBuddyViewModel(
          checkSchedule: _EmptyCheckSchedule(),
          setNotification: EmptySetNotification(),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: RecordingNotificationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(delivered, isTrue);
    expect(navigatorAtDelivery, isNull);
    expect(find.byType(CheckScheduleUI), findsOneWidget);
    expect(
      tester.widget<CheckScheduleUI>(find.byType(CheckScheduleUI)).initialSlotKey,
      'morning',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });

  // Android delivers notification actions to the exported launcher activity, which any other
  // app can start with the same action and extras. A quick action without this app's tag, or with
  // a tag issued for another account, opens the schedule and records nothing.
  for (final forged in ['unsigned', 'other-account']) {
    // Function Name: forged taken-action test
    // Description: Verifies that an unsigned action or one signed for another account opens the schedule without recording a dose.
    // Parameters: tester (WidgetTester) - dispatches the forged selection and inspects navigation and the schedule spy.
    // Returns: Future<void>; fails if a dose update occurs or the schedule does not open.
    testWidgets('a $forged taken action records nothing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final schedule = _RecordingCheckSchedule();
      MedicationNotificationSelectionHandler? selectionHandler;
      await tester.pumpWidget(
        MedBuddyApp(
          notificationSelectionRegistrar: (handler) {
            selectionHandler = handler;
          },
          viewModelFactory: () => MedBuddyViewModel(
            checkSchedule: schedule,
            setNotification: EmptySetNotification(),
            manageUserSetting: ManageUserSetting(useRemotePersistence: false),
            notificationService: RecordingNotificationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selection = forged == 'unsigned'
          ? MedicationNotificationSelection(
              destination: MedicationNotificationDestination.schedule,
              slotKey: 'evening',
              notificationId: 29,
              action: MedicationNotificationAction.markSlotTaken,
              scheduleDate: DateTime.now(),
            )
          : await _signedSelection(
              tester,
              slotKey: 'evening',
              notificationId: 29,
              action: MedicationNotificationAction.markSlotTaken,
              owner: 'another-account',
            );

      selectionHandler!(selection);
      await tester.pumpAndSettle();

      expect(schedule.updatedSlotKey, isNull);
      expect(find.byType(CheckScheduleUI), findsOneWidget);
    });
  }

  // Function Name: cold-start taken-action test
  // Description: Delivers a signed action before the root navigator exists and verifies that the deferred action records the slot after startup without opening the schedule.
  // Parameters: tester (WidgetTester) - creates the signed selection and builds the app through its first frames.
  // Returns: Future<void>; fails if delivery is late, the slot is not marked taken, or a schedule screen opens.
  testWidgets('a cold-start taken action records the dose slot', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final coldStartSelection = await _signedSelection(
      tester,
      slotKey: 'evening',
      notificationId: 29,
      action: MedicationNotificationAction.markSlotTaken,
    );
    final navigatorKey = GlobalKey<NavigatorState>();
    final schedule = _RecordingCheckSchedule();
    NavigatorState? navigatorAtDelivery;
    var delivered = false;

    await tester.pumpWidget(
      MedBuddyApp(
        navigatorKey: navigatorKey,
        // Function Name: notificationSelectionRegistrar callback
        // Description:
        // - Deliver the launch notification action as soon as the application registers its handler.
        // Parameters:
        // - handler (MedicationNotificationSelectionHandler?): Selection handler registered by the
        //   application; null when it is removed.
        // Returns:
        // - No value; the callback completes after delivering the selection once.
        notificationSelectionRegistrar: (handler) {
          if (handler == null || delivered) return;
          delivered = true;
          navigatorAtDelivery = navigatorKey.currentState;
          handler(
            coldStartSelection,
          );
        },
        viewModelFactory: () => MedBuddyViewModel(
          checkSchedule: schedule,
          setNotification: EmptySetNotification(),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: RecordingNotificationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(delivered, isTrue);
    expect(navigatorAtDelivery, isNull);
    expect(schedule.updatedSlotKey, 'evening');
    expect(schedule.updatedStatus, isTrue);
    expect(find.byType(CheckScheduleUI), findsNothing);
  });

  for (final action in [
    MedicationNotificationAction.open,
    MedicationNotificationAction.markSlotTaken,
  ]) {
    // Function Name: cold-start account-change test
    // Description: Verifies that a deferred open or taken action is discarded when the account changes before the first frame, leaving navigation and dose records untouched.
    // Parameters: tester (WidgetTester) - builds the app and runs the frame after notification delivery and account replacement.
    // Returns: Future<void>; fails if the old account's notification opens a route or updates the schedule.
    testWidgets(
      'a cold-start ${action.name} notification is dropped after an account change',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final navigatorKey = GlobalKey<NavigatorState>();
        final schedule = _RecordingCheckSchedule();
        final authenticationControl = AuthenticationControl.development();
        addTearDown(authenticationControl.dispose);
        final firstAccount = authenticationControl.session!.userHash;
        var delivered = false;

        await tester.pumpWidget(
          MedBuddyApp(
            navigatorKey: navigatorKey,
            authenticationControl: authenticationControl,
            sessionReminderCleanup: () async {},
            // Function Name: notificationSelectionRegistrar callback
            // Description:
            // - Deliver the launch notification, then sign another account in before the first
            //   frame runs the deferred navigation.
            // Parameters:
            // - handler (MedicationNotificationSelectionHandler?): Selection handler registered by
            //   the application; null when it is removed.
            // Returns:
            // - No value; the callback completes after the selection and the account change.
            notificationSelectionRegistrar: (handler) {
              if (handler == null || delivered) return;
              delivered = true;
              handler(
                MedicationNotificationSelection(
                  destination: MedicationNotificationDestination.schedule,
                  slotKey: 'evening',
                  notificationId: 29,
                  action: action,
                  scheduleDate: DateTime.now(),
                ),
              );
              authenticationControl.establishSessionForTest('another-account');
            },
            viewModelFactory: () => MedBuddyViewModel(
              checkSchedule: schedule,
              setNotification: EmptySetNotification(),
              manageUserSetting: ManageUserSetting(useRemotePersistence: false),
              notificationService: RecordingNotificationService(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(delivered, isTrue);
        expect(authenticationControl.session?.userHash, isNot(firstAccount));
        expect(find.byType(CheckScheduleUI), findsNothing);
        expect(navigatorKey.currentState?.canPop(), isFalse);
        expect(schedule.updatedSlotKey, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 30));
      },
    );
  }
}

// Function Name: _signedSelection
// Description: Signs a current-day schedule payload outside the widget fake clock and builds the corresponding quick-action selection.
// Parameters:
// - tester (WidgetTester): Runs asynchronous signing through runAsync.
// - slotKey (String): Dose slot included in both payload and selection.
// - notificationId (int): Reminder ID included in both payload and selection.
// - action (MedicationNotificationAction): Action to apply to the signed selection.
// - owner (String?): Signing account; defaults to the normalized development user.
// Returns: Future<MedicationNotificationSelection>; current-day selection with the payload and signing result returned by runAsync.
Future<MedicationNotificationSelection> _signedSelection(
  WidgetTester tester, {
  required String slotKey,
  required int notificationId,
  required MedicationNotificationAction action,
  String? owner,
}) async {
  final today = DateTime.now();
  final payload =
      'schedule:$slotKey:$notificationId:${today.toIso8601String().split('T').first}';
  final tag = await tester.runAsync(
    () => MedicationReminderActionTag.sign(
      owner: owner ?? PatientHash.normalizePatientHash(AuthConfig.localUserHash),
      payload: payload,
    ),
  );
  return MedicationNotificationSelection(
    destination: MedicationNotificationDestination.schedule,
    slotKey: slotKey,
    notificationId: notificationId,
    action: action,
    scheduleDate: today,
    signedPayload: payload,
    actionTag: tag,
  );
}
