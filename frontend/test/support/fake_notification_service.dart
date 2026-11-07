// File Name: fake_notification_service.dart
// Role: Shared recording substitute for NotificationService, so a change to the notification
//   interface is made in one test double instead of in a full copy per test file.
//
// Records: reminder registrations, cancellations, snoozes, selected alert fields, language changes,
//   history-account changes and permission/session counters in per-operation call order.
//   Optional grouping metadata and onlyAlertOnce are accepted but not recorded.
// Does not simulate: the platform plugin, scheduling, the per-date notification ids, the
//   notification inbox, the serialisation of reminder writes, or the privacy-neutral text chosen
//   by setShowSensitiveDetails (alert bodies are recorded exactly as passed). A cancellation does
//   not remove an earlier entry from `registrations`. The static members of NotificationService
//   (payload parsing and the selection handler) are not replaced; tests keep using the real ones.

import 'package:medbuddy_frontend/entities/caregiver_alert_context_entity.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/services/slot_check_notification_context.dart';

// One registerNotification call.
typedef RecordedReminderRegistration = ({
  int id,
  String slotKey,
  String slotTitle,
  int hour,
  int minute,
  List<DateTime> activeDates,
  String language,
});

// One cancelReminder call.
typedef RecordedReminderCancellation = ({int id, String? slotKey});

// One cancelReminderForDate call.
typedef RecordedDateCancellation = ({
  String owner,
  String slotKey,
  DateTime date,
});

// One snoozeMedicationReminder call.
typedef RecordedSnooze = ({
  int id,
  String slotKey,
  String slotTitle,
  String language,
  Duration delay,
  DateTime? scheduleDate,
});

// One showCaregiverAlert call.
typedef RecordedCaregiverAlert = ({
  int id,
  String title,
  String body,
  String? patientHash,
  String language,
  String? historyUserHash,
  bool recordHistory,
  CaregiverAlertContext? alertContext,
});

// One showLinkedChatAlert call.
typedef RecordedLinkedChatAlert = ({
  int id,
  int linkId,
  String language,
  String? messagePreview,
  String? messageKind,
  String? slotKey,
  String? historyUserHash,
  bool recordHistory,
});

// One setHistoryUser call.
typedef RecordedHistoryUser = ({String? userHash, bool persistSession});

// Class Name: RecordingNotificationService
// Role: Notification-platform substitute that accepts every call and records its arguments.
// Responsibilities:
// - Satisfy the NotificationService interface without touching the notification plugin, the
//   settings channel or SharedPreferences.
// - Keep each call in a list so a test can assert what was registered, cancelled, snoozed or shown.
// - Fail reminder registration or snoozing on request, after recording the attempt.
// Attributes:
// - failRegistration (bool): When true, registerNotification records the call and then throws
//   StateError.
// - failSnooze (bool): When true, snoozeMedicationReminder records the call and then throws
//   StateError.
// - permissionGranted (bool): Result returned by requestPermission.
// - registrations, cancellations, dateCancellations, snoozes, caregiverAlerts, linkedChatAlerts,
//   historyUsers (List): Recorded calls, oldest first.
// - showSensitiveDetails (bool?): Last value passed to setShowSensitiveDetails; null before any
//   call.
// - initializeCount, permissionRequestCount, systemSettingsOpenCount,
//   cancelAllMedicationRemindersCount, cancelAllScheduledMedicationRemindersCount (int): Call
//   counters.
// - slotCheckAlerts (List of records): Slot-check context and presentation flags.
// - languages (List<String>): Requested language changes in order.
// - exactRemindersAllowed (bool), exactPermissionAfterRequest (bool?): Current and next permission results.
// - exactPermissionRequestCount, exactRescheduleCount (int): Exact-alarm request counters.
class RecordingNotificationService implements NotificationService {
  final List<
    ({
      SlotCheckNotificationContext request,
      int id,
      String language,
      String? messagePreview,
      bool recordHistory,
      bool withTakenAction,
    })
  >
  slotCheckAlerts = [];

