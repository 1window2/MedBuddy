// 파일명: notification_service.dart
// 역할: 복약, 보호자와 채팅 로컬 알림의 초기화, 예약, 표시와 취소를 담당한다.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:shared_preferences/shared_preferences.dart';
// Only Asia/Seoul is used and it has no DST, so the 10-year set (decoded in about a tenth of the full set's time before the first frame) is enough.
import 'package:timezone/data/latest_10y.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../entities/json_value_reader.dart';
import '../entities/chat_notification_summary.dart';
import '../entities/medication_alarm_entity.dart';
import '../entities/medication_reminder_text.dart';
import '../entities/caregiver_alert_context_entity.dart';
import '../entities/medication_notification_selection_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/notification_inbox_entity.dart';
import '../entities/user_setting_entity.dart';
import 'medication_notification_payload_codec.dart';
import 'medication_reminder_action_tag.dart';
import 'app_language_resolver.dart';
import 'notification_inbox_store.dart';
import 'slot_check_notification_context.dart';
import 'slot_check_notification_service.dart';

// Preserve existing imports while keeping the action contract platform-neutral.
export '../entities/medication_notification_selection_entity.dart';
export '../entities/chat_notification_summary.dart';

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
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;
  static MedicationNotificationSelectionHandler? _selectionHandler;
  static MedicationNotificationSelection? _pendingSelection;
  // Android가 앱을 띄운 알림 버튼을 시작 인텐트와 onNewIntent로 두 번 넘기면, 한 번 누른 버튼이 응답 콜백과
  // 시작 정보로 모두 들어온다. 같은 버튼을 다시 누르려면 알림이 다시 떠야 하므로(가장 짧은 경우 10분 후 다시
  // 알림) 이 시간 안의 같은 버튼 응답은 같은 누름이다.
  static const Duration _actionCopyWindow = Duration(seconds: 30);
  static String? _lastActionKey;
  static DateTime? _lastActionAt;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _settingsChannel = MethodChannel(
    'com.medbuddy.app/settings',
  );
  bool _isInitialized = false;
  Future<void>? _initializationFuture;
  bool _channelsInitialized = false;
  String? _notificationLanguage;
  String? _channelLanguage;
  Future<void>? _channelInitializationFuture;
  bool _showSensitiveDetails = true;
  String? _historyUserHash;
  Future<void> _scopeWrite = Future<void>.value();
  Future<void>? _reminderWrite;
  Future<void> _chatWrite = Future<void>.value();
  final Map<int, int> _chatLatestIds = {};
  final Map<int, int> _chatReadIds = {};

  // 함수이름: _serializeChat
  // 함수역할: 채팅 알림 쓰기를 순서대로 실행하고 대기 중 계정이 바뀌면 해당 작업을 건너뛴다.
  // 매개변수: action (Future<void> Function()): 이번 계정의 알림 쓰기 작업.
  // 반환값: 이번 작업 완료 Future. 앞선 실패는 다음 작업을 막지 않으며 이번 작업 오류는 호출자에게 전달한다.
  Future<void> _serializeChat(Future<void> Function() action) {
    final session = _historyUserHash;
    final next = _chatWrite.catchError((Object _) {}).then((_) async {
      if (session == _historyUserHash) await action();
    });
    _chatWrite = next;
    return next;
  }

  // 이 실행 중 실제로 취소한 구형 고정 ID.
  final Set<int> _cancelledLegacyReminderIds = <int>{};
  // 이 실행에서 직접 예약한 날짜별 알림 ID. 강제 종료나 '알람 및 리마인더' 권한 회수 뒤에는 Android가 알람을
  // 지워도 플러그인의 예약 목록에는 그대로 남으므로, 새로 시작한 실행은 그 목록만 믿지 않고 한 번씩 다시 예약한다.
  final Set<int> _armedReminderIds = <int>{};
  // 정확한 알람이 허용되지 않아 부정확 알람으로 예약한 날짜를 계획 서명에 표시하는 값.
  static const String _inexactScheduleMarker = 'inexact';
  // Android 알림 채널 ID. 채널 생성·표시·취소 필터·준비 상태 확인이 같은 값을 써야 한다.
  static const String _medicationChannelId = 'medbuddy_medication_reminders';
  static const String _caregiverChannelId = 'medbuddy_caregiver_updates';
  static const String _chatChannelId = 'medbuddy_linked_chat';

  // 예약·미루기·취소의 호출 순서를 지켜 늦은 예약이 취소를 되돌리지 않게 한다.
  // 함수이름: _serializeReminder
  // 함수역할: 복약 알림 쓰기를 직렬화하고 차례가 왔을 때 계정이 같은 경우에만 실행한다.
  // 매개변수: action (Future<void> Function()): 예약·취소 작업.
  // 반환값: 이번 작업 완료 Future. 이전 오류는 무시하고 완료 시 자신의 대기 표식만 지우며 작업 오류는 전파한다.
  Future<void> _serializeReminder(Future<void> Function() action) {
    final owner = _historyUserHash;
    final previous = _reminderWrite;
    late final Future<void> current;
    current =
        (() async {
          if (previous != null) {
            try {
              await previous;
            } catch (_) {
              /* 다음 요청은 재시도할 수 있다. */
            }
          }
          if (owner == _historyUserHash) await action();
        })().whenComplete(() {
          if (identical(_reminderWrite, current)) _reminderWrite = null;
        });
    return _reminderWrite = current;
  }

  // 함수이름: setHistoryUser
  // 함수역할: 알림 기록 계정을 바꾸고 계정 변경 시 채팅 읽음·최신 ID 캐시를 비운다. 세션 저장은 순차 비동기로 수행하며 실패를 기록한다.
  // 매개변수: userHash (String?): 새 계정, null·빈 값이면 해제; persistSession (bool): 영속 활성 계정도 갱신할지 여부.
  // 반환값: void; 세션 저장 완료를 기다리지 않는다.
  void setHistoryUser(String? userHash, {bool persistSession = true}) {
    if (_historyUserHash != userHash?.trim()) {
      _chatLatestIds.clear();
      _chatReadIds.clear();
    }
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

  // Function Name: _inboxStore
  // Description: Create an inbox store using this service's preference loader.
  // Parameters: owner (String): history owner.
  // Returns: NotificationInboxStore: owner-scoped history access.
  NotificationInboxStore _inboxStore(String owner) => NotificationInboxStore(
    userHash: owner,
    loadPreferences: () => preferencesLoader(),
  );

  // Function Name: _recordInbox
  // Description: Record one history entry when an owner exists; log and suppress persistence failures.
  // Parameters: owner (String?): history owner; entry (NotificationInboxEntry): notification record.
  // Returns: Future<void>: best-effort recording completion.
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

  // Function Name: _recordInboxAll
  // Description: Record a nonempty history batch for a known owner; log and suppress persistence failures.
  // Parameters: owner (String?): history owner; entries (List<NotificationInboxEntry>): notification records.
  // Returns: Future<void>: best-effort batch completion.
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

  // Function Name: _cancelInboxReminders
  // Description: Remove matching future reminder history for the current owner; log and suppress cleanup failures.
  // Parameters: slotKey (String?): slot filter; id (int?): ID filter when slot is absent.
  // Returns: Future<void>: best-effort history cleanup, no-op without an owner.
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

  // Function Name: forgetArmedRemindersForTest
  // Description: Clear the in-memory armed-reminder cache for test isolation without touching platform schedules.
  // Parameters: None.
  // Returns: void.
  @visibleForTesting
  void forgetArmedRemindersForTest() => _armedReminderIds.clear();

  // Function Name: canScheduleExactReminders
  // Description: Check Android exact-alarm capability after initialization; other platforms and an unavailable Android adapter are treated as supported.
  // Parameters: None.
  // Returns: Future<bool>: whether exact reminders can be scheduled; plugin errors propagate.
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

  // Function Name: requestExactReminderPermission
  // Description: Request Android exact-alarm permission after initialization; return true on other platforms or without an Android adapter.
  // Parameters: None.
  // Returns: Future<bool>: granted capability; plugin errors propagate.
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

  // Function Name: rescheduleInexactRemindersAsExact
  // Description: Serialize promotion of previously inexact reminders to exact schedules.
  // Parameters: None.
  // Returns: Future<void>: promotion attempt completion.
  Future<void> rescheduleInexactRemindersAsExact() =>
      _serializeReminder(_rescheduleInexactRemindersAsExact);

  // 함수이름: _rescheduleInexactRemindersAsExact
  // 함수역할: 정확 알람 권한을 얻은 뒤 아직 미래인 부정확 예약만 같은 날짜·시각·내용의 정확 예약으로 바꾼다.
  // 매개변수: 없음. 현재 알림 계정과 저장 계획·플랫폼 예약을 조회한다.
  // 반환값: 완료 Future. 손상된 계획은 건너뛰고 권한·계정 변경은 중단하며 일반 저장소 오류는 전파한다.
  Future<void> _rescheduleInexactRemindersAsExact() async {
    final owner = _historyUserHash;
    final preferences = await preferencesLoader();
    await preferences.reload();
    final plans = <String, Map<String, dynamic>>{};
    for (final slotKey in medicationScheduleSlotKeys) {
      final rawPlan = preferences.getString(reminderPlanKey(owner, slotKey));
      // 부정확 알람이 없는 계획은 해석하지 않고 넘어간다.
      if (rawPlan == null || !rawPlan.contains(_inexactScheduleMarker)) {
        continue;
      }
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
        final scheduleDate = selectionFromPayload(
          request?.payload,
        )?.scheduleDate;
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
          reminderPlanKey(owner, plan.key),
          jsonEncode(plan.value),
        );
      }
    }
  }

  // Function Name: reminderPlanKey
  // Description: Build a persisted reminder-plan key scoped by owner and slot.
  // Parameters: owner (String?): owner, using guest for null; slotKey (String): medication slot.
  // Returns: String: reminder-plan preference key.
  static String reminderPlanKey(String? owner, String slotKey) =>
      'medbuddy_reminder_plan_${owner ?? "guest"}_$slotKey';

  // 함수이름: _decodeReminderSignature
  // 함수역할: 예약 계획에 저장한 서명에서 예약 시각·문구와 부정확 알람 표시를 읽는다.
  // 매개변수: rawSignature - 계획에 저장된 값. 반환값: 해석한 값, 형식이 다르면 null.
  ({
    int hour,
    int minute,
    String slotTitle,
    String language,
    String body,
    bool inexact,
  })?
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

  // Function Name: isSessionNotificationPayload
  // Description: Classify session-related notification prefixes using the shared payload codec.
  // Parameters: payload (String?): notification payload.
  // Returns: bool: recognized session prefix, not full payload validity.
  @visibleForTesting
  static bool isSessionNotificationPayload(String? payload) {
    return MedicationNotificationPayloadCodec.isSessionPayload(payload);
  }

  // 함수이름: initialize
  // 함수역할: 초기화를 공유하여 중복 실행을 막고 초기화 후에는 Android 채널 상태를 다시 확인한다.
  // 매개변수: 없음.
  // 반환값: Future<void>: 초기화 또는 채널 확인 완료; 초기화 실패는 전파된다.
  Future<void> initialize() {
    if (_isInitialized) {
      return _ensureAndroidNotificationChannels();
    }
    return _initializationFuture ??= _initialize();
  }

  // 함수이름: _initialize
  // 함수역할: 서울 시간대·저장 언어·플랫폼 응답 핸들러를 설정하고 앱을 연 알림을 처리한다. 실패한 초기화 시도는 재시도할 수 있게 비운다.
  // 매개변수: 없음.
  // 반환값: Future<void>: 초기화와 채널 준비 완료; 실패 시 원래 오류를 전파한다.
  Future<void> _initialize() async {
    try {
      timezone_data.initializeTimeZones();
      // 서버의 APPLICATION_TIME_ZONE 기본값과 같다. 앱 기준 날짜(doseWidgetUtcOffset 기본 540분)도 이
      // 시간대이며, 한국은 일광 절약 시간이 없어 둘이 어긋나지 않는다.
      timezone.setLocalLocation(timezone.getLocation('Asia/Seoul'));

      if (_notificationLanguage == null) {
        try {
          final preferences = await preferencesLoader();
          _notificationLanguage ??= resolveAppLanguage(
            preferences.getString(appLanguagePreferenceKey) ?? 'ko',
          );
        } catch (_) {
          _notificationLanguage ??= 'ko';
        }
      }

      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      await _plugin.initialize(
        settings: const InitializationSettings(
          // 상태 표시줄 아이콘은 투명도로만 그려지므로 불투명한 앱 아이콘 대신 흰 실루엣을 쓴다.
          android: AndroidInitializationSettings('@drawable/ic_stat_medbuddy'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _handleNotificationResponse,
        onDidReceiveBackgroundNotificationResponse:
            medBuddySlotCheckNotificationBackground,
      );
      _isInitialized = true;
      await _ensureAndroidNotificationChannels();

      if (launchDetails?.didNotificationLaunchApp ?? false) {
        final response = launchDetails?.notificationResponse;
        if (response != null) _handleNotificationResponse(response);
      }
    } catch (_) {
      _initializationFuture = null;
      rethrow;
    }
  }

  // 채널 생성 실패는 초기화를 막지 않되 다음 호출에서 재시도하고 동시 호출은 합친다.
  // 함수이름: _ensureAndroidNotificationChannels
  // 함수역할: 같은 언어의 채널 준비 결과를 재사용하고 동시에 들어온 초기화를 하나로 합친다.
  // 매개변수: 없음.
  // 반환값: 채널 준비 완료 Future. 실패 후 진행 중 표식을 해제하므로 다음 호출에서 다시 시도할 수 있다.
  Future<void> _ensureAndroidNotificationChannels() {
    if (_channelInitializationFuture != null) {
      return _channelInitializationFuture!;
    }
    if (_channelsInitialized && _channelLanguage == _notificationLanguage) {
      return Future<void>.value();
    }
    return _channelInitializationFuture ??= _createAndroidNotificationChannels()
        .whenComplete(() {
          _channelInitializationFuture = null;
        });
  }

  // 기존 채널 ID를 유지한 채 이름만 갱신해 사용자의 권한·소리 선택과 예약을 보존한다.
  // 함수이름: updateLanguage
  // 함수역할: 알림 언어를 앱 언어 규칙으로 정규화하고 해당 언어의 Android 채널을 준비한다.
  // 매개변수: language (String): 요청한 언어 또는 언어 모드.
  // 반환값: 채널 갱신 완료 Future. 준비 오류는 전파한다.
  Future<void> updateLanguage(String language) {
    _notificationLanguage = resolveAppLanguage(language);
    return _ensureAndroidNotificationChannels();
  }

  // 함수이름: _createAndroidNotificationChannels
  // 함수역할: 현재 언어로 Android 알림 채널을 만들고 도중에 언어가 바뀌면 반복한다. 플랫폼 오류는 후속 재시도를 위해 완료 표시 없이 흡수한다.
  // 매개변수: 없음.
  // 반환값: Future<void>: 채널 생성 시도 완료; Android 구현이 없으면 준비 완료로 처리한다.
  Future<void> _createAndroidNotificationChannels() async {
    _channelsInitialized = false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) {
        _channelLanguage = _notificationLanguage;
        _channelsInitialized = true;
        return;
      }
      do {
        final language = _notificationLanguage;
        final english = language == 'en';
        final channels = <AndroidNotificationChannel>[
          AndroidNotificationChannel(
            _medicationChannelId,
            english ? 'Medication reminders' : '복약 알림',
            description: english
                ? 'MedBuddy medication time reminders'
                : 'MedBuddy 복약 시간 알림',
            importance: Importance.high,
          ),
          AndroidNotificationChannel(
            _caregiverChannelId,
            english ? 'Caregiver medication updates' : '보호자 복약 확인',
            description: english
                ? 'Medication completion and missed-dose updates for linked patients'
                : '연동된 환자의 복약 완료 및 미복용 상태 알림',
            importance: Importance.high,
          ),
          AndroidNotificationChannel(
            _chatChannelId,
            english ? 'Family chat' : '가족 채팅',
            description: english
                ? 'New chat messages between linked patients and caregivers'
                : '연동된 환자와 보호자의 새 채팅 메시지 알림',
            importance: Importance.high,
          ),
        ];
        for (final channel in channels) {
          await android.createNotificationChannel(channel);
        }
        _channelLanguage = language;
        // 생성 중 언어가 바뀌었으면 마지막 선택으로 세 채널을 모두 맞춘다.
      } while (_channelLanguage != _notificationLanguage);
      _channelsInitialized = true;
    } catch (_) {
      // Channels are still created lazily when a local notification is shown.
    }
  }

  // 함수이름: _handleNotificationResponse
  // 함수역할: 복약 확인 동작은 백그라운드 처리기로 보내고 나머지는 공통 알림 선택 처리기로 전달한다.
  // 매개변수: response (NotificationResponse): 플랫폼이 전달한 페이로드·동작·알림 ID.
  // 반환값: void; 복약 확인 작업은 기다리지 않고 시작한다.
  static void _handleNotificationResponse(NotificationResponse response) {
    if (_isRepeatedActionCopy(response)) return;
    if (response.actionId == SlotCheckNotificationContext.actionId) {
      unawaited(medBuddySlotCheckNotificationBackground(response));
      return;
    }
    handleNotificationPayload(
      response.payload,
      actionId: response.actionId,
      notificationId: response.id,
    );
  }

  // Function Name: handleNotificationResponseForTest
  // Description: Runs the platform response handler, including the duplicate-copy check.
  // Parameters: response (NotificationResponse): platform response to dispatch.
  // Returns: void.
  @visibleForTesting
  static void handleNotificationResponseForTest(
    NotificationResponse response,
  ) => _handleNotificationResponse(response);

  // Function Name: _isRepeatedActionCopy
  // Description: Recognises the second delivery of one action-button press (launch details and response callback).
  // Parameters: response (NotificationResponse): platform response; plain notification taps are never treated as copies.
  // Returns: bool: true when the same button of the same notification was handled within the copy window.
  static bool _isRepeatedActionCopy(NotificationResponse response) {
    final actionId = response.actionId;
    if (actionId == null || actionId.isEmpty) return false;
    final key = '${response.id}|$actionId|${response.payload}';
    final now = clock();
    final last = _lastActionAt;
    if (key == _lastActionKey &&
        last != null &&
        now.difference(last).abs() < _actionCopyWindow) {
      return true;
    }
    _lastActionKey = key;
    _lastActionAt = now;
    return false;
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

  // 함수이름: registerNotification
  // 함수역할: 호출 시점의 사용자와 복용 날짜 복사본으로 알림 재조정을 순차 실행한다.
  // 매개변수: id (int): 기본 예약 ID; slotKey/slotTitle (String): 시간대 키·표시명; hour/minute (int): 현지 시각; activeDates (List<DateTime>): 복용 날짜; language (String): 알림 언어.
  // 반환값: Future<void>: 예약 재조정 완료; 예약 오류는 전파된다.
  Future<void> registerNotification({
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<DateTime> activeDates,
    String language = 'ko',
  }) {
    final owner = _historyUserHash;
    return _serializeReminder(
      () => _reconcileReminder(
        owner: owner,
        id: id,
        slotKey: slotKey,
        slotTitle: slotTitle,
        hour: hour,
        minute: minute,
        activeDates: List.of(activeDates),
        language: language,
      ),
    );
  }

  // 날짜별 예약 계획을 보존해 동일한 예약과 사용자가 미룬 알림은 건드리지 않는다.
  // Function Name: _reconcileReminder
  // Description: Reconciles dated reminders against persisted signatures and native pending requests, retaining eligible snoozes and falling back to inexact alarms when exact scheduling fails.
  // Parameters: owner (String?): Session guard; id (int): Base ID; slotKey/slotTitle/language (String): Slot and text; hour/minute (int): Wall time; activeDates (List<DateTime>): Desired course dates.
  // Returns: Completion after scheduling and plan persistence; owner changes stop further work. Already-created inbox entries are recorded even after partial failure; other errors propagate.
  Future<void> _reconcileReminder({
    required String? owner,
    required int id,
    required String slotKey,
    required String slotTitle,
    required int hour,
    required int minute,
    required List<DateTime> activeDates,
    required String language,
  }) async {
    await initialize();
    if (owner != _historyUserHash) return;
    final preferences = await preferencesLoader();
    await preferences.reload();
    if (owner != _historyUserHash) return;
    final planKey = reminderPlanKey(owner, slotKey);
    Map<String, dynamic> previous = {};
    try {
      previous = Map<String, dynamic>.from(
        jsonDecode(preferences.getString(planKey) ?? '{}'),
      );
    } catch (_) {
      // 손상된 계획은 실제 기기 예약을 확인한 뒤 다시 작성한다.
    }
    final pending = {
      for (final request in await _plugin.pendingNotificationRequests())
        if (request.id == id ||
            (request.payload?.startsWith('schedule:$slotKey:') ?? false))
          request.id: request,
    };
    final now = timezone.TZDateTime.from(clock(), timezone.local);
    final uniqueDates = <String, DateTime>{};
    for (final activeDate in activeDates) {
      final normalizedDate = DateTime(
        activeDate.year,
        activeDate.month,
        activeDate.day,
      );
      uniqueDates[formatJsonDate(normalizedDate)!] = normalizedDate;
    }
    final sortedDates = uniqueDates.values.toList(growable: false)..sort();
    final desiredIds = {
      for (final date in sortedDates) _notificationIdForDate(id, slotKey, date),
    };
    for (final staleId in pending.keys.where(
      (key) =>
          !desiredIds.contains(key) &&
          !_mayBeLiveSnoozeFromYesterday(pending[key]!, now),
    )) {
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
        final body = medicationReminderBody(
          slotKey,
          isEnglish: isEnglishLanguage(language),
        );
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
          hour,
          minute,
          slotTitle,
          language,
          body,
          _inexactScheduleMarker,
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

  // Function Name: _canScheduleExactAlarmsSafely
  // Description: Check exact-alarm capability while treating capability-query failures as unavailable.
  // Parameters: None.
  // Returns: Future<bool>: false on any query error.
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

  // Function Name: _notificationIdForDate
  // Description: Derive a stable per-date reminder ID from the base ID, slot and calendar date.
  // Parameters: baseId (int): base reminder ID; slotKey (String): slot; date (DateTime): reminder day.
  // Returns: int: positive hash-derived notification ID; collisions remain possible.
  int _notificationIdForDate(int baseId, String slotKey, DateTime date) {
    final hash = fnv1a31('$baseId|$slotKey|${formatJsonDate(date)!}');
    return 100000 + (hash % 2000000000);
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
  // - owner (String?): expected history owner, rechecked before scheduling to reject work from an obsolete account.
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
    final title = medicationReminderTitle(
      slotKey,
      slotTitle: slotTitle,
      isEnglish: isEnglishLanguage(language),
    );
    final unsignedPayload =
        'schedule:$slotKey:$id:${formatJsonDate(scheduleDate ?? scheduledDate)!}';
    // 다른 앱도 알림 동작과 같은 인텐트를 보낼 수 있으므로, 빠른 동작이 있는 알림은 이 앱만 아는
    // 키로 서명해 둔다. 필요시 확인 알림은 빠른 동작이 없어 서명하지 않는다.
    final payload = slotKey == 'as_needed'
        ? unsignedPayload
        : '$unsignedPayload:${await MedicationReminderActionTag.sign(owner: owner ?? '', payload: unsignedPayload)}';
    if (owner != _historyUserHash) return null;

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _medicationChannelId,
          isEnglishLanguage(language) ? 'Medication reminders' : '복약 알림',
          channelDescription: isEnglishLanguage(language)
              ? 'MedBuddy medication time reminders'
              : 'MedBuddy 복약 시간 알림',
          importance: Importance.high,
          priority: Priority.high,
          groupKey: _reminderGroupKey(slotKey),
          actions: slotKey == 'as_needed'
              ? const []
              : <AndroidNotificationAction>[
                  AndroidNotificationAction(
                    markSlotTakenActionId,
                    isEnglishLanguage(language) ? 'Taken' : '복용했어요',
                    showsUserInterface: true,
                  ),
                  AndroidNotificationAction(
                    snoozeTenMinutesActionId,
                    isEnglishLanguage(language)
                        ? 'Remind in 10 min'
                        : '10분 후 다시 알림',
                    showsUserInterface: true,
                  ),
                ],
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: scheduleMode,
      payload: payload,
    );
    return NotificationInboxEntry(
      id: 'reminder:$id:${scheduledDate.millisecondsSinceEpoch}',
      title: title,
      body: body,
      payload: unsignedPayload,
      category: NotificationInboxCategory.medication,
      occurredAt: scheduledDate,
    );
  }

  // Function Name: _mayBeLiveSnoozeFromYesterday
  // Description: Reports whether a pending reminder may be yesterday's snooze that has not fired
  //   yet. A snooze is only set on the reminder of its own day and fires after ten minutes, so it
  //   can outlive midnight only briefly; the hour allows for an inexact alarm firing late. Every
  //   other earlier-day entry is an alarm Android dropped (a force-stopped app) that the plugin
  //   still lists and would re-arm at the next reboot or update, so it is cancelled.
  // Parameters:
  // - request (PendingNotificationRequest): Pending platform reminder.
  // - now (DateTime): Current local time.
  // Returns: True for yesterday's reminder during the first hour of today.
  static bool _mayBeLiveSnoozeFromYesterday(
    PendingNotificationRequest request,
    DateTime now,
  ) {
    final date = MedicationNotificationPayloadCodec.decode(
      request.payload,
    )?.scheduleDate;
    if (date == null) return false;
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    // Compare the wall clock of now, not instants: now is in the reminder time zone, while
    // DateTime() would build midnight in the system zone, which can differ.
    final minutesSinceMidnight = now.hour * 60 + now.minute;
    return DateTime(date.year, date.month, date.day) == yesterday &&
        minutesSinceMidnight < _snoozeGraceAfterMidnight.inMinutes;
  }

  static const Duration _snoozeGraceAfterMidnight = Duration(hours: 1);

  // 함수이름: snoozeMedicationReminder
  // 함수역할: 선택한 복약 알림의 미루기 예약을 다른 예약 변경과 순차 실행한다.
  // 매개변수: id (int): 알림 ID; slotKey/slotTitle (String): 시간대 키·표시명; language (String): 표시 언어; delay (Duration): 기본 10분 지연; scheduleDate (DateTime?): 원래 복용 날짜.
  // 반환값: Future<void>: 미루기 처리 완료; 예약 오류는 전파된다.
  Future<void> snoozeMedicationReminder({
    required int id,
    required String slotKey,
    required String slotTitle,
    String language = 'ko',
    Duration delay = const Duration(minutes: 10),
    DateTime? scheduleDate,
  }) => _serializeReminder(
    () => _snoozeMedicationReminder(
      id: id,
      slotKey: slotKey,
      slotTitle: slotTitle,
      language: language,
      delay: delay,
      scheduleDate: scheduleDate,
    ),
  );

  // Function Name: _snoozeMedicationReminder
  // Description: Schedules a delayed reminder while retaining its original dose date, with exact-to-inexact fallback and inbox recording.
  // Parameters: id (int): Reminder ID; slotKey/slotTitle/language (String): Content; delay (Duration): Offset from now; scheduleDate (DateTime?): Original dose day.
  // Returns: Scheduling/inbox completion; an ownership rejection produces no entry and unrecovered platform/storage errors propagate.
  Future<void> _snoozeMedicationReminder({
    required int id,
    required String slotKey,
    required String slotTitle,
    required String language,
    required Duration delay,
    DateTime? scheduleDate,
  }) async {
    final owner = _historyUserHash;
    await initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final scheduledDate = now.add(delay);
    final originalDate = scheduleDate ?? now;
    final body = medicationReminderBody(
      slotKey,
      isEnglish: isEnglishLanguage(language),
    );
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
  // 함수이름: cancelReminderForDate
  // 함수역할: 직렬화한 작업에서 현재 활성 계정을 재확인하며 특정 날짜·시간대의 예정·표시 알림과 알림함 예정 항목을 지운다.
  // 매개변수: owner/slotKey (String): 계정·정기 시간대; date (DateTime): 완료한 복약 날짜.
  // 반환값: 취소 완료 Future. 빈 계정·잘못된 시간대·계정 변경은 무시하고 플러그인·저장소 오류는 전파한다.
  Future<void> cancelReminderForDate({
    required String owner,
    required String slotKey,
    required DateTime date,
  }) => _serializeReminder(() async {
    if (owner.trim().isEmpty || !medicationScheduleSlotKeys.contains(slotKey)) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    // 함수이름: stillActive
    // 함수역할: 각 알림 취소 전에 설정을 새로 읽어 요청 계정이 아직 활성인지 확인한다.
    // 매개변수: 없음. 바깥 작업의 preferences와 owner를 사용한다.
    // 반환값: 활성 계정 키가 owner와 같으면 true인 Future. 설정 읽기 오류는 전파한다.
    Future<bool> stillActive() async {
      await preferences.reload();
      return preferences.getString(NotificationInboxStore.activeUserKey) ==
          owner;
    }

    if (!await stillActive()) return;
    await initialize();
    final baseId = MedicationAlarm.defaults(
      slotKey,
    ).copyWith(patientHash: owner).notificationId;
    final id = _notificationIdForDate(baseId, slotKey, date);
    if (!await stillActive()) return;
    await _plugin.cancel(id: id);
    // Android가 표시 중인 알림의 payload를 반환하지 않아 날짜별 ID로 구분한다.
    for (final notification in await _plugin.getActiveNotifications()) {
      if (notification.id == id &&
          notification.channelId == _medicationChannelId) {
        if (!await stillActive()) return;
        await _plugin.cancel(id: id, tag: notification.tag);
      }
    }
    await _inboxStore(owner).cancelFutureReminders(id: id);
  });

  // 함수이름: _cancelReminder
  // 함수역할: 알림함 예정 항목을 정리하고 ID 또는 시간대에 속한 예정·표시 알림을 취소한다.
  // 매개변수: id (int): 기본 알림 ID; slotKey (String?): 시간대가 있으면 날짜별·기존 형식 알림도 함께 정리한다.
  // 반환값: 완료 Future. 다른 시간대·채널은 보존하며 초기화·플랫폼 오류는 전파한다.
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
        legacyIds.add(
          _notificationIdForDate(
            id,
            slotKey,
            DateTime(now.year, now.month, now.day - day),
          ),
        );
      }
      for (final notification in activeNotifications) {
        final notificationId = notification.id;
        final androidMatch =
            notification.channelId == _medicationChannelId &&
            (notification.groupKey == _reminderGroupKey(slotKey) ||
                (notification.groupKey == null &&
                    legacyIds.contains(notificationId)));
        if (notificationId != null &&
            (androidMatch ||
                (notification.payload?.startsWith('schedule:$slotKey:') ??
                    false))) {
          await _plugin.cancel(id: notificationId, tag: notification.tag);
        }
      }
      return;
    }
    await _plugin.cancel(id: id);
    await _rememberLegacyReminderCancelled(id);
  }

  // Function Name: _rememberLegacyReminderCancelled
  // Description: Track canceled legacy slot IDs and persist a migration marker once all are canceled; log persistence failure.
  // Parameters: id (int): successfully canceled notification ID.
  // Returns: Future<void>: marker attempt completion; unrelated IDs are ignored.
  Future<void> _rememberLegacyReminderCancelled(int id) async {
    final legacyIds = {
      for (final slotKey in medicationScheduleSlotKeys)
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

  // 함수이름: cancelAllMedicationReminders
  // 함수역할: 모든 복약 알림 취소를 예약 작업 대기열에서 순서대로 처리한다.
  // 매개변수: 없음.
  // 반환값: Future<void>: 취소 처리 완료; 처리 오류는 전파된다.
  Future<void> cancelAllMedicationReminders() =>
      _serializeReminder(_cancelAllMedicationReminders);

  // Function Name: _cancelAllMedicationReminders
  // Description: Clears session-related pending and delivered medication/caregiver/chat notifications, legacy reminders, and a pending navigation selection.
  // Parameters: None.
  // Returns: Cleanup completion; unrelated notification channels/payloads remain and plugin/inbox errors propagate.
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
                _medicationChannelId,
                _caregiverChannelId,
                _chatChannelId,
              }.contains(notification.channelId))) {
        await _plugin.cancel(id: notificationId, tag: notification.tag);
      }
    }
    await _cancelLegacySlotReminders();
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

  // Function Name: _cancelAllScheduledMedicationReminders
  // Description: Removes scheduled and delivered medication reminders, including snooze shortcuts and legacy slot IDs, while retaining other notification categories.
  // Parameters: None.
  // Returns: Cancellation completion; platform/inbox errors propagate.
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
          (notification.channelId == _medicationChannelId ||
              (notification.payload ?? '').startsWith('schedule:'))) {
        await _plugin.cancel(id: id, tag: notification.tag);
      }
    }
    await _cancelLegacySlotReminders();
  }

  // Function Name: _cancelLegacySlotReminders
  // Description: Cancel every legacy slot notification and record completion of the legacy-ID migration.
  // Parameters: None.
  // Returns: Future<void>: platform cancellation completion; platform errors propagate.
  Future<void> _cancelLegacySlotReminders() async {
    for (final slotKey in medicationScheduleSlotKeys) {
      final legacyId = MedicationAlarm.legacyNotificationIdForSlot(slotKey);
      await _plugin.cancel(id: legacyId);
      await _rememberLegacyReminderCancelled(legacyId);
    }
  }

  // Function Name: _reminderGroupKey
  // Description: Build the platform grouping key for one medication slot.
  // Parameters: slotKey (String): medication slot.
  // Returns: String: reminder group key.
  String _reminderGroupKey(String slotKey) => 'medbuddy.reminder.$slotKey';

  // 함수이름: showCaregiverAlert
  // 함수역할: 환자의 복약 체크 변화를 보호자 기기의 즉시 로컬 알림으로 표시한다.
  // 매개변수:
  // - id (int): 중복 알림을 교체하기 위한 고정 알림 식별자
  // - title (String): 보호자 알림 제목
  // - body (String): 보호자에게 보여줄 복약 상태 설명
  // - patientHash (String?): 알림을 누를 때 열어야 하는 환자 식별 hash
  // - language (String): 알림 채널 안내에 사용할 언어 코드
  // - historyUserHash (String?): 기록 소유 계정; 생략하면 현재 알림 계정을 사용한다.
  // - recordHistory (bool): 환자 식별자가 있을 때 알림 내역을 보관할지 여부.
  // - alertContext (CaregiverAlertContext?): 미루기·확인 요청 동작과 상세 이동에 쓸 보호자 알림 문맥.
  // - onlyAlertOnce (bool): Android에서 같은 알림 갱신 시 소리·진동 반복을 억제할지 여부.
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
    bool onlyAlertOnce = false,
  }) async {
    final owner = historyUserHash ?? _historyUserHash;
    await initialize();
    final isEnglish = isEnglishLanguage(language);
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
          _caregiverChannelId,
          isEnglish ? 'Caregiver medication updates' : '보호자 복약 확인',
          onlyAlertOnce: onlyAlertOnce,
          channelDescription: isEnglish
              ? 'Medication completion and missed-dose updates for linked patients'
              : '연동된 환자의 복약 완료 및 미복용 상태 알림',
          importance: Importance.high,
          priority: Priority.high,
          actions: alertContext == null
              ? null
              : [
                  AndroidNotificationAction(
                    caregiverSnoozeActionId,
                    isEnglish ? 'Remind in 10 min' : '10분 후 다시 알림',
                    showsUserInterface: true,
                  ),
                  AndroidNotificationAction(
                    caregiverChatActionId,
                    isEnglish ? 'Send chat request' : '채팅으로 알림',
                    showsUserInterface: true,
                  ),
                ],
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload:
          alertContext?.payload ??
          (patientHash == null || patientHash.trim().isEmpty
              ? null
              : MedicationNotificationPayloadCodec.caregiverPayload(
                  patientHash.trim(),
                )),
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
          payload:
              alertContext?.payload ??
              MedicationNotificationPayloadCodec.caregiverPayload(
                patientHash.trim(),
              ),
          category: NotificationInboxCategory.medication,
          occurredAt: DateTime.now(),
        ),
      );
    }
  }

  // Function Name: showSlotCheckAlert
  // Description: Show a slot-check request only for the persisted active owner, optionally adding a Taken action and inbox history.
  // Parameters: request (SlotCheckNotificationContext): owner and check context; id (int): platform ID; language (String): locale; messagePreview (String?): preview; recordHistory (bool): append history; withTakenAction (bool): include background completion action.
  // Returns: Future<void>: display/history completion or no-op after an owner mismatch; platform errors propagate.
  Future<void> showSlotCheckAlert({
    required SlotCheckNotificationContext request,
    required int id,
    required String language,
    String? messagePreview,
    bool recordHistory = false,
    bool withTakenAction = true,
  }) async {
    await initialize();
    final preferences = await preferencesLoader();
    await preferences.reload();
    if (preferences.getString(NotificationInboxStore.activeUserKey) !=
        request.owner) {
      return;
    }
    final english = isEnglishLanguage(language);
    await _plugin.show(
      id: id,
      title: english ? 'Medication check request' : '복약 확인 요청',
      body: buildLinkedChatNotificationBody(
        messagePreview: messagePreview,
        language: language,
      ),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _chatChannelId,
          english ? 'Family chat' : '가족 채팅',
          importance: Importance.high,
          priority: Priority.high,
          tag: request.eventId,
          onlyAlertOnce: true,
          // 날짜가 지난 요청은 오늘 기록으로 받을 수 없으므로 버튼 없이 채팅만 연다.
          actions: withTakenAction
              ? [
                  AndroidNotificationAction(
                    SlotCheckNotificationContext.actionId,
                    english ? 'Taken' : '복용 완료',
                    showsUserInterface: false,
                    cancelNotification: false,
                  ),
                ]
              : null,
        ),
      ),
      payload: request.payload,
    );
    if (recordHistory) {
      await _recordInbox(
        request.owner,
        NotificationInboxEntry(
          id: 'chat:${request.linkId}:$id',
          title: english ? 'Medication check request' : '복약 확인 요청',
          body: buildLinkedChatNotificationBody(
            messagePreview: messagePreview,
            language: language,
          ),
          payload: MedicationNotificationPayloadCodec.chatPayload(
            request.linkId,
          ),
          category: NotificationInboxCategory.chat,
          occurredAt: DateTime.now(),
        ),
      );
    }
  }

  // Function Name: showLinkedChatAlert
  // Description: Serialize grouped chat notifications with owner, read-watermark and privacy checks; optionally record individual history.
  // Parameters: id (int): history event ID; linkId (int): conversation; language (String): locale; messagePreview (String?): preview; messageKind/slotKey (String?): accepted but currently unused; historyUserHash (String?): expected owner; recordHistory (bool): append history; summary (ChatNotificationSummary?): unread grouping and details policy.
  // Returns: Future<void>: display/history completion; stale, read, empty or wrong-owner summaries are skipped.
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
  }) => _serializeChat(() async {
    final owner = historyUserHash ?? _historyUserHash;
    if (owner != _historyUserHash) return;
    final detailsAllowed =
        _showSensitiveDetails && (summary?.showDetails ?? true);
    final body = buildLinkedChatNotificationBody(
      messagePreview: messagePreview,
      showSensitiveDetails: detailsAllowed,
      language: language,
    );
    await initialize();
    final tag = await ChatNotificationSummary.groupTag(owner ?? '', linkId);
    if (owner != _historyUserHash) return;
    final latestId = summary?.latestMessageId;
    if (latestId != null &&
        latestId > 0 &&
        (latestId < (_chatLatestIds[linkId] ?? 0) ||
            latestId <= (_chatReadIds[linkId] ?? 0))) {
      return;
    }
    if (summary?.count == 0) return;
    final isEnglish = isEnglishLanguage(language);
    final genericTitle = isEnglish ? 'New family message' : '새 가족 메시지';
    // 요약이 없으면(이전 서버, 요약 조회 실패) 개수를 모르므로 개수 없이 이번 메시지만 보인다.
    final count = summary?.count;
    final name = detailsAllowed ? summary?.senderName.trim() ?? '' : '';
    final title = count == null
        ? genericTitle
        : '${name.isEmpty ? genericTitle : name} ($count)';
    final lines = detailsAllowed && summary != null && summary.lines.isNotEmpty
        ? summary.lines.map(linkedChatMessagePreview).toList()
        : [body];
    await _plugin.show(
      id: _chatNotificationId(tag),
      title: title,
      body: lines.last,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _chatChannelId,
          isEnglish ? 'Family chat' : '가족 채팅',
          channelDescription: isEnglish
              ? 'New chat messages between linked patients and caregivers'
              : '연동된 환자와 보호자의 새 채팅 메시지 알림',
          importance: Importance.high,
          priority: Priority.high,
          tag: tag,
          number: count,
          category: AndroidNotificationCategory.message,
          styleInformation: count == null
              ? null
              : InboxStyleInformation(
                  lines,
                  contentTitle: title,
                  summaryText: isEnglish
                      ? '$count unread messages'
                      : '안 읽은 메시지 $count개',
                ),
        ),
        iOS: DarwinNotificationDetails(threadIdentifier: tag),
      ),
      // A dose-check request is still a chat message. Open its conversation;
      // the patient chooses whether to record a dose from there.
      payload: MedicationNotificationPayloadCodec.chatPayload(linkId),
    );
    if (latestId != null) _chatLatestIds[linkId] = latestId;
    if (recordHistory) {
      await _recordInbox(
        owner,
        NotificationInboxEntry(
          id: 'chat:$linkId:$id',
          title: isEnglish ? 'New family message' : '새 가족 메시지',
          body: body,
          payload: MedicationNotificationPayloadCodec.chatPayload(linkId),
          category: NotificationInboxCategory.chat,
          occurredAt: DateTime.now(),
        ),
      );
    }
  });

  // Function Name: buildLinkedChatNotificationBody
  // Description: Use a normalized preview only when details are allowed, otherwise return localized generic chat text.
  // Parameters: messagePreview (String?): raw preview; showSensitiveDetails (bool): privacy policy; language (String): fallback locale.
  // Returns: String: privacy-appropriate notification body.
  static String buildLinkedChatNotificationBody({
    String? messagePreview,
    bool showSensitiveDetails = true,
    String language = 'ko',
  }) {
    final preview = linkedChatMessagePreview(messagePreview);
    if (showSensitiveDetails && preview.isNotEmpty) return preview;
    return isEnglishLanguage(language)
        ? 'You received a new message from a linked family member.'
        : '연동된 가족에게 새 메시지가 도착했습니다.';
  }

  // Function Name: linkedChatMessagePreview
  // Description: Collapse whitespace and limit a preview to 120 grapheme clusters, including an ellipsis when truncated.
  // Parameters: value (String?): message text.
  // Returns: String: normalized preview, empty for null/blank input.
  @visibleForTesting
  static String linkedChatMessagePreview(String? value) {
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
    final characters = normalized.characters;
    if (characters.length <= maximumLength) {
      return normalized;
    }
    return '${characters.take(maximumLength - 1).toString().trimRight()}…';
  }
}

