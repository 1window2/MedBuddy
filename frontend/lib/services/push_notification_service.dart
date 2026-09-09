// 파일명: push_notification_service.dart
// 역할: Firebase 푸시 토큰 등록, 갱신, 수신과 선택 동작을 관리한다.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_config.dart';
import 'notification_service.dart';



// 클래스명: PushNotificationService
// 역할: 서버 푸시 등록과 전경 보호자 알림 표시를 앱 생명주기에 맞춰 처리한다.
// 주요 책임:
// - 로그인한 기기의 FCM 토큰을 백엔드에 등록한다.
// - Firebase가 토큰을 갱신하면 서버 등록값도 교체한다.
// - 앱이 열려 있을 때 수신한 보호자 알림을 로컬 알림으로 표시한다.
// - 로그아웃 시 현재 기기 토큰을 서버에서 비활성화한다.
// 속성:
// - _requestTimeout (Duration): 식별·분석 요청의 최대 대기시간
// - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
// - _client (http.Client): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
// - _languageProvider (String Function()): 알림 생성 시점의 언어 조회 경계
// - _messaging (FirebaseMessaging?): FCM 권한·토큰·수신 경계
class PushNotificationService {
  static const Duration _requestTimeout = Duration(seconds: 10);

  final String userHash;
  final http.Client _client;
  final String Function() _languageProvider;
  FirebaseMessaging? _messaging;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedMessageSubscription;
  String? _registeredToken;
  bool _started = false;
  bool _stopping = false;
  Future<void>? _startOperation;
  final Set<Future<void>> _pendingTokenRegistrations = <Future<void>>{};

  // 함수이름: PushNotificationService
  // 함수역할: 현재 사용자와 인증 HTTP 클라이언트, 선택적 FCM 인스턴스 및 표시 언어 제공자를 연결한다.
  // 매개변수:
  // - userHash (String): 현재 사용자 소유권·표시·저장 범위의 해시
  // - client (http.Client): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
  // - messaging (FirebaseMessaging?): FCM 권한·토큰·수신 경계
  // - languageProvider (String Function()?): 알림 생성 시점의 언어 조회 경계
  // 반환값:
  // - PushNotificationService: 초기화된 인스턴스.
  PushNotificationService({
    required this.userHash,
    required http.Client client,
    FirebaseMessaging? messaging,
    String Function()? languageProvider,
  }) : _client = client,
       _languageProvider = languageProvider ?? _defaultLanguage,
       _messaging = messaging;

  // 함수이름: _defaultLanguage
  // 함수역할: 언어 제공자가 없을 때 푸시 표시 문구에 사용할 한국어 코드를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - String: 언어 제공자가 없을 때 푸시 표시 문구에 사용할 한국어 코드를 제공한다.
  static String _defaultLanguage() => 'ko';

