// 파일명: notification_readiness_service_test.dart
// 역할: 실제 플러그인 경계에서 권한 상태와 복약에 영향 없는 테스트 알림을 검증한다.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/notification_readiness_control.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = NotificationService.instance;
  final calls = <MethodCall>[];
  bool? permission = true;
  bool? exact = true;
  int importance = Importance.high.value;
  bool failPermissionRead = false;
  bool missingChannel = false;
  bool failShow = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    permission = true;
    exact = true;
    importance = Importance.high.value;
    failPermissionRead = false;
    missingChannel = false;
    failShow = false;
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'areNotificationsEnabled':
          if (failPermissionRead) throw PlatformException(code: 'unavailable');
          return permission;
        case 'canScheduleExactNotifications':
          return exact;
        case 'getNotificationChannels':
          return missingChannel
              ? []
              : [
                  {
                    'id': 'medbuddy_medication_reminders',
                    'name': '복약 알림',
                    'importance': importance,
                    'showBadge': true,
                    'bypassDnd': false,
                    'playSound': true,
                    'enableLights': false,
                    'enableVibration': true,
                    'ledColor': 0,
                    'audioAttributesUsage': 5,
                  },
                ];
        case 'show':
          if (failShow) throw PlatformException(code: 'failed');
      }
      return null;
    });
  });
  tearDown(() {
    NotificationService.setNotificationSelectionHandler(null);
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('점검은 권한을 요청하거나 예약을 변경하지 않는다', () async {
    final state = await service.readReadinessPermissions();
    expect(state.notifications, isTrue);
    expect(state.medicationChannel, isTrue);
    expect(state.exactAlarms, isTrue);
    expect(
      calls.where(
        (c) =>
            c.method.startsWith('request') ||
            c.method.contains('Schedule') &&
                c.method != 'canScheduleExactNotifications' ||
            c.method.startsWith('cancel') ||
            c.method == 'show',
      ),
      isEmpty,
    );
  });

  test('앱 알림과 복약 채널 차단 및 정확한 알람 미허용을 구분한다', () async {
    permission = false;
    exact = false;
    importance = Importance.none.value;
    final state = await service.readReadinessPermissions();
    expect(state.notifications, isFalse);
    expect(state.medicationChannel, isFalse);
    expect(state.exactAlarms, isFalse);
    await expectLater(
      service.showReadinessTestNotification(),
      throwsStateError,
    );
    expect(calls.where((c) => c.method == 'show'), isEmpty);
  });

  test('확인 실패와 누락된 채널은 허용으로 표시하지 않는다', () async {
    failPermissionRead = true;
    missingChannel = true;
    final state = await service.readReadinessPermissions();
    expect(state.notifications, isNull);
    expect(state.medicationChannel, isNull);
    expect(state.exactAlarms, isTrue);
    await expectLater(
      service.showReadinessTestNotification(),
      throwsStateError,
    );
  });

  test('실제 테스트 알림은 복약 채널을 사용하지만 동작과 이동 대상이 없다', () async {
    var selections = 0;
    NotificationService.setNotificationSelectionHandler((_) {
      selections++;
    });
    await service.showReadinessTestNotification(language: 'en');
    final arguments =
        calls.singleWhere((c) => c.method == 'show').arguments as Map;
    expect(arguments['title'], 'MedBuddy test notification');
    expect(arguments['payload'], anyOf(isNull, isEmpty));
    expect(arguments['id'], -17023);
    final android = arguments['platformSpecifics'] as Map;
    expect(android['channelId'], 'medbuddy_medication_reminders');
    expect(android['tag'], 'medbuddy_readiness_test');
    expect(android['actions'], isNull);
    NotificationService.handleNotificationPayload(
      arguments['payload'] as String?,
      notificationId: arguments['id'] as int,
    );
    expect(selections, 0);
    expect(
      calls.where(
        (c) => c.method == 'zonedSchedule' || c.method.startsWith('cancel'),
      ),
      isEmpty,
    );
  });

  test('테스트 표시 실패를 호출자에게 전달한다', () async {
    failShow = true;
    await expectLater(
      service.showReadinessTestNotification(),
      throwsA(isA<PlatformException>()),
    );
  });

  test('미지원 환경에서는 테스트 알림을 성공 처리하지 않는다', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await expectLater(
      service.showReadinessTestNotification(),
      throwsUnsupportedError,
    );
    expect(calls, isEmpty);
  });

  test('등록 조회 오류는 약 없음이 아니며 동시 점검을 합친다', () async {
    final gate = Completer<bool?>();
    var reads = 0;
    final control = NotificationReadinessControl(
      notificationService: service,
      loadHasMedication: () {
        reads++;
        return gate.future;
      },
    );
    final first = control.refresh();
    final second = control.refresh();
    await pumpEventQueue();
    expect(reads, 1);
    gate.completeError(StateError('offline'));
    final state = await first;
    expect(identical(state, await second), isTrue);
    expect(state.hasMedication, isNull);
    expect(state.notifications, isTrue);
  });
}
