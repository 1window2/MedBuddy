// File Name: session_drop_route_test.dart
// Role: Regression coverage for ending the session while a provider-reading route is open above the root.

import 'package:flutter/material.dart';
import 'package:medbuddy_frontend/entities/caregiver_alert_context_entity.dart';
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
import 'package:medbuddy_frontend/services/slot_check_notification_context.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Class Name: _EmptyCheckSchedule
// Role: Keep the routed schedule empty in the session-invalidation regression.
// Responsibilities: Avoid backend reads while the provider-backed route is opened and removed.
// Attributes: No additional state; overridden reads ignore inherited client configuration.
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

// Class Name: _EmptySetNotification
// Role: Remove stored alarm dependencies from the route teardown test.
// Responsibilities: Return no alarm settings without invoking persistence or device synchronization.
// Attributes: No additional state.
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
// Role: Satisfy notification dependencies while testing session-driven route removal.
// Responsibilities: Accept display, scheduling and cleanup calls without device effects; report permission as granted.
// Attributes: None; this fake retains no reminders, account history or notification payloads.
class _NoopNotificationService implements NotificationService {
  // Function Name: showSlotCheckAlert
  // Description: Accept a caregiver dose-check notification without showing it or recording history.
  // Parameters: request (SlotCheckNotificationContext) is the action context; id (int), language (String) and messagePreview (String?) describe display; recordHistory and withTakenAction (bool) select persistence/actions. All are ignored by this fake.
  // Returns: Future<void> completing without platform calls.
  @override
  Future<void> showSlotCheckAlert({
    required SlotCheckNotificationContext request,
    required int id,
    required String language,
    String? messagePreview,
    bool recordHistory = false,
    bool withTakenAction = true,
  }) async {}

  // 함수이름: updateLanguage
  // 함수역할: 경로 정리 테스트에서 실제 알림 채널을 변경하지 않고 언어 변경 요청을 받아들인다.
  // 매개변수: language (String)는 요청 언어이며 이 대역에서는 사용하지 않는다.
  // 반환값: 플랫폼 호출 없이 완료되는 Future<void>.
  @override
  Future<void> updateLanguage(String language) async {}

  // Function Name: setHistoryUser
  // Description: Accept account-history configuration without changing stored notification ownership.
  // Parameters: userHash (String?) is the requested owner; persistSession (bool) requests persistence. Both are unused here.
  // Returns: None.
  @override
  void setHistoryUser(String? userHash, {bool persistSession = true}) {}

  // Function Name: setShowSensitiveDetails
  // Description: Ignore lock-screen detail preferences because the route test never displays native notifications.
  // Parameters: showSensitiveDetails (bool) is the requested preview policy.
  // Returns: None; no state is retained.
  @override
  void setShowSensitiveDetails(bool showSensitiveDetails) {}

  // Function Name: forgetArmedRemindersForTest
  // Description: Satisfy reminder-reset calls; this fake has no armed-reminder registry.
  // Parameters: None.
  // Returns: None.
  @override
  void forgetArmedRemindersForTest() {}

  // Function Name: canScheduleExactReminders
  // Description: Make exact-alarm capability available without querying the operating system.
  // Parameters: None.
  // Returns: Future<bool> resolving to true.
  @override
  Future<bool> canScheduleExactReminders() async => true;

  // Function Name: requestExactReminderPermission
  // Description: Grant the test's exact-alarm permission request without opening settings.
  // Parameters: None.
  // Returns: Future<bool> resolving to true.
  @override
  Future<bool> requestExactReminderPermission() async => true;

  // Function Name: rescheduleInexactRemindersAsExact
  // Description: Acknowledge alarm upgrading without creating or replacing native alarms.
  // Parameters: None.
  // Returns: Future<void> completing immediately.
  @override
  Future<void> rescheduleInexactRemindersAsExact() async {}

  // Function Name: openSystemNotificationSettings
  // Description: Keep a requested notification-settings transition inside the test process.
  // Parameters: None.
  // Returns: Future<void> without launching system settings.
  @override
  Future<void> openSystemNotificationSettings() async {}

