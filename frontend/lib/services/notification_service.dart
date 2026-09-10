// 파일명: notification_service.dart
// 역할: 복약, 보호자와 채팅 로컬 알림의 초기화, 예약, 표시와 취소를 담당한다.

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../entities/medication_alarm_entity.dart';

// 클래스명: MedicationNotificationDestination
// 역할: 복약 일정·보호자 환자 일정·가족 채팅 알림의 이동 대상을 구분한다.
// 주요 책임:
// - payload 해석과 앱 내 경로 선택에서 동일한 목적지 분류를 사용하게 한다.
enum MedicationNotificationDestination {
  schedule,
  caregiverSchedule,
  linkedChat,
}

// Class Name: MedicationNotificationAction
// Role: Distinguishes opening a reminder, completing its slot, and snoozing for ten minutes.
// Responsibilities:
// - Preserve the selected system-notification action for application dispatch.
enum MedicationNotificationAction { open, markSlotTaken, snoozeTenMinutes }

// Class Name: MedicationNotificationSelection
// Role: Carries a notification destination and its scoped navigation or action arguments.
// Responsibilities:
// - Preserve patient, link, slot, and notification identifiers so navigation and quick actions target the intended record.
// Attributes:
// - destination (MedicationNotificationDestination): Screen destination selected by the notification.
// - patientHash (String?): Ownership hash of the patient targeted by lookup, storage, or alerts.
// - linkId (int?): Link ID targeted by lookup, messaging, or monitoring.
// - slotKey (String?): Medication slot key: morning, lunch, evening, or bedtime.
// - notificationId (int?): Platform notification or server setting identifier.
// - action (MedicationNotificationAction): Selected open, completion, or snooze action.
// - scheduleDate (DateTime?): Original dose day; absent on legacy notifications.
class MedicationNotificationSelection {
  final MedicationNotificationDestination destination;
  final String? patientHash;
  final int? linkId;
  final String? slotKey;
  final int? notificationId;
  final MedicationNotificationAction action;
  final DateTime? scheduleDate;

  // Function Name: MedicationNotificationSelection
  // Description: Captures a parsed notification destination with optional patient, link, slot, and notification identifiers plus the selected action.
  // Parameters:
  // - destination (MedicationNotificationDestination): Screen destination selected by the notification.
  // - patientHash (String?): Ownership hash of the patient targeted by lookup, storage, or alerts.
  // - linkId (int?): Link ID targeted by lookup, messaging, or monitoring.
  // - slotKey (String?): Medication slot key: morning, lunch, evening, or bedtime.
  // - notificationId (int?): Platform notification or server setting identifier.
  // - action (MedicationNotificationAction): Selected open, completion, or snooze action.
  // - scheduleDate (DateTime?): Original dose day, preserved across snoozes.
  // Returns:
  // - MedicationNotificationSelection: the initialized instance.
  const MedicationNotificationSelection({
    required this.destination,
    this.patientHash,
    this.linkId,
    this.slotKey,
    this.notificationId,
    this.action = MedicationNotificationAction.open,
    this.scheduleDate,
  });

  // Function Name: isForDate
  // Description: Rejects undated legacy actions and actions for a different dose day.
  // Parameters: date (DateTime): Current local calendar date.
  // Returns: Whether a quick action belongs to the supplied day.
  bool isForDate(DateTime date) =>
      scheduleDate != null &&
      scheduleDate!.year == date.year &&
      scheduleDate!.month == date.month &&
      scheduleDate!.day == date.day;
}

// 함수이름: MedicationNotificationSelectionHandler
// 함수역할: 해석된 알림 이동 대상과 사용자 액션을 앱 내비게이션 경계에 전달하는 계약이다.
// 매개변수:
// - selection (MedicationNotificationSelection): 해석된 알림 목적지와 액션 인자
// 반환값:
// - 없음.
typedef MedicationNotificationSelectionHandler =
    void Function(MedicationNotificationSelection selection);



