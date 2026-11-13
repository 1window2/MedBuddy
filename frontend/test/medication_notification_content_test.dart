// File Name: medication_notification_content_test.dart
// Role: Regression coverage at the Android notification channel boundary, including privacy, localization and dated reminder refresh.
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
// Role: Counts preference reloads and writes made by reminder refreshes without changing storage behavior.
// Responsibilities:
// - Forward supported operations to the wrapped store and reject any unexpected interface call.
// Attributes:
// - _inner (SharedPreferences): underlying in-memory test store.
// - reloads (int): reload attempts. writes (List<String>): written or removed keys in call order.
class _CountingPreferences implements SharedPreferences {
  // Function Name: _CountingPreferences
  // Description:
  // - Wrap the real test preference store so refresh side effects can be counted.
  // Parameters:
  // - _inner (SharedPreferences): store receiving forwarded operations.
  // Returns:
  // - _CountingPreferences; wrapper with empty counters.
  _CountingPreferences(this._inner);

  final SharedPreferences _inner;
  int reloads = 0;
  final List<String> writes = [];

  // Function Name: reload
  // Description:
  // - Count a reload attempt before forwarding it to the underlying store.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completion or failure from the wrapped reload.
  @override
  Future<void> reload() {
    reloads++;
    return _inner.reload();
  }

  // Function Name: getKeys
  // Description:
  // - Read the complete key set from the wrapped preference cache.
  // Parameters:
  // - None.
  // Returns:
  // - Set<String>; keys currently present in the store.
  @override
  Set<String> getKeys() => _inner.getKeys();

  // Function Name: containsKey
  // Description:
  // - Check whether the wrapped store contains a given key.
  // Parameters:
  // - key (String): preference key to look up.
  // Returns:
  // - bool; true when the key exists.
  @override
  bool containsKey(String key) => _inner.containsKey(key);

  // Function Name: get
  // Description:
  // - Read a preference without coercing its stored type.
  // Parameters:
  // - key (String): preference key to look up.
  // Returns:
  // - Object?; stored value or null when absent.
  @override
  Object? get(String key) => _inner.get(key);

  // Function Name: getString
  // Description:
  // - Read a string preference using the wrapped store's type checks.
  // Parameters:
  // - key (String): preference key to look up.
  // Returns:
  // - String?; stored text or null, with type errors delegated to the store.
  @override
  String? getString(String key) => _inner.getString(key);

  // Function Name: getBool
  // Description:
  // - Read a boolean preference using the wrapped store's type checks.
  // Parameters:
  // - key (String): preference key to look up.
  // Returns:
  // - bool?; stored flag or null, with type errors delegated to the store.
  @override
  bool? getBool(String key) => _inner.getBool(key);

  // Function Name: setString
  // Description:
  // - Record the key of a string write before forwarding the original value.
  // Parameters:
  // - key (String): destination preference key.
  // - value (String): text to persist.
  // Returns:
  // - Future<bool>; wrapped write result or propagated storage failure.
  @override
  Future<bool> setString(String key, String value) {
    writes.add(key);
    return _inner.setString(key, value);
  }

  // Function Name: setBool
  // Description:
  // - Record the key of a boolean write before forwarding the original flag.
  // Parameters:
  // - key (String): destination preference key.
  // - value (bool): flag to persist.
  // Returns:
  // - Future<bool>; wrapped write result or propagated storage failure.
  @override
  Future<bool> setBool(String key, bool value) {
    writes.add(key);
    return _inner.setBool(key, value);
  }

  // Function Name: remove
  // Description:
  // - Record a removal attempt before deleting the key through the wrapped store.
  // Parameters:
  // - key (String): preference key to remove.
  // Returns:
  // - Future<bool>; wrapped removal result or propagated storage failure.
  @override
  Future<bool> remove(String key) {
    writes.add(key);
    return _inner.remove(key);
  }

