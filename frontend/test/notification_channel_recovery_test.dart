// 파일명: notification_channel_recovery_test.dart
// 역할: 알림 채널 생성 실패 뒤 동시 초기화가 하나의 복구 작업을 공유하는지 검증한다.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';

// 함수이름: main
// 함수역할:
// - 알림 채널 생성 실패 뒤 동시 초기화가 하나의 복구 작업을 공유하는지 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 공통 설정과 개별 회귀 사례를 등록한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 함수이름: test callback
  // 함수역할:
  // - 최초 채널 생성에 실패한 뒤 두 초기화를 겹쳐 호출해 재생성이 한 번만 진행되고 플러그인 초기화는 반복하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('failed channel creation retries once across concurrent initializers', () async {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final created = <String>[];
    final gate = Completer<void>();
    var initializations = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') {
        initializations++;
        return true;
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'createNotificationChannel') {
        final arguments = call.arguments as Map;
        created.add(arguments['id'] as String);
        if (created.length == 1) throw PlatformException(code: 'temporary');
        if (created.length == 2) await gate.future;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    final service = NotificationService.instance;
    await service.initialize();
    expect(created, ['medbuddy_medication_reminders']);
    final first = service.initialize();
    final second = service.initialize();
    await pumpEventQueue();
    expect(created, hasLength(2));
    gate.complete();
    await first;
    await second;
    expect(created, [
      'medbuddy_medication_reminders',
      'medbuddy_medication_reminders',
      'medbuddy_caregiver_updates',
      'medbuddy_linked_chat',
    ]);
    expect(initializations, 1);
    await service.initialize();
    expect(created, hasLength(4));
  });
}