// Class Name: NotificationService
// Role: Wraps local notifications for medication, caregiver, and linked-chat workflows.
// Responsibilities:
// - Initialize the Seoul timezone and plugin, request permissions, schedule course-bounded dates, apply privacy settings, dispatch selections, and cancel session-owned alerts.
// Attributes:
// - _showSensitiveDetails (bool): Whether notification bodies may include sensitive details.
class NotificationService {
  // Function Name: NotificationService._
  // Description: Creates the private notification-service instance used by the shared singleton.
  // Parameters:
  // - None.
  // Returns:
  // - NotificationService: the initialized instance.
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  static const String markSlotTakenActionId = 'medbuddy_mark_slot_taken';
  static const String snoozeTenMinutesActionId = 'medbuddy_snooze_10_minutes';
  static MedicationNotificationSelectionHandler? _selectionHandler;
  static MedicationNotificationSelection? _pendingSelection;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _settingsChannel = MethodChannel(
    'com.medbuddy.app/settings',
  );
  bool _isInitialized = false;
  Future<void>? _initializationFuture;
  bool _showSensitiveDetails = true;

  // 함수이름: setShowSensitiveDetails
  // 함수역할: 이후 표시·예약하는 복약·보호자·채팅 알림에 적용할 민감정보 본문 노출 여부를 바꾼다.
  // 매개변수:
  // - showSensitiveDetails (bool): 알림 본문에 민감한 세부 내용을 포함할지 여부
  // 반환값:
  // - 없음.
  void setShowSensitiveDetails(bool showSensitiveDetails) {
    _showSensitiveDetails = showSensitiveDetails;
  }

