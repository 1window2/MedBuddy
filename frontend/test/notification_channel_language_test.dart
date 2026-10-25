import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/app_language_resolver.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('알림 채널은 저장된 언어와 마지막 변경을 반영하며 ID와 예약을 유지한다', () async {
    SharedPreferences.setMockInitialValues({appLanguagePreferenceKey: 'en'});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    final channels = <String, Map>{};
    Completer<void>? gate;
    var failNext = false;
    String? failChannel;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') return true;
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      if (call.method == 'createNotificationChannel') {
        final arguments = call.arguments as Map;
        if (failNext || arguments['id'] == failChannel) {
          failNext = false;
          failChannel = null;
          throw PlatformException(code: 'temporary');
        }
        final pending = gate;
        gate = null;
        if (pending != null) await pending.future;
        channels[arguments['id'] as String] = arguments;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    final service = NotificationService.instance;
    await service.initialize();
    const englishNames = [
      'Medication reminders',
      'Caregiver medication updates',
      'Family chat',
    ];
    expect(channels.values.map((c) => c['name']), englishNames);
    expect(
      channels.values.every(
        (c) => !RegExp('[가-힣]').hasMatch(c['description'] as String),
      ),
      isTrue,
    );
    final initialIds = channels.keys.toList();
    final initialChannelOptions = {
      for (final entry in channels.entries)
        entry.key: Map.of(entry.value)
          ..remove('name')
          ..remove('description'),
    };
    calls.clear();
    await service.updateLanguage('en');
    expect(calls, isEmpty);

    await service.updateLanguage('ko');
    expect(channels.values.map((c) => c['name']), [
      '복약 알림',
      '보호자 복약 확인',
      '가족 채팅',
    ]);
    expect(channels.keys, initialIds);

    // 생성 실패 후에도 다음 호출이 번역을 다시 적용한다.
    failNext = true;
    await service.updateLanguage('en');
    await service.initialize();
    expect(channels.values.map((c) => c['name']), englishNames);

    // 일부만 변경된 뒤 실패해도 이전 언어로 돌아가는 요청을 생략하지 않는다.
    failChannel = 'medbuddy_caregiver_updates';
    await service.updateLanguage('ko');
    expect(channels['medbuddy_medication_reminders']!['name'], '복약 알림');
    await service.updateLanguage('en');
    expect(channels.values.map((c) => c['name']), englishNames);

    // 생성 도중 언어를 다시 바꾸어도 오래된 요청이 마지막 선택을 덮지 않는다.
    final pending = Completer<void>();
    gate = pending;
    final first = service.updateLanguage('ko');
    await pumpEventQueue();
    final second = service.updateLanguage('en');
    pending.complete();
    await first;
    await second;
    expect(channels.values.map((c) => c['name']), englishNames);
    for (final entry in channels.entries) {
      expect(
        Map.of(entry.value)
          ..remove('name')
          ..remove('description'),
        initialChannelOptions[entry.key],
      );
    }
    expect(
      calls.every((call) => call.method == 'createNotificationChannel'),
      isTrue,
    );
  });
}
