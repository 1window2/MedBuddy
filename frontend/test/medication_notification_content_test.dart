// Regression coverage at the Android notification channel boundary.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final scheduled = <Map<dynamic, dynamic>>[];
  final cancelled = <Map<dynamic, dynamic>>[];
  final active = <Map<String, Object?>>[];
  final pending = <Map<String, Object?>>[];
  var rejectExact = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    scheduled.clear();
    cancelled.clear();
    active.clear();
    pending.clear();
    rejectExact = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'pendingNotificationRequests':
              return pending;
            case 'getActiveNotifications':
              return active;
            case 'cancel':
              cancelled.add(Map<dynamic, dynamic>.from(call.arguments as Map));
              return null;
            case 'zonedSchedule':
              scheduled.add(Map<dynamic, dynamic>.from(call.arguments as Map));
              if (rejectExact && scheduled.length == 1) {
                throw PlatformException(code: 'exact_alarms_not_permitted');
              }
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    NotificationService.instance.setShowSensitiveDetails(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('disabling reminders removes delivered actions but preserves other alerts', () async {
    pending.addAll([
      {'id': 901, 'payload': 'schedule:morning:901:2026-09-11'},
      {'id': 902, 'payload': 'chat:5'},
    ]);
    active.addAll([
      {'id': 903, 'tag': 'dose', 'payload': 'schedule:evening:903:2026-09-11'},
      {'id': 904, 'tag': 'caregiver', 'payload': 'caregiver:patient'},
      {'id': 905, 'payload': 'chat:5'},
      {'id': 906, 'payload': null},
    ]);
    await NotificationService.instance.cancelAllScheduledMedicationReminders();
    expect(cancelled, contains(containsPair('id', 901)));
    expect(cancelled, contains(allOf(
      containsPair('id', 903),
      containsPair('tag', 'dose'),
    )));
    for (final id in [902, 904, 905, 906]) {
      expect(cancelled, isNot(contains(containsPair('id', id))));
    }
  });

  test('disabling one slot removes its delivered actions only', () async {
    pending.addAll([
      {'id': 911, 'payload': 'schedule:evening:911:2026-09-12'},
      {'id': 912, 'payload': 'schedule:morning:912:2026-09-12'},
    ]);
    active.addAll([
      {'id': 913, 'tag': 'snooze', 'payload': 'schedule:evening:913:2026-09-12'},
      {'id': 914, 'payload': 'schedule:morning:914:2026-09-12'},
      {'id': 915, 'payload': 'caregiver:patient'},
      {'id': 916, 'payload': 'chat:5'},
      {'id': 917, 'payload': null},
      {'id': 918, 'payload': 'schedule:eveningExtra:918:2026-09-12'},
    ]);
    await NotificationService.instance.cancelReminder(103, slotKey: 'evening');
    expect(cancelled, contains(containsPair('id', 103)));
    expect(cancelled, contains(containsPair('id', 911)));
    expect(cancelled, contains(allOf(
      containsPair('id', 913),
      containsPair('tag', 'snooze'),
    )));
    for (final id in [912, 914, 915, 916, 917, 918]) {
      expect(cancelled, isNot(contains(containsPair('id', id))));
    }
  });

  for (final language in ['ko', 'en']) {
    for (final sensitiveDetails in [true, false]) {
      test('stale name snapshots are neutral: $language/$sensitiveDetails', () async {
        final service = NotificationService.instance;
        service.setShowSensitiveDetails(sensitiveDetails);
        await service.initialize();
        final tomorrow = timezone.TZDateTime.now(timezone.local)
            .add(const Duration(days: 1));
        // Names captured before partial or full completion must never be
        // presented as instructions to take those medications again.
        for (final names in [
          ['ALREADY_COMPLETED', 'PENDING'],
          ['ALREADY_COMPLETED'],
          <String>[],
        ]) {
          await service.registerNotification(
            id: 101,
            slotKey: 'evening',
            slotTitle: 'Evening',
            hour: 20,
            minute: 0,
            medicationNames: names,
            activeDates: [tomorrow],
            medicationNamesByDate: {
              _dateKey(tomorrow): names,
            },
            language: language,
          );
          expect(scheduled.last['body'], _body(language));
          expect(scheduled.last['title'], language == 'en'
              ? 'Evening medication schedule' : 'Evening 복약 일정 확인');
          expect(scheduled.last['payload'], endsWith(':${_dateKey(tomorrow)}'));
        }
        expect(scheduled, hasLength(3));
      });
    }

    test('snooze fallback keeps neutral copy and original day: $language', () async {
      final service = NotificationService.instance;
      await service.initialize();
      final original = timezone.TZDateTime.now(timezone.local);
      rejectExact = true;
      await service.snoozeMedicationReminder(
        id: 102,
        slotKey: 'evening',
        slotTitle: 'Evening',
        language: language,
        scheduleDate: original,
        delay: const Duration(days: 1),
      );
      expect(scheduled, hasLength(2));
      for (final notification in scheduled) {
        expect(notification['body'], _body(language));
        expect(notification['payload'], 'schedule:evening:102:${_dateKey(original)}');
      }
    });
  }
}

String _body(String language) => language == 'en'
    ? 'Check your medication schedule and recorded completion status.'
    : '복약 일정과 복용 완료 기록을 확인해 주세요.';

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
