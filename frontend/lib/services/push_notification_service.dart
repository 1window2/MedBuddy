import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_config.dart';
import 'notification_service.dart';

// 파일명: push_notification_service.dart
// 역할: Firebase 인증 사용자 기기의 FCM 토큰과 전경 푸시 표시를 관리한다.

// 클래스명: PushNotificationService
// 역할: 서버 푸시 등록과 전경 보호자 알림 표시를 앱 생명주기에 맞춰 처리한다.
// 주요 책임:
// - 로그인한 기기의 FCM 토큰을 백엔드에 등록한다.
// - Firebase가 토큰을 갱신하면 서버 등록값도 교체한다.
// - 앱이 열려 있을 때 수신한 보호자 알림을 로컬 알림으로 표시한다.
// - 로그아웃 시 현재 기기 토큰을 서버에서 비활성화한다.
class PushNotificationService {
  static const Duration _requestTimeout = Duration(seconds: 10);

  final http.Client _client;
  FirebaseMessaging? _messaging;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  String? _registeredToken;
  bool _started = false;

  PushNotificationService({
    required http.Client client,
    FirebaseMessaging? messaging,
  }) : _client = client,
       _messaging = messaging;

  // 함수명: start
  // 역할:
  // - Firebase 모드에서 알림 권한과 토큰을 준비하고 수신 스트림을 연결한다.
  // 반환값:
  // - 없음
  Future<void> start() async {
    if (_started || AuthConfig.mode != AuthenticationMode.firebase) {
      return;
    }
    _started = true;
    try {
      final messaging = _resolvedMessaging;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await _registerToken(token);
      }
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen((
        refreshedToken,
      ) {
        unawaited(_registerToken(refreshedToken));
      }, onError: _reportPushError);
      _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen((
        message,
      ) {
        unawaited(_showForegroundMessage(message));
      }, onError: _reportPushError);
    } catch (error, stackTrace) {
      _started = false;
      _reportPushError(error, stackTrace);
    }
  }

  // 함수명: stop
  // 역할:
  // - 현재 기기 토큰을 서버에서 비활성화하고 메시지 구독을 정리한다.
  // 반환값:
  // - 없음
  Future<void> stop() async {
    final token = _registeredToken;
    _registeredToken = null;
    _started = false;
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundMessageSubscription = null;
    if (token == null || token.isEmpty) {
      return;
    }
    try {
      await _client
          .delete(
            Uri.parse(ApiConfig.pushTokenUrl),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'token': token, 'platform': 'android'}),
          )
          .timeout(_requestTimeout);
    } catch (error, stackTrace) {
      _reportPushError(error, stackTrace);
    }
  }

  // 함수명: _registerToken
  // 역할:
  // - 새 FCM 토큰을 현재 인증 사용자의 기기 토큰으로 서버에 등록한다.
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

  // 함수명: _showForegroundMessage
  // 역할:
  // - 앱 전경에서 받은 보호자 복약 알림을 로컬 알림 형태로 표시한다.
  Future<void> _showForegroundMessage(RemoteMessage message) async {
    if (message.data['type'] != 'caregiver_dose_completed') {
      return;
    }
    final notification = message.notification;
    final title = notification?.title ?? '환자 복약 확인';
    final body = notification?.body ?? '연동된 환자의 복약 상태가 변경되었습니다.';
    final source = message.messageId ?? '$title|$body';
    await NotificationService.instance.showCaregiverAlert(
      id: source.hashCode & 0x7fffffff,
      title: title,
      body: body,
    );
  }

  // 함수명: _reportPushError
  // 역할:
  // - 푸시 등록·수신 오류를 앱 종료 없이 진단 로그로 남긴다.
  void _reportPushError(Object error, [StackTrace? stackTrace]) {
    developer.log(
      '보호자 원격 알림 처리에 실패했습니다.',
      name: 'PushNotificationService',
      error: error,
      stackTrace: stackTrace,
    );
  }

  FirebaseMessaging get _resolvedMessaging {
    return _messaging ??= FirebaseMessaging.instance;
  }
}
