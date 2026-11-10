// 파일명: push_notification_service.dart
// 역할: Firebase 푸시 토큰 등록, 갱신, 수신과 선택 동작을 관리한다.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/notification_inbox_entity.dart';
import '../entities/caregiver_alert_context_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/medication_slot_label.dart';
import '../entities/user_setting_entity.dart';
import 'caregiver_alert_delivery_service.dart';
import 'api_config.dart';
import 'auth_config.dart';
import 'notification_service.dart';
import 'medication_notification_payload_codec.dart';
import 'notification_inbox_store.dart';
import 'user_setting_preference_keys.dart';
import 'slot_check_notification_context.dart';
import 'slot_check_notification_service.dart';

// 보호자 알림으로 처리하는 FCM 메시지 유형. 수신 저장·표시·선택 처리가 같은 목록을 쓴다.
const Set<String> _caregiverMessageTypes = {
  'caregiver_slot_completed',
  'caregiver_dose_completed',
  'caregiver_slot_missed',
};

// 재전송된 필요시 복용 푸시는 FCM 메시지 ID가 달라도 같은 알림으로 묶는다.
// 함수이름: _asNeededPushIdentity
// 함수역할: 필요시 복용 완료 푸시의 유형·시간대·이벤트 해시를 검증해 중복 구분 키를 만든다.
// 매개변수: message (RemoteMessage): 수신한 FCM 데이터 메시지.
// 반환값: 유효한 caregiver_dose_completed/as_needed 이벤트면 접두사 키, 아니면 null.
String? _asNeededPushIdentity(RemoteMessage message) {
  final key = message.data['event_key']?.toString() ?? '';
  return message.data['type'] == 'caregiver_dose_completed' &&
          message.data['slot_key'] == 'as_needed' &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(key)
      ? 'as-needed:$key'
      : null;
}

// Function Name: _slotCompletionEventKey
// Description: Validates a scheduled-slot completion push and its lowercase 64-hex server event key.
// Parameters: message (RemoteMessage): Received FCM data message.
// Returns: Event key for caregiver_slot_completed with a known regular slot; otherwise null.
String? _slotCompletionEventKey(RemoteMessage message) {
  final key = message.data['event_key']?.toString() ?? '';
  return message.data['type'] == 'caregiver_slot_completed' &&
          medicationScheduleSlotKeys.contains(message.data['slot_key']) &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(key)
      ? key
      : null;
}

// 함수이름: _completionPushIdentity
// 함수역할: 정기 시간대 완료를 우선 확인하고 필요시 완료 이벤트도 같은 중복 방지 경로로 구분한다.
// 매개변수: message (RemoteMessage): 수신 FCM 메시지.
// 반환값: 유형별 접두사가 붙은 검증된 이벤트 키 또는 대상이 아니면 null.
String? _completionPushIdentity(RemoteMessage message) {
  final key = _slotCompletionEventKey(message);
  return key == null ? _asNeededPushIdentity(message) : 'slot-completed:$key';
}

// 서버 재시도는 FCM 메시지 ID가 매번 바뀌므로 서버가 보낸 고정 event_id를 먼저 쓴다.
// 같은 채팅 메시지·보호자 알림이 알림함과 시스템 알림에 두 번 쌓이지 않게 한다.
// Function Name: _serverEventIdentity
// Description: Extracts the optional server event identifier without interpreting or authenticating its format.
// Parameters: message (RemoteMessage): Received FCM message.
// Returns: Trimmed event_id text, or null when absent/blank.
String? _serverEventIdentity(RemoteMessage message) {
  final eventId = message.data['event_id']?.toString().trim() ?? '';
  return eventId.isEmpty ? null : eventId;
}

