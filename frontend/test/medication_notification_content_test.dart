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

// Class Name: _CountingPreferences
// Role: Counts the reloads and writes a reminder refresh makes on the device preference store.
// Responsibilities:
// - Forward every call to the real in-memory test store, so behavior is unchanged.
// Attributes: reloads - number of reload calls; writes - keys written or removed, in order.
class _CountingPreferences implements SharedPreferences {
  // Function Name: _CountingPreferences
  // Description: Wraps the store returned by SharedPreferences.getInstance.
  // Parameters: _inner - the real test store. Returns: The counting wrapper.
  _CountingPreferences(this._inner);

  final SharedPreferences _inner;
  int reloads = 0;
  final List<String> writes = [];

  @override
  Future<void> reload() {
    reloads++;
    return _inner.reload();
  }

  @override
  Set<String> getKeys() => _inner.getKeys();

  @override
  bool containsKey(String key) => _inner.containsKey(key);

  @override
  Object? get(String key) => _inner.get(key);

  @override
  String? getString(String key) => _inner.getString(key);

  @override
  bool? getBool(String key) => _inner.getBool(key);

  @override
  Future<bool> setString(String key, String value) {
    writes.add(key);
    return _inner.setString(key, value);
  }

  @override
  Future<bool> setBool(String key, bool value) {
    writes.add(key);
    return _inner.setBool(key, value);
  }

  @override
  Future<bool> remove(String key) {
    writes.add(key);
    return _inner.remove(key);
  }

  // The reminder path uses only the members above; any other call fails the test.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final scheduled = <Map<dynamic, dynamic>>[];
  final cancelled = <Map<dynamic, dynamic>>[];
  final active = <Map<String, Object?>>[];
  final pending = <Map<String, Object?>>[];
  final pluginCalls = <String>[];
  var rejectExact = false;
  // Android 14 default: exact alarms are refused until the user allows "Alarms & reminders".
  var exactDenied = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationService.instance.setHistoryUser(null, persistSession: false);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    scheduled.clear();
    cancelled.clear();
    active.clear();
    pending.clear();
    pluginCalls.clear();
    rejectExact = false;
    exactDenied = false;
    // Every test starts as a freshly started process.
    NotificationService.instance.forgetArmedRemindersForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          pluginCalls.add(call.method);
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
            case 'canScheduleExactNotifications':
              return !exactDenied;
            case 'zonedSchedule':
              scheduled.add(Map<dynamic, dynamic>.from(call.arguments as Map));
              if (rejectExact && scheduled.length == 1) {
                throw PlatformException(code: 'exact_alarms_not_permitted');
              }
              if (exactDenied && _scheduleMode(scheduled.last).startsWith('exact')) {
                // The plugin refuses the request and leaves an existing alarm as it is.
                scheduled.removeLast();
                throw PlatformException(code: 'exact_alarms_not_permitted');
              }
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    NotificationService.preferencesLoader = SharedPreferences.getInstance;
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