  // Function Name: showSlotCheckAlert
  // Description:
  // - Records the slot-check request and taken-action flag without displaying a notification.
  // Parameters:
  // - request (SlotCheckNotificationContext): Patient and dose context.
  // - id (int): Notification identifier.
  // - language (String): Requested locale.
  // - messagePreview (String?): Optional body preview.
  // - recordHistory (bool): Requested inbox flag, recorded only.
  // - withTakenAction (bool): Whether a taken action was requested.
  // Returns:
  // - Future<void>: Completes after appending the call record.
  @override
  Future<void> showSlotCheckAlert({
    required SlotCheckNotificationContext request,
    required int id,
    required String language,
    String? messagePreview,
    bool recordHistory = false,
    bool withTakenAction = true,
  }) async {
    slotCheckAlerts.add((
      request: request,
      id: id,
      language: language,
      messagePreview: messagePreview,
      recordHistory: recordHistory,
      withTakenAction: withTakenAction,
    ));
  }

  // Function Name: RecordingNotificationService
  // Description: Creates a fake that succeeds unless a failure switch is set.
  // Parameters: failRegistration, failSnooze, permissionGranted - see the class attributes.
  // Returns: The recording fake with empty call lists.
  RecordingNotificationService({
    this.failRegistration = false,
    this.failSnooze = false,
    this.permissionGranted = true,
  });

  bool failRegistration;
  bool failSnooze;
  bool permissionGranted;

  final List<RecordedReminderRegistration> registrations = [];
  final List<RecordedReminderCancellation> cancellations = [];
  final List<RecordedDateCancellation> dateCancellations = [];
  final List<RecordedSnooze> snoozes = [];
  final List<RecordedCaregiverAlert> caregiverAlerts = [];
  final List<RecordedLinkedChatAlert> linkedChatAlerts = [];
  final List<RecordedHistoryUser> historyUsers = [];
  bool? showSensitiveDetails;
  final List<String> languages = [];

  // 함수이름: updateLanguage
  // 함수역할:
  // - 플랫폼 언어를 바꾸지 않고 전달된 언어를 호출 순서대로 기록한다.
  // 매개변수:
  // - language (String): 요청한 알림 언어.
  // 반환값:
  // - Future<void>: languages 목록에 추가한 뒤 완료한다.
  @override
  Future<void> updateLanguage(String language) async {
    languages.add(language);
  }

  // Result of canScheduleExactReminders; requestExactReminderPermission sets it to
  // exactPermissionAfterRequest when that is not null.
  bool exactRemindersAllowed = true;
  bool? exactPermissionAfterRequest;
  int exactPermissionRequestCount = 0;
  int exactRescheduleCount = 0;
  int initializeCount = 0;
  int permissionRequestCount = 0;
  int systemSettingsOpenCount = 0;
  int cancelAllMedicationRemindersCount = 0;
  int cancelAllScheduledMedicationRemindersCount = 0;

  // Function Name: registeredIds
  // Description: Lists the notification id of every registration attempt, oldest first.
  // Parameters: None. Returns: The ids, including attempts that failRegistration rejected.
  List<int> get registeredIds => [for (final r in registrations) r.id];

  // Function Name: registeredSlotKeys
  // Description: Lists the slot key of every registration attempt, oldest first.
  // Parameters: None. Returns: The slot keys, including attempts that failRegistration rejected.
  List<String> get registeredSlotKeys => [
    for (final r in registrations) r.slotKey,
  ];

  // Function Name: registeredActiveDates
  // Description: Lists the active dates passed with every registration attempt.
  // Parameters: None. Returns: One date list per attempt, oldest first.
  List<List<DateTime>> get registeredActiveDates => [
    for (final r in registrations) r.activeDates,
  ];

  // Function Name: canceledIds
  // Description: Lists the id of every cancelReminder call, oldest first.
  // Parameters: None. Returns: The cancelled ids; cancelReminderForDate calls are not included.
  List<int> get canceledIds => [for (final c in cancellations) c.id];

  // Function Name: canceledAllMedicationReminders
  // Description: Reports whether either session-wide cancellation ran.
  // Parameters: None.
  // Returns: True after cancelAllMedicationReminders or cancelAllScheduledMedicationReminders.
  bool get canceledAllMedicationReminders =>
      cancelAllMedicationRemindersCount > 0 ||
      cancelAllScheduledMedicationRemindersCount > 0;