// 함수이름: recordPushNotificationHistory
// 함수역할: 수신자가 현재 계정인 지원 푸시를 내역에 저장하고 서버의 내용 숨김 결정을 보존한다. 실패는 로그에 남기고 흡수한다.
// 매개변수: message (RemoteMessage): 수신 푸시; userHash (String?): 활성 계정 대체 값; language (String?): 페이로드 언어 대체 값; markRead (bool): 저장 후 읽음 처리 여부.
// 반환값: Future<void>: 저장·읽음 처리 시도 완료; 미지원·잘못된 수신 정보는 건너뛴다.
Future<void> recordPushNotificationHistory(
  RemoteMessage message, {
  String? userHash,
  String? language,
  bool markRead = false,
}) async {
  try {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final active =
        userHash ?? preferences.getString(NotificationInboxStore.activeUserKey);
    final recipient = message.data['recipient_hash']?.toString().trim();
    if (active == null ||
        active.isEmpty ||
        (recipient != null && recipient != active) ||
        recipient == null) {
      return;
    }
    final type = message.data['type'];
    final english = isEnglishLanguage(
      language ?? message.data['language']?.toString(),
    );
    late final String payload;
    late final String title;
    late final String body;
    late final NotificationInboxCategory category;
    if (type == 'linked_chat_message') {
      final linkId = int.tryParse(message.data['link_id']?.toString() ?? '');
      if (linkId == null || linkId < 1) return;
      payload = MedicationNotificationPayloadCodec.chatPayload(linkId);
      title = english ? 'New family message' : '새 가족 메시지';
      // 빈 message_preview는 서버의 내용 숨김 결정이므로 notification 본문으로 우회하지 않는다.
      final preview = message.data.containsKey('message_preview')
          ? message.data['message_preview']?.toString()
          : message.notification?.body;
      body = NotificationService.buildLinkedChatNotificationBody(
        messagePreview: preview,
        language: english ? 'en' : 'ko',
      );
      category = NotificationInboxCategory.chat;
    } else if (_caregiverMessageTypes.contains(type)) {
      final patient = message.data['patient_hash']?.toString().trim() ?? '';
      if (patient.isEmpty) return;
      payload = MedicationNotificationPayloadCodec.caregiverPayload(patient);
      final showDetails =
          preferences.getString(
            UserSettingPreference.notificationDetailMode.keyFor(active.trim()),
          ) !=
          'type_only';
      final deliveredTitle = message.notification?.title?.trim() ?? '';
      final deliveredBody = message.notification?.body?.trim() ?? '';
      // 서버가 숨긴 내용은 payload의 시간대·유형으로 다시 생성하지 않는다.
      title = showDetails && deliveredTitle.isNotEmpty
          ? deliveredTitle
          : english
          ? 'Medication update'
          : '복약 상태 알림';
      body = showDetails && deliveredBody.isNotEmpty
          ? deliveredBody
          : english
          ? 'Check your linked patient\'s medication status.'
          : '연동된 환자의 복약 상태를 확인해 주세요.';
      category = NotificationInboxCategory.medication;
    } else {
      return;
    }
    final entry = NotificationInboxEntry(
      id: 'push:${_completionPushIdentity(message) ?? _serverEventIdentity(message) ?? message.messageId ?? '$type:$payload:${message.sentTime?.millisecondsSinceEpoch ?? 0}'}',
      title: title,
      body: body,
      payload: payload,
      category: category,
      occurredAt: message.sentTime ?? DateTime.now(),
    );
    final store = NotificationInboxStore(userHash: active);
    await store.record(entry);
    if (markRead) await store.markRead([entry.id]);
  } catch (error, stack) {
    developer.log(
      '푸시 알림 내역 저장 실패',
      name: 'PushNotificationService',
      error: error,
      stackTrace: stack,
    );
  }
}

// 함수이름: medBuddyPushBackgroundHandler
// 함수역할: 앱 비활성 중 수신된 푸시도 같은 계정 알림함에 기록한다.
// 매개변수: message. 반환값: 기록 완료. Firebase API는 사용하지 않는다.
@pragma('vm:entry-point')
Future<void> medBuddyPushBackgroundHandler(RemoteMessage message) async {
  if (SlotCheckNotificationContext.fromData(message.data) != null) {
    await recordPushNotificationHistory(message);
    await SlotCheckNotificationService.display(message.data);
    return;
  }
  if (message.data['type'] == 'caregiver_slot_missed' &&
      message.data['action_version'] == '1') {
    await CaregiverAlertDeliveryService.display(message.data);
    return;
  }
  await recordPushNotificationHistory(message);
  final key = _slotCompletionEventKey(message);
  if (key != null && message.notification != null) {
    // 백그라운드에서는 OS가 이미 표시했으므로 이후 전경 재수신 때 다시 울리지 않는다.
    await CaregiverAlertDeliveryService.presentCompletionOnce(
      recipientHash: message.data['recipient_hash']?.toString() ?? '',
      eventKey: key,
      present: () async {},
    );
  }
}

// Function Name: registerMedBuddyPushBackgroundHandler
// Description: Registers the top-level FCM background entry point only when Firebase authentication mode is enabled.
// Parameters: None.
// Returns: Nothing; disabled/local mode leaves the messaging background handler unchanged.
void registerMedBuddyPushBackgroundHandler() {
  if (AuthConfig.mode == AuthenticationMode.firebase) {
    FirebaseMessaging.onBackgroundMessage(medBuddyPushBackgroundHandler);
  }
}

// Class Name: PushMessagingPlatform
// Role: Adapt Firebase Messaging to the push-service boundary.
// Responsibilities: Expose token lifecycle, message streams, permission requests and background registration.
// Attributes: _injectedMessaging (FirebaseMessaging?): optional instance override; static Firebase streams remain platform-wide.
class PushMessagingPlatform {
  final FirebaseMessaging? _injectedMessaging;