  // Function Name: start
  // Description: Shares an in-flight FCM startup and starts permission, token, and message subscriptions only once in Firebase authentication mode.
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
    if (_started || AuthConfig.mode != AuthenticationMode.firebase) {
      return;
    }
    late final Future<void> startOperation;
    startOperation = _start().whenComplete(/* Function Name: whenComplete callback
     * Description: Clears the in-flight start reference only when the completing operation is still the tracked start.
     * Parameters:
     * - None.
     * Returns:
     * - No return value.
     */() {
      if (identical(_startOperation, startOperation)) {
        _startOperation = null;
      }
    });
    _startOperation = startOperation;
    await startOperation;
  }

  // Function Name: _start
  // Description: Requests FCM permission, registers the initial token, subscribes to token and message streams, and dispatches a launch message while reporting initialization failures.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _start() async {
    _started = true;
    try {
      final messaging = _resolvedMessaging;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await _trackTokenRegistration(token);
      }
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen(/* Function Name: listen callback
       * Description: Registers each refreshed FCM token and reports asynchronous registration failures.
       * Parameters:
       * - refreshedToken (String): Refreshed Firebase device messaging token.
       * Returns:
       * - No return value.
       */(
        refreshedToken,
      ) {
        unawaited(
          _trackTokenRegistration(refreshedToken).catchError(/* Function Name: catchError callback
           * Description: Routes refreshed-token registration failures to the push error reporter.
           * Parameters:
           * - error (Object): Original failure object to classify or record.
           * - stackTrace (StackTrace): Call stack recorded alongside the error.
           * Returns:
           * - No return value.
           */(
            Object error,
            StackTrace stackTrace,
          ) {
            _reportPushError(error, stackTrace);
          }),
        );
      }, onError: _reportPushError);
      _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(/* 함수이름: listen 콜백
       * 함수역할: 포그라운드 FCM 메시지를 로컬 알림 표시 처리기로 전달한다.
       * 매개변수:
       * - message (RemoteMessage): Firebase에서 수신한 푸시 메시지
       * 반환값:
       * - 없음; 알림 표시는 비동기로 이어진다.
       */(
        message,
      ) {
        unawaited(_showForegroundMessage(message));
      }, onError: _reportPushError);
      _openedMessageSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleOpenedMessage,
        onError: _reportPushError,
      );
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleOpenedMessage(initialMessage);
      }
    } catch (error, stackTrace) {
      _started = false;
      _reportPushError(error, stackTrace);
    }
  }

  // Function Name: stop
  // Description: Waits for startup and tracked token registrations, unregisters the last token, and cancels message subscriptions; strict cleanup rethrows server-unregistration failure before discarding state.
  // Parameters:
  // - requireServerUnregistration (bool): Whether server token-unregistration failure must propagate to the caller.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> stop({bool requireServerUnregistration = false}) async {
    _stopping = true;
    await _startOperation;
    await _awaitPendingTokenRegistrations();
    final token = _registeredToken;
    if (token != null && token.isNotEmpty) {
      try {
        final response = await _client
            .delete(
              Uri.parse(ApiConfig.pushTokenUrl),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({'token': token, 'platform': 'android'}),
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
          rethrow;
        }
      }
    }

    _started = false;
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
  // Description: Tracks token registration until settlement so sign-out waits for it, and rejects new work while cleanup is stopping the service.
  // Parameters:
  // - token (String): Current device push token issued by Firebase.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _trackTokenRegistration(String token) async {
    if (_stopping) {
      return;
    }
    late final Future<void> registration;
    registration = _registerToken(token).whenComplete(/* Function Name: whenComplete callback
     * Description: Removes the completed token registration from the set awaited during cleanup.
     * Parameters:
     * - None.
     * Returns:
     * - No return value.
     */() {
      _pendingTokenRegistrations.remove(registration);
    });
    _pendingTokenRegistrations.add(registration);
    await registration;
  }

  // Function Name: _awaitPendingTokenRegistrations
  // Description: Waits for the current registration snapshot to settle, logs individual failures, and allows cleanup of the last successfully registered token to continue.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> _awaitPendingTokenRegistrations() async {
    for (final registration in _pendingTokenRegistrations.toList(
      growable: false,
    )) {
      try {
        await registration;
      } catch (error, stackTrace) {
        _reportPushError(error, stackTrace);
      }
    }
  }

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
          body: jsonEncode({'token': normalizedToken, 'platform': 'android'}),
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
    final language = _languageProvider();
    if (message.data['type'] == 'linked_chat_message') {
      final linkId = int.tryParse(message.data['link_id']?.trim() ?? '');
      if (linkId == null || linkId < 1) {
        return;
      }
      final source = message.messageId ?? 'linked-chat|$linkId';
      final notificationBody = message.notification?.body?.trim() ?? '';
      final dataPreview = message.data['message_preview']?.trim() ?? '';
      await NotificationService.instance.showLinkedChatAlert(
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
      id: source.hashCode & 0x7fffffff,
      title: title,
      body: body,
      patientHash: patientHash,
      language: language,
    );
  }

  // 함수이름: _handleOpenedMessage
  // 함수역할: 보호자가 시스템 푸시를 누르면 해당 환자의 복약 일정으로 이동시킨다.
  // 매개변수:
  // - message (RemoteMessage): 사용자가 선택한 FCM 메시지
  // 반환값:
  // - 없음.
  void _handleOpenedMessage(RemoteMessage message) {
    if (message.data['type'] == 'linked_chat_message') {
      final linkId = int.tryParse(message.data['link_id']?.trim() ?? '');
      if (linkId != null && linkId > 0) {
        final slotKey = message.data['slot_key']?.trim() ?? '';
        final isSlotRequest =
            message.data['message_kind'] == 'slot_check_request' &&
            const {'morning', 'lunch', 'evening', 'bedtime'}.contains(slotKey);
        NotificationService.handleNotificationPayload(
          isSlotRequest
              ? 'schedule:$slotKey:${linkId.hashCode & 0x7fffffff}'
              : 'chat:$linkId',
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
    final isEnglish = language.trim().toLowerCase() == 'en';
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
    final isEnglish = language.trim().toLowerCase() == 'en';
    return switch (slotKey) {
      'morning' => isEnglish ? 'morning' : '아침',
      'lunch' => isEnglish ? 'lunch' : '점심',
      'evening' => isEnglish ? 'evening' : '저녁',
      'bedtime' => isEnglish ? 'bedtime' : '취침 전',
      _ => isEnglish ? 'scheduled' : '복약',
    };
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

  // 함수이름: _resolvedMessaging
  // 함수역할: 주입된 메시징 인스턴스를 재사용하고 없으면 FirebaseMessaging 기본 인스턴스를 지연 선택한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - FirebaseMessaging: 주입된 메시징 인스턴스를 재사용하고 없으면 FirebaseMessaging 기본 인스턴스를 지연 선택한다.
  FirebaseMessaging get _resolvedMessaging {
    return _messaging ??= FirebaseMessaging.instance;
  }
}
