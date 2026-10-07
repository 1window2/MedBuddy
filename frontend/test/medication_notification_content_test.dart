// Regression coverage at the Android notification channel boundary.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/services/notification_inbox_store.dart';
import 'package:timezone/timezone.dart' as timezone;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final scheduled = <Map<dynamic, dynamic>>[];
  final cancelled = <Map<dynamic, dynamic>>[];
  final active = <Map<String, Object?>>[];
  final pending = <Map<String, Object?>>[];
  var rejectExact = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationService.instance.setHistoryUser(null, persistSession: false);
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

  test('completed widget dose cancels its dated snooze without losing other reminders', () async {
    final service = NotificationService.instance;
    service.setHistoryUser('patient-a', persistSession: false);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(NotificationInboxStore.activeUserKey, 'patient-a');
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final first = DateTime(now.year, now.month, now.day + 1);
    final second = DateTime(now.year, now.month, now.day + 2);
    for (final owner in ['patient-a', 'patient-b']) {
      for (final slot in ['morning', 'evening']) {
        await service.registerNotification(
          id: MedicationAlarm.defaults(slot).copyWith(patientHash: owner).notificationId,
          slotKey: slot, slotTitle: slot, hour: 8, minute: 0,
          medicationNames: [], activeDates: [first, second],
        );
      }
    }
    final target = scheduled.first['id'] as int;
    final preserved = scheduled.skip(1).map((item) => item['id']).toSet();
    pending.addAll(scheduled.map((item) => {'id': item['id'], 'payload': item['payload']}));
    active.addAll([
      {'id': target, 'tag': 'dose', 'channelId': 'medbuddy_medication_reminders'},
      {'id': target, 'tag': 'chat', 'channelId': 'medbuddy_linked_chat'},
      {'id': 77, 'channelId': 'medbuddy_caregiver_updates'},
    ]);
    await service.snoozeMedicationReminder(
      id: target, slotKey: 'morning', slotTitle: '아침',
      scheduleDate: first, delay: const Duration(days: 2),
    );
    cancelled.clear();
    // 백그라운드 isolate는 전경의 메모리 계정을 공유하지 않는다.
    service.setHistoryUser(null, persistSession: false);
    await service.cancelReminderForDate(owner: 'patient-a', slotKey: 'morning', date: first);
    expect(cancelled, contains(containsPair('id', target)));
    expect(cancelled, contains(containsPair('tag', 'dose')));
    expect(cancelled, isNot(contains(containsPair('tag', 'chat'))));
    expect(cancelled, isNot(contains(containsPair('id', 77))));
    for (final id in preserved) {
      expect(cancelled, isNot(contains(containsPair('id', id))));
    }
    final history = await NotificationInboxStore(
      userHash: 'patient-a', now: () => now.add(const Duration(days: 3)),
    ).load();
    expect(history.where((entry) => entry.payload.split(':')[2] == '$target'), isEmpty);
    expect(history, hasLength(7));
    expect(preferences.getString(NotificationInboxStore.activeUserKey), 'patient-a');
  });

  test('widget cancellation stops after logout or account switch', () async {
    final preferences = await SharedPreferences.getInstance();
    for (final owner in [null, 'patient-b']) {
      if (owner == null) {
        await preferences.remove(NotificationInboxStore.activeUserKey);
      } else {
        await preferences.setString(NotificationInboxStore.activeUserKey, owner);
      }
      await NotificationService.instance.cancelReminderForDate(
        owner: 'patient-a', slotKey: 'morning', date: DateTime(2026, 10, 2),
      );
      expect(cancelled, isEmpty);
    }
  });

  // 같은 예약·미루기는 보존하고 변경된 날짜와 시각만 기기에 반영한다.
  test('unchanged reminders and snoozes survive differential refresh', () async {
    final service = NotificationService.instance;
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final first = DateTime(now.year, now.month, now.day + 1);
    final second = DateTime(now.year, now.month, now.day + 2);
    Future<void> refresh(List<DateTime> dates, {int hour = 8}) => service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: '아침', hour: hour, minute: 0,
      medicationNames: [], activeDates: dates,
    );
    await refresh([first, second]);
    expect(scheduled.length, 2);
    for (final item in scheduled) {
      pending.add({'id': item['id'], 'payload': item['payload']});
    }
    final firstId = scheduled.first['id'] as int;
    scheduled.clear();
    cancelled.clear();
    await refresh([first, second]);
    expect(scheduled, isEmpty);
    expect(cancelled, isEmpty);
    await service.snoozeMedicationReminder(id: firstId, slotKey: 'morning',
        slotTitle: '아침', scheduleDate: first);
    scheduled.clear();
    await refresh([first, second]);
    expect(scheduled, isEmpty);
    expect(cancelled, isEmpty);
    await refresh([second], hour: 9);
    expect(cancelled, contains(containsPair('id', firstId)));
    expect(scheduled, hasLength(1));
    expect(scheduled.single['scheduledDateTime'].toString(), contains('09:00'));
  });

  test('account and missing platform reservations cannot reuse another plan', () async {
    final service = NotificationService.instance;
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final date = DateTime(now.year, now.month, now.day + 1);
    Future<void> refresh() => service.registerNotification(id: 101,
        slotKey: 'morning', slotTitle: '아침', hour: 8, minute: 0,
        medicationNames: [], activeDates: [date]);
    service.setHistoryUser('first', persistSession: false);
    await refresh();
    final item = scheduled.single;
    pending.add({'id': item['id'], 'payload': item['payload']});
    scheduled.clear();
    service.setHistoryUser('second', persistSession: false);
    await refresh();
    expect(scheduled, hasLength(1));
    scheduled.clear();
    pending.clear();
    await refresh();
    expect(scheduled, hasLength(1));
  });

  test('disabling reminders removes delivered actions but preserves other alerts', () async {
    pending.addAll([
      {'id': 901, 'payload': 'schedule:morning:901:2026-09-11'},
      {'id': 902, 'payload': 'chat:5'},
    ]);
    active.addAll([
      {'id': 903, 'tag': 'dose', 'channelId': 'medbuddy_medication_reminders'},
      {'id': 904, 'tag': 'caregiver', 'channelId': 'medbuddy_caregiver_updates'},
      {'id': 905, 'channelId': 'medbuddy_linked_chat'},
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
      {'id': 913, 'tag': 'snooze', 'channelId': 'medbuddy_medication_reminders',
        'groupKey': 'medbuddy.reminder.evening'},
      {'id': 914, 'channelId': 'medbuddy_medication_reminders',
        'groupKey': 'medbuddy.reminder.morning'},
      {'id': 915, 'channelId': 'medbuddy_caregiver_updates'},
      {'id': 916, 'channelId': 'medbuddy_linked_chat'},
      {'id': 917, 'payload': null},
      {'id': 918, 'channelId': 'medbuddy_medication_reminders',
        'groupKey': 'medbuddy.reminder.eveningExtra'},
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

  test('legacy Android reminders match date IDs only on their channel', () async {
    await NotificationService.instance.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final previousDay = DateTime(now.year, now.month, now.day - 1);
    var hash = 0x811C9DC5;
    for (final unit in '103|evening|${_dateKey(previousDay)}'.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7FFFFFFF;
    }
    final legacyDateId = 100000 + (hash % 2000000000);
    active.addAll([
      {'id': legacyDateId, 'tag': 'legacy',
        'channelId': 'medbuddy_medication_reminders'},
      {'id': legacyDateId, 'tag': 'unrelated', 'channelId': 'other'},
      {'id': 923, 'channelId': 'medbuddy_medication_reminders'},
    ]);
    await NotificationService.instance.cancelReminder(103, slotKey: 'evening');
    expect(cancelled, contains(allOf(
      containsPair('id', legacyDateId), containsPair('tag', 'legacy'),
    )));
    expect(cancelled, isNot(contains(containsPair('tag', 'unrelated'))));
    expect(cancelled, isNot(contains(containsPair('id', 923))));
  });

  test('session cleanup recognizes Android channels without payloads', () async {
    active.addAll([
      {'id': 931, 'channelId': 'medbuddy_medication_reminders'},
      {'id': 932, 'channelId': 'medbuddy_caregiver_updates'},
      {'id': 933, 'channelId': 'medbuddy_linked_chat'},
      {'id': 934, 'channelId': 'other'},
    ]);
    await NotificationService.instance.cancelAllMedicationReminders();
    for (final id in [931, 932, 933]) {
      expect(cancelled, contains(containsPair('id', id)));
    }
    expect(cancelled, isNot(contains(containsPair('id', 934))));
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
          expect((scheduled.last['platformSpecifics'] as Map)['groupKey'],
              'medbuddy.reminder.evening');
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
