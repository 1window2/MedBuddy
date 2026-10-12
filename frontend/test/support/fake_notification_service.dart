// File Name: fake_notification_service.dart
// Role: Shared recording substitute for NotificationService, so a change to the notification
//   interface is made in one test double instead of in a full copy per test file.
//
// Records: every call to the 17 instance members of NotificationService, in call order, with the
//   arguments it received (reminder registrations, cancellations, snoozes, shown alerts, the
//   history account and the privacy flag).
// Does not simulate: the platform plugin, scheduling, the per-date notification ids, the
//   notification inbox, the serialisation of reminder writes, or the privacy-neutral text chosen
//   by setShowSensitiveDetails (alert bodies are recorded exactly as passed). A cancellation does
//   not remove an earlier entry from `registrations`. The static members of NotificationService
//   (payload parsing and the selection handler) are not replaced; tests keep using the real ones.

import 'package:medbuddy_frontend/entities/caregiver_alert_context_entity.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';

// One registerNotification call.
typedef RecordedReminderRegistration = ({
  int id,
  String slotKey,
  String slotTitle,
  int hour,
  int minute,
  List<String> medicationNames,
  List<DateTime> activeDates,
  Map<String, List<String>> medicationNamesByDate,
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
class RecordingNotificationService implements NotificationService {
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

  // Function Name: registeredMedicationNames
  // Description: Lists the medication names passed with every registration attempt.
  // Parameters: None. Returns: One name list per attempt, oldest first.
  List<List<String>> get registeredMedicationNames => [
    for (final r in registrations) r.medicationNames,
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
    exactRemindersAllowed = exactPermissionAfterRequest ?? exactRemindersAllowed;
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
  // Description: Records a reminder registration, then fails when failRegistration is set.
  // Parameters: Same as NotificationService.registerNotification; lists and maps are copied.
  // Returns: Completion, or StateError when failRegistration is true.
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
  }) async {
    registrations.add((
      id: id,
      slotKey: slotKey,
      slotTitle: slotTitle,
      hour: hour,
      minute: minute,
      medicationNames: List.of(medicationNames),
      activeDates: List.of(activeDates),
      medicationNamesByDate: {
        for (final entry in medicationNamesByDate.entries)
          entry.key: List.of(entry.value),
      },
      language: language,
    ));
    if (failRegistration) {
      throw StateError('Simulated local notification failure.');
    }
  }

  // Function Name: snoozeMedicationReminder
  // Description: Records a snooze request, then fails when failSnooze is set.
  // Parameters: Same as NotificationService.snoozeMedicationReminder.
  // Returns: Completion, or StateError when failSnooze is true.
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
  // Description: Records a caregiver alert exactly as passed instead of displaying it.
  // Parameters: Same as NotificationService.showCaregiverAlert. Returns: Completion.
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
  // Description: Records a linked-chat alert exactly as passed instead of displaying it.
  // Parameters: Same as NotificationService.showLinkedChatAlert. Returns: Completion.
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