// Class Name: LinkedChatNotificationCleanup
// Role: Adds read-receipt-aware cleanup of linked-chat alerts.
// Responsibilities: Retain newer-message alerts, advance read watermarks, and remove only read slot-check request notifications.
// Attributes: No added fields; uses NotificationService account state, chat ID maps, plugin, and serialization queue.
extension LinkedChatNotificationCleanup on NotificationService {
  // Function Name: clearReadChatAlert
  // Description: Advances the read watermark and removes the grouped alert only if no newer message exists; also clears read Android slot-check tags.
  // Parameters: owner (String): Current account; linkId (int): Conversation; throughMessageId (int): Highest confirmed read message.
  // Returns: Serialized cleanup completion; account changes are ignored and active-notification enumeration failure is tolerated after group cleanup.
  Future<void> clearReadChatAlert({
    required String owner,
    required int linkId,
    required int throughMessageId,
  }) => _serializeChat(() async {
    if (owner != _historyUserHash) return;
    final previous = _chatReadIds[linkId] ?? 0;
    if (throughMessageId > previous) _chatReadIds[linkId] = throughMessageId;
    // 읽음 요청 이후 도착한 새 메시지 알림은 지우지 않는다.
    if ((_chatLatestIds[linkId] ?? 0) > throughMessageId) return;
    final tag = await ChatNotificationSummary.groupTag(owner, linkId);
    if (owner != _historyUserHash) return;
    await _plugin.cancel(id: _chatNotificationId(tag), tag: tag);
    // 보호자의 확인 요청은 메시지별 태그(chat:<연동>:<메시지>)로 따로 표시하므로 읽은 범위의 것도 지운다.
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      for (final active in await _plugin.getActiveNotifications()) {
        final match = RegExp(r'^chat:(\d+):(\d+)$').firstMatch(active.tag ?? '');
        if (match == null ||
            active.channelId != NotificationService._chatChannelId ||
            int.parse(match.group(1)!) != linkId ||
            int.parse(match.group(2)!) > throughMessageId) {
          continue;
        }
        if (owner != _historyUserHash) return;
        await _plugin.cancel(id: active.id ?? 0, tag: active.tag);
      }
    } catch (_) {
      // 표시 중 알림 목록을 읽지 못해도 묶음 채팅 알림 정리는 이미 끝났다.
    }
  });
}