  // Function Name: setHistoryUser
  // Description: Records the inbox account without writing the session to SharedPreferences.
  // Parameters: userHash - account or null; persistSession - flag passed by the caller.
  // Returns: None.
  @override
  void setHistoryUser(String? userHash, {bool persistSession = true}) {
    historyUsers.add((userHash: userHash, persistSession: persistSession));
  }

  // Function Name: setShowSensitiveDetails
  // Description: Remembers the privacy flag; recorded alert bodies are not rewritten by it.
  // Parameters: showSensitiveDetails - value passed by the caller. Returns: None.
  @override
  void setShowSensitiveDetails(bool showSensitiveDetails) {
    this.showSensitiveDetails = showSensitiveDetails;
  }

  // Function Name: forgetArmedRemindersForTest
  // Description: Nothing to forget; the fake keeps no reservations.
  // Parameters: None. Returns: None.
  @override
  void forgetArmedRemindersForTest() {}

  // Function Name: canScheduleExactReminders
  // Description: Reports the configured exact-alarm state without asking the platform.
  // Parameters: None. Returns: exactRemindersAllowed.
  @override
  Future<bool> canScheduleExactReminders() async => exactRemindersAllowed;

  // Function Name: requestExactReminderPermission
  // Description: Counts the request instead of opening the system screen, then applies
  //   exactPermissionAfterRequest as the user's answer when a test set it.
  // Parameters: None. Returns: The exact-alarm state after the request.
  @override
  Future<bool> requestExactReminderPermission() async {
    exactPermissionRequestCount++;
    exactRemindersAllowed =
        exactPermissionAfterRequest ?? exactRemindersAllowed;
    return exactRemindersAllowed;
  }

  // Function Name: rescheduleInexactRemindersAsExact
  // Description: Counts the request; no reminder is rescheduled.
  // Parameters: None. Returns: Completion.
  @override
  Future<void> rescheduleInexactRemindersAsExact() async {
    exactRescheduleCount++;
  }

  // Function Name: openSystemNotificationSettings
  // Description: Counts the request instead of opening the device settings.
  // Parameters: None. Returns: Completion without a platform call.
  @override
  Future<void> openSystemNotificationSettings() async {
    systemSettingsOpenCount++;
  }

  // Function Name: initialize
  // Description: Counts the request instead of initialising the plugin and the time zone.
  // Parameters: None. Returns: Completion without a platform call.
  @override
  Future<void> initialize() async {
    initializeCount++;
  }

  // Function Name: requestPermission
  // Description: Counts the request and answers with the configured permission result.
  // Parameters: None. Returns: permissionGranted, without an OS prompt.
  @override
  Future<bool> requestPermission() async {
    permissionRequestCount++;
    return permissionGranted;
  }

