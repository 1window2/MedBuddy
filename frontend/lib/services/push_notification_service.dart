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
import '../entities/medication_slot_label.dart';
import '../entities/user_setting_entity.dart';
import 'caregiver_alert_delivery_service.dart';
import 'api_config.dart';
import 'auth_config.dart';
import 'notification_service.dart';
import 'notification_inbox_store.dart';

// 함수이름: recordPushNotificationHistory
// 함수역할: 수신 계정을 확인하고 서버에서 표시를 허용한 메시지 미리보기와 푸시 내역을 보관한다.
// 매개변수: message, 전경 계정·언어·읽음 여부. 반환값: 기록 완료.
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
      payload = 'chat:$linkId';
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
    } else if (const {
      'caregiver_slot_completed',
      'caregiver_dose_completed',
      'caregiver_slot_missed',
    }.contains(type)) {
      final patient = message.data['patient_hash']?.toString().trim() ?? '';
      if (patient.isEmpty) return;
      payload = 'caregiver:${Uri.encodeComponent(patient)}';
      final showDetails =
          preferences.getString(
            'user_setting_${active.trim()}_notification_detail_mode',
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
      id: 'push:${message.messageId ?? message.data['event_id'] ?? '$type:$payload:${message.sentTime?.millisecondsSinceEpoch ?? 0}'}',
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
  if (message.data['type'] == 'caregiver_slot_missed' && message.data['action_version'] == '1') {
    await CaregiverAlertDeliveryService.display(message.data);
    return;
  }
  await recordPushNotificationHistory(message);
}

void registerMedBuddyPushBackgroundHandler() {
  if (AuthConfig.mode == AuthenticationMode.firebase) {
    FirebaseMessaging.onBackgroundMessage(medBuddyPushBackgroundHandler);
  }
}

// 클래스명: PushMessagingPlatform
// 역할: PushNotificationService가 쓰는 FCM 호출을 한곳에 묶는다.
// 주요 책임:
// - 기본 구현은 실제 FirebaseMessaging을 호출한다.
// - 테스트는 이 클래스를 대체해 토큰 발급·갱신과 메시지 수신을 재현한다.
class PushMessagingPlatform {
  final FirebaseMessaging? _injectedMessaging;

  // 함수이름: PushMessagingPlatform
  // 함수역할: 주입된 FCM 인스턴스를 쓰고, 없으면 처음 필요할 때 기본 인스턴스를 고른다.
  // 매개변수: messaging - 선택적 FCM 인스턴스. 반환값: 초기화된 인스턴스.
  const PushMessagingPlatform({FirebaseMessaging? messaging})
    : _injectedMessaging = messaging;

  FirebaseMessaging get _messaging =>
      _injectedMessaging ?? FirebaseMessaging.instance;

  // 함수이름: enabled
  // 함수역할: 서버 푸시를 쓰는 인증 모드인지 알려 준다. 반환값: Firebase 인증 모드이면 true.
  bool get enabled => AuthConfig.mode == AuthenticationMode.firebase;

  // 함수이름: registerBackgroundHandler
  // 함수역할: 앱이 꺼져 있을 때 받은 메시지를 처리할 함수를 등록한다. 반환값: 없음.
  void registerBackgroundHandler() =>
      FirebaseMessaging.onBackgroundMessage(medBuddyPushBackgroundHandler);

  // 함수이름: requestPermission
  // 함수역할: 알림 표시 권한을 요청한다. 반환값: 사용자가 응답하면 완료되는 Future.
  Future<void> requestPermission() =>
      _messaging.requestPermission(alert: true, badge: true, sound: true);

  // 함수이름: deleteToken
  // 함수역할: 이 기기의 FCM 토큰을 폐기해 서버에 남은 등록이 더는 전달되지 않게 한다. 매개변수: 없음. 반환값: 완료.
  Future<void> deleteToken() => _messaging.deleteToken();

  // 함수이름: getToken
  // 함수역할: 이 기기의 현재 FCM 토큰을 받는다. 반환값: 토큰 또는 아직 없으면 null.
  Future<String?> getToken() => _messaging.getToken();

  // 함수이름: onTokenRefresh
  // 함수역할: Firebase가 토큰을 바꿀 때마다 새 토큰을 전달한다. 반환값: 토큰 스트림.
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  // 함수이름: onMessage
  // 함수역할: 앱이 열려 있을 때 받은 메시지를 전달한다. 반환값: 메시지 스트림.
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  // 함수이름: onMessageOpenedApp
  // 함수역할: 사용자가 알림을 눌러 앱을 앞으로 가져온 메시지를 전달한다. 반환값: 메시지 스트림.
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  // 함수이름: getInitialMessage
  // 함수역할: 꺼져 있던 앱을 알림으로 실행한 메시지를 받는다. 반환값: 메시지 또는 null.
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

  // 함수이름: PushNotificationService
  // 함수역할: 현재 사용자와 인증 HTTP 클라이언트, 선택적 FCM 인스턴스 및 표시 언어 제공자를 연결한다.
  // 매개변수:
  // - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
  // - client (http.Client): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
  // - messaging (FirebaseMessaging?): FCM 권한·토큰·수신 경계
  // - languageProvider (String Function()?): 알림 생성 시점의 언어 조회 경계
  // - platform (PushMessagingPlatform?): FCM 호출 묶음; 생략하면 messaging으로 실제 구현을 만든다.
  // - retryBaseDelay (Duration): 시작 실패 뒤 첫 재시도까지의 간격
  // - retryMaxDelay (Duration): 재시도 간격의 상한
  // 반환값:
  // - PushNotificationService: 초기화된 인스턴스.
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
    if (!_started ||
        _stopping ||
        _isStartComplete ||
        _startOperation != null) {
      return;
    }
    await _runStart();
  }

  // 함수이름: _isStartComplete
  // 함수역할: 시작의 모든 단계가 끝나 재시도할 일이 없는지 알려 준다. 반환값: 모두 끝났으면 true.
  bool get _isStartComplete =>
      _listening &&
      _initialMessageChecked &&
      _permissionRequested &&
      !_registrationPending;

  // 함수이름: _runStart
  // 함수역할: 예약된 재시도를 취소하고 시작 시도 하나를 진행 중 작업으로 등록해 겹치는 호출이 함께 기다리게 한다.
  // 매개변수: 없음. 반환값: 이번 시도가 끝나면 완료되는 Future.
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

  // Function Name: _start
  // Description: Subscribes to token and message streams first, dispatches a launch message, then requests FCM permission and registers the current token. Each completed step is remembered, so a later attempt repeats only what failed and never subscribes or prompts twice; a failure is reported and retried with a growing delay.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _start() async {
    try {
      if (!_listening) {
        // 포그라운드 수신을 구독하기 전에, 이 기기에 저장된 계정 설정이 내용 숨김이면 먼저 적용한다.
        // 설정 조회가 끝나기 전에 도착한 보호자 알림이 세부 내용을 다시 만들지 않게 한다.
        final preferences = await SharedPreferences.getInstance();
        if (preferences.getString(
              'user_setting_${userHash.trim()}_notification_detail_mode',
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
            unawaited(_showForegroundMessage(message));
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
      if (token != null && token.trim().isNotEmpty) {
        await _trackTokenRegistration(token);
      }
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
      milliseconds: proposedMilliseconds.clamp(
        0,
        retryMaxDelay.inMilliseconds,
      ),
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

  // 함수이름: _isAndroid
  // 함수역할: 현재 실행 대상이 Android인지 확인한다. 매개변수: 없음. 반환값: Android 여부.
  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  // 함수이름: _platformName
  // 함수역할: 서버에 등록할 기기 플랫폼 이름을 만든다. 매개변수: 없음. 반환값: android 또는 ios.
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
    final response = await _client
        .post(
          Uri.parse(ApiConfig.pushTokenUrl),
          headers: const {'Content-Type': 'application/json'},
          // 알림 동작 버튼은 Android에만 정의되어 있으므로 그 기기만 동작 지원으로 등록한다.
          body: jsonEncode({'token': normalizedToken, 'platform': _platformName,
            'supports_caregiver_actions': _isAndroid}),
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
    if (message.data['type'] == 'caregiver_slot_missed' && message.data['action_version'] == '1') {
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
      final source = message.messageId ?? 'linked-chat|$linkId';
      final notificationBody = message.notification?.body?.trim() ?? '';
      final dataPreview = message.data['message_preview']?.trim() ?? '';
      await NotificationService.instance.showLinkedChatAlert(
        historyUserHash: userHash,
        recordHistory: false,
        id: source.hashCode & 0x7fffffff,
        linkId: linkId,
        language: language,
        messagePreview: notificationBody.isNotEmpty
            ? notificationBody
            : dataPreview,
        messageKind: message.data['message_kind'],
        slotKey: message.data['slot_key'],
      );
      return;
    }
    const supportedTypes = {
      'caregiver_slot_completed',
      'caregiver_dose_completed',
      'caregiver_slot_missed',
    };
    if (!supportedTypes.contains(message.data['type'])) {
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
    final source = message.messageId ?? '$patientHash|$title|$body';
    await NotificationService.instance.showCaregiverAlert(
      historyUserHash: userHash,
      recordHistory: false,
      id: source.hashCode & 0x7fffffff,
      title: title,
      body: body,
      patientHash: patientHash,
      language: language,
    );
  }

  // 함수이름: _handleOpenedMessage
  // 함수역할: 수신자와 알림 유형을 확인해 해당 채팅 또는 환자의 복약 일정으로 이동시킨다.
  // 매개변수:
  // - message (RemoteMessage): 사용자가 선택한 FCM 메시지
  // 반환값:
  // - 없음.
  void _handleOpenedMessage(RemoteMessage message) {
    if (message.data['recipient_hash'] != userHash) return;
    if (!const {
      'linked_chat_message',
      'caregiver_slot_completed',
      'caregiver_dose_completed',
      'caregiver_slot_missed',
    }.contains(message.data['type'])) {
      return;
    }
    final alert = CaregiverAlertContext.fromData(message.data);
    if (alert != null) {
      NotificationService.handleNotificationPayload(alert.payload);
      return;
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
          'chat:$linkId',
        );
      }
      return;
    }
    final patientHash = message.data['patient_hash']?.trim() ?? '';
    if (patientHash.isEmpty) {
      return;
    }
    NotificationService.handleNotificationPayload(
      'caregiver:${Uri.encodeComponent(patientHash)}',
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

  // 함수이름: _slotName
  // 함수역할: 푸시 데이터의 시간대를 현재 언어의 복약 안내 이름으로 바꾸고 알 수 없는 키는 일반 복약 표현으로 처리한다.
  // 매개변수:
  // - slotKey (String?): morning·lunch·evening·bedtime 복약 시간대 키
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - String: 푸시 데이터의 시간대를 현재 언어의 복약 안내 이름으로 바꾸고 알 수 없는 키는 일반 복약 표현으로 처리한다.
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
