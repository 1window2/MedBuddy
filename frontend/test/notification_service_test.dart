// File Name: notification_service_test.dart
// Role: Regression coverage for notification routing, cold starts, dose actions, and sign-out cleanup.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';
import 'package:medbuddy_frontend/controls/manage_user_setting_control.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/main.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

// Class Name: _RecordingCheckSchedule
// Role: Schedule spy for checking the slot and status sent by a notification action.
// Responsibilities:
// - Record the requested dose slot and completion status without modifying backend data.
class _RecordingCheckSchedule extends _EmptyCheckSchedule {
  String? updatedSlotKey;
  bool? updatedStatus;

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
    bool medicationStatus,
  ) async {
    updatedSlotKey = slotKey;
    updatedStatus = medicationStatus;
    return const [];
  }
}

// Class Name: _EmptySetNotification
// Role: Empty alarm fixture for notification-routing tests.
// Responsibilities:
// - Avoid platform synchronization by returning no stored alarm settings.
class _EmptySetNotification extends SetNotification {
  // Function Name: requestMedicationAlarm
  // Description:
  // - Avoid platform synchronization by returning no stored alarm settings.
  // Parameters:
  // - None.
  // Returns:
  // - An empty alarm list.
  @override
  Future<List<MedicationAlarm>> requestMedicationAlarm() async {
    return const [];
  }
}

// Class Name: _NoopNotificationService
// Role: Inert notification-platform implementation for routing and session tests.
// Responsibilities:
// - Skip real notification-plugin initialization while satisfying the platform interface.
// - Grant notification permission in the fake without invoking an OS permission prompt.
// - Accept reminder registration without creating a real device notification.
class _NoopNotificationService implements NotificationService {
  // 함수이름: setShowSensitiveDetails
  // 함수역할:
  // - 플랫폼 알림을 표시하지 않는 대역이므로 잠금 화면 상세정보 설정을 외부에 적용하지 않는다.
  // 매개변수:
  // - showSensitiveDetails (bool): 잠금 화면 알림에 민감 상세정보를 표시할지 여부. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 없음; 플랫폼 상태를 변경하지 않는다.
  @override
  void setShowSensitiveDetails(bool showSensitiveDetails) {}

  // 함수이름: openSystemNotificationSettings
  // 함수역할:
  // - 기기의 설정 앱을 열지 않고 시스템 알림 설정 이동을 성공 처리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> openSystemNotificationSettings() async {}

  // 함수이름: cancelAllScheduledMedicationReminders
  // 함수역할:
  // - 실제 기기 알림을 건드리지 않고 예약 복약 알림 정리를 성공 처리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> cancelAllScheduledMedicationReminders() async {}

  // Function Name: initialize
  // Description:
  // - Skip real notification-plugin initialization while satisfying the platform interface.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> initialize() async {}

  // Function Name: requestPermission
  // Description:
  // - Grant notification permission in the fake without invoking an OS permission prompt.
  // Parameters:
  // - None.
  // Returns:
  // - Future<bool> resolving to true.
  @override
  Future<bool> requestPermission() async => true;

