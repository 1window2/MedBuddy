import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/services/caregiver_alert_delivery_service.dart';
import 'package:medbuddy_frontend/services/notification_inbox_store.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/services/push_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Messaging extends PushMessagingPlatform {
  final messages = StreamController<RemoteMessage>.broadcast();

  @override
  bool get enabled => true;
  @override
  void registerBackgroundHandler() {}
  @override
  Future<void> requestPermission() async {}
  @override
  Future<String?> getToken() async => 'synthetic-token';
  @override
  Future<void> deleteToken() async {}
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Stream<RemoteMessage> get onMessage => messages.stream;
  @override
  Stream<RemoteMessage> get onMessageOpenedApp => const Stream.empty();
  @override
  Future<RemoteMessage?> getInitialMessage() async => null;
}

RemoteMessage _message(
  String id, {
  String? eventKey,
  String recipient = 'caregiver-a',
  String slot = 'morning',
  String kind = 'caregiver_slot_completed',
  bool notification = true,
}) => RemoteMessage(
  messageId: id,
  data: {
    'type': kind,
    'slot_key': slot,
    'patient_hash': 'patient-a',
    'recipient_hash': recipient,
    'event_key': ?eventKey,
    'language': 'ko',
  },
  notification: notification
      ? const RemoteNotification(title: '복약 상태 알림', body: '복약 상태가 변경되었습니다.')
      : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late List<Map<dynamic, dynamic>> shown;
  late _Messaging platform;
  late PushNotificationService service;
  late MockClient client;
  final eventKey = 'a' * 64;

  PushNotificationService build() => PushNotificationService(
    userHash: 'caregiver-a',
    platform: platform,
    client: client,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      NotificationInboxStore.activeUserKey: 'caregiver-a',
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    NotificationService.instance.setShowSensitiveDetails(true);
    shown = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'show') {
            shown.add(Map<dynamic, dynamic>.from(call.arguments as Map));
          }
          return call.method == 'initialize' ? true : null;
        });
    platform = _Messaging();
    client = MockClient((_) async => http.Response('{}', 200));
    service = build();
    await service.start();
  });

  tearDown(() async {
    await service.stop();
    await platform.messages.close();
    client.close();
    debugDefaultTargetPlatformOverride = null;
    NotificationService.instance.setShowSensitiveDetails(true);
    NotificationService.setNotificationSelectionHandler(null);
    CaregiverAlertDeliveryService.clock = DateTime.now;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('동일 완료 이벤트는 동시 수신과 서비스 재시작에도 한 번만 표시한다', () async {
    platform.messages.add(_message('first', eventKey: eventKey));
    platform.messages.add(_message('concurrent-retry', eventKey: eventKey));
    await pumpEventQueue();
    expect(shown, hasLength(1));
    expect((shown.single['platformSpecifics'] as Map)['onlyAlertOnce'], isTrue);
    final firstId = shown.single['id'];
    final store = NotificationInboxStore(userHash: 'caregiver-a');
    final entry = (await store.load()).single;
    await store.markRead([entry.id]);

    await service.stop();
    service = build();
    await service.start();
    platform.messages.add(_message('after-restart', eventKey: eventKey));
    await pumpEventQueue();
    expect(shown, hasLength(1));
    expect((await store.load()).single.isRead, isTrue);
    await store.remove([entry.id]);
    platform.messages.add(_message('after-dismissal', eventKey: eventKey));
    await pumpEventQueue();
    expect(shown, hasLength(1));
    expect(await store.load(), isEmpty);

    platform.messages.add(_message('new-event-same-slot', eventKey: 'b' * 64));
    await pumpEventQueue();
    expect(shown, hasLength(2));
    expect(shown.last['id'], isNot(firstId));
    expect(await store.load(), hasLength(1));
  });

  test('백그라운드에서 표시된 완료 이벤트의 전경 재수신은 다시 표시하지 않는다', () async {
    await medBuddyPushBackgroundHandler(
      _message('background', eventKey: eventKey),
    );
    await medBuddyPushBackgroundHandler(
      _message('background-retry', eventKey: eventKey),
    );
    platform.messages.add(_message('foreground-retry', eventKey: eventKey));
    await pumpEventQueue();
    expect(shown, isEmpty);
    expect(
      await NotificationInboxStore(userHash: 'caregiver-a').load(),
      hasLength(1),
    );
    platform.messages.add(_message('new-event', eventKey: 'b' * 64));
    await pumpEventQueue();
    expect(shown, hasLength(1));
  });

  test('OS 알림이 없는 데이터 수신은 완료 알림 표시를 미리 소비하지 않는다', () async {
    await medBuddyPushBackgroundHandler(
      _message('data-only', eventKey: eventKey, notification: false),
    );
    platform.messages.add(_message('visible', eventKey: eventKey));
    await pumpEventQueue();
    expect(shown, hasLength(1));
  });

  test('기존 알림 선택으로 시작해도 해당 완료 이벤트의 재수신을 억제한다', () async {
    service.handleOpenedMessageForTesting(
      _message('opened', eventKey: eventKey),
    );
    await pumpEventQueue();
    platform.messages.add(_message('retry', eventKey: eventKey));
    await pumpEventQueue();
    expect(shown, isEmpty);
  });

  for (final key in [null, 'invalid', '${'a' * 64}\n']) {
    test('고정 키가 없거나 잘못된 구형 메시지는 기존 FCM 식별자로 표시한다: $key', () async {
      platform.messages.add(_message('legacy-first', eventKey: key));
      await pumpEventQueue();
      platform.messages.add(_message('legacy-second', eventKey: key));
      await pumpEventQueue();
      expect(shown, hasLength(2));
      expect(shown.first['id'], isNot(shown.last['id']));
      expect(
        (shown.first['platformSpecifics'] as Map)['onlyAlertOnce'],
        isFalse,
      );
    });
  }

  test('다른 계정의 완료 이벤트는 표시하거나 전달 마커를 저장하지 않는다', () async {
    final other = _message(
      'wrong-recipient',
      eventKey: eventKey,
      recipient: 'other',
    );
    await medBuddyPushBackgroundHandler(other);
    platform.messages.add(other);
    await pumpEventQueue();
    expect(shown, isEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getKeys().where(
        CaregiverAlertDeliveryService.markerKeyPattern.hasMatch,
      ),
      isEmpty,
    );
  });

  test('필요시 복용 및 미복용 알림은 정기 완료 전달 마커를 사용하지 않는다', () async {
    for (final (kind, slot) in [
      ('caregiver_dose_completed', 'as_needed'),
      ('caregiver_slot_missed', 'morning'),
    ]) {
      platform.messages.add(
        _message(kind, eventKey: eventKey, kind: kind, slot: slot),
      );
      await pumpEventQueue();
    }
    expect(shown, hasLength(2));
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getKeys().where(
        CaregiverAlertDeliveryService.markerKeyPattern.hasMatch,
      ),
      isEmpty,
    );
  });

  test('표시 실패 후 같은 완료 이벤트는 재시도할 수 있다', () async {
    await expectLater(
      CaregiverAlertDeliveryService.presentCompletionOnce(
        recipientHash: 'caregiver-a',
        eventKey: eventKey,
        present: () async => throw StateError('synthetic display failure'),
      ),
      throwsStateError,
    );
    var count = 0;
    expect(
      await CaregiverAlertDeliveryService.presentCompletionOnce(
        recipientHash: 'caregiver-a',
        eventKey: eventKey,
        present: () async {
          count++;
        },
      ),
      isTrue,
    );
    expect(count, 1);
  });

  test('전달 마커는 시각만 보존하고 오래된 마커를 정리한다', () async {
    final now = DateTime.utc(2026, 10, 22);
    CaregiverAlertDeliveryService.clock = () => now;
    final preferences = await SharedPreferences.getInstance();
    final oldKey = CaregiverAlertDeliveryService.markerKeyFor(
      'caregiver-a',
      'b' * 64,
    );
    await preferences.setInt(
      oldKey,
      now.subtract(const Duration(days: 8)).millisecondsSinceEpoch,
    );
    await CaregiverAlertDeliveryService.presentCompletionOnce(
      recipientHash: 'caregiver-a',
      eventKey: eventKey,
      present: () async {},
    );
    await preferences.reload();
    expect(preferences.containsKey(oldKey), isFalse);
    expect(
      preferences.get(
        CaregiverAlertDeliveryService.markerKeyFor('caregiver-a', eventKey),
      ),
      now.millisecondsSinceEpoch,
    );
  });
}
