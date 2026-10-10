// 파일명: notification_service.dart
// 역할: 복약, 보호자와 채팅 로컬 알림의 초기화, 예약, 표시와 취소를 담당한다.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../entities/json_value_reader.dart';
import '../entities/medication_alarm_entity.dart';
import '../entities/caregiver_alert_context_entity.dart';
import '../entities/medication_notification_selection_entity.dart';
import '../entities/notification_inbox_entity.dart';
import '../entities/user_setting_entity.dart';
import 'medication_notification_payload_codec.dart';
import 'notification_inbox_store.dart';

// Preserve existing imports while keeping the action contract platform-neutral.
export '../entities/medication_notification_selection_entity.dart';

// Class Name: NotificationService
// Role: Wraps local notifications for medication, caregiver, and linked-chat workflows.
// Responsibilities:
// - Initialize the Seoul timezone and plugin, request permissions, schedule course-bounded dates, apply privacy settings, dispatch selections, and cancel session-owned alerts.
// - Report whether exact alarms are allowed, open the system screen that allows them, and replace reminders that had to be scheduled as inexact alarms once they are.
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
  static const String markSlotTakenActionId =
      MedicationNotificationPayloadCodec.markSlotTakenActionId;
  static const String snoozeTenMinutesActionId =
      MedicationNotificationPayloadCodec.snoozeTenMinutesActionId;
  static const String caregiverSnoozeActionId =
      MedicationNotificationPayloadCodec.caregiverSnoozeActionId;
  static const String caregiverChatActionId =
      MedicationNotificationPayloadCodec.caregiverChatActionId;
  // 구형 고정 ID(1001~1004) 예약을 이 설치에서 모두 지웠음을 기록하는 기기 저장소 키.
  static const String legacyReminderIdsCancelledKey =
      'medbuddy_legacy_reminder_ids_cancelled';
  // 테스트에서만 교체한다. 예약 갱신이 기기 저장소를 읽고 쓰는 횟수를 세는 데 쓴다.
  @visibleForTesting
  static Future<SharedPreferences> Function() preferencesLoader =
      SharedPreferences.getInstance;
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
  String? _historyUserHash;
  Future<void> _scopeWrite = Future<void>.value();
  Future<void>? _reminderWrite;
  // 이 실행 중 실제로 취소한 구형 고정 ID.
  final Set<int> _cancelledLegacyReminderIds = <int>{};
  // 이 실행에서 직접 예약한 날짜별 알림 ID. 강제 종료나 '알람 및 리마인더' 권한 회수 뒤에는 Android가 알람을
  // 지워도 플러그인의 예약 목록에는 그대로 남으므로, 새로 시작한 실행은 그 목록만 믿지 않고 한 번씩 다시 예약한다.
  final Set<int> _armedReminderIds = <int>{};
  // 정확한 알람이 허용되지 않아 부정확 알람으로 예약한 날짜를 계획 서명에 표시하는 값.
  static const String _inexactScheduleMarker = 'inexact';

  // 예약·미루기·취소의 호출 순서를 지켜 늦은 예약이 취소를 되돌리지 않게 한다.
  Future<void> _serializeReminder(Future<void> Function() action) {
    final owner = _historyUserHash;
    final previous = _reminderWrite;
    late final Future<void> current;
    current = (() async {
      if (previous != null) {
        try { await previous; } catch (_) { /* 다음 요청은 재시도할 수 있다. */ }
      }
      if (owner == _historyUserHash) await action();
    })().whenComplete(() {
      if (identical(_reminderWrite, current)) _reminderWrite = null;
    });
    return _reminderWrite = current;
  }

  // 함수이름: setHistoryUser
  // 함수역할: 알림 기록의 계정 범위를 교체한다. 매개변수: userHash, 전경 세션 저장 여부. 반환값: 없음.
  void setHistoryUser(String? userHash, {bool persistSession = true}) {
    _historyUserHash = userHash?.trim();
    if (!persistSession) return;
    _scopeWrite = _scopeWrite
        .catchError((Object _) {})
        .then((_) async {
          final preferences = await SharedPreferences.getInstance();
          final current = _historyUserHash;
          if (current == null || current.isEmpty) {
            await preferences.remove(NotificationInboxStore.activeUserKey);
          } else {
            await preferences.setString(
              NotificationInboxStore.activeUserKey,
              current,
            );
          }
        })
        .catchError((Object error, StackTrace stack) {
          developer.log(
            '알림함 세션을 저장하지 못했습니다.',
            name: 'NotificationService',
            error: error,
            stackTrace: stack,
          );
        });
  }

  // 함수이름: _inboxStore
  // 함수역할: 계정의 알림함 저장소를 이 서비스와 같은 기기 저장소 경계로 만든다. 매개변수: owner. 반환값: 저장소.
  NotificationInboxStore _inboxStore(String owner) => NotificationInboxStore(
    userHash: owner,
    loadPreferences: () => preferencesLoader(),
  );

  // 함수이름: _recordInbox
  // 함수역할: 기록 오류가 실제 알림 표시를 막지 않게 한다. 매개변수: owner, entry. 반환값: 기록 시도 완료.
  Future<void> _recordInbox(String? owner, NotificationInboxEntry entry) async {
    if (owner == null || owner.isEmpty) return;
    try {
      await _inboxStore(owner).record(entry);
    } catch (error, stack) {
      developer.log(
        '알림 내역 저장 실패',
        name: 'NotificationService',
        error: error,
        stackTrace: stack,
      );
    }
  }

  // 함수이름: _recordInboxAll
  // 함수역할: 한 번의 예약 갱신에서 생긴 알림함 항목을 한꺼번에 기록한다. 기록 오류는 예약을 막지 않는다.
  // 매개변수: owner, entries. 반환값: 기록 시도 완료.
  Future<void> _recordInboxAll(
    String? owner,
    List<NotificationInboxEntry> entries,
  ) async {
    if (owner == null || owner.isEmpty || entries.isEmpty) return;
    try {
      await _inboxStore(owner).recordAll(entries);
    } catch (error, stack) {
      developer.log(
        '알림 내역 저장 실패',
        name: 'NotificationService',
        error: error,
        stackTrace: stack,
      );
    }
  }

  // 함수이름: _cancelInboxReminders
  // 함수역할: 알림함의 미래 예약만 취소한다. 매개변수: 선택적 slotKey, id. 반환값: 완료.
  Future<void> _cancelInboxReminders({String? slotKey, int? id}) async {
    final owner = _historyUserHash;
    if (owner == null || owner.isEmpty) return;
    try {
      await _inboxStore(owner).cancelFutureReminders(slotKey: slotKey, id: id);
    } catch (error, stack) {
      developer.log(
        '알림 내역 예약 취소 실패',
        name: 'NotificationService',
        error: error,
        stackTrace: stack,
      );
    }
  }

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

  // 함수이름: forgetArmedRemindersForTest
  // 함수역할: 앱이 강제 종료되어 새 실행이 시작된 상황을 테스트에서 만든다. 이 실행이 예약했다고 기억하는
  //   알림 ID를 비워, 다음 예약 갱신이 플러그인의 예약 목록만 믿지 않게 한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  @visibleForTesting
  void forgetArmedRemindersForTest() => _armedReminderIds.clear();

  // 함수이름: canScheduleExactReminders
  // 함수역할: 복약 알림을 정한 분에 울리는 정확한 알람으로 예약할 수 있는지 확인한다. Android 14 이상은
  //   '알람 및 리마인더' 권한이 기본으로 꺼져 있어, 꺼진 동안에는 알림이 몇 분 늦을 수 있는 부정확 알람으로 예약된다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: 정확한 알람을 쓸 수 있으면 true. Android가 아니거나 플랫폼 구현이 없으면 true.
  Future<bool> canScheduleExactReminders() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    await initialize();
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await androidPlugin?.canScheduleExactNotifications() ?? true;
  }

  // 함수이름: requestExactReminderPermission
  // 함수역할: 시스템의 '알람 및 리마인더' 설정 화면을 열어 사용자가 정확한 알람을 허용하게 한다. 이미 허용된
  //   기기에서는 화면을 열지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<bool>: 사용자가 돌아온 시점에 정확한 알람이 허용되어 있으면 true.
  Future<bool> requestExactReminderPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    await initialize();
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await androidPlugin?.requestExactAlarmsPermission() ?? true;
  }

  // 함수이름: rescheduleInexactRemindersAsExact
  // 함수역할: 권한이 없어 부정확 알람으로 예약했던 현재 계정의 복약 알림을, 권한이 허용된 뒤 같은 날짜·시각·문구의
  //   정확한 알람으로 다시 예약한다. 저장된 예약 계획과 기기의 예약 목록만 쓰므로 서버 조회 없이 동작한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 다시 예약할 알림이 없거나 권한이 아직 없으면 아무것도 바꾸지 않고 완료한다.
  Future<void> rescheduleInexactRemindersAsExact() =>
      _serializeReminder(_rescheduleInexactRemindersAsExact);

  Future<void> _rescheduleInexactRemindersAsExact() async {
    final owner = _historyUserHash;
    final preferences = await preferencesLoader();
    await preferences.reload();
    final plans = <String, Map<String, dynamic>>{};
    for (final slotKey in const ['morning', 'lunch', 'evening', 'bedtime']) {
      final rawPlan = preferences.getString(_reminderPlanKey(owner, slotKey));
      // 부정확 알람이 없는 계획은 해석하지 않고 넘어간다.
      if (rawPlan == null || !rawPlan.contains(_inexactScheduleMarker)) continue;
      try {
        plans[slotKey] = Map<String, dynamic>.from(jsonDecode(rawPlan));
      } catch (_) {
        // 손상된 계획은 다음 예약 갱신이 다시 작성한다.
      }
    }
    if (plans.isEmpty || !await canScheduleExactReminders()) return;
    if (owner != _historyUserHash) return;
    final pending = {
      for (final request in await _plugin.pendingNotificationRequests())
        request.id: request,
    };
    final now = timezone.TZDateTime.now(timezone.local);
    for (final plan in plans.entries) {
      var changed = false;
      for (final key in plan.value.keys.toList(growable: false)) {
        final notificationId = int.tryParse(key);
        final signature = _decodeReminderSignature(plan.value[key]);
        final request = pending[notificationId];
        final scheduleDate = selectionFromPayload(request?.payload)?.scheduleDate;
        if (notificationId == null ||
            signature == null ||
            !signature.inexact ||
            scheduleDate == null) {
          continue;
        }
        final scheduledDate = timezone.TZDateTime(
          timezone.local,
          scheduleDate.year,
          scheduleDate.month,
          scheduleDate.day,
          signature.hour,
          signature.minute,
        );
        // 이미 울린 날짜에 남은 예약은 사용자가 미룬 알림이므로 건드리지 않는다.
        if (!scheduledDate.isAfter(now)) continue;
        try {
          final entry = await _scheduleWithMode(
            owner: owner,
            id: notificationId,
            slotKey: plan.key,
            slotTitle: signature.slotTitle,
            language: signature.language,
            body: signature.body,
            scheduledDate: scheduledDate,
            scheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
          if (entry == null) return;
        } on PlatformException {
          // 그 사이 권한이 다시 꺼졌다. 플러그인은 기존 부정확 알람을 그대로 둔다.
          return;
        }
        _armedReminderIds.add(notificationId);
        plan.value[key] = jsonEncode([
          signature.hour,
          signature.minute,
          signature.slotTitle,
          signature.language,
          signature.body,
        ]);
        changed = true;
      }
      if (changed && owner == _historyUserHash) {
        await preferences.setString(
          _reminderPlanKey(owner, plan.key),
          jsonEncode(plan.value),
        );
      }
    }
  }

  // 함수이름: _reminderPlanKey
  // 함수역할: 계정과 시간대별 예약 계획을 저장하는 기기 저장소 키를 만든다.
  // 매개변수: owner - 계정 해시(없으면 guest), slotKey - 복약 시간대 키. 반환값: 저장소 키.
  String _reminderPlanKey(String? owner, String slotKey) =>
      'medbuddy_reminder_plan_${owner ?? "guest"}_$slotKey';

  // 함수이름: _decodeReminderSignature
  // 함수역할: 예약 계획에 저장한 서명에서 예약 시각·문구와 부정확 알람 표시를 읽는다.
  // 매개변수: rawSignature - 계획에 저장된 값. 반환값: 해석한 값, 형식이 다르면 null.
  ({int hour, int minute, String slotTitle, String language, String body, bool inexact})?
  _decodeReminderSignature(Object? rawSignature) {
    if (rawSignature is! String) return null;
    try {
      final values = jsonDecode(rawSignature);
      if (values is! List || values.length < 5) return null;
      return (
        hour: values[0] as int,
        minute: values[1] as int,
        slotTitle: values[2] as String,
        language: values[3] as String,
        body: values[4] as String,
        inexact: values.length > 5 && values[5] == _inexactScheduleMarker,
      );
    } catch (_) {
      return null;
    }
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
  // Description: Preserves the public parser API while delegating validation to the platform-independent codec.
  // Parameters:
  // - payload (String?): Navigation payload from a system notification or FCM.
  // - actionId (String?): System notification button identifier.
  // - notificationId (int?): Platform notification or server setting identifier.
  // Returns:
  // - MedicationNotificationSelection?: Validated navigation/action arguments, or null for a malformed payload.
  static MedicationNotificationSelection? selectionFromPayload(
    String? payload, {
    String? actionId,
    int? notificationId,
  }) {
    return MedicationNotificationPayloadCodec.decode(
      payload,
      actionId: actionId,
      notificationId: notificationId,
    );
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
    return MedicationNotificationPayloadCodec.isSessionPayload(payload);
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
      await _createAndroidNotificationChannels();

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

  // Function Name: _createAndroidNotificationChannels
  // Description: Creates the three Android channels at start-up. The plugin otherwise creates a channel only when the app
  //   first shows a local notification on it, so a server push that names a channel the app has not used yet would be
  //   shown on the Firebase fallback channel without this app's importance and sound. Names follow the last shown language
  //   once a local notification is displayed; a failure here must not block notification initialization.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _createAndroidNotificationChannels() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) {
        return;
      }
      const channels = <AndroidNotificationChannel>[
        AndroidNotificationChannel(
          'medbuddy_medication_reminders',
          '복약 알림',
          description: 'MedBuddy 복약 시간 알림',
          importance: Importance.high,
        ),
        AndroidNotificationChannel(
          'medbuddy_caregiver_updates',
          '보호자 복약 확인',
          description: '연동된 환자의 복약 완료 및 미복용 상태 알림',
          importance: Importance.high,
        ),
        AndroidNotificationChannel(
          'medbuddy_linked_chat',
          '가족 채팅',
          description: '연동된 환자와 보호자의 새 채팅 메시지 알림',
          importance: Importance.high,
        ),
      ];
      for (final channel in channels) {
        await android.createNotificationChannel(channel);
      }
    } catch (_) {
      // Channels are still created lazily when a local notification is shown.
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
  // Description: Replaces dated slot reminders with neutral text and an inexact fallback when exact alarms are unavailable. A reminder already reserved with the same time and text is left alone only when this process scheduled it; a newly started process re-arms each future date once, because Android drops the alarms of a force-stopped app while the plugin keeps listing them.
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
  }) {
    final owner = _historyUserHash;
    return _serializeReminder(() =>
      _reconcileReminder(owner: owner, id: id, slotKey: slotKey,
          slotTitle: slotTitle, hour: hour, minute: minute,
          activeDates: List.of(activeDates), language: language));
  }

  // 날짜별 예약 계획을 보존해 동일한 예약과 사용자가 미룬 알림은 건드리지 않는다.
  Future<void> _reconcileReminder({
    required String? owner, required int id, required String slotKey,
    required String slotTitle, required int hour, required int minute,
    required List<DateTime> activeDates, required String language,
  }) async {
    await initialize();
    if (owner != _historyUserHash) return;
    final preferences = await preferencesLoader();
    await preferences.reload();
    if (owner != _historyUserHash) return;
    final planKey = _reminderPlanKey(owner, slotKey);
    Map<String, dynamic> previous = {};
    try {
      previous = Map<String, dynamic>.from(jsonDecode(preferences.getString(planKey) ?? '{}'));
    } catch (_) {
      // 손상된 계획은 실제 기기 예약을 확인한 뒤 다시 작성한다.
    }
    final pending = {
      for (final request in await _plugin.pendingNotificationRequests())
        if (request.id == id || (request.payload?.startsWith('schedule:$slotKey:') ?? false))
          request.id: request,
    };
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
    final desiredIds = {
      for (final date in sortedDates) _notificationIdForDate(id, slotKey, date),
    };
    for (final staleId in pending.keys.where((key) => !desiredIds.contains(key))) {
      if (owner != _historyUserHash) return;
      await _plugin.cancel(id: staleId);
      await _cancelInboxReminders(id: staleId);
    }
    final nextPlan = <String, String>{};
    // 새로 예약한 날짜의 알림함 항목은 모아 두었다가 한 번에 기록한다.
    final scheduledEntries = <NotificationInboxEntry>[];
    // 부정확 알람으로 남은 날짜가 있을 때만 한 번 확인하는 정확한 알람 허용 여부.
    bool? exactAllowed;

    try {
      for (final activeDate in sortedDates) {
        if (owner != _historyUserHash) return;
        final body = _buildReminderBody(language);
        final scheduledDate = timezone.TZDateTime(
          timezone.local,
          activeDate.year,
          activeDate.month,
          activeDate.day,
          hour,
          minute,
        );
        final notificationId = _notificationIdForDate(id, slotKey, activeDate);
        final key = '$notificationId';
        final signature = jsonEncode([hour, minute, slotTitle, language, body]);
        final inexactSignature = jsonEncode([
          hour, minute, slotTitle, language, body, _inexactScheduleMarker,
        ]);
        final previousSignature = previous[key];
        final sameContent =
            previousSignature == signature ||
            previousSignature == inexactSignature;
        if (!scheduledDate.isAfter(now)) {
          // 이미 지난 시각은 예약하지 않는다. 알림 시각을 지금보다 이르게 옮긴 날에는 이전 시각으로 남은
          // 오늘 예약을 일부러 그대로 둔다. 취소하면 아직 복용하지 않은 오늘 분의 알림이 하나도 남지 않는다.
          nextPlan[key] = sameContent ? previousSignature as String : signature;
          continue;
        }
        // 같은 내용으로 이미 예약되어 있는지. 이 실행이 직접 예약한 것만 그대로 믿는다.
        final reserved = pending.containsKey(notificationId) && sameContent;
        if (reserved && _armedReminderIds.contains(notificationId)) {
          if (previousSignature == signature) {
            nextPlan[key] = signature;
            continue;
          }
          // 부정확 알람으로 예약된 날짜는 권한이 허용된 뒤에만 정확한 알람으로 바꾼다.
          exactAllowed ??= await _canScheduleExactAlarmsSafely();
          if (owner != _historyUserHash) return;
          if (!exactAllowed) {
            nextPlan[key] = inexactSignature;
            continue;
          }
        }
        NotificationInboxEntry? entry;
        var scheduledExact = true;
        try {
          entry = await _scheduleWithMode(
            owner: owner,
            id: notificationId,
            slotKey: slotKey,
            slotTitle: slotTitle,
            language: language,
            body: body,
            scheduledDate: scheduledDate,
            scheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
        } on PlatformException {
          scheduledExact = false;
          entry = await _scheduleWithMode(
            owner: owner,
            id: notificationId,
            slotKey: slotKey,
            slotTitle: slotTitle,
            language: language,
            body: body,
            scheduledDate: scheduledDate,
            scheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
        if (entry == null) continue;
        _armedReminderIds.add(notificationId);
        nextPlan[key] = scheduledExact ? signature : inexactSignature;
        // 같은 날짜·시각·문구를 다시 건 예약은 알림함 항목이 이미 있다.
        if (reserved) continue;
        // 시각이나 문구가 바뀌어 다시 예약한 날짜는 이전 시각으로 남은 알림함 예정 항목을 지운다.
        if (previousSignature != null && !sameContent) {
          await _cancelInboxReminders(id: notificationId);
        }
        scheduledEntries.add(entry);
      }
    } finally {
      // 도중에 중단되어도 이미 기기에 예약한 알림은 알림함에 남긴다.
      await _recordInboxAll(owner, scheduledEntries);
    }
    final encodedPlan = jsonEncode(nextPlan);
    // 계획이 그대로면 다시 저장하지 않는다.
    if (owner == _historyUserHash &&
        preferences.getString(planKey) != encodedPlan) {
      await preferences.setString(planKey, encodedPlan);
    }
  }

  // 함수이름: _canScheduleExactAlarmsSafely
  // 함수역할: 예약 갱신 도중 정확한 알람 허용 여부를 확인한다. 확인하지 못하면 허용되지 않은 것으로 보아
  //   이미 걸려 있는 부정확 알람을 그대로 둔다.
  // 매개변수: 없음. 반환값: 정확한 알람을 쓸 수 있다고 확인되면 true.
  Future<bool> _canScheduleExactAlarmsSafely() async {
    try {
      return await canScheduleExactReminders();
    } catch (_) {
      return false;
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
    await _cancelInboxReminders(slotKey: slotKey);
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
  String _dateKey(DateTime date) => formatJsonDate(date)!;

  // 함수이름: _notificationIdForDate
  // 함수역할: 시간대와 복용 날짜마다 충돌 가능성이 낮은 고정 알림 ID를 생성한다.
  // 매개변수:
  // - baseId (int): 날짜별 알림 ID 계산에 쓸 기본 ID
  // - slotKey (String): morning·lunch·evening·bedtime 복약 시간대 키
  // - date (DateTime): 달력 날짜 계산 또는 비교의 기준 시각
  // 반환값:
  // - int: 시간대와 복용 날짜마다 충돌 가능성이 낮은 고정 알림 ID를 생성한다.
  int _notificationIdForDate(int baseId, String slotKey, DateTime date) {
    final hash = fnv1a31('$baseId|$slotKey|${_dateKey(date)}');
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
  bool _isEnglish(String language) => isEnglishLanguage(language);

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
  // - Future<NotificationInboxEntry?>: The inbox entry for the scheduled reminder, which the caller records; null when the account changed and nothing was scheduled.
  Future<NotificationInboxEntry?> _scheduleWithMode({
    required String? owner,
    required int id,
    required String slotKey,
    required String slotTitle,
    required String language,
    required String body,
    required timezone.TZDateTime scheduledDate,
    required AndroidScheduleMode scheduleMode,
    DateTime? scheduleDate,
  }) async {
    // 예약 도중 계정이 바뀌면 나머지 예약을 새 계정에 남기지 않는다.
    if (owner != _historyUserHash) return null;
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
          groupKey: 'medbuddy.reminder.$slotKey',
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
      payload:
          'schedule:$slotKey:$id:${_dateKey(scheduleDate ?? scheduledDate)}',
    );
    return NotificationInboxEntry(
      id: 'reminder:$id:${scheduledDate.millisecondsSinceEpoch}',
      title: title,
      body: body,
      payload:
          'schedule:$slotKey:$id:${_dateKey(scheduleDate ?? scheduledDate)}',
      category: NotificationInboxCategory.medication,
      occurredAt: scheduledDate,
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
  }) => _serializeReminder(() => _snoozeMedicationReminder(
    id: id, slotKey: slotKey, slotTitle: slotTitle, language: language,
    delay: delay, scheduleDate: scheduleDate,
  ));

  Future<void> _snoozeMedicationReminder({
    required int id, required String slotKey, required String slotTitle,
    required String language, required Duration delay, DateTime? scheduleDate,
  }) async {
    final owner = _historyUserHash;
    await initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final scheduledDate = now.add(delay);
    final originalDate = scheduleDate ?? now;
    final body = _buildReminderBody(language);
    NotificationInboxEntry? entry;
    try {
      entry = await _scheduleWithMode(
        owner: owner,
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
      entry = await _scheduleWithMode(
        owner: owner,
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
    if (entry != null) await _recordInbox(owner, entry);
  }

  // 함수이름: cancelReminder
  // 함수역할: 지정한 복약 알림 예약을 취소한다.
  // 매개변수:
  // - id (int): 취소할 알림 id
  // - slotKey (String?): morning·lunch·evening·bedtime 복약 시간대 키
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> cancelReminder(int id, {String? slotKey}) =>
      _serializeReminder(() => _cancelReminder(id, slotKey: slotKey));

  // 완료된 날짜의 예약·재알림만 취소한다. 다른 날짜와 계정의 예약은 보존한다.
  Future<void> cancelReminderForDate({
    required String owner,
    required String slotKey,
    required DateTime date,
  }) => _serializeReminder(() async {
    if (owner.trim().isEmpty ||
        !const ['morning', 'lunch', 'evening', 'bedtime'].contains(slotKey)) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    Future<bool> stillActive() async {
      await preferences.reload();
      return preferences.getString(NotificationInboxStore.activeUserKey) == owner;
    }

    if (!await stillActive()) return;
    await initialize();
    final baseId = MedicationAlarm.defaults(slotKey)
        .copyWith(patientHash: owner)
        .notificationId;
    final id = _notificationIdForDate(baseId, slotKey, date);
    if (!await stillActive()) return;
    await _plugin.cancel(id: id);
    // Android가 표시 중인 알림의 payload를 반환하지 않아 날짜별 ID로 구분한다.
    for (final notification in await _plugin.getActiveNotifications()) {
      if (notification.id == id &&
          notification.channelId == 'medbuddy_medication_reminders') {
        if (!await stillActive()) return;
        await _plugin.cancel(id: id, tag: notification.tag);
      }
    }
    await _inboxStore(owner).cancelFutureReminders(id: id);
  });

  Future<void> _cancelReminder(int id, {String? slotKey}) async {
    await _cancelInboxReminders(slotKey: slotKey, id: id);
    await initialize();
    if (slotKey != null && slotKey.trim().isNotEmpty) {
      await _cancelScheduledNotificationsForSlot(slotKey, legacyId: id);
      // Delivered date-specific reminders are no longer pending. Explicitly
      // disabling this slot must remove their completion/snooze shortcuts too.
      // Keep this out of routine rescheduling, which should retain delivered
      // reminders while refreshing future dates.
      final activeNotifications = await _plugin.getActiveNotifications();
      // Android's plugin does not return payload for active notifications.
      // Older builds also lack our group marker: recognize their deterministic
      // IDs over the same 90-day window as local reminder history, but only on
      // the medication channel. Unknown/other-slot notifications stay intact.
      final now = timezone.TZDateTime.now(timezone.local);
      final legacyIds = <int>{id};
      for (var day = 0; day <= 90; day++) {
        legacyIds.add(_notificationIdForDate(
          id,
          slotKey,
          DateTime(now.year, now.month, now.day - day),
        ));
      }
      for (final notification in activeNotifications) {
        final notificationId = notification.id;
        final androidMatch =
            notification.channelId == 'medbuddy_medication_reminders' &&
            (notification.groupKey == 'medbuddy.reminder.$slotKey' ||
                (notification.groupKey == null &&
                    legacyIds.contains(notificationId)));
        if (notificationId != null &&
            (androidMatch ||
                (notification.payload?.startsWith('schedule:$slotKey:') ?? false))) {
          await _plugin.cancel(id: notificationId, tag: notification.tag);
        }
      }
      return;
    }
    await _plugin.cancel(id: id);
    await _rememberLegacyReminderCancelled(id);
  }

  // 함수이름: _rememberLegacyReminderCancelled
  // 함수역할: 구형 고정 ID 예약은 현재 앱이 다시 만들지 않으므로 설치마다 한 번만 지우면 된다. 네 시간대의
  //   구형 ID를 실제로 모두 취소한 뒤 기기에 표시해 이후 동기화가 같은 취소를 반복하지 않게 한다.
  // 매개변수: id - 방금 취소한 알림 ID. 반환값: 완료. 표시 저장 실패는 다음 실행에서 다시 시도한다.
  Future<void> _rememberLegacyReminderCancelled(int id) async {
    final legacyIds = {
      for (final slotKey in const ['morning', 'lunch', 'evening', 'bedtime'])
        MedicationAlarm.legacyNotificationIdForSlot(slotKey),
    };
    if (!legacyIds.contains(id)) return;
    _cancelledLegacyReminderIds.add(id);
    if (!_cancelledLegacyReminderIds.containsAll(legacyIds)) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      if (preferences.getBool(legacyReminderIdsCancelledKey) != true) {
        await preferences.setBool(legacyReminderIdsCancelledKey, true);
      }
    } catch (error, stack) {
      developer.log(
        '구형 알림 정리 기록 실패',
        name: 'NotificationService',
        error: error,
        stackTrace: stack,
      );
    }
  }

  // Function Name: cancelAllMedicationReminders
  // Description: Cancels pending and displayed session-owned medication, caregiver, and chat notifications plus legacy reminder IDs, while preserving unrelated notifications and clearing pending selections.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> cancelAllMedicationReminders() =>
      _serializeReminder(_cancelAllMedicationReminders);

  Future<void> _cancelAllMedicationReminders() async {
    await _cancelInboxReminders();
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
          (isSessionNotificationPayload(notification.payload) ||
              const {
                'medbuddy_medication_reminders',
                'medbuddy_caregiver_updates',
                'medbuddy_linked_chat',
              }.contains(notification.channelId))) {
        await _plugin.cancel(id: notificationId, tag: notification.tag);
      }
    }
    for (final slotKey in const ['morning', 'lunch', 'evening', 'bedtime']) {
      final legacyId = MedicationAlarm.legacyNotificationIdForSlot(slotKey);
      await _plugin.cancel(id: legacyId);
      await _rememberLegacyReminderCancelled(legacyId);
    }
    if (_pendingSelection != null) {
      _pendingSelection = null;
    }
  }

  // 함수이름: cancelAllScheduledMedicationReminders
  // 함수역할: 보호자·채팅 알림은 유지하고 예약 및 표시 중인 복약 알림을 취소한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> cancelAllScheduledMedicationReminders() =>
      _serializeReminder(_cancelAllScheduledMedicationReminders);

  Future<void> _cancelAllScheduledMedicationReminders() async {
    await _cancelInboxReminders();
    await initialize();
    final pendingRequests = await _plugin.pendingNotificationRequests();
    for (final request in pendingRequests) {
      if ((request.payload ?? '').startsWith('schedule:')) {
        await _plugin.cancel(id: request.id);
      }
    }
    // Delivered reminders are no longer pending. Remove their quick actions
    // too, so disabling reminders does not leave a visible snooze shortcut.
    final activeNotifications = await _plugin.getActiveNotifications();
    for (final notification in activeNotifications) {
      final id = notification.id;
      if (id != null &&
          (notification.channelId == 'medbuddy_medication_reminders' ||
              (notification.payload ?? '').startsWith('schedule:'))) {
        await _plugin.cancel(id: id, tag: notification.tag);
      }
    }
    for (final slotKey in const ['morning', 'lunch', 'evening', 'bedtime']) {
      final legacyId = MedicationAlarm.legacyNotificationIdForSlot(slotKey);
      await _plugin.cancel(id: legacyId);
      await _rememberLegacyReminderCancelled(legacyId);
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
    String? historyUserHash,
    bool recordHistory = true,
    CaregiverAlertContext? alertContext,
  }) async {
    final owner = historyUserHash ?? _historyUserHash;
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
          actions: alertContext == null ? null : [
            AndroidNotificationAction(caregiverSnoozeActionId,
                isEnglish ? 'Remind in 10 min' : '10분 후 다시 알림', showsUserInterface: true),
            AndroidNotificationAction(caregiverChatActionId,
                isEnglish ? 'Send chat request' : '채팅으로 알림', showsUserInterface: true),
          ],
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: alertContext?.payload ?? (patientHash == null || patientHash.trim().isEmpty
          ? null
          : 'caregiver:${Uri.encodeComponent(patientHash.trim())}'),
    );
    if (recordHistory && patientHash != null && patientHash.trim().isNotEmpty) {
      await _recordInbox(
        owner,
        NotificationInboxEntry(
          id: 'caregiver:$id',
          // 표시가 허용된 실제 완료·미복용 설명을 보존한다.
          title: _showSensitiveDetails
              ? title
              : isEnglish
              ? 'Medication update'
              : '복약 상태 알림',
          body: visibleBody,
          payload: alertContext?.payload ?? 'caregiver:${Uri.encodeComponent(patientHash.trim())}',
          category: NotificationInboxCategory.medication,
          occurredAt: DateTime.now(),
        ),
      );
    }
  }

  // 함수이름: showLinkedChatAlert
  // 함수역할: 전경에서 받은 가족 채팅 푸시를 제한된 메시지 미리보기와 함께 표시한다.
  // 매개변수:
  // - id (int): 플랫폼 알림의 예약·교체·취소 식별자
  // - linkId (int): 조회·전송·감시 대상 연동 ID
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // - messagePreview (String?): 시스템 알림과 알림함에 표시할 선택적 메시지 미리보기
  // - messageKind (String?): 일반·복약·약국 맥락 메시지 유형
  // - slotKey (String?): morning·lunch·evening·bedtime 복약 시간대 키
  // - historyUserHash (String?): 기록할 수신 계정. 생략하면 현재 세션을 사용한다.
  // - recordHistory (bool): 푸시 처리기에서 이미 저장한 알림의 중복 기록을 막는 선택값.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
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
    final owner = historyUserHash ?? _historyUserHash;
    final body = buildLinkedChatNotificationBody(
      messagePreview: messagePreview,
      showSensitiveDetails: _showSensitiveDetails,
      language: language,
    );
    await initialize();
    final isEnglish = _isEnglish(language);
    await _plugin.show(
      id: id,
      title: isEnglish ? 'New family message' : '새 가족 메시지',
      body: body,
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
      // A dose-check request is still a chat message. Open its conversation;
      // the patient chooses whether to record a dose from there.
      payload: 'chat:$linkId',
    );
    if (recordHistory) {
      await _recordInbox(
        owner,
        NotificationInboxEntry(
          id: 'chat:$linkId:$id',
          title: isEnglish ? 'New family message' : '새 가족 메시지',
          body: body,
          payload: 'chat:$linkId',
          category: NotificationInboxCategory.chat,
          occurredAt: DateTime.now(),
        ),
      );
    }
  }

  // 함수이름: buildLinkedChatNotificationBody
  // 함수역할: 로컬·푸시 알림함이 같은 미리보기 길이와 내용 숨김 규칙을 사용하게 한다.
  // 매개변수: messagePreview: 수신 내용, showSensitiveDetails: 내용 표시 허용 여부, language: 언어.
  // 반환값: 최대 120자의 미리보기 또는 내용 없는 알림의 대체 문구.
  static String buildLinkedChatNotificationBody({
    String? messagePreview,
    bool showSensitiveDetails = true,
    String language = 'ko',
  }) {
    final preview = _linkedChatMessagePreview(messagePreview);
    if (showSensitiveDetails && preview.isNotEmpty) return preview;
    return isEnglishLanguage(language)
        ? 'You received a new message from a linked family member.'
        : '연동된 가족에게 새 메시지가 도착했습니다.';
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
        .where(
          /* 함수이름: where 콜백
         * 함수역할: 알림 본문 조각 중 비어 있지 않은 부분만 결합 대상으로 남긴다.
         * 매개변수:
         * - part (String): 알림 본문에 결합할 문구 조각
         * 반환값:
         * - 본문 조각이 비어 있지 않으면 true.
         */
          (part) => part.isNotEmpty,
        )
        .join(' ');
    if (normalized.length <= maximumLength) {
      return normalized;
    }
    return '${normalized.substring(0, maximumLength - 1).trimRight()}…';
  }
}