  // Function Name: PushMessagingPlatform
  // Description: Use an injected messaging instance or resolve the Firebase singleton lazily.
  // Parameters: messaging (FirebaseMessaging?): instance override.
  // Returns: PushMessagingPlatform: messaging adapter.
  const PushMessagingPlatform({FirebaseMessaging? messaging})
    : _injectedMessaging = messaging;

  // Function Name: _messaging
  // Description: Selects the injected messaging dependency for tests or the runtime Firebase singleton.
  // Parameters: None.
  // Returns: Injected FirebaseMessaging instance, otherwise FirebaseMessaging.instance.
  FirebaseMessaging get _messaging =>
      _injectedMessaging ?? FirebaseMessaging.instance;

  // Function Name: enabled
  // Description: Check whether Firebase authentication mode enables push integration.
  // Parameters: None.
  // Returns: bool: true only for firebase mode.
  bool get enabled => AuthConfig.mode == AuthenticationMode.firebase;

  // Function Name: registerBackgroundHandler
  // Description: Register the app's top-level Firebase background message handler.
  // Parameters: None.
  // Returns: void.
  void registerBackgroundHandler() =>
      FirebaseMessaging.onBackgroundMessage(medBuddyPushBackgroundHandler);

  // Function Name: requestPermission
  // Description: Request alert, badge and sound permissions from Firebase Messaging.
  // Parameters: None.
  // Returns: Future<void>: permission request completion; the returned authorization setting is not exposed.
  Future<void> requestPermission() =>
      _messaging.requestPermission(alert: true, badge: true, sound: true);

  // Function Name: deleteToken
  // Description: Delete the current device's Firebase push token.
  // Parameters: None.
  // Returns: Future<void>: deletion completion; platform errors propagate.
  Future<void> deleteToken() => _messaging.deleteToken();

  // Function Name: getToken
  // Description: Fetch the device push token from the messaging instance.
  // Parameters: None.
  // Returns: Future<String?>: token, or null when unavailable; platform errors propagate.
  Future<String?> getToken() => _messaging.getToken();

  // Function Name: onTokenRefresh
  // Description: Expose refreshed device push tokens.
  // Parameters: None.
  // Returns: Stream<String>: token updates from the messaging instance.
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  // Function Name: onMessage
  // Description: Expose foreground Firebase messages.
  // Parameters: None.
  // Returns: Stream<RemoteMessage>: platform-wide foreground events.
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  // Function Name: onMessageOpenedApp
  // Description: Expose messages that opened the app from the background.
  // Parameters: None.
  // Returns: Stream<RemoteMessage>: platform-wide notification-open events.
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  // Function Name: getInitialMessage
  // Description: Fetch the notification message that launched a terminated app.
  // Parameters: None.
  // Returns: Future<RemoteMessage?>: launch message or null.
  Future<RemoteMessage?> getInitialMessage() => _messaging.getInitialMessage();
}

// 클래스명: PushNotificationService
// 역할: 서버 푸시 등록과 전경 보호자 알림 표시를 앱 생명주기에 맞춰 처리한다.
// 주요 책임:
// - 로그인한 기기의 FCM 토큰을 백엔드에 등록한다.
// - 등록에 실패하면 수신 구독은 유지한 채 간격을 늘려 가며 다시 시도한다.
// - Firebase가 토큰을 갱신하면 서버 등록값도 교체한다.
// - 앱이 열려 있을 때 수신한 보호자 알림을 로컬 알림으로 표시한다.
// - 로그아웃 시 현재 기기 토큰을 서버에서 비활성화한다.
// 속성:
// - _requestTimeout (Duration): 식별·분석 요청의 최대 대기시간
// - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
// - _client (http.Client): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
// - _languageProvider (String Function()): 알림 생성 시점의 언어 조회 경계
// - _platform (PushMessagingPlatform): FCM 권한·토큰·수신 경계
// - retryBaseDelay (Duration): 시작 실패 뒤 첫 재시도까지의 간격; 실패할 때마다 두 배가 된다.
// - retryMaxDelay (Duration): 재시도 간격의 상한
class PushNotificationService {
  static const Duration _requestTimeout = Duration(seconds: 10);

  final String userHash;
  final http.Client _client;
  final String Function() _languageProvider;
  final PushMessagingPlatform _platform;
  final Duration retryBaseDelay;
  final Duration retryMaxDelay;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedMessageSubscription;
  String? _registeredToken;
  // 이 기기 토큰이 서버에 등록되어 있을 수 있는지 여부. 이전 실행에서 등록했을 수 있으므로 true로
  // 시작하고, 서버 해제나 기기 토큰 폐기가 끝나면 false가 된다.
  bool _platformTokenMayBeRegistered = true;
  bool _started = false;
  bool _stopping = false;
  // 시작 단계별 완료 여부. 재시도는 끝내지 못한 단계만 다시 수행한다.
  bool _listening = false;
  bool _initialMessageChecked = false;
  bool _permissionRequested = false;
  bool _registrationPending = true;
  Future<void>? _startOperation;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  // 같은 토큰의 등록 요청이 겹치면 진행 중인 요청 하나를 함께 기다린다.
  final Map<String, Future<void>> _pendingTokenRegistrations =
      <String, Future<void>>{};