  // 함수이름: openSystemNotificationSettings
  // 함수역할: 사용자가 MedBuddy의 휴대폰 알림 권한과 잠금 화면 정책을 확인하게 한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> openSystemNotificationSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Notification settings are unavailable.');
    }
    await _settingsChannel.invokeMethod<void>('openNotificationSettings');
  }

  // 함수이름: setNotificationSelectionHandler
  // 함수역할: 알림 선택 수신자를 교체하고 새 수신자가 준비되면 보류된 선택을 한 번 전달한다.
  // 매개변수:
  // - handler (MedicationNotificationSelectionHandler?): 알림 선택 수신자; null이면 등록 해제
  // 반환값:
  // - 없음.
  static void setNotificationSelectionHandler(
    MedicationNotificationSelectionHandler? handler,
  ) {
    _selectionHandler = handler;
    final pendingSelection = _pendingSelection;
    if (handler == null || pendingSelection == null) {
      return;
    }
    _pendingSelection = null;
    handler(pendingSelection);
  }

  // 함수이름: destinationFromPayload
  // 함수역할: 유효한 알림 payload에서 이동 대상만 추출하고 형식 오류는 null로 처리한다.
  // 매개변수:
  // - payload (String?): 시스템 알림 또는 FCM에서 전달한 이동 문자열
  // 반환값:
  // - MedicationNotificationDestination?: 유효한 알림 payload에서 이동 대상만 추출하고 형식 오류는 null로 처리한다.
  static MedicationNotificationDestination? destinationFromPayload(
    String? payload,
  ) {
    return selectionFromPayload(payload)?.destination;
  }

  // Function Name: selectionFromPayload
  // Description: Parses personal schedule actions, encoded caregiver patient hashes, or positive chat link IDs and rejects malformed navigation payloads.
  // Parameters:
  // - payload (String?): Navigation payload from a system notification or FCM.
  // - actionId (String?): System notification button identifier.
  // - notificationId (int?): Platform notification or server setting identifier.
  // Returns:
  // - MedicationNotificationSelection?: Parses personal schedule actions, encoded caregiver patient hashes, or positive chat link IDs and rejects malformed navigation payloads.
  static MedicationNotificationSelection? selectionFromPayload(
    String? payload, {
    String? actionId,
    int? notificationId,
  }) {
    final segments = payload?.split(':') ?? const <String>[];
    if ((segments.length == 3 || segments.length == 4) &&
        segments[0] == 'schedule' &&
        segments[1].trim().isNotEmpty) {
      final notificationID = int.tryParse(segments[2]);
      if (notificationID == null || notificationID < 0) {
        return null;
      }
      DateTime? scheduleDate;
      if (segments.length == 4) {
        final rawDate = segments[3];
        scheduleDate = DateTime.tryParse(rawDate);
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate) ||
            scheduleDate == null ||
            scheduleDate.toIso8601String().split('T').first != rawDate) {
          return null;
        }
      }
      return MedicationNotificationSelection(
        destination: MedicationNotificationDestination.schedule,
        slotKey: segments[1].trim(),
        notificationId: notificationId ?? notificationID,
        scheduleDate: scheduleDate,
        action: switch (actionId) {
          markSlotTakenActionId =>
            MedicationNotificationAction.markSlotTaken,
          snoozeTenMinutesActionId =>
            MedicationNotificationAction.snoozeTenMinutes,
          _ => MedicationNotificationAction.open,
        },
      );
    }
    if (segments.length == 2 &&
        segments[0] == 'caregiver' &&
        segments[1].trim().isNotEmpty) {
      try {
        final patientHash = Uri.decodeComponent(segments[1]).trim();
        if (patientHash.isEmpty) {
          return null;
        }
        return MedicationNotificationSelection(
          destination: MedicationNotificationDestination.caregiverSchedule,
          patientHash: patientHash,
        );
      } on FormatException {
        return null;
      }
    }
    if (segments.length == 2 && segments[0] == 'chat') {
      final linkId = int.tryParse(segments[1]);
      if (linkId == null || linkId < 1) {
        return null;
      }
      return MedicationNotificationSelection(
        destination: MedicationNotificationDestination.linkedChat,
        linkId: linkId,
      );
    }
    return null;
  }

  // Function Name: handleNotificationPayload
  // Description: Dispatches a valid parsed notification selection to the active handler or retains it until a handler is registered.
  // Parameters:
  // - payload (String?): Navigation payload from a system notification or FCM.
  // - actionId (String?): System notification button identifier.
  // - notificationId (int?): Platform notification or server setting identifier.
  // Returns:
  // - No return value.
  static void handleNotificationPayload(
    String? payload, {
    String? actionId,
    int? notificationId,
  }) {
    final selection = selectionFromPayload(
      payload,
      actionId: actionId,
      notificationId: notificationId,
    );
    if (selection == null) {
      return;
    }
    final handler = _selectionHandler;
    if (handler == null) {
      _pendingSelection = selection;
      return;
    }
    handler(selection);
  }

  // 함수이름: isSessionNotificationPayload
  // 함수역할: 복약·보호자·채팅 접두사를 확인해 현재 세션 정리 대상인 MedBuddy 알림인지 판정한다.
  // 매개변수:
  // - payload (String?): 시스템 알림 또는 FCM에서 전달한 이동 문자열
  // 반환값:
  // - bool: 복약·보호자·채팅 접두사를 확인해 현재 세션 정리 대상인 MedBuddy 알림인지 판정한다.
  @visibleForTesting
  static bool isSessionNotificationPayload(String? payload) {
    return payload?.startsWith('schedule:') == true ||
        payload?.startsWith('caregiver:') == true ||
        payload?.startsWith('chat:') == true;
  }

  // Function Name: initialize
  // Description: Reuses the completed or in-flight notification initialization so concurrent callers do not initialize the platform plugin twice.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> initialize() {
    if (_isInitialized) {
      return Future<void>.value();
    }
    return _initializationFuture ??= _initialize();
  }

  // Function Name: _initialize
  // Description: Initializes timezone data and the Seoul local zone, installs the response callback, restores launch selections, and clears the shared future after failure for retry.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _initialize() async {
    try {
      timezone_data.initializeTimeZones();
      timezone.setLocalLocation(timezone.getLocation('Asia/Seoul'));

      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );
      _isInitialized = true;

      if (launchDetails?.didNotificationLaunchApp ?? false) {
        final response = launchDetails?.notificationResponse;
        handleNotificationPayload(
          response?.payload,
          actionId: response?.actionId,
          notificationId: response?.id,
        );
      }
    } catch (_) {
      _initializationFuture = null;
      rethrow;
    }
  }

  // Function Name: _handleNotificationResponse
  // Description: Passes the plugin response payload, action identifier, and notification ID through the shared selection parser.
  // Parameters:
  // - response (NotificationResponse): Platform response identifying the selected notification or action.
  // Returns:
  // - No return value.
  static void _handleNotificationResponse(NotificationResponse response) {
    handleNotificationPayload(
      response.payload,
      actionId: response.actionId,
      notificationId: response.id,
    );
  }

  // Function Name: requestPermission
  // Description: Initializes notifications and requests Android or iOS display permissions, treating other platforms or absent platform implementations as not requiring a request.
  // Parameters:
  // - None.
  // Returns:
  // - Future<bool>: Initializes notifications and requests Android or iOS display permissions, treating other platforms or absent platform implementations as not requiring a request.
  Future<bool> requestPermission() async {
    await initialize();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await androidPlugin?.requestNotificationsPermission() ?? true;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await iosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
    }

    return true;
  }

  // Function Name: registerNotification
  // Description: Replaces dated slot reminders with neutral text and an inexact fallback when exact alarms are unavailable.
  // Parameters:
  // - id (int): Platform identifier used to schedule, replace, or cancel an alert.
  // - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
  // - slotTitle (String): Localized medication slot name.
  // - hour (int): Local hour in 24-hour time.
  // - minute (int): Minute component of local time.
  // - medicationNames (List<String>): Retained for caller compatibility; never used as a live pending-dose claim.
  // - activeDates (List<DateTime>): Reminder dates within the medication course.
  // - medicationNamesByDate (Map<String, List<String>>): Legacy name snapshots, deliberately excluded from reminder text.
  // - language (String): Language code used for display or speech guidance.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
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
    await initialize();
    await _cancelScheduledNotificationsForSlot(slotKey, legacyId: id);
    final now = timezone.TZDateTime.now(timezone.local);
    final uniqueDates = <String, DateTime>{};
    for (final activeDate in activeDates) {
      final normalizedDate = DateTime(
        activeDate.year,
        activeDate.month,
        activeDate.day,
      );
      uniqueDates[_dateKey(normalizedDate)] = normalizedDate;
    }
    final sortedDates = uniqueDates.values.toList(growable: false)..sort();

    for (final activeDate in sortedDates) {
      final body = _buildReminderBody(language);
      final scheduledDate = timezone.TZDateTime(
        timezone.local,
        activeDate.year,
        activeDate.month,
        activeDate.day,
        hour,
        minute,
      );
      if (!scheduledDate.isAfter(now)) {
        continue;
      }
      final notificationId = _notificationIdForDate(id, slotKey, activeDate);
      try {
        await _scheduleWithMode(
          id: notificationId,
          slotKey: slotKey,
          slotTitle: slotTitle,
          language: language,
          body: body,
          scheduledDate: scheduledDate,
          scheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } on PlatformException {
        await _scheduleWithMode(
          id: notificationId,
          slotKey: slotKey,
          slotTitle: slotTitle,
          language: language,
          body: body,
          scheduledDate: scheduledDate,
          scheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }
  }

  // 함수이름: _cancelScheduledNotificationsForSlot
  // 함수역할: 같은 시간대에 남아 있는 기존 반복 알림과 날짜별 단발 알림을 모두 취소한다.
  // 매개변수:
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // - legacyId (int?): 함께 취소할 구형 고정 알림 ID
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _cancelScheduledNotificationsForSlot(
    String slotKey, {
    int? legacyId,
  }) async {
    if (legacyId != null) {
      await _plugin.cancel(id: legacyId);
    }
    final pendingRequests = await _plugin.pendingNotificationRequests();
    final payloadPrefix = 'schedule:$slotKey:';
    for (final request in pendingRequests) {
      if (request.payload?.startsWith(payloadPrefix) ?? false) {
        await _plugin.cancel(id: request.id);
      }
    }
  }

  // 함수이름: _dateKey
  // 함수역할: 알림 날짜별 약명과 안정 ID에 사용할 YYYY-MM-DD 달력 날짜 키를 만든다.
  // 매개변수:
  // - date (DateTime): 달력 날짜 계산 또는 비교의 기준 시각
  // 반환값:
  // - String: 알림 날짜별 약명과 안정 ID에 사용할 YYYY-MM-DD 달력 날짜 키를 만든다.
  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // 함수이름: _notificationIdForDate
  // 함수역할: 시간대와 복용 날짜마다 충돌 가능성이 낮은 고정 알림 ID를 생성한다.
  // 매개변수:
  // - baseId (int): 날짜별 알림 ID 계산에 쓸 기본 ID
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // - date (DateTime): 달력 날짜 계산 또는 비교의 기준 시각
  // 반환값:
  // - int: 시간대와 복용 날짜마다 충돌 가능성이 낮은 고정 알림 ID를 생성한다.
  int _notificationIdForDate(int baseId, String slotKey, DateTime date) {
    final source = '$baseId|$slotKey|${_dateKey(date)}';
    var hash = 0x811C9DC5;
    for (final codeUnit in source.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return 100000 + (hash % 2000000000);
  }

  // 함수이름: _buildReminderBody
  // 함수역할: 예약 후 복용 상태가 바뀌어도 재복용을 지시하지 않는 중립적 안내를 만든다.
  // 매개변수:
  // - language (String): 안내 문장에 사용할 언어 코드
  // 반환값:
  // - 알림 본문 문자열
  String _buildReminderBody(String language) {
    // Android retains this text until delivery. A name snapshot cannot tell us
    // which doses are still pending then, even when sensitive details are on.
    return _isEnglish(language)
        ? 'Check your medication schedule and recorded completion status.'
        : '복약 일정과 복용 완료 기록을 확인해 주세요.';
  }

  // 함수이름: _isEnglish
  // 함수역할: 언어 코드의 공백과 대소문자를 정리한 뒤 en 접두사로 영어 계열을 판정한다.
  // 매개변수:
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - bool: 언어 코드의 공백과 대소문자를 정리한 뒤 en 접두사로 영어 계열을 판정한다.
  bool _isEnglish(String language) {
    return language.trim().toLowerCase().startsWith('en');
  }

  // Function Name: _scheduleWithMode
  // Description: Schedules a localized zoned reminder with the chosen Android precision mode, completion and snooze actions, and a slot-aware navigation payload.
  // Parameters:
  // - id (int): Platform identifier used to schedule, replace, or cancel an alert.
  // - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
  // - slotTitle (String): Localized medication slot name.
  // - language (String): Language code used for display or speech guidance.
  // - body (String): Message or notification body to send or display.
  // - scheduledDate (timezone.TZDateTime): Zoned timestamp at which the notification is scheduled.
  // - scheduleMode (AndroidScheduleMode): Exact or inexact Android scheduling mode.
  // - scheduleDate (DateTime?): Original dose day when rescheduling a snooze.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _scheduleWithMode({
    required int id,
    required String slotKey,
    required String slotTitle,
    required String language,
    required String body,
    required timezone.TZDateTime scheduledDate,
    required AndroidScheduleMode scheduleMode,
    DateTime? scheduleDate,
  }) async {
    final title = _isEnglish(language)
        ? '$slotTitle medication schedule'
        : '$slotTitle 복약 일정 확인';

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'medbuddy_medication_reminders',
          _isEnglish(language) ? 'Medication reminders' : '복약 알림',
          channelDescription: _isEnglish(language)
              ? 'MedBuddy medication time reminders'
              : 'MedBuddy 복약 시간 알림',
          importance: Importance.high,
          priority: Priority.high,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              markSlotTakenActionId,
              _isEnglish(language) ? 'Taken' : '복용했어요',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              snoozeTenMinutesActionId,
              _isEnglish(language) ? 'Remind in 10 min' : '10분 후 다시 알림',
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: scheduleMode,
      payload: 'schedule:$slotKey:$id:${_dateKey(scheduleDate ?? scheduledDate)}',
    );
  }

  // Function Name: snoozeMedicationReminder
  // Description: Reschedules the selected slot after the supplied delay, defaulting to ten minutes, with privacy-neutral text and an inexact-alarm fallback.
  // Parameters:
  // - id (int): Platform identifier used to schedule, replace, or cancel an alert.
  // - slotKey (String): Medication slot key: morning, lunch, evening, or bedtime.
  // - slotTitle (String): Localized medication slot name.
  // - language (String): Language code used for display or speech guidance.
  // - delay (Duration): Delay before displaying the snoozed reminder.
  // - scheduleDate (DateTime?): Original dose day; defaults to today's date.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> snoozeMedicationReminder({
    required int id,
    required String slotKey,
    required String slotTitle,
    String language = 'ko',
    Duration delay = const Duration(minutes: 10),
    DateTime? scheduleDate,
  }) async {
    await initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final scheduledDate = now.add(delay);
    final originalDate = scheduleDate ?? now;
    final body = _buildReminderBody(language);
    try {
      await _scheduleWithMode(
        id: id,
        slotKey: slotKey,
        slotTitle: slotTitle,
        language: language,
        body: body,
        scheduledDate: scheduledDate,
        scheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        scheduleDate: originalDate,
      );
    } on PlatformException {
      await _scheduleWithMode(
        id: id,
        slotKey: slotKey,
        slotTitle: slotTitle,
        language: language,
        body: body,
        scheduledDate: scheduledDate,
        scheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        scheduleDate: originalDate,
      );
    }
  }

  // 함수이름: cancelReminder
  // 함수역할: 지정한 복약 알림 예약을 취소한다.
  // 매개변수:
  // - id (int): 취소할 알림 id
  // - slotKey (String?): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> cancelReminder(int id, {String? slotKey}) async {
    await initialize();
    if (slotKey != null && slotKey.trim().isNotEmpty) {
      await _cancelScheduledNotificationsForSlot(slotKey, legacyId: id);
      return;
    }
    await _plugin.cancel(id: id);
  }

  // Function Name: cancelAllMedicationReminders
  // Description: Cancels pending and displayed session-owned medication, caregiver, and chat notifications plus legacy reminder IDs, while preserving unrelated notifications and clearing pending selections.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> cancelAllMedicationReminders() async {
    await initialize();
    final pendingRequests = await _plugin.pendingNotificationRequests();
    for (final request in pendingRequests) {
      if (isSessionNotificationPayload(request.payload)) {
        await _plugin.cancel(id: request.id);
      }
    }
    final activeNotifications = await _plugin.getActiveNotifications();
    for (final notification in activeNotifications) {
      final notificationId = notification.id;
      if (notificationId != null &&
          isSessionNotificationPayload(notification.payload)) {
        await _plugin.cancel(id: notificationId, tag: notification.tag);
      }
    }
    for (final slotKey in const ['morning', 'lunch', 'evening', 'bedtime']) {
      await _plugin.cancel(
        id: MedicationAlarm.legacyNotificationIdForSlot(slotKey),
      );
    }
    if (_pendingSelection != null) {
      _pendingSelection = null;
    }
  }

  // 함수이름: cancelAllScheduledMedicationReminders
  // 함수역할: 보호자·채팅 알림은 유지하고 사용자의 복약 시간 알림 예약만 취소한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> cancelAllScheduledMedicationReminders() async {
    await initialize();
    final pendingRequests = await _plugin.pendingNotificationRequests();
    for (final request in pendingRequests) {
      if ((request.payload ?? '').startsWith('schedule:')) {
        await _plugin.cancel(id: request.id);
      }
    }
    for (final slotKey in const ['morning', 'lunch', 'evening', 'bedtime']) {
      await _plugin.cancel(
        id: MedicationAlarm.legacyNotificationIdForSlot(slotKey),
      );
    }
  }

  // 함수이름: showCaregiverAlert
  // 함수역할: 환자의 복약 체크 변화를 보호자 기기의 즉시 로컬 알림으로 표시한다.
  // 매개변수:
  // - id (int): 중복 알림을 교체하기 위한 고정 알림 식별자
  // - title (String): 보호자 알림 제목
  // - body (String): 보호자에게 보여줄 복약 상태 설명
  // - patientHash (String?): 알림을 누를 때 열어야 하는 환자 식별 hash
  // - language (String): 알림 채널 안내에 사용할 언어 코드
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> showCaregiverAlert({
    required int id,
    required String title,
    required String body,
    String? patientHash,
    String language = 'ko',
  }) async {
    await initialize();
    final isEnglish = _isEnglish(language);
    final visibleBody = _showSensitiveDetails
        ? body
        : isEnglish
        ? 'A linked patient has a medication update.'
        : '연동된 환자의 복약 상태가 변경되었습니다.';
    await _plugin.show(
      id: id,
      title: title,
      body: visibleBody,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'medbuddy_caregiver_updates',
          isEnglish ? 'Caregiver medication updates' : '보호자 복약 확인',
          channelDescription: isEnglish
              ? 'Medication completion and missed-dose updates for linked patients'
              : '연동된 환자의 복약 완료 및 미복용 상태 알림',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: patientHash == null || patientHash.trim().isEmpty
          ? null
          : 'caregiver:${Uri.encodeComponent(patientHash.trim())}',
    );
  }

  // 함수이름: showLinkedChatAlert
  // 함수역할: 전경에서 받은 가족 채팅 푸시를 제한된 메시지 미리보기와 함께 표시한다.
  // 매개변수:
  // - id (int): 플랫폼 알림의 예약·교체·취소 식별자
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // - messagePreview (String?): 시스템 알림에 표시할 선택적 메시지 미리보기
  // - messageKind (String?): 일반·복약·약국 맥락 메시지 유형
  // - slotKey (String?): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> showLinkedChatAlert({
    required int id,
    required int linkId,
    String language = 'ko',
    String? messagePreview,
    String? messageKind,
    String? slotKey,
  }) async {
    await initialize();
    final isEnglish = _isEnglish(language);
    final normalizedPreview = _linkedChatMessagePreview(messagePreview);
    final fallbackBody = isEnglish
        ? 'You received a new message from a linked family member.'
        : '연동된 가족에게 새 메시지가 도착했습니다.';
    await _plugin.show(
      id: id,
      title: isEnglish ? 'New family message' : '새 가족 메시지',
      body: _showSensitiveDetails && normalizedPreview.isNotEmpty
          ? normalizedPreview
          : fallbackBody,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'medbuddy_linked_chat',
          isEnglish ? 'Family chat' : '가족 채팅',
          channelDescription: isEnglish
              ? 'New chat messages between linked patients and caregivers'
              : '연동된 환자와 보호자의 새 채팅 메시지 알림',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload:
          messageKind == 'slot_check_request' &&
              _isSupportedScheduleSlot(slotKey)
          ? 'schedule:${slotKey!.trim()}:$id'
          : 'chat:$linkId',
    );
  }

  // 함수이름: _isSupportedScheduleSlot
  // 함수역할: 선택적 시간대 문자열을 정규화해 지원하는 네 복약 시간대에 포함되는지 확인한다.
  // 매개변수:
  // - value (String?): 알림 이동에 사용할 수 있는지 검사할 시간대 키
  // 반환값:
  // - bool: 선택적 시간대 문자열을 정규화해 지원하는 네 복약 시간대에 포함되는지 확인한다.
  static bool _isSupportedScheduleSlot(String? value) {
    return const {
      'morning',
      'lunch',
      'evening',
      'bedtime',
    }.contains(value?.trim().toLowerCase());
  }

  // 함수이름: _linkedChatMessagePreview
  // 함수역할: 채팅 알림 본문을 한 줄로 정리하고 시스템 알림에 적합한 길이로 제한한다.
  // 매개변수:
  // - value (String?): 알림 길이에 맞게 공백 정리·축약할 채팅 본문
  // 반환값:
  // - String: 채팅 알림 본문을 한 줄로 정리하고 시스템 알림에 적합한 길이로 제한한다.
  static String _linkedChatMessagePreview(String? value) {
    const maximumLength = 120;
    final normalized = (value ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where(/* 함수이름: where 콜백
         * 함수역할: 알림 본문 조각 중 비어 있지 않은 부분만 결합 대상으로 남긴다.
         * 매개변수:
         * - part (String): 알림 본문에 결합할 문구 조각
         * 반환값:
         * - 본문 조각이 비어 있지 않으면 true.
         */(part) => part.isNotEmpty)
        .join(' ');
    if (normalized.length <= maximumLength) {
      return normalized;
    }
    return '${normalized.substring(0, maximumLength - 1).trimRight()}…';
  }
}