  // Function Name: noSuchMethod
  // Description:
  // - Reject calls outside the preference operations used by the reminder path.
  // Parameters:
  // - invocation (Invocation): unsupported member invocation.
  // Returns:
  // - dynamic; delegates to Object.noSuchMethod, which throws NoSuchMethodError.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Function Name: main
// Description:
// - Register mocked platform-channel cases for reminder contents, actions, privacy changes and differential rescheduling.
// Parameters:
// - None.
// Returns:
// - No value; the framework executes the registered cases and fixture hooks.
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

  // Function Name: as-needed check has neutral copy and no take or snooze action
  // Description:
  // - Schedule an as-needed check with neutral review wording and no take or snooze actions.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('as-needed check has neutral copy and no take or snooze action', () async {
    final now = DateTime.now();
    final next = now.add(const Duration(days: 1));
    await NotificationService.instance.registerNotification(
      id: 84005, slotKey: 'as_needed', slotTitle: '필요시 약', hour: 12, minute: 0,
      activeDates: [next],
    );
    expect(scheduled, hasLength(1));
    expect(scheduled.single['title'], '필요시 약 확인');
    expect(scheduled.single['body'], '필요시 약과 오늘 기록한 복용 내역을 확인해 주세요.');
    final details = scheduled.single['platformSpecifics'] as Map;
    expect(details['actions'], isEmpty);
  });

  // Function Name: setUp
  // Description:
  // - Reset account, preferences, reservation logs, and process-local reminder state; install an Android channel fake with configurable exact-alarm rejection.
  // Parameters:
  // - None.
  // Returns:
  // - void; subsequent plugin calls are recorded and answered without native notifications.
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

  // 함수이름: tearDown
  // 함수역할:
  // - 환경설정 로더·시계·민감정보 표시를 기본값으로 복구하고 채널 대역과 Android 플랫폼 강제를 해제한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - void; 테스트별 전역 대역을 정리한다.
  tearDown(() {
    NotificationService.preferencesLoader = SharedPreferences.getInstance;
    NotificationService.clock = DateTime.now;
    NotificationService.instance.setShowSensitiveDetails(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  // Function Name: chat preview truncation never splits an emoji
  // Description:
  // - Normalize preview whitespace and truncate by grapheme clusters, preserving complete emoji sequences at the length boundary.
  // Parameters:
  // - None.
  // Returns:
  // - void; no return value.
  test('chat preview truncation never splits an emoji', () {
    expect(
      NotificationService.linkedChatMessagePreview('  hello \n  there '),
      'hello there',
    );
    const family = '👨‍👩‍👧';
    final long = '${'a' * 118}$family${'b' * 10}';
    final preview = NotificationService.linkedChatMessagePreview(long);
    expect(preview, '${'a' * 118}$family…');
    final exact = '${'a' * 119}$family';
    expect(NotificationService.linkedChatMessagePreview(exact), exact);
    expect(
      NotificationService.linkedChatMessagePreview('${'a' * 119}👍👍'),
      '${'a' * 119}…',
    );
  });

  // Function Name: completed widget dose cancels its dated snooze without losing other reminders
  // Description:
  // - Cancel only the completed patient/date/slot reminder and snooze, using persisted ownership when background memory has no account; preserve other reminders and chat alerts.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
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
          activeDates: [first, second],
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

  // 함수이름: widget cancellation stops after logout or account switch
  // 함수역할:
  // - 로그아웃했거나 저장된 계정이 바뀌었으면 이전 사용자의 위젯 취소 요청이 아무 알림도 취소하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 비동기 검증이 끝나면 완료한다.
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

  // Function Name: unchanged reminders and snoozes survive differential refresh
  // Description:
  // - Keep unchanged reservations and snoozes, then cancel only the removed date and reschedule the changed time.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('unchanged reminders and snoozes survive differential refresh', () async {
    final service = NotificationService.instance;
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final first = DateTime(now.year, now.month, now.day + 1);
    final second = DateTime(now.year, now.month, now.day + 2);
    // Function Name: refresh
    // Description:
    // - Refresh the morning reminder for a selected date set and hour.
    // Parameters:
    // - dates (List<DateTime>): active dose dates.
    // - hour (int): local reminder hour, defaulting to 8.
    // Returns:
    // - Future<void>; reminder reconciliation completion.
    Future<void> refresh(List<DateTime> dates, {int hour = 8}) => service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: '아침', hour: hour, minute: 0,
      activeDates: dates,
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

  // Function Name: moving a reminder before now preserves today and replaces future history
  // Description:
  // - Moving a reminder earlier than the fixed current time keeps today's old alarm and inbox time while replacing tomorrow's planned time.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('moving a reminder before now preserves today and replaces future history', () async {
    final service = NotificationService.instance;
    service.setHistoryUser('patient-a', persistSession: false);
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final today = timezone.TZDateTime(timezone.local, now.year, now.month, now.day + 2);
    NotificationService.clock = () => today.add(const Duration(hours: 12));
    final tomorrow = today.add(const Duration(days: 1));
    // Function Name: refresh
    // Description:
    // - Register English morning reminders for today and tomorrow at the supplied hour.
    // Parameters:
    // - hour (int): local reminder hour used for the fixed two-day plan.
    // Returns:
    // - Future<void>; reconciliation completion.
    Future<void> refresh(int hour) => service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: 'Morning', hour: hour, minute: 0,
      activeDates: [today, tomorrow], language: 'en',
    );

    await refresh(16);
    expect(scheduled, hasLength(2));
    final oldTodayId = scheduled.first['id'];
    pending.addAll(scheduled.map((item) => {'id': item['id'], 'payload': item['payload']}));
    scheduled.clear();

    await refresh(8);
    expect(cancelled, isNot(contains(containsPair('id', oldTodayId))));
    expect(scheduled, hasLength(1));
    expect(scheduled.single['id'], isNot(oldTodayId));
    expect(scheduled.single['scheduledDateTime'].toString(), contains('08:00'));
    final history = await NotificationInboxStore(
      userHash: 'patient-a', now: () => tomorrow.add(const Duration(days: 1)),
    ).load();
    expect(history, hasLength(2));
    final todayEntry = history.singleWhere(
      (entry) => entry.payload.split(':')[2] == '$oldTodayId',
    );
    expect(
      todayEntry.occurredAt.isAtSameMomentAs(today.add(const Duration(hours: 16))),
      isTrue,
    );
    final tomorrowEntry = history.singleWhere(
      (entry) => entry.payload.split(':')[2] != '$oldTodayId',
    );
    expect(
      tomorrowEntry.occurredAt.isAtSameMomentAs(tomorrow.add(const Duration(hours: 8))),
      isTrue,
    );
  });

  // Function Name: a snooze survives refresh after the unchanged original time has passed
  // Description:
  // - Preserve an existing snooze when refresh occurs after the unchanged original reminder time.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('a snooze survives refresh after the unchanged original time has passed', () async {
    final service = NotificationService.instance;
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final today = timezone.TZDateTime(timezone.local, now.year, now.month, now.day + 2);
    NotificationService.clock = () => today.add(const Duration(hours: 7));
    // Function Name: refresh
    // Description:
    // - Reapply the fixed 08:00 reminder for the captured test day.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; reconciliation completion.
    Future<void> refresh() => service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: 'Morning', hour: 8, minute: 0,
      activeDates: [today], language: 'en',
    );
    await refresh();
    final id = scheduled.single['id'] as int;
    pending.add({'id': id, 'payload': scheduled.single['payload']});
    NotificationService.clock = () => today.add(const Duration(hours: 9));
    await service.snoozeMedicationReminder(
      id: id, slotKey: 'morning', slotTitle: 'Morning', scheduleDate: today,
    );
    scheduled.clear();
    cancelled.clear();

    await refresh();
    expect(scheduled, isEmpty);
    expect(cancelled, isEmpty);
  });

  // Function Name: a snooze across midnight survives a refresh of the new day
  // Description:
  // - Keep a pre-midnight snooze tied to its original dose day when the next-day plan is refreshed.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('a snooze across midnight survives a refresh of the new day', () async {
    final service = NotificationService.instance;
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final day = timezone.TZDateTime(timezone.local, now.year, now.month, now.day + 2);
    final nextDay = day.add(const Duration(days: 1));
    NotificationService.clock = () => day.add(const Duration(hours: 21));
    await service.registerNotification(
      id: 104, slotKey: 'bedtime', slotTitle: 'Bedtime', hour: 22, minute: 0,
      activeDates: [day, nextDay], language: 'en',
    );
    NotificationService.clock = () => day.add(const Duration(hours: 23, minutes: 58));
    final snoozedId = scheduled.first['id'] as int;
    await service.snoozeMedicationReminder(
      id: snoozedId, slotKey: 'bedtime', slotTitle: 'Bedtime', scheduleDate: day,
    );
    pending
      ..clear()
      ..addAll(scheduled.map((item) => {'id': item['id'], 'payload': item['payload']}));
    cancelled.clear();

    NotificationService.clock = () => nextDay.add(const Duration(minutes: 2));
    await service.registerNotification(
      id: 104, slotKey: 'bedtime', slotTitle: 'Bedtime', hour: 22, minute: 0,
      activeDates: [nextDay], language: 'en',
    );
    expect(cancelled.map((call) => call['id']), isNot(contains(snoozedId)));
  });

  // Function Name: earlier-day reminders that cannot be a snooze are still cancelled
  // Description:
  // - Cancel entries too old to remain snoozed while preserving yesterday's possible snooze just after midnight, preventing obsolete alarms from being restored on reboot.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('earlier-day reminders that cannot be a snooze are still cancelled', () async {
    final service = NotificationService.instance;
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final day = timezone.TZDateTime(timezone.local, now.year, now.month, now.day + 2);
    final nextDay = day.add(const Duration(days: 1));
    final thirdDay = nextDay.add(const Duration(days: 1));
    NotificationService.clock = () => day.subtract(const Duration(hours: 1));
    await service.registerNotification(
      id: 104, slotKey: 'bedtime', slotTitle: 'Bedtime', hour: 22, minute: 0,
      activeDates: [day, nextDay, thirdDay], language: 'en',
    );
    final dayId = scheduled[0]['id'] as int;
    final nextDayId = scheduled[1]['id'] as int;
    pending
      ..clear()
      ..addAll(scheduled.map((item) => {'id': item['id'], 'payload': item['payload']}));
    cancelled.clear();

    // Opened just after midnight two days later: the entry of two days ago goes, yesterday's
    // may still be a snooze and stays.
    NotificationService.clock = () => thirdDay.add(const Duration(minutes: 2));
    await service.registerNotification(
      id: 104, slotKey: 'bedtime', slotTitle: 'Bedtime', hour: 22, minute: 0,
      activeDates: [thirdDay], language: 'en',
    );
    expect(cancelled.map((call) => call['id']), contains(dayId));
    expect(cancelled.map((call) => call['id']), isNot(contains(nextDayId)));

    // After the first hour no snooze of yesterday can still be waiting.
    cancelled.clear();
    NotificationService.clock = () => thirdDay.add(const Duration(hours: 2));
    await service.registerNotification(
      id: 104, slotKey: 'bedtime', slotTitle: 'Bedtime', hour: 22, minute: 0,
      activeDates: [thirdDay], language: 'en',
    );
    expect(cancelled.map((call) => call['id']), contains(nextDayId));
  });

  // Function Name: an unchanged refresh only reads the pending reservations
  // Description:
  // - In steady state, read pending reservations and reload preferences once per refresh without scheduling, cancellation, writes, or inbox events; still persist a newly added date.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
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
    // Function Name: refresh
    // Description:
    // - Reconcile the captured three-day morning plan, including any date appended by the test.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; reminder reconciliation completion.
    Future<void> refresh() => service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: '아침', hour: 8, minute: 0,
      activeDates: dates,
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
    // Function Name: stored
    // Description:
    // - Snapshot every stored preference without changing the counting wrapper.
    // Parameters:
    // - None.
    // Returns:
    // - Map<String, Object?>; current key/value pairs for equality checks.
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

  // Function Name: time, language, new-date and lost-reservation changes are always rescheduled
  // Description:
  // - Reschedule changed time, language, new dates, or missing device reservations, then become quiet again; remove only a withdrawn dose date.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('time, language, new-date and lost-reservation changes are always rescheduled', () async {
    final service = NotificationService.instance;
    service.setHistoryUser('patient-a', persistSession: false);
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    // Function Name: day
    // Description:
    // - Construct a local midnight date relative to the captured calendar day.
    // Parameters:
    // - offset (int): number of calendar days after the captured day.
    // Returns:
    // - DateTime; normalized local date.
    DateTime day(int offset) => DateTime(now.year, now.month, now.day + offset);
    // Function Name: refresh
    // Description:
    // - Reconcile a morning plan with selectable dates, time, title, and language.
    // Parameters:
    // - dates (List<DateTime>): active dose dates.
    // - hour (int): local hour, default 8.
    // - slotTitle (String): displayed slot label, default Korean morning.
    // - language (String): notification language, default ko.
    // Returns:
    // - Future<void>; reconciliation completion.
    Future<void> refresh(
      List<DateTime> dates, {
      int hour = 8,
      String slotTitle = '아침',
      String language = 'ko',
    }) => service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: slotTitle, hour: hour, minute: 0,
      activeDates: dates, language: language,
    );
    // Function Name: deliverToDevice
    // Description:
    // - Apply recorded schedules to the fake pending list by notification ID, then clear the outgoing schedule log.
    // Parameters:
    // - None.
    // Returns:
    // - void; mirrors Android replacement of an existing reservation with the same ID.
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
    expect(scheduled.single['payload'], contains(':${_dateKey(day(3))}:'));
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

  // Function Name: changing the reminder time withdraws the inbox entries planned for the old time
  // Description:
  // - Replace inbox entries for a changed reminder time, including its snooze, while preserving the other slot; stable notification IDs must not leave the old planned time visible.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('changing the reminder time withdraws the inbox entries planned for the old time', () async {
    final service = NotificationService.instance;
    service.setHistoryUser('patient-a', persistSession: false);
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final dates = [
      DateTime(now.year, now.month, now.day + 1),
      DateTime(now.year, now.month, now.day + 2),
    ];
    // Function Name: refresh
    // Description:
    // - Refresh the captured dates for one slot and notification ID at a new hour.
    // Parameters:
    // - hour (int): replacement local hour.
    // - slotKey (String): slot to refresh, default morning.
    // - id (int): base notification identifier, default 101.
    // Returns:
    // - Future<void>; reconciliation completion.
    Future<void> refresh(int hour, {String slotKey = 'morning', int id = 101}) =>
        service.registerNotification(
          id: id, slotKey: slotKey, slotTitle: slotKey, hour: hour, minute: 0,
          activeDates: dates,
        );
    // Function Name: plannedTimes
    // Description:
    // - Read future inbox entries using a five-day look-ahead clock and sort their slot/hour summaries.
    // Parameters:
    // - None.
    // Returns:
    // - Future<List<String>>; sorted local-time slot/hour labels.
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

  // Function Name: a new process re-arms reservations the plugin still lists
  // Description:
  // - After process memory is cleared, re-arm every future reservation once even when the plugin still lists it, without changing inbox data or emitting events.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('a new process re-arms reservations the plugin still lists', () async {
    final service = NotificationService.instance;
    service.setHistoryUser('patient-a', persistSession: false);
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final dates = [
      for (var day = 1; day <= 3; day++) DateTime(now.year, now.month, now.day + day),
    ];
    // Function Name: refresh
    // Description:
    // - Reapply the captured morning dates to exercise first-process rearming and later no-op refresh.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; reconciliation completion.
    Future<void> refresh() => service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: '아침', hour: 8, minute: 0,
      activeDates: dates,
    );
    await refresh();
    await pumpEventQueue();
    final firstIds = [for (final item in scheduled) item['id']];
    expect(firstIds, hasLength(3));
    pending.addAll(scheduled.map((item) => {'id': item['id'], 'payload': item['payload']}));
    final events = <String>[];
    final subscription = NotificationInboxStore.changes.stream.listen(events.add);
    addTearDown(subscription.cancel);
    // Function Name: inboxSize
    // Description:
    // - Count this patient's inbox entries visible five days after the captured time.
    // Parameters:
    // - None.
    // Returns:
    // - Future<int>; inbox entry count including the planned test dates.
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

  // Function Name: reminders scheduled without the exact-alarm permission become exact once it is granted
  // Description:
  // - Use inexact alarms while permission is denied, preserve them on unchanged refresh, and replace them once with exact alarms when permission is granted.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('reminders scheduled without the exact-alarm permission become exact once it is granted', () async {
    final service = NotificationService.instance;
    service.setHistoryUser('patient-a', persistSession: false);
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final dates = [
      DateTime(now.year, now.month, now.day + 1),
      DateTime(now.year, now.month, now.day + 2),
    ];
    // Function Name: refresh
    // Description:
    // - Reconcile the captured two-day morning plan under the current exact-alarm permission state.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; reconciliation completion.
    Future<void> refresh() => service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: '아침', hour: 8, minute: 0,
      activeDates: dates,
    );
    // Function Name: deliverToDevice
    // Description:
    // - Replace fake pending entries by ID with the scheduled alarms and empty the schedule log.
    // Parameters:
    // - None.
    // Returns:
    // - void; updates the simulated device reservation state.
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

  // Function Name: inexact reminders are replaced from the stored plan without a schedule refresh
  // Description:
  // - Upgrade inexact alarms from the stored plan alone after permission is granted, preserving IDs, text, payloads, and times without repeating the upgrade.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
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
      activeDates: dates,
    );
    await service.registerNotification(
      id: 103, slotKey: 'evening', slotTitle: 'Evening', hour: 19, minute: 5,
      activeDates: [dates.first], language: 'en',
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
      activeDates: dates,
    );
    expect(scheduled, isEmpty);
  });

  // Function Name: moving the reminder time to earlier than now keeps the alarm still due today
  // Description:
  // - Keep today's still-due alarm when its replacement time is already past and apply the new time tomorrow; skip near midnight when the five-minute comparison spans days.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
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
    // Function Name: refresh
    // Description:
    // - Refresh today and tomorrow using the hour and minute of the supplied zoned time.
    // Parameters:
    // - time (timezone.TZDateTime): reminder time before or after the captured current time.
    // Returns:
    // - Future<void>; reconciliation completion.
    Future<void> refresh(timezone.TZDateTime time) => service.registerNotification(
      id: 101, slotKey: 'morning', slotTitle: '아침', hour: time.hour, minute: time.minute,
      activeDates: [today, tomorrow],
    );
    await refresh(later);
    expect(scheduled, hasLength(2));
    final todayId = scheduled.first['id'];
    pending.addAll(scheduled.map((item) => {'id': item['id'], 'payload': item['payload']}));
    scheduled.clear();

    await refresh(earlier);

    expect(cancelled, isNot(contains(containsPair('id', todayId))));
    expect(scheduled, hasLength(1));
    expect(scheduled.single['payload'], contains(':${_dateKey(tomorrow)}:'));
    expect(
      scheduled.single['scheduledDateTime'].toString(),
      contains('${earlier.hour.toString().padLeft(2, '0')}:${earlier.minute.toString().padLeft(2, '0')}'),
    );
  });

  // Function Name: account and missing platform reservations cannot reuse another plan
  // Description:
  // - Do not reuse another account's reminder plan, and restore missing device reservations even when the current account's plan is unchanged.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
  test('account and missing platform reservations cannot reuse another plan', () async {
    final service = NotificationService.instance;
    await service.initialize();
    final now = timezone.TZDateTime.now(timezone.local);
    final date = DateTime(now.year, now.month, now.day + 1);
    // Function Name: refresh
    // Description:
    // - Refresh the same captured morning date under whichever account is currently active.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; reconciliation completion.
    Future<void> refresh() => service.registerNotification(id: 101,
        slotKey: 'morning', slotTitle: '아침', hour: 8, minute: 0,
        activeDates: [date]);
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

  // Function Name: disabling reminders removes delivered actions but preserves other alerts
  // Description:
  // - Remove pending medication reminders and delivered dose actions while retaining chat, caregiver, and unidentified notifications.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
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

  // Function Name: disabling one slot removes its delivered actions only
  // Description:
  // - Cancel only the requested slot's base, dated, and delivered reminders; preserve other slots and similarly prefixed group keys.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
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

  // Function Name: legacy Android reminders match date IDs only on their channel
  // Description:
  // - Recognize legacy date-derived IDs only on the medication reminder channel, leaving matching IDs on unrelated channels untouched.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
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

  // Function Name: session cleanup recognizes Android channels without payloads
  // Description:
  // - Clear all MedBuddy notification channels during session cleanup even without payloads, preserving unrelated channels.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes after the asynchronous checks.
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
      // Function Name: stale name snapshots are neutral: $language/$sensitiveDetails
      // Description:
      // - Use neutral slot text without medication names for either language and privacy mode, with the correct date payload and reminder group.
      // Parameters:
      // - None.
      // Returns:
      // - Future<void>; completes after the asynchronous checks.
      test('stale name snapshots are neutral: $language/$sensitiveDetails', () async {
        final service = NotificationService.instance;
        service.setShowSensitiveDetails(sensitiveDetails);
        await service.initialize();
        final tomorrow = timezone.TZDateTime.now(timezone.local)
            .add(const Duration(days: 1));
        // Names captured before partial or full completion must never be
        // presented as instructions to take those medications again. The
        // registration takes no medication names at all, so the reminder
        // carries only the neutral slot text.
        await service.registerNotification(
          id: 101,
          slotKey: 'evening',
          slotTitle: 'Evening',
          hour: 20,
          minute: 0,
          activeDates: [tomorrow],
          language: language,
        );
        expect(scheduled.last['body'], _body(language));
        expect((scheduled.last['platformSpecifics'] as Map)['groupKey'],
            'medbuddy.reminder.evening');
        expect(scheduled.last['title'], language == 'en'
            ? 'Evening medication schedule' : 'Evening 복약 일정 확인');
        expect(scheduled.last['payload'], contains(':${_dateKey(tomorrow)}:'));
        expect(scheduled, hasLength(1));
      });
    }

    // Function Name: snooze fallback keeps neutral copy and original day: $language
    // Description:
    // - When exact snooze scheduling fails, keep neutral localized wording and the original dose day in both exact and fallback attempts.
    // Parameters:
    // - None.
    // Returns:
    // - Future<void>; completes after the asynchronous checks.
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
        expect(
          notification['payload'],
          startsWith('schedule:evening:102:${_dateKey(original)}:'),
        );
      }
    });
  }
}

// Function Name: _body
// Description:
// - Return the expected neutral reminder body for English or the Korean fallback.
// Parameters:
// - language (String): en selects English; every other value selects Korean.
// Returns:
// - String; localized schedule-and-completion review text.
String _body(String language) => language == 'en'
    ? 'Check your medication schedule and recorded completion status.'
    : '복약 일정과 복용 완료 기록을 확인해 주세요.';

// Function Name: _dateKey
// Description:
// - Format the supplied calendar fields as a zero-padded date without timezone conversion.
// Parameters:
// - date (DateTime): date whose year, month, and day are encoded.
// Returns:
// - String; YYYY-MM-DD key.
String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

// Function Name: _scheduleMode
// Description:
// - Read the Android schedule-mode string from a recorded plugin call.
// Parameters:
// - call (Map<dynamic, dynamic>): zonedSchedule arguments containing platformSpecifics.scheduleMode.
// Returns:
// - String; schedule mode; malformed map shapes or types fail the casts.
String _scheduleMode(Map<dynamic, dynamic> call) =>
    (call['platformSpecifics'] as Map)['scheduleMode'] as String;