  // Function Name: PushNotificationService
  // Description: Bind one user's push registration to a borrowed HTTP client and replaceable messaging platform.
  // Parameters: userHash (String): owner; client (http.Client): borrowed API transport; messaging (FirebaseMessaging?): default adapter override; languageProvider (String Function()?): display locale; platform (PushMessagingPlatform?): complete adapter override; retryBaseDelay/retryMaxDelay (Duration): retry bounds.
  // Returns: PushNotificationService: unstarted service.
  PushNotificationService({
    required this.userHash,
    required http.Client client,
    FirebaseMessaging? messaging,
    String Function()? languageProvider,
    PushMessagingPlatform? platform,
    this.retryBaseDelay = const Duration(seconds: 5),
    this.retryMaxDelay = const Duration(minutes: 5),
  }) : _client = client,
       _languageProvider = languageProvider ?? _defaultLanguage,
       _platform = platform ?? PushMessagingPlatform(messaging: messaging);

  // 함수이름: _defaultLanguage
  // 함수역할: 언어 제공자가 없을 때 푸시 표시 문구에 사용할 한국어 코드를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 언어 제공자가 없을 때 푸시 표시 문구에 사용할 한국어 코드를 제공한다.
  static String _defaultLanguage() => 'ko';

  // Function Name: start
  // Description: Shares an in-flight FCM startup and starts permission, token, and message subscriptions only once in Firebase authentication mode. A failed startup keeps what already succeeded and is retried later.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> start() async {
    final pendingStart = _startOperation;
    if (pendingStart != null) {
      await pendingStart;
      return;
    }
    if (!_platform.enabled) {
      return;
    }
    if (_started) {
      // 이미 시작했다면 끝내지 못한 단계만 다시 시도한다.
      await retryRegistration();
      return;
    }
    _started = true;
    await _runStart();
  }

  // 함수이름: retryRegistration
  // 함수역할: 시작이 끝까지 성공하지 못했을 때 남은 단계(수신 구독, 실행 메시지 확인, 권한 요청, 토큰 등록)를
  //   지금 다시 시도한다. 앱이 다시 앞으로 올 때 호출한다. 이미 끝났거나 시작 전·중지 중이면 아무 일도 하지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 이번 시도가 끝나면 완료된다. 실패는 기록하고 다음 재시도를 예약한다.
  Future<void> retryRegistration() async {
    final pendingStart = _startOperation;
    if (pendingStart != null) {
      await pendingStart;
    }
    if (!_started || _stopping || _isStartComplete || _startOperation != null) {
      return;
    }
    await _runStart();
  }

  // Function Name: _isStartComplete
  // Description: Check completion of listeners, launch-message handling, permission request and token registration.
  // Parameters: None.
  // Returns: bool: true when startup is complete with no pending registration.
  bool get _isStartComplete =>
      _listening &&
      _initialMessageChecked &&
      _permissionRequested &&
      !_registrationPending;

  // Function Name: _runStart
  // Description: Cancel the retry timer and track a startup attempt, clearing only that attempt's shared reference on completion.
  // Parameters: None.
  // Returns: Future<void>: current startup attempt completion.
  Future<void> _runStart() {
    _retryTimer?.cancel();
    _retryTimer = null;
    late final Future<void> startOperation;
    startOperation = _start().whenComplete(
      /* Function Name: whenComplete callback
     * Description: Clears the in-flight start reference only when the completing operation is still the tracked start.
     * Parameters:
     * - None.
     * Returns:
     * - No return value.
     */
      () {
        if (identical(_startOperation, startOperation)) {
          _startOperation = null;
        }
      },
    );
    _startOperation = startOperation;
    return startOperation;
  }

  // 함수이름: _start
  // 함수역할: 알림 개인정보 설정과 구독을 준비하고 시작 메시지·권한·토큰 등록을 순서대로 처리한다. 실패는 기록 후 재시도 대상으로 남긴다.
  // 매개변수: 없음.
  // 반환값: Future<void>: 시작 시도 완료; 처리된 실패는 외부로 던지지 않고 재시도 예약한다.
  Future<void> _start() async {
    try {
      if (!_listening) {
        // 포그라운드 수신을 구독하기 전에, 이 기기에 저장된 계정 설정이 내용 숨김이면 먼저 적용한다.
        // 설정 조회가 끝나기 전에 도착한 보호자 알림이 세부 내용을 다시 만들지 않게 한다.
        final preferences = await SharedPreferences.getInstance();
        if (preferences.getString(
              UserSettingPreference.notificationDetailMode.keyFor(
                userHash.trim(),
              ),
            ) ==
            'type_only') {
          NotificationService.instance.setShowSensitiveDetails(false);
        }
        _platform.registerBackgroundHandler();
        // 토큰 등록이 실패해도 수신과 알림 선택은 동작하도록 구독을 먼저 연결한다.
        _tokenRefreshSubscription ??= _platform.onTokenRefresh.listen(
          /* Function Name: listen callback
         * Description: Registers each refreshed FCM token; a failed registration is reported and retried later.
         * Parameters:
         * - refreshedToken (String): Refreshed Firebase device messaging token.
         * Returns:
         * - No return value.
         */
          (refreshedToken) {
            unawaited(
              _trackTokenRegistration(refreshedToken).catchError(
                /* Function Name: catchError callback
             * Description: Routes refreshed-token registration failures to the push error reporter and schedules a retry.
             * Parameters:
             * - error (Object): Original failure object to classify or record.
             * - stackTrace (StackTrace): Call stack recorded alongside the error.
             * Returns:
             * - No return value.
             */
                (Object error, StackTrace stackTrace) {
                  _reportPushError(error, stackTrace);
                  _registrationPending = true;
                  _scheduleRetry();
                },
              ),
            );
          },
          onError: _reportPushError,
        );
        _foregroundMessageSubscription ??= _platform.onMessage.listen(
          /* 함수이름: listen 콜백
         * 함수역할: 포그라운드 FCM 메시지를 로컬 알림 표시 처리기로 전달한다.
         * 매개변수:
         * - message (RemoteMessage): Firebase에서 수신한 푸시 메시지
         * 반환값:
         * - 없음; 알림 표시는 비동기로 이어진다.
         */
          (message) {
            unawaited(
              _showForegroundMessage(message).catchError(_reportPushError),
            );
          },
          onError: _reportPushError,
        );
        _openedMessageSubscription ??= _platform.onMessageOpenedApp.listen(
          _handleOpenedMessage,
          onError: _reportPushError,
        );
        _listening = true;
      }
      if (!_initialMessageChecked) {
        final initialMessage = await _platform.getInitialMessage();
        _initialMessageChecked = true;
        if (initialMessage != null) {
          _handleOpenedMessage(initialMessage);
        }
      }
      if (!_permissionRequested) {
        await _platform.requestPermission();
        _permissionRequested = true;
      }
      // 이 시도 중에 갱신 토큰 등록이 실패하면 다시 true가 되어 재시도 대상으로 남는다.
      _registrationPending = false;
      final token = await _platform.getToken();
      if (token == null || token.trim().isEmpty) {
        // 초기 설치나 연결 복구 중 토큰이 아직 없으면 등록 완료로 처리하지 않는다.
        throw StateError('The device push token is not available yet.');
      }
      await _trackTokenRegistration(token);
      if (!_registrationPending) {
        _retryAttempt = 0;
      }
    } catch (error, stackTrace) {
      _registrationPending = true;
      _reportPushError(error, stackTrace);
      _scheduleRetry();
    }
  }

  // 함수이름: _scheduleRetry
  // 함수역할: 시작 실패 뒤 다음 시도를 예약한다. 간격은 retryBaseDelay에서 시작해 실패할 때마다 두 배가 되고
  //   retryMaxDelay를 넘지 않는다. 이미 예약되어 있거나 시작 전·중지 중이면 예약하지 않는다.
  // 매개변수: 없음. 반환값: 없음.
  void _scheduleRetry() {
    if (!_started || _stopping || _retryTimer != null) {
      return;
    }
    final proposedMilliseconds =
        retryBaseDelay.inMilliseconds * (1 << _retryAttempt.clamp(0, 16));
    final delay = Duration(
      milliseconds: proposedMilliseconds.clamp(0, retryMaxDelay.inMilliseconds),
    );
    _retryAttempt += 1;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(retryRegistration());
    });
  }

  // Function Name: stop
  // Description: Cancels any scheduled start retry, waits for startup and tracked token registrations, unregisters the last token, and cancels message subscriptions; strict cleanup rethrows server-unregistration failure before discarding state.
  // Parameters:
  // - requireServerUnregistration (bool): Whether server token-unregistration failure must propagate to the caller.
  // - discardUnregisteredToken (bool): Whether a token the server could not unregister is deleted on the device, so the server's stale registration for the ended account stops delivering here.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> stop({
    bool requireServerUnregistration = false,
    bool discardUnregisteredToken = false,
  }) async {
    _stopping = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _startOperation;
    await _awaitPendingTokenRegistrations();
    // 이번 실행에서 등록을 마치지 못했어도(오프라인으로 시작했거나 등록이 계속 실패) 이전 실행에서 등록한
    // 이 기기 토큰이 서버에 남아 있을 수 있다. 그대로 두면 끝난 계정의 푸시(채팅 미리보기 포함)가 이 기기에
    // 계속 표시되므로, 기기에서 토큰을 읽어 같은 방법으로 해제한다. 서버는 등록되지 않은 토큰의 해제도
    // 성공으로 답한다.
    if ((_registeredToken == null || _registeredToken!.isEmpty) &&
        _platformTokenMayBeRegistered) {
      try {
        _registeredToken = await _platform.getToken().timeout(_requestTimeout);
      } catch (error, stackTrace) {
        _reportPushError(error, stackTrace);
      }
    }
    final token = _registeredToken;
    if (token != null && token.isNotEmpty) {
      try {
        final response = await _client
            .delete(
              Uri.parse(ApiConfig.pushTokenUrl),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({'token': token, 'platform': _platformName}),
            )
            .timeout(_requestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw StateError(
            'The device push token could not be unregistered. '
            '(${response.statusCode})',
          );
        }
        if (_registeredToken == token) {
          _registeredToken = null;
          _platformTokenMayBeRegistered = false;
        }
      } catch (error, stackTrace) {
        _reportPushError(error, stackTrace);
        if (requireServerUnregistration) {
          _stopping = false;
          // 중지가 취소되었으므로 끝내지 못한 시작 단계의 재시도를 다시 예약한다.
          if (!_isStartComplete) _scheduleRetry();
          rethrow;
        }
      }
    }
    final unregisteredToken = _registeredToken;
    if (discardUnregisteredToken &&
        unregisteredToken != null &&
        unregisteredToken.isNotEmpty) {
      try {
        await _platform.deleteToken();
        _registeredToken = null;
        _platformTokenMayBeRegistered = false;
      } catch (error, stackTrace) {
        _reportPushError(error, stackTrace);
      }
    }

    _started = false;
    _listening = false;
    _registrationPending = true;
    _retryAttempt = 0;
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    await _openedMessageSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundMessageSubscription = null;
    _openedMessageSubscription = null;
    _stopping = false;
  }

  // Function Name: setRegisteredTokenForTesting
  // Description: Seeds the known registered token for tests of unregistration and session cleanup ordering.
  // Parameters:
  // - token (String): Current device push token issued by Firebase.
  // Returns:
  // - No return value.
  @visibleForTesting
  void setRegisteredTokenForTesting(String token) {
    _registeredToken = token;
  }

  // Function Name: registerTokenForTesting
  // Description: Exercises the tracked token-registration path without requiring a live FCM token stream.
  // Parameters:
  // - token (String): Current device push token issued by Firebase.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  @visibleForTesting
  Future<void> registerTokenForTesting(String token) {
    return _trackTokenRegistration(token);
  }

  // Function Name: _trackTokenRegistration
  // Description: Tracks token registration until settlement so sign-out waits for it, and rejects new work while cleanup is stopping the service. A second request for a token that is already being registered joins the request in flight, so the start path and the token-refresh listener do not register the same token twice.
  // Parameters:
  // - token (String): Current device push token issued by Firebase.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _trackTokenRegistration(String token) async {
    if (_stopping) {
      return;
    }
    final normalizedToken = token.trim();
    final inFlight = _pendingTokenRegistrations[normalizedToken];
    if (inFlight != null) {
      await inFlight;
      return;
    }
    late final Future<void> registration;
    registration = _registerToken(token).whenComplete(
      /* Function Name: whenComplete callback
     * Description: Removes the completed token registration from the set awaited during cleanup.
     * Parameters:
     * - None.
     * Returns:
     * - No return value.
     */
      () {
        if (identical(
          _pendingTokenRegistrations[normalizedToken],
          registration,
        )) {
          _pendingTokenRegistrations.remove(normalizedToken);
        }
      },
    );
    _pendingTokenRegistrations[normalizedToken] = registration;
    await registration;
  }

  // Function Name: _awaitPendingTokenRegistrations
  // Description: Waits for the current registration snapshot to settle, logs individual failures, and allows cleanup of the last successfully registered token to continue.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _awaitPendingTokenRegistrations() async {
    for (final registration in _pendingTokenRegistrations.values.toList(
      growable: false,
    )) {
      try {
        await registration;
      } catch (error, stackTrace) {
        _reportPushError(error, stackTrace);
      }
    }
  }

  // Function Name: _isAndroid
  // Description: Read whether Flutter targets Android.
  // Parameters: None.
  // Returns: bool: Android target flag.
  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  // Function Name: _platformName
  // Description: Choose the push-registration platform value, using ios for non-Android targets.
  // Parameters: None.
  // Returns: String: android or ios.
  String get _platformName => _isAndroid ? 'android' : 'ios';

  // 함수이름: _registerToken
  // 함수역할: 새 FCM 토큰을 현재 인증 사용자의 기기 토큰으로 서버에 등록한다.
  // 매개변수:
  // - token (String): Firebase가 발급한 현재 기기 푸시 토큰
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _registerToken(String token) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty || normalizedToken == _registeredToken) {
      return;
    }
    // 응답을 받지 못해도 서버에는 등록되었을 수 있다.
    _platformTokenMayBeRegistered = true;
    final response = await _client
        .post(
          Uri.parse(ApiConfig.pushTokenUrl),
          headers: const {'Content-Type': 'application/json'},
          // 알림 동작 버튼은 Android에만 정의되어 있으므로 그 기기만 동작 지원으로 등록한다.
          body: jsonEncode({
            'token': normalizedToken,
            'platform': _platformName,
            'supports_caregiver_actions': _isAndroid,
            'supports_slot_check_actions': _isAndroid,
          }),
        )
        .timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('기기 푸시 토큰 등록에 실패했습니다. (${response.statusCode})');
    }
    _registeredToken = normalizedToken;
  }

  // 함수이름: _showForegroundMessage
  // 함수역할: 앱 전경에서 받은 보호자 복약 알림을 로컬 알림 형태로 표시한다.
  // 매개변수:
  // - message (RemoteMessage): Firebase에서 수신한 푸시 메시지
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> _showForegroundMessage(RemoteMessage message) async {
    if (message.data['recipient_hash'] != userHash) return;
    if (SlotCheckNotificationContext.fromData(message.data) != null) {
      await recordPushNotificationHistory(
        message,
        userHash: userHash,
        language: _languageProvider(),
      );
      await SlotCheckNotificationService.display(message.data);
      return;
    }
    if (message.data['type'] == 'caregiver_slot_missed' &&
        message.data['action_version'] == '1') {
      await CaregiverAlertDeliveryService.display(message.data);
      return;
    }
    final language = _languageProvider();
    await recordPushNotificationHistory(
      message,
      userHash: userHash,
      language: language,
    );
    if (message.data['type'] == 'linked_chat_message') {
      final linkId = int.tryParse(message.data['link_id']?.trim() ?? '');
      if (linkId == null || linkId < 1) {
        return;
      }
      final source =
          _serverEventIdentity(message) ??
          message.messageId ??
          'linked-chat|$linkId';
      final notificationBody = message.notification?.body?.trim() ?? '';
      final dataPreview = message.data['message_preview']?.trim() ?? '';
      await NotificationService.instance.showLinkedChatAlert(
        historyUserHash: userHash,
        recordHistory: false,
        id: source.hashCode & 0x7fffffff,
        linkId: linkId,
        language: language,
        messagePreview: message.data.containsKey('message_preview')
            ? dataPreview
            : notificationBody,
        summary: ChatNotificationSummary.parse(message.data['chat_summary']),
        messageKind: message.data['message_kind'],
        slotKey: message.data['slot_key'],
      );
      return;
    }
    if (!_caregiverMessageTypes.contains(message.data['type'])) {
      return;
    }
    final patientHash = message.data['patient_hash']?.trim() ?? '';
    final text = caregiverNotificationTextForTesting(
      type: message.data['type'],
      slotKey: message.data['slot_key'],
      language: language,
    );
    final title = text.title;
    final body = text.body;
    final completionIdentity = _completionPushIdentity(message);
    final source =
        completionIdentity ??
        _serverEventIdentity(message) ??
        message.messageId ??
        '$patientHash|$title|$body';
    // 함수이름: present
    // 함수역할: 정리한 푸시 문구를 보호자 알림으로 표시하되 이미 처리한 알림함 기록은 다시 만들지 않는다.
    // 매개변수: 없음. 바깥 처리의 수신자·환자·문구·언어·이벤트 식별자를 사용한다.
    // 반환값: 표시 완료 Future. 완료 이벤트는 한 번 울리도록 요청하며 표시 오류는 전파한다.
    Future<void> present() => NotificationService.instance.showCaregiverAlert(
      historyUserHash: userHash,
      recordHistory: false,
      id: source.hashCode & 0x7fffffff,
      title: title,
      onlyAlertOnce: completionIdentity != null,
      body: body,
      patientHash: patientHash,
      language: language,
    );
    final eventKey = _slotCompletionEventKey(message);
    if (eventKey != null) {
      await CaregiverAlertDeliveryService.presentCompletionOnce(
        recipientHash: userHash,
        eventKey: eventKey,
        present: present,
      );
    } else {
      await present();
    }
  }

  // 함수이름: _handleOpenedMessage
  // 함수역할: 수신자와 알림 유형을 확인해 해당 채팅 또는 환자의 복약 일정으로 이동시킨다.
  // 매개변수:
  // - message (RemoteMessage): 사용자가 선택한 FCM 메시지
  // 반환값:
  // - 없음.
  void _handleOpenedMessage(RemoteMessage message) {
    if (message.data['recipient_hash'] != userHash) return;
    final type = message.data['type'];
    if (type != 'linked_chat_message' &&
        !_caregiverMessageTypes.contains(type)) {
      return;
    }
    final alert = CaregiverAlertContext.fromData(message.data);
    if (alert != null) {
      NotificationService.handleNotificationPayload(alert.payload);
      return;
    }
    final completionEventKey = _slotCompletionEventKey(message);
    if (completionEventKey != null) {
      // 알림 선택으로 앱을 시작했을 때도 이미 표시된 이벤트를 기억한다.
      unawaited(
        CaregiverAlertDeliveryService.presentCompletionOnce(
          recipientHash: userHash,
          eventKey: completionEventKey,
          present: () async {},
        ).then<void>((_) {}).catchError(_reportPushError),
      );
    }
    unawaited(
      recordPushNotificationHistory(
        message,
        userHash: userHash,
        language: _languageProvider(),
        markRead: true,
      ),
    );
    if (message.data['type'] == 'linked_chat_message') {
      final linkId = int.tryParse(message.data['link_id']?.trim() ?? '');
      if (linkId != null && linkId > 0) {
        NotificationService.handleNotificationPayload(
          MedicationNotificationPayloadCodec.chatPayload(linkId),
        );
      }
      return;
    }
    final patientHash = message.data['patient_hash']?.trim() ?? '';
    if (patientHash.isEmpty) {
      return;
    }
    NotificationService.handleNotificationPayload(
      MedicationNotificationPayloadCodec.caregiverPayload(patientHash),
    );
  }

  // Function Name: handleOpenedMessageForTesting
  // Description: Exercise the same handler used by launch and background taps.
  // Parameters: message - simulated FCM delivery. Returns: No value.
  @visibleForTesting
  void handleOpenedMessageForTesting(RemoteMessage message) =>
      _handleOpenedMessage(message);

  // 함수이름: caregiverNotificationTextForTesting
  // 함수역할: 완료·미복약 보호자 푸시의 언어별 제목과 본문을 구성한다.
  // 매개변수:
  // - type (String?): FCM 데이터의 보호자 알림 유형.
  // - slotKey (String?): morning·lunch·evening·bedtime 복약 시간대 키.
  // - language (String): 표시할 앱 언어 코드.
  // 반환값:
  // - 제목과 본문을 담은 이름 있는 레코드.
  @visibleForTesting
  static ({String title, String body}) caregiverNotificationTextForTesting({
    required String? type,
    required String? slotKey,
    required String language,
  }) {
    final isEnglish = isEnglishLanguage(language);
    final slotName = _slotName(slotKey, language);
    final isMissed = type == 'caregiver_slot_missed';
    if (slotKey == 'as_needed' && !isMissed) {
      return (
        title: isEnglish ? 'As-needed dose recorded' : '필요시 약 복용 기록',
        body: isEnglish
            ? 'The linked patient recorded taking an as-needed medication.'
            : '연동된 환자가 필요시 약 복용을 기록했습니다.',
      );
    }
    return (
      title: isMissed
          ? (isEnglish ? 'Medication not checked' : '미복용 일정 확인')
          : (isEnglish ? 'Patient medication completed' : '환자 복약 완료'),
      body: isMissed
          ? (isEnglish
                ? "The linked patient's $slotName medication is not checked yet."
                : '연동된 환자의 $slotName 복약이 아직 확인되지 않았습니다.')
          : (isEnglish
                ? 'The linked patient completed all $slotName medications.'
                : '연동된 환자의 $slotName 복약이 모두 완료되었습니다.'),
    );
  }

  // Function Name: _slotName
  // Description: Resolve a lowercase localized medication-slot name with a generic fallback.
  // Parameters: slotKey (String?): slot; language (String): display locale.
  // Returns: String: localized slot or scheduled-dose label.
  static String _slotName(String? slotKey, String language) {
    final isEnglish = isEnglishLanguage(language);
    return medicationSlotLabelOrNull(
          slotKey ?? '',
          isEnglish: isEnglish,
          lowercase: true,
        ) ??
        (isEnglish ? 'scheduled' : '복약');
  }

  // 함수이름: _reportPushError
  // 함수역할: 푸시 등록·수신 오류를 앱 종료 없이 진단 로그로 남긴다.
  // 매개변수:
  // - error (Object): 처리하거나 기록할 원래 실패 객체
  // - stackTrace (StackTrace?): 오류 진단에 함께 기록할 호출 스택
  // 반환값:
  // - 없음.
  void _reportPushError(Object error, [StackTrace? stackTrace]) {
    developer.log(
      '보호자 원격 알림 처리에 실패했습니다.',
      name: 'PushNotificationService',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