  // Function Name: registerNotification
  // Description:
  // - Accept reminder registration without creating a real device notification.
  // Parameters:
  // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
  //   consumed by this fixture.
  // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime. Accepted but not consumed
  //   by this fixture.
  // - slotTitle (String): Localized user-visible name of the dose slot. Accepted but not consumed by
  //   this fixture.
  // - hour (int): Selected local alarm hour in 24-hour time. Accepted but not consumed by this fixture.
  // - minute (int): Selected minute component of the local alarm time. Accepted but not consumed by this
  //   fixture.
  // - medicationNames (List<String>): Medication names eligible for this reminder. Accepted but not
  //   consumed by this fixture.
  // - activeDates (List<DateTime>): Dates on which this dose is active. Accepted but not consumed by
  //   this fixture.
  // - medicationNamesByDate (Map<String, List<String>>): Medication names active on each scheduled date.
  //   Accepted but not consumed by this fixture.
  // - language (String): Language code used for labels or notification content. Accepted but not
  //   consumed by this fixture.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<String> medicationNames,
    required List<DateTime> activeDates,
    Map<String, List<String>> medicationNamesByDate = const {},
    String language = 'ko',
  }) async {}

  // 함수이름: cancelReminder
  // 함수역할:
  // - 기기 예약을 변경하지 않고 개별 복약 알림 취소를 성공 처리한다.
  // 매개변수:
  // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - slotKey (String?): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> cancelReminder(int id, {String? slotKey}) async {}

  // Function Name: cancelAllMedicationReminders
  // Description:
  // - Acknowledge session reminder cleanup without calling the platform plugin.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> cancelAllMedicationReminders() async {}

  // Function Name: snoozeMedicationReminder
  // Description:
  // - Accept the snooze action without scheduling a real delayed notification.
  // Parameters:
  // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
  //   consumed by this fixture.
  // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime. Accepted but not consumed
  //   by this fixture.
  // - slotTitle (String): Localized user-visible name of the dose slot. Accepted but not consumed by
  //   this fixture.
  // - language (String): Language code used for labels or notification content. Accepted but not
  //   consumed by this fixture.
  // - delay (Duration): Requested snooze interval or retry-wait callback. Accepted but not consumed by
  //   this fixture.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> snoozeMedicationReminder({
    required int id,
    required String slotKey,
    required String slotTitle,
    String language = 'ko',
    Duration delay = const Duration(minutes: 10),
  }) async {}

  // 함수이름: showCaregiverAlert
  // 함수역할:
  // - 보호자 알림을 실제로 표시하지 않고 테스트 흐름의 알림 요청을 완료한다.
  // 매개변수:
  // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - title (String): 가로챈 알림의 표시 제목. 이 대역에서는 직접 사용하지 않는다.
  // - body (String): 호출자가 전달한 알림 또는 메시지 본문. 이 대역에서는 직접 사용하지 않는다.
  // - patientHash (String?): 요청 데이터 범위를 제한하는 환자 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - language (String): 화면 문구 또는 알림 내용의 언어 코드. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> showCaregiverAlert({
    required int id,
    required String title,
    required String body,
    String? patientHash,
    String language = 'ko',
  }) async {}

  // 함수이름: showLinkedChatAlert
  // 함수역할:
  // - 복약 대화 알림을 실제로 표시하지 않고 테스트 흐름의 알림 요청을 완료한다.
  // 매개변수:
  // - id (int): 약·메시지·알림 대역의 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - linkId (int): 대화를 구분하는 환자·보호자 연결 식별자. 이 대역에서는 직접 사용하지 않는다.
  // - language (String): 화면 문구 또는 알림 내용의 언어 코드. 이 대역에서는 직접 사용하지 않는다.
  // - messageKind (String?): 일반 텍스트 또는 복약 문맥 메시지 유형. 이 대역에서는 직접 사용하지 않는다.
  // - messagePreview (String?): 알림 인터페이스로 전달하는 선택적 채팅 미리보기. 이 대역에서는 직접 사용하지 않는다.
  // - slotKey (String?): 아침·점심·저녁·취침 전 등을 구분하는 복약 시간대 키. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> showLinkedChatAlert({
    required int id,
    required int linkId,
    String language = 'ko',
    String? messageKind,
    String? messagePreview,
    String? slotKey,
  }) async {}
}

// Class Name: _RecordingNotificationService
// Role: Notification spy that captures the identity, label, and delay of a snoozed dose.
// Responsibilities:
// - Record the snoozed notification ID, dose slot, title, and delay for action assertions.
class _RecordingNotificationService extends _NoopNotificationService {
  int? snoozedId;
  String? snoozedSlotKey;
  String? snoozedSlotTitle;
  Duration? snoozedDelay;

  // Function Name: snoozeMedicationReminder
  // Description:
  // - Record the snoozed notification ID, dose slot, title, and delay for action assertions.
  // Parameters:
  // - id (int): Identifier of the medication, message, or notification fixture.
  // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime.
  // - slotTitle (String): Localized user-visible name of the dose slot.
  // - language (String): Language code used for labels or notification content. Accepted but not
  //   consumed by this fixture.
  // - delay (Duration): Requested snooze interval or retry-wait callback.
  // Returns:
  // - Completion after recording snooze arguments.
  @override
  Future<void> snoozeMedicationReminder({
    required int id,
    required String slotKey,
    required String slotTitle,
    String language = 'ko',
    Duration delay = const Duration(minutes: 10),
  }) async {
    snoozedId = id;
    snoozedSlotKey = slotKey;
    snoozedSlotTitle = slotTitle;
    snoozedDelay = delay;
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
          setNotification: _EmptySetNotification(),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: _NoopNotificationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(selectionHandler, isNotNull);
    selectionHandler!(
      const MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(navigatorKey.currentState?.canPop(), isTrue);
    expect(find.byType(CheckScheduleUI), findsOneWidget);
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
          setNotification: _EmptySetNotification(),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: _NoopNotificationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    selectionHandler!(
      const MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule,
        slotKey: 'evening',
        notificationId: 29,
        action: MedicationNotificationAction.markSlotTaken,
      ),
    );
    await tester.pumpAndSettle();

    expect(schedule.updatedSlotKey, 'evening');
    expect(schedule.updatedStatus, isTrue);
    expect(find.byType(CheckScheduleUI), findsNothing);
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
    final notifications = _RecordingNotificationService();
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
          setNotification: _EmptySetNotification(),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: notifications,
        ),
      ),
    );
    await tester.pumpAndSettle();

    selectionHandler!(
      const MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule,
        slotKey: 'bedtime',
        notificationId: 31,
        action: MedicationNotificationAction.snoozeTenMinutes,
      ),
    );
    await tester.pumpAndSettle();

    expect(notifications.snoozedId, 31);
    expect(notifications.snoozedSlotKey, 'bedtime');
    expect(notifications.snoozedSlotTitle, '취침 전');
    expect(notifications.snoozedDelay, const Duration(minutes: 10));
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
          setNotification: _EmptySetNotification(),
          manageUserSetting: ManageUserSetting(useRemotePersistence: false),
          notificationService: _NoopNotificationService(),
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

    expect(events, ['reminders-canceled', 'provider-sign-out']);
  });
}