  // Function Name: cancelAllScheduledMedicationReminders
  // Description: Acknowledge scheduled-reminder cleanup without contacting the notification plugin.
  // Parameters: None.
  // Returns: Future<void>; the fake has no stored schedules to remove.
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
  // - activeDates (List<DateTime>): Dates on which this dose is active. Accepted but not consumed by
  //   this fixture.
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
    required List<DateTime> activeDates,
    String language = 'ko',
  }) async {}

  // Function Name: cancelReminder
  // Description: Accept one reminder's cancellation without touching device schedules.
  // Parameters: id (int) selects the reminder; slotKey (String?) optionally narrows its slot. Both are unused.
  // Returns: Future<void> completing immediately.
  @override
  Future<void> cancelReminder(int id, {String? slotKey}) async {}

  // Function Name: cancelReminderForDate
  // Description: Accept date-scoped reminder cleanup without retaining or canceling platform alarms.
  // Parameters: owner (String), slotKey (String) and date (DateTime) identify the requested dose; all are ignored.
  // Returns: Future<void> completing immediately.
  @override
  Future<void> cancelReminderForDate({
    required String owner,
    required String slotKey,
    required DateTime date,
  }) async {}

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
  // - scheduleDate (DateTime?): Original dose date to preserve when snoozing; accepted but unused by this fake.
  // Returns:
  // - Future<void>; completes without a platform call.
  @override
  Future<void> snoozeMedicationReminder({
    required int id,
    required String slotKey,
    required String slotTitle,
    String language = 'ko',
    Duration delay = const Duration(minutes: 10),
    DateTime? scheduleDate,
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
  // - alertContext (CaregiverAlertContext?): 보호자 조치 맥락, historyUserHash (String?): 이력 소유자, recordHistory (bool): 이력 저장 여부, onlyAlertOnce (bool): 재알림 억제 여부. 이 대역은 모두 무시한다.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> showCaregiverAlert({
    CaregiverAlertContext? alertContext,
    String? historyUserHash,
    bool recordHistory = true,
    bool onlyAlertOnce = false,
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
  // - summary (ChatNotificationSummary?): 묶음 알림 요약, historyUserHash (String?): 이력 소유자, recordHistory (bool): 이력 저장 여부. 이 대역은 모두 무시한다.
  // 반환값:
  // - Future<void>; 플랫폼 호출 없이 완료된다.
  @override
  Future<void> showLinkedChatAlert({
    ChatNotificationSummary? summary,
    String? historyUserHash,
    bool recordHistory = true,
    required int id,
    required int linkId,
    String language = 'ko',
    String? messageKind,
    String? messagePreview,
    String? slotKey,
  }) async {}
}

// 함수이름: main
// 함수역할: 인증 세션이 무효화될 때 루트 위의 복약 일정 경로가 안전하게 정리되는 위젯 회귀 검사를 등록한다.
// 매개변수: 없음.
// 반환값: 없음. 실제 검증은 등록된 테스트에서 수행한다.
void main() {
  // 함수이름: ending the session removes routes above the root without a provider error
  // 함수역할: 알림으로 복약 일정 경로를 연 뒤 세션을 무효화하여 제거된 provider를 참조하는 화면이 남지 않는지 확인한다.
  // 매개변수: tester (WidgetTester)는 화면·알림 이동·세션 무효화 후 프레임을 진행한다.
  // 반환값: Future<void>. Flutter 오류가 없고 루트 위 경로와 일정 화면이 모두 사라져야 한다.
  testWidgets(
    'ending the session removes routes above the root without a provider error',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final navigatorKey = GlobalKey<NavigatorState>();
      MedicationNotificationSelectionHandler? selectionHandler;
      final authenticationControl = AuthenticationControl.development();
      addTearDown(authenticationControl.dispose);
      final errors = <Object>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exception);
      await tester.pumpWidget(
        MedBuddyApp(
          navigatorKey: navigatorKey,
          authenticationControl: authenticationControl,
          sessionReminderCleanup: () async {},
          notificationSelectionRegistrar: (handler) =>
              selectionHandler = handler,
          viewModelFactory: () => MedBuddyViewModel(
            checkSchedule: _EmptyCheckSchedule(),
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
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CheckScheduleUI), findsOneWidget);
      await authenticationControl.invalidateUnauthorizedSessionForTest(
        () async {},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      FlutterError.onError = previous;
      expect(errors, isEmpty);
      expect(navigatorKey.currentState?.canPop(), isFalse);
      expect(find.byType(CheckScheduleUI), findsNothing);
    },
  );
}