  // Steady state: a refresh that finds every reminder already reserved with the same time and text
  // only reads the device reservations. It schedules, cancels, writes and announces nothing.
  test('an unchanged refresh only reads the pending reservations', () async {
    final service = NotificationService.instance;
    service.setHistoryUser('patient-a', persistSession: false);
    await service.initialize();
    final events = <String>[];
    final subscription = NotificationInboxStore.changes.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final now = timezone.TZDateTime.now(timezone.local);
    final dates = [
      for (var day = 1; day <= 3; day++) DateTime(now.year, now.month, now.day + day),
    ];
    Future<void> refresh() => service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: '아침', hour: 8, minute: 0,
      medicationNames: [], activeDates: dates,
    );

    await refresh();
    await pumpEventQueue();
    expect(scheduled, hasLength(3));
    // Three inbox entries are stored together and announced once.
    expect(events, ['patient-a']);
    pending.addAll(scheduled.map((item) => {'id': item['id'], 'payload': item['payload']}));
    final preferences = _CountingPreferences(
      await SharedPreferences.getInstance(),
    );
    NotificationService.preferencesLoader = () async => preferences;
    Map<String, Object?> stored() =>
        {for (final key in preferences.getKeys()) key: preferences.get(key)};
    final before = stored();
    scheduled.clear();
    cancelled.clear();
    events.clear();

    for (var run = 1; run <= 2; run++) {
      pluginCalls.clear();
      await refresh();
      await pumpEventQueue();
      expect(pluginCalls, ['pendingNotificationRequests']);
      expect(preferences.reloads, run);
    }
    expect(preferences.writes, isEmpty);
    expect(scheduled, isEmpty);
    expect(cancelled, isEmpty);
    expect(events, isEmpty);
    expect(stored(), before);

    // A changed plan is still written: one more date means one schedule call and one plan write.
    dates.add(DateTime(now.year, now.month, now.day + 4));
    await refresh();
    expect(scheduled, hasLength(1));
    expect(preferences.writes.where((key) => key.startsWith('medbuddy_reminder_plan_')),
        hasLength(1));
  });

  // Skipping repeated work must never skip a reservation that is needed: each change below has to
  // reach the device, and the refresh after it must be quiet again.
  test('time, language, new-date and lost-reservation changes are always rescheduled', () async {
    final service = NotificationService.instance;
    service.setHistoryUser('patient-a', persistSession: false);
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    DateTime day(int offset) => DateTime(now.year, now.month, now.day + offset);
    Future<void> refresh(
      List<DateTime> dates, {
      int hour = 8,
      String slotTitle = '아침',
      String language = 'ko',
    }) => service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: slotTitle, hour: hour, minute: 0,
      medicationNames: [], activeDates: dates, language: language,
    );
    // Mirrors Android: a scheduled id replaces the pending reservation with that id.
    void deliverToDevice() {
      for (final item in scheduled) {
        pending.removeWhere((entry) => entry['id'] == item['id']);
        pending.add({'id': item['id'], 'payload': item['payload']});
      }
      scheduled.clear();
    }

    await refresh([day(1), day(2)]);
    expect(scheduled, hasLength(2));
    deliverToDevice();

    // Reminder time changed.
    await refresh([day(1), day(2)], hour: 9);
    expect(scheduled, hasLength(2));
    for (final item in scheduled) {
      expect(item['scheduledDateTime'].toString(), contains('09:00'));
    }
    deliverToDevice();
    await refresh([day(1), day(2)], hour: 9);
    expect(scheduled, isEmpty);

    // Language changed, which changes the notification text.
    await refresh([day(1), day(2)], hour: 9, slotTitle: 'Morning', language: 'en');
    expect(scheduled, hasLength(2));
    expect(scheduled.first['title'], 'Morning medication schedule');
    expect(scheduled.first['body'], _body('en'));
    deliverToDevice();
    await refresh([day(1), day(2)], hour: 9, slotTitle: 'Morning', language: 'en');
    expect(scheduled, isEmpty);

    // A new medication or the rolling window adds a date.
    await refresh([day(1), day(2), day(3)], hour: 9, slotTitle: 'Morning', language: 'en');
    expect(scheduled, hasLength(1));
    expect(scheduled.single['payload'], endsWith(':${_dateKey(day(3))}'));
    deliverToDevice();

    // The device lost its reservations (reboot without the boot receiver, cleared alarms) while
    // the stored plan still lists them.
    pending.clear();
    await refresh([day(1), day(2), day(3)], hour: 9, slotTitle: 'Morning', language: 'en');
    expect(scheduled, hasLength(3));
    deliverToDevice();

    // A slot taken today is passed without today; its reservation is withdrawn, the others stay.
    cancelled.clear();
    await refresh([day(2), day(3)], hour: 9, slotTitle: 'Morning', language: 'en');
    expect(scheduled, isEmpty);
    expect(cancelled, hasLength(1));
  });

  // A changed reminder time keeps the notification id, so the inbox entry planned for the old time
  // has to be withdrawn explicitly or it would surface when the old time passes.
  test('changing the reminder time withdraws the inbox entries planned for the old time', () async {
    final service = NotificationService.instance;
    service.setHistoryUser('patient-a', persistSession: false);
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final dates = [
      DateTime(now.year, now.month, now.day + 1),
      DateTime(now.year, now.month, now.day + 2),
    ];
    Future<void> refresh(int hour, {String slotKey = 'morning', int id = 101}) =>
        service.registerNotification(
          id: id, slotKey: slotKey, slotTitle: slotKey, hour: hour, minute: 0,
          medicationNames: [], activeDates: dates,
        );
    Future<List<String>> plannedTimes() async => [
      for (final entry in await NotificationInboxStore(
        userHash: 'patient-a', now: () => now.add(const Duration(days: 5)),
      ).load())
        '${entry.payload.split(':')[1]} ${timezone.TZDateTime.from(entry.occurredAt, timezone.local).hour}',
    ]..sort();

    await refresh(8);
    await refresh(20, slotKey: 'evening', id: 103);
    pending.addAll(scheduled.map((item) => {'id': item['id'], 'payload': item['payload']}));
    // A snooze of the first morning reminder is planned under the same notification id.
    await service.snoozeMedicationReminder(
      id: scheduled.first['id'] as int, slotKey: 'morning', slotTitle: 'morning',
      scheduleDate: dates.first, delay: const Duration(days: 1, hours: 1),
    );
    expect(await plannedTimes(), hasLength(5));

    await refresh(9);

    final planned = await plannedTimes();
    expect(planned.where((entry) => entry.startsWith('morning')), ['morning 9', 'morning 9']);
    expect(planned.where((entry) => entry.startsWith('evening')), ['evening 20', 'evening 20']);
  });

  // After a force-stop Android has dropped the app's alarms, but the plugin still lists them as
  // pending. A new process must therefore re-arm every future date once instead of trusting the
  // list, without touching the inbox, and be quiet again afterwards.
  test('a new process re-arms reservations the plugin still lists', () async {
    final service = NotificationService.instance;
    service.setHistoryUser('patient-a', persistSession: false);
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final dates = [
      for (var day = 1; day <= 3; day++) DateTime(now.year, now.month, now.day + day),
    ];
    Future<void> refresh() => service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: '아침', hour: 8, minute: 0,
      medicationNames: [], activeDates: dates,
    );
    await refresh();
    await pumpEventQueue();
    final firstIds = [for (final item in scheduled) item['id']];
    expect(firstIds, hasLength(3));
    pending.addAll(scheduled.map((item) => {'id': item['id'], 'payload': item['payload']}));
    final events = <String>[];
    final subscription = NotificationInboxStore.changes.stream.listen(events.add);
    addTearDown(subscription.cancel);
    Future<int> inboxSize() async => (await NotificationInboxStore(
      userHash: 'patient-a', now: () => now.add(const Duration(days: 5)),
    ).load()).length;
    final inboxBefore = await inboxSize();
    scheduled.clear();

    // The process was killed: nothing in memory says the alarms were set by this run.
    service.forgetArmedRemindersForTest();
    await refresh();
    await pumpEventQueue();
    expect([for (final item in scheduled) item['id']], firstIds);
    for (final item in scheduled) {
      expect(item['scheduledDateTime'].toString(), contains('08:00'));
      expect(_scheduleMode(item), 'exactAllowWhileIdle');
    }
    expect(cancelled, isEmpty);
    expect(events, isEmpty);
    expect(await inboxSize(), inboxBefore);

    scheduled.clear();
    pluginCalls.clear();
    await refresh();
    expect(scheduled, isEmpty);
    expect(pluginCalls, ['pendingNotificationRequests']);
  });

  // Android 14 and later refuse exact alarms until the user allows them. The reminder is still
  // scheduled (inexact), stays untouched while the permission is missing, and is replaced by an
  // exact alarm by the first refresh after the permission was granted.
  test('reminders scheduled without the exact-alarm permission become exact once it is granted', () async {
    final service = NotificationService.instance;
    service.setHistoryUser('patient-a', persistSession: false);
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final dates = [
      DateTime(now.year, now.month, now.day + 1),
      DateTime(now.year, now.month, now.day + 2),
    ];
    Future<void> refresh() => service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: '아침', hour: 8, minute: 0,
      medicationNames: [], activeDates: dates,
    );
    void deliverToDevice() {
      for (final item in scheduled) {
        pending.removeWhere((entry) => entry['id'] == item['id']);
        pending.add({'id': item['id'], 'payload': item['payload']});
      }
      scheduled.clear();
    }

    exactDenied = true;
    expect(await service.canScheduleExactReminders(), isFalse);
    await refresh();
    expect(scheduled, hasLength(2));
    expect(scheduled.map(_scheduleMode).toSet(), {'inexactAllowWhileIdle'});
    deliverToDevice();

    // Still denied: nothing is rescheduled, the working inexact alarms stay.
    pluginCalls.clear();
    await refresh();
    expect(scheduled, isEmpty);
    expect(cancelled, isEmpty);
    expect(pluginCalls, ['pendingNotificationRequests', 'canScheduleExactNotifications']);

    // The user allowed "Alarms & reminders".
    exactDenied = false;
    expect(await service.canScheduleExactReminders(), isTrue);
    await refresh();
    expect(scheduled, hasLength(2));
    expect(scheduled.map(_scheduleMode).toSet(), {'exactAllowWhileIdle'});
    for (final item in scheduled) {
      expect(item['scheduledDateTime'].toString(), contains('08:00'));
    }
    expect(cancelled, isEmpty);
    deliverToDevice();

    pluginCalls.clear();
    await refresh();
    expect(scheduled, isEmpty);
    expect(pluginCalls, ['pendingNotificationRequests']);
  });

  // Returning from the system settings screen must not need a schedule refresh from the server:
  // the stored plan and the device's pending list are enough to replace the inexact alarms.
  test('inexact reminders are replaced from the stored plan without a schedule refresh', () async {
    final service = NotificationService.instance;
    service.setHistoryUser('patient-a', persistSession: false);
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final dates = [
      DateTime(now.year, now.month, now.day + 1),
      DateTime(now.year, now.month, now.day + 2),
    ];
    exactDenied = true;
    await service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: '아침', hour: 8, minute: 30,
      medicationNames: [], activeDates: dates,
    );
    await service.registerNotification(
      id: 103, slotKey: 'evening', slotTitle: 'Evening', hour: 19, minute: 5,
      medicationNames: [], activeDates: [dates.first], language: 'en',
    );
    final inexact = [for (final item in scheduled) Map<dynamic, dynamic>.from(item)];
    expect(inexact, hasLength(3));
    pending.addAll(scheduled.map((item) => {'id': item['id'], 'payload': item['payload']}));
    scheduled.clear();

    // Permission still missing: the plan is left alone.
    await service.rescheduleInexactRemindersAsExact();
    expect(scheduled, isEmpty);

    exactDenied = false;
    await service.rescheduleInexactRemindersAsExact();
    expect(scheduled, hasLength(3));
    for (final before in inexact) {
      final after = scheduled.singleWhere((item) => item['id'] == before['id']);
      expect(_scheduleMode(after), 'exactAllowWhileIdle');
      for (final field in ['title', 'body', 'payload', 'scheduledDateTime']) {
        expect(after[field], before[field], reason: field);
      }
    }
    expect(cancelled, isEmpty);

    // Done once: neither a second call nor the next refresh schedules anything again.
    scheduled.clear();
    pluginCalls.clear();
    await service.rescheduleInexactRemindersAsExact();
    expect(scheduled, isEmpty);
    expect(pluginCalls, isEmpty);
    await service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: '아침', hour: 8, minute: 30,
      medicationNames: [], activeDates: dates,
    );
    expect(scheduled, isEmpty);
  });

  // Decision pinned here: when the reminder time is moved to a time that has already passed today,
  // today's alarm at the previous time is kept. Cancelling it would leave today's dose, not yet
  // taken, without any reminder; from tomorrow the new time applies.
  test('moving the reminder time to earlier than now keeps the alarm still due today', () async {
    final service = NotificationService.instance;
    service.setHistoryUser('patient-a', persistSession: false);
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final later = now.add(const Duration(minutes: 5));
    final earlier = now.subtract(const Duration(minutes: 5));
    if (later.day != now.day || earlier.day != now.day) {
      markTestSkipped('Needs five minutes on both sides of now within one day.');
      return;
    }
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    Future<void> refresh(timezone.TZDateTime time) => service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: '아침', hour: time.hour, minute: time.minute,
      medicationNames: [], activeDates: [today, tomorrow],
    );
    await refresh(later);
    expect(scheduled, hasLength(2));
    final todayId = scheduled.first['id'];
    pending.addAll(scheduled.map((item) => {'id': item['id'], 'payload': item['payload']}));
    scheduled.clear();

    await refresh(earlier);

    expect(cancelled, isNot(contains(containsPair('id', todayId))));
    expect(scheduled, hasLength(1));
    expect(scheduled.single['payload'], endsWith(':${_dateKey(tomorrow)}'));
    expect(
      scheduled.single['scheduledDateTime'].toString(),
      contains('${earlier.hour.toString().padLeft(2, '0')}:${earlier.minute.toString().padLeft(2, '0')}'),
    );
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

// Function Name: _scheduleMode
// Description: Reads the Android schedule mode of a recorded zonedSchedule call.
// Parameters: call - arguments the plugin received. Returns: The mode name, such as exactAllowWhileIdle.
String _scheduleMode(Map<dynamic, dynamic> call) =>
    (call['platformSpecifics'] as Map)['scheduleMode'] as String;