  // Function Name: registerNotification
  // Description:
  // - Copies a registration into the call log, then throws StateError when failRegistration is enabled.
  // Parameters:
  // - id (int): Notification identifier.
  // - slotKey, slotTitle (String): Dose slot and display label.
  // - hour, minute (int): Requested reminder time.
  // - activeDates (List<DateTime>): Dates copied into the record.
  // - language (String): Requested locale; defaults to ko.
  // Returns:
  // - Future<void>: Recorded attempt, or the configured registration failure.
  @override
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<DateTime> activeDates,
    String language = 'ko',
  }) async {
    registrations.add((
      id: id,
      slotKey: slotKey,
      slotTitle: slotTitle,
      hour: hour,
      minute: minute,
      activeDates: List.of(activeDates),
      language: language,
    ));
    if (failRegistration) {
      throw StateError('Simulated local notification failure.');
    }
  }

  // Function Name: snoozeMedicationReminder
  // Description:
  // - Records a snooze request before applying the failSnooze switch.
  // Parameters:
  // - id (int): Notification identifier.
  // - slotKey, slotTitle (String): Dose slot and label.
  // - language (String): Requested locale.
  // - delay (Duration): Requested delay; defaults to ten minutes.
  // - scheduleDate (DateTime?): Optional dose day.
  // Returns:
  // - Future<void>: Recorded request, or StateError when failSnooze is enabled.
  @override
  Future<void> snoozeMedicationReminder({
    required int id,
    required String slotKey,
    required String slotTitle,
    String language = 'ko',
    Duration delay = const Duration(minutes: 10),
    DateTime? scheduleDate,
  }) async {
    snoozes.add((
      id: id,
      slotKey: slotKey,
      slotTitle: slotTitle,
      language: language,
      delay: delay,
      scheduleDate: scheduleDate,
    ));
    if (failSnooze) {
      throw StateError('Simulated local notification failure.');
    }
  }

  // Function Name: cancelReminder
  // Description: Records the cancelled id and slot; earlier registrations stay in `registrations`.
  // Parameters: id - reminder id; slotKey - optional dose slot. Returns: Completion.
  @override
  Future<void> cancelReminder(int id, {String? slotKey}) async {
    cancellations.add((id: id, slotKey: slotKey));
  }

  // Function Name: cancelReminderForDate
  // Description: Records a per-day cancellation without deriving the dated notification id.
  // Parameters: owner - account; slotKey - dose slot; date - dose day. Returns: Completion.
  @override
  Future<void> cancelReminderForDate({
    required String owner,
    required String slotKey,
    required DateTime date,
  }) async {
    dateCancellations.add((owner: owner, slotKey: slotKey, date: date));
  }

  // Function Name: cancelAllMedicationReminders
  // Description: Counts a session-wide cancellation of medication, caregiver and chat alerts.
  // Parameters: None. Returns: Completion.
  @override
  Future<void> cancelAllMedicationReminders() async {
    cancelAllMedicationRemindersCount++;
  }

  // Function Name: cancelAllScheduledMedicationReminders
  // Description: Counts a cancellation of the scheduled medication reminders only.
  // Parameters: None. Returns: Completion.
  @override
  Future<void> cancelAllScheduledMedicationReminders() async {
    cancelAllScheduledMedicationRemindersCount++;
  }

  // Function Name: showCaregiverAlert
  // Description:
  // - Records caregiver alert content and scope without displaying it; onlyAlertOnce is accepted but not recorded.
  // Parameters:
  // - id (int): Alert identifier.
  // - title, body (String): Unmodified alert text.
  // - patientHash (String?): Optional patient scope.
  // - language (String): Requested locale.
  // - historyUserHash (String?): Optional inbox owner.
  // - recordHistory (bool): Requested history flag; no inbox is written.
  // - alertContext (CaregiverAlertContext?): Optional dose-action context.
  // - onlyAlertOnce (bool): Ignored platform-alert suppression flag.
  // Returns:
  // - Future<void>: Completes after appending the recorded alert.
  @override
  Future<void> showCaregiverAlert({
    required int id,
    required String title,
    required String body,
    String? patientHash,
    String language = 'ko',
    String? historyUserHash,
    bool recordHistory = true,
    CaregiverAlertContext? alertContext,
    bool onlyAlertOnce = false,
  }) async {
    caregiverAlerts.add((
      id: id,
      title: title,
      body: body,
      patientHash: patientHash,
      language: language,
      historyUserHash: historyUserHash,
      recordHistory: recordHistory,
      alertContext: alertContext,
    ));
  }

  // Function Name: showLinkedChatAlert
  // Description:
  // - Records chat alert fields without displaying an alert or simulating grouped summaries.
  // Parameters:
  // - id, linkId (int): Alert and conversation identifiers.
  // - language (String): Requested locale.
  // - messagePreview, messageKind, slotKey (String?): Optional preview, message type and dose slot.
  // - historyUserHash (String?): Optional inbox owner.
  // - recordHistory (bool): Requested history flag; no inbox is written.
  // - summary (ChatNotificationSummary?): Accepted but ignored grouping metadata.
  // Returns:
  // - Future<void>: Completes after appending the recorded alert.
  @override
  Future<void> showLinkedChatAlert({
    required int id,
    required int linkId,
    String language = 'ko',
    String? messagePreview,
    String? messageKind,
    String? slotKey,
    String? historyUserHash,
    bool recordHistory = true,
    ChatNotificationSummary? summary,
  }) async {
    linkedChatAlerts.add((
      id: id,
      linkId: linkId,
      language: language,
      messagePreview: messagePreview,
      messageKind: messageKind,
      slotKey: slotKey,
      historyUserHash: historyUserHash,
      recordHistory: recordHistory,
    ));
  }
}