// 표시와 읽음 정리가 같은 알림을 가리키도록 연동별 채팅 알림 ID를 한곳에서 정한다.
// Android는 태그로 구분하므로 ID 0을 쓰고(FCM 알림과 같은 자리), 그 밖에는 태그에서 ID를 만든다.
// Function Name: _chatNotificationId
// Description: Uses Android tags for identity and a numeric hash prefix on other platforms.
// Parameters: tag (String): Valid medbuddy-chat tag generated by ChatNotificationSummary.groupTag.
// Returns: Zero on Android; otherwise a 28-bit hexadecimal prefix. Malformed tags may throw outside Android.
int _chatNotificationId(String tag) =>
    defaultTargetPlatform == TargetPlatform.android
    ? 0
    : int.parse(tag.split('-').last.substring(0, 7), radix: 16);

// 기존 알림 계약과 테스트 대역에 새 의무를 추가하지 않는 기기 알림 확인 기능이다.
// 클래스명: NotificationReadinessDiagnostics
// 역할: 알림 권한·정확 예약 설정·표시 시험을 진단하는 확장이다.
// 주요 책임: 권한 요청 없이 상태를 읽고 시스템 설정으로 이동하거나 복용 기록 없는 시험 알림을 표시한다.
// 속성: 추가 필드 없음. NotificationService의 플러그인·설정 채널·초기화 기능을 사용한다.
extension NotificationReadinessDiagnostics on NotificationService {
  // 함수이름: supportsExactReminderSettings
  // 함수역할: 네이티브 Android에서 정확 알람 설정 화면 지원 여부를 질의한다.
  // 매개변수: 없음.
  // 반환값: 지원이면 true. 웹·다른 플랫폼·null 응답은 false이며 플랫폼 호출 오류는 전파한다.
  Future<bool> supportsExactReminderSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    return await NotificationService._settingsChannel.invokeMethod<bool>(
          'supportsExactReminderSettings',
        ) ??
        false;
  }

  // 켜짐·꺼짐 모두 운영체제 화면에서 변경하고 앱 복귀 시 실제 상태를 다시 읽는다.
  // 함수이름: openExactReminderSettings
  // 함수역할: 정확 알람 허용 상태를 사용자가 바꿀 수 있는 운영체제 설정 화면을 연다.
  // 매개변수: 없음.
  // 반환값: 설정 열기 요청 완료 Future. 웹·비Android는 UnsupportedError이고 플랫폼 오류는 전파한다.
  Future<void> openExactReminderSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Exact reminder settings are unavailable.');
    }
    await NotificationService._settingsChannel.invokeMethod<void>(
      'openExactReminderSettings',
    );
  }

  // 상태 조회는 권한을 요청하지 않는다. 확인 실패를 허용으로 해석하지 않는다.
  // 함수이름: readReadinessPermissions
  // 함수역할: 권한을 요청하지 않고 알림 허용·복약 채널·정확 알람 상태를 조회한다.
  // 매개변수: 없음.
  // 반환값: 각 상태가 bool?인 레코드 Future. 미지원·확인 불가는 null; Android 개별 질의 실패는 흡수하며 초기화·iOS 질의 오류는 전파한다.
  Future<({bool? notifications, bool? medicationChannel, bool? exactAlarms})>
  readReadinessPermissions() async {
    if (kIsWeb) {
      return (notifications: null, medicationChannel: null, exactAlarms: null);
    }
    await initialize();
    bool? notifications;
    bool? medicationChannel;
    bool? exactAlarms;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      try {
        notifications = await android?.areNotificationsEnabled();
      } catch (_) {}
      try {
        final channels = await android?.getNotificationChannels();
        if (channels != null) {
          for (final channel in channels) {
            if (channel.id == NotificationService._medicationChannelId) {
              medicationChannel = channel.importance != Importance.none;
              break;
            }
          }
        }
      } catch (_) {}
      try {
        exactAlarms = await android?.canScheduleExactNotifications();
      } catch (_) {}
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final permissions = await ios?.checkPermissions();
      notifications = permissions?.isAlertEnabled;
    }
    return (
      notifications: notifications,
      medicationChannel: medicationChannel,
      exactAlarms: exactAlarms,
    );
  }

  // 복약 채널로 즉시 표시만 시험한다. 복용 동작·이동 payload·알림함 기록은 만들지 않는다.
  // Function Name: showReadinessTestNotification
  // Description: Shows an immediate medication-channel display test only after notification permission is positively confirmed, without dose actions or history entries.
  // Parameters: language (String): Localized test title/body selection.
  // Returns: Display completion; unsupported platforms throw UnsupportedError, unknown/denied permissions throw StateError, and plugin failures propagate.
  Future<void> showReadinessTestNotification({String language = 'ko'}) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw UnsupportedError('Notification test is unavailable.');
    }
    final permissions = await readReadinessPermissions();
    if (permissions.notifications != true ||
        (defaultTargetPlatform == TargetPlatform.android &&
            permissions.medicationChannel != true)) {
      throw StateError('Notification permission could not be confirmed.');
    }
    final english = isEnglishLanguage(language);
    await _plugin.show(
      id: -17023,
      title: english ? 'MedBuddy test notification' : 'MedBuddy 테스트 알림',
      body: english
          ? 'Display check only. No medication record is changed.'
          : '표시 확인용입니다. 복용 기록은 변경되지 않습니다.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationService._medicationChannelId,
          english ? 'Medication reminders' : '복약 알림',
          importance: Importance.high,
          priority: Priority.high,
          tag: 'medbuddy_readiness_test',
          timeoutAfter: 60000,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}
