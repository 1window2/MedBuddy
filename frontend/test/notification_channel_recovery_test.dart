import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
