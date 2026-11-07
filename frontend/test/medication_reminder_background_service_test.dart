// File Name: medication_reminder_background_service_test.dart
// Role: Verify background reminder recovery, account ownership, completion filtering, and rolling dose-cycle windows.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/app_language_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:medbuddy_frontend/services/medication_reminder_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Function Name: main
// Description: Registers background-refresh regressions for offline recovery, sign-out ownership, rolling reminder windows, completed slots, and dose cycles.
// Parameters: None.
// Returns: void; the test framework executes the registered fixtures and cases.
void main() {
  // Function Name: offline refresh recovery test
  // Description: Verifies that a failed schedule load leaves all native alarms untouched; after reconnection, refresh registers the active morning slot and cancels the other three.
  // Parameters: None.
  // Returns: Future<void>; fails if offline refresh changes alarms or the recovered registration/cancellation counts differ.
  test('offline refresh preserves native alarms and recovers after reconnect', () async {
    SharedPreferences.setMockInitialValues({});
    var offline = true;
    var registered = 0;
    var cancelled = 0;
    final service = MedicationReminderRefreshService(
      loadSettings: () async => const [
        MedicationAlarm(slotKey: 'morning', hour: 8, minute: 0, enabled: true),
      ],
      loadSchedules: () async {
        if (offline) throw StateError('network unavailable');
        return [MedicationSchedule(
          medicationName: 'TEST_ONLY',
          prescriptionDate: DateTime(2026, 9, 13),
          medicationTime: 2,
          scheduleSlotKeys: const ['morning'],
        )];
      },
      registerReminder: ({required id, required slotKey, required slotTitle,
        required hour, required minute,
        required activeDates, language = 'ko'}) async { registered++; },
      cancelReminder: (id, {slotKey}) async { cancelled++; },
      now: () => DateTime(2026, 9, 13, 7),
    );
    expect(await service.synchronize(), isFalse);
    expect(registered, 0);
    expect(cancelled, 0);
    offline = false;
    expect(await service.synchronize(), isTrue);
    expect(registered, 1);
    expect(cancelled, 3);
    service.dispose();
  });
  // 로그아웃 때 이미 돌던 작업은 이전 계정의 알림을 다시 걸지 않는다. 확인 직전·직후 어느 쪽에서
  // 로그아웃해도 알림이 남지 않는다.
  for (final signOutAfter in [0, 1]) {
    // Function Name: sign-out during refresh test
    // Description: Revokes reminder ownership on the first or second check and verifies that synchronization completes with no old-account reminder left armed.
    // Parameters: None; signOutAfter selects how many ownership checks succeed before sign-out.
    // Returns: Future<void>; fails if synchronization reports failure or any slot remains armed.
    test('a worker running at sign-out leaves no reminder (checks before sign-out: $signOutAfter)', () async {
      SharedPreferences.setMockInitialValues({});
      final armed = <String>{};
      var checks = 0;
      final service = MedicationReminderRefreshService(
        loadSettings: () async => const [
          MedicationAlarm(slotKey: 'morning', hour: 8, minute: 0, enabled: true),
          MedicationAlarm(slotKey: 'evening', hour: 19, minute: 0, enabled: true),
        ],
        loadSchedules: () async => [MedicationSchedule(
          medicationName: 'TEST_ONLY',
          prescriptionDate: DateTime(2026, 9, 13),
          medicationTime: 2,
          scheduleSlotKeys: const ['morning', 'evening'],
        )],
        registerReminder: ({required id, required slotKey, required slotTitle,
          required hour, required minute,
          required activeDates, language = 'ko'}) async { armed.add(slotKey); },
        cancelReminder: (id, {slotKey}) async { armed.remove(slotKey); },
        now: () => DateTime(2026, 9, 13, 7),
        ownsReminders: () async => checks++ < signOutAfter,
      );
      expect(await service.synchronize(), isTrue);
      expect(armed, isEmpty);
      service.dispose();
    });
  }

  // Function Name: rolling long-course window test
  // Description: Verifies that a forty-day course registers the first fourteen-day window, then replenishes a new fourteen-day window when the clock advances two weeks.
  // Parameters: None.
  // Returns: Future<void>; fails if either synchronization or the registered window's length and endpoints differ.
  test('백그라운드 동기화가 14일 이후의 장기 복약 알림을 보충한다', () async {
    SharedPreferences.setMockInitialValues({
      AppLanguageControl.preferenceKey: 'ko',
    });
    final courseStart = DateTime(2026, 8, 1);
    var currentTime = DateTime(2026, 8, 1, 7);
    final registeredWindows = <List<DateTime>>[];
    final service = MedicationReminderRefreshService(
      // Function Name: loadSettings callback
      // Description:
      // - Provide an enabled 08:00 morning alarm for patient-a without server access.
      // Parameters:
      // - None.
      // Returns:
      // - One enabled morning alarm.
      loadSettings: () async => const [
        MedicationAlarm(
          patientHash: 'patient-a',
          slotKey: 'morning',
          hour: 8,
          minute: 0,
          enabled: true,
        ),
      ],
      // Function Name: loadSchedules callback
      // Description:
      // - Provide a forty-day morning medication course starting at the controlled course date.
      // Parameters:
      // - None.
      // Returns:
      // - A schedule list containing the long-running course.
      loadSchedules: () async => [
        MedicationSchedule(
          medicationName: '장기복용정',
          prescriptionDate: courseStart,
          medicationTime: 40,
          scheduleSlotKeys: const ['morning'],
        ),
      ],
      registerReminder:
          // Function Name: registerReminder callback
          // Description:
          // - Copy each registered date window so later replenishment can be compared with earlier
          //   registrations.
          // Parameters:
          // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
          //   consumed by this fixture.
          // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime. Accepted but not consumed
          //   by this fixture.
          // - slotTitle (String): Localized user-visible name of the dose slot. Accepted but not consumed by
          //   this fixture.
          // - hour (int): Selected local alarm hour in 24-hour time. Accepted but not consumed by this fixture.
          // - minute (int): Selected minute component of the local alarm time. Accepted but not consumed by this
          //   fixture.
          // - activeDates (List<DateTime>): Dates on which this dose is active.
          // - language (String): Language code used for labels or notification content. Accepted but not
          //   consumed by this fixture.
          // Returns:
          // - Future<void>; records the active-date window.
          ({
            required id,
            required slotKey,
            required slotTitle,
            required hour,
            required minute,
            required activeDates,
            language = 'ko',
          }) async {
            registeredWindows.add(List<DateTime>.from(activeDates));
          },
      // Function Name: cancelReminder callback
      // Description:
      // - Acknowledge unrelated reminder cancellations without device access.
      // Parameters:
      // - id (int): Notification ID; ignored by this no-op cancellation.
      // - slotKey (String?): Optional dose slot; ignored by this no-op cancellation.
      // Returns:
      // - Future<void>; completes without side effects.
      cancelReminder: (id, {slotKey}) async {},
      // Function Name: now callback
      // Description:
      // - Supply a controllable clock so dose deadlines and reminder windows do not depend on wall time.
      // Parameters:
      // - None.
      // Returns:
      // - DateTime from currentTime.
      now: () => currentTime,
    );

    expect(await service.synchronize(), isTrue);
    expect(registeredWindows.single, hasLength(14));
    expect(registeredWindows.single.first, DateTime(2026, 8, 1));
    expect(registeredWindows.single.last, DateTime(2026, 8, 14));

    currentTime = DateTime(2026, 8, 15, 7);
    expect(await service.synchronize(), isTrue);
    expect(registeredWindows.last, hasLength(14));
    expect(registeredWindows.last.first, DateTime(2026, 8, 15));
    expect(registeredWindows.last.last, DateTime(2026, 8, 28));
  });

  // Function Name: disabled reminder cancellation test
  // Description: Supplies a disabled morning alarm and empty schedules; any registration fails the test, while successful refresh must cancel all four local slots.
  // Parameters: None.
  // Returns: Future<void>; fails if a reminder is registered, synchronization fails, or slot cancellation order differs.
  test('비활성화된 시간대는 서버 설정을 바꾸지 않고 로컬 알림만 취소한다', () async {
    SharedPreferences.setMockInitialValues({});
    final canceledSlots = <String>[];
    final service = MedicationReminderRefreshService(
      // Function Name: loadSettings callback
      // Description:
      // - Provide a disabled morning alarm without changing the persisted server setting.
      // Parameters:
      // - None.
      // Returns:
      // - One disabled 08:00 morning alarm.
      loadSettings: () async => const [
        MedicationAlarm(
          patientHash: 'patient-a',
          slotKey: 'morning',
          hour: 8,
          minute: 0,
          enabled: false,
        ),
      ],
      // Function Name: loadSchedules callback
      // Description:
      // - Provide a successful empty patient schedule without making another request.
      // Parameters:
      // - None.
      // Returns:
      // - An empty medication-schedule list.
      loadSchedules: () async => const [],
      registerReminder:
          // Function Name: registerReminder callback
          // Description:
          // - Fail immediately if background synchronization tries to register a disabled reminder.
          // Parameters:
          // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
          //   consumed by this fixture.
          // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime. Accepted but not consumed
          //   by this fixture.
          // - slotTitle (String): Localized user-visible name of the dose slot. Accepted but not consumed by
          //   this fixture.
          // - hour (int): Selected local alarm hour in 24-hour time. Accepted but not consumed by this fixture.
          // - minute (int): Selected minute component of the local alarm time. Accepted but not consumed by this
          //   fixture.
          // - activeDates (List<DateTime>): Dates on which this dose is active. Accepted but not consumed by
          //   this fixture.
          // - language (String): Language code used for labels or notification content. Accepted but not
          //   consumed by this fixture.
          // Returns:
          // - A test failure for unexpected registration.
          ({
            required id,
            required slotKey,
            required slotTitle,
            required hour,
            required minute,
            required activeDates,
            language = 'ko',
          }) async {
            fail('Disabled reminder should not be registered.');
          },
      // Function Name: cancelReminder callback
      // Description:
      // - Record the slot canceled by background synchronization of a disabled alarm.
      // Parameters:
      // - id (int): Notification ID; ignored because this spy records only the slot.
      // - slotKey (String?): Canceled slot; null is recorded as an empty string.
      // Returns:
      // - Future<void>; appends the canceled slot key.
      cancelReminder: (id, {slotKey}) async {
        canceledSlots.add(slotKey ?? '');
      },
      // Function Name: now callback
      // Description:
      // - Supply a controllable clock so dose deadlines and reminder windows do not depend on wall time.
      // Parameters:
      // - None.
      // Returns:
      // - DateTime from DateTime(2026, 8, 1).
      now: () => DateTime(2026, 8, 1),
    );

    expect(await service.synchronize(), isTrue);
    expect(canceledSlots, ['morning', 'lunch', 'evening', 'bedtime']);
  });

  // Function Name: overlapping course date union test
  // Description: Verifies that two overlapping two-day courses produce one ordered three-day reminder window for their shared slot.
  // Parameters: None.
  // Returns: Future<void>; fails if synchronization fails or overlapping dates are duplicated or omitted.
  test('겹치는 복용 기간의 모든 날짜를 등록한다', () async {
    SharedPreferences.setMockInitialValues({});
    List<DateTime>? registeredDates;
    final service = MedicationReminderRefreshService(
      // Function Name: loadSettings callback
      // Description:
      // - Provide an enabled 08:00 morning alarm for patient-a without server access.
      // Parameters:
      // - None.
      // Returns:
      // - One enabled morning alarm.
      loadSettings: () async => const [
        MedicationAlarm(
          patientHash: 'patient-a',
          slotKey: 'morning',
          hour: 8,
          minute: 0,
          enabled: true,
        ),
      ],
      // Function Name: loadSchedules callback
      // Description:
      // - Provide two overlapping two-day courses that begin on consecutive days.
      // Parameters:
      // - None.
      // Returns:
      // - Two morning schedules active on different date ranges.
      loadSchedules: () async => [
        MedicationSchedule(
          medicationName: '약-A',
          prescriptionDate: DateTime(2026, 8, 1),
          medicationTime: 2,
          scheduleSlotKeys: const ['morning'],
        ),
        MedicationSchedule(
          medicationName: '약-B',
          prescriptionDate: DateTime(2026, 8, 2),
          medicationTime: 2,
          scheduleSlotKeys: const ['morning'],
        ),
      ],
      registerReminder:
          // Function Name: registerReminder callback
          // Description:
          // - Capture the dates passed to local reminder registration.
          // Parameters:
          // - id, slotKey, slotTitle, hour, minute, language: Accepted but not consumed by this fixture.
          // - activeDates (List<DateTime>): Dates on which this dose is active.
          // Returns:
          // - Future<void>; stores the registration arguments.
          ({
            required id,
            required slotKey,
            required slotTitle,
            required hour,
            required minute,
            required activeDates,
            language = 'ko',
          }) async {
            registeredDates = activeDates;
          },
      // Function Name: cancelReminder callback
      // Description:
      // - Acknowledge unrelated reminder cancellations without device access.
      // Parameters:
      // - id (int): Notification ID; ignored by this no-op cancellation.
      // - slotKey (String?): Optional dose slot; ignored by this no-op cancellation.
      // Returns:
      // - Future<void>; completes without side effects.
      cancelReminder: (id, {slotKey}) async {},
      // Function Name: now callback
      // Description:
      // - Supply a controllable clock so dose deadlines and reminder windows do not depend on wall time.
      // Parameters:
      // - None.
      // Returns:
      // - DateTime from DateTime(2026, 8, 1, 7).
      now: () => DateTime(2026, 8, 1, 7),
    );

    expect(await service.synchronize(), isTrue);
    expect(registeredDates, [
      DateTime(2026, 8, 1),
      DateTime(2026, 8, 2),
      DateTime(2026, 8, 3),
    ]);
  });

  // Group: reminders for a slot already taken today
  // Description:
  // - The reminder-window response carries no completion records, so the refresh reads today's schedule
  //   to learn which slots are already taken. These cases pin both directions: a taken slot is not
  //   re-armed for today, and a slot that is not (or not provably) taken always keeps today's reminder.
  // Function Name: completed-slot reminder test group
  // Description: Registers cases distinguishing confirmed completion from missing, partial, failed, or previous-day schedule data when choosing today's reminder dates.
  // Parameters: None.
  // Returns: void; defines controlled-date fixtures and registers the completion-filter cases.
  group('today reminder for a completed slot', () {
    // An hour at which the device-local date and the server schedule day are both 2026-08-01, whatever
    // time zone the test machine uses.
    final sameDayHour = [
      for (var hour = 0; hour < 24; hour++)
        if (doseScheduleDay(DateTime(2026, 8, 1, hour)) == '2026-08-01') hour,
    ].first;
    late DateTime currentTime;
    late Map<String, List<DateTime>> registered;
    late List<String> cancelled;
    late int todayReads;

    // Function Name: course
    // Description: Builds a five-day course starting August 1 with configurable slots and completion flags.
    // Parameters:
    // - name (String): Synthetic medication label.
    // - slots (List<String>): Dose slots included in the schedule.
    // - taken (Map<String, bool>): Per-slot completion flags; defaults to no explicit flags.
    // Returns: MedicationSchedule; the constructed fixture without backend access.
    MedicationSchedule course(
      String name,
      List<String> slots, {
      Map<String, bool> taken = const {},
    }) => MedicationSchedule(
      medicationName: name,
      prescriptionDate: DateTime(2026, 8, 1),
      medicationTime: 5,
      scheduleSlotKeys: slots,
      slotStatuses: taken,
    );

    // Function Name: build
    // Description: Builds a controlled-clock refresh service with configurable morning/evening alarms and captures registrations, cancellations, and today's schedule-read count.
    // Parameters:
    // - loadToday (Future<List<MedicationSchedule>> Function()?):
    //   Optional current-day loader; null omits it, and supplied loader failures reach the refresh service.
    // - morning (bool): Whether the morning alarm is enabled; defaults to true.
    // - evening (bool): Whether the evening alarm is enabled; defaults to true.
    // - window (List<MedicationSchedule>?): Window response; null supplies two default five-day courses without completion flags.
    // Returns: MedicationReminderRefreshService; isolated service using the group's recorded state.
    MedicationReminderRefreshService build({
      Future<List<MedicationSchedule>> Function()? loadToday,
      bool morning = true,
      bool evening = true,
      List<MedicationSchedule>? window,
    }) => MedicationReminderRefreshService(
      loadSettings: () async => [
        MedicationAlarm(slotKey: 'morning', hour: 8, minute: 0, enabled: morning),
        MedicationAlarm(slotKey: 'evening', hour: 20, minute: 0, enabled: evening),
      ],
      loadSchedules: () async =>
          window ??
          [
            course('약-A', const ['morning', 'evening']),
            course('약-B', const ['evening']),
          ],
      loadTodaySchedules: loadToday == null
          ? null
          : () {
              todayReads++;
              return loadToday();
            },
      registerReminder:
          ({
            required id,
            required slotKey,
            required slotTitle,
            required hour,
            required minute,
            required activeDates,
            language = 'ko',
          }) async {
            registered[slotKey] = List<DateTime>.from(activeDates);
          },
      cancelReminder: (id, {slotKey}) async => cancelled.add(slotKey ?? ''),
      now: () => currentTime,
    );

    // Function Name: setUp callback
    // Description: Clears preferences and recorded reminder operations, resets today's read count, and chooses the controlled hour shared by local and server schedule dates.
    // Parameters: None.
    // Returns: void; initializes independent state for each completion-filter case.
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      currentTime = DateTime(2026, 8, 1, sameDayHour);
      registered = {};
      cancelled = [];
      todayReads = 0;
    });

    // Function Name: completed-slot test
    // Description: Verifies that a fully taken morning slot omits only today, retaining its four future dates while the untaken evening slot keeps all five.
    // Parameters: None.
    // Returns: Future<void>; fails if today's schedule is not read once or either slot's date window differs.
    test('slot taken before its reminder time is not registered for today', () async {
      final service = build(
        loadToday: () async => [
          course(
            '약-A',
            const ['morning', 'evening'],
            taken: const {'morning': true, 'evening': false},
          ),
          course('약-B', const ['evening'], taken: const {'evening': false}),
        ],
      );

      expect(await service.synchronize(), isTrue);

      expect(todayReads, 1);
      expect(registered['morning']!.first, DateTime(2026, 8, 2));
      expect(registered['morning'], hasLength(4));
      expect(registered['evening']!.first, DateTime(2026, 8, 1));
      expect(registered['evening'], hasLength(5));
    });

    // Function Name: partially-taken test
    // Description: Verifies that a partly taken evening slot and a morning slot absent from today's response both retain today's reminder.
    // Parameters: None.
    // Returns: Future<void>; fails if synchronization fails or either slot loses today.
    test('partly taken or unknown slots keep the reminder for today', () async {
      final service = build(
        loadToday: () async => [
          course('약-B', const ['evening'], taken: const {'evening': true}),
          course('약-C', const ['evening'], taken: const {'evening': false}),
        ],
      );

      expect(await service.synchronize(), isTrue);

      expect(registered['morning']!.first, DateTime(2026, 8, 1));
      expect(registered['evening']!.first, DateTime(2026, 8, 1));
    });

    // Function Name: day-change test
    // Description: Advances the day during the completion read and verifies that yesterday's taken flags do not remove the new day's morning or evening reminder.
    // Parameters: None.
    // Returns: Future<void>; fails if synchronization fails or either window skips the new day.
    test('completion read before midnight does not drop the next day', () async {
      final service = build(
        loadToday: () async {
          currentTime = DateTime(2026, 8, 2, sameDayHour);
          return [
            course(
              '약-A',
              const ['morning', 'evening'],
              taken: const {'morning': true, 'evening': true},
            ),
            course('약-B', const ['evening'], taken: const {'evening': true}),
          ];
        },
      );

      expect(await service.synchronize(), isTrue);

      expect(registered['morning']!.first, DateTime(2026, 8, 2));
      expect(registered['evening']!.first, DateTime(2026, 8, 2));
    });

    // Function Name: failed today read test
    // Description: Makes the completion loader throw and verifies that refresh reports failure for retry without registering or canceling any native reminder.
    // Parameters: None.
    // Returns: Future<void>; fails if the read error is reported as success or changes existing alarms.
    test('failed today read leaves reminders untouched and asks for a retry', () async {
      final service = build(
        loadToday: () async => throw StateError('network unavailable'),
      );

      expect(await service.synchronize(), isFalse);

      expect(registered, isEmpty);
      expect(cancelled, isEmpty);
    });

    // Function Name: no reminder slot test
    // Description: Disables both configured alarms and verifies that refresh skips today's schedule read, registers nothing, and cancels all four local slots.
    // Parameters: None.
    // Returns: Future<void>; fails if a completion read or registration occurs, or cancellation order differs.
    test('today is not read when no slot has a reminder to register', () async {
      final service = build(
        loadToday: () async => const [],
        morning: false,
        evening: false,
      );

      expect(await service.synchronize(), isTrue);

      expect(todayReads, 0);
      expect(registered, isEmpty);
      expect(cancelled, ['morning', 'lunch', 'evening', 'bedtime']);
    });

    // Function Name: shared completion date rule test
    // Description: Compares the same active course with and without today's completion flag; only the completed case drops today while preserving later dates.
    // Parameters: None.
    // Returns: void; fails if completion filtering removes future dates or leaves today's reminder.
    test('activeReminderDates drops only today for a completed slot', () {
      final schedules = [course('약-A', const ['morning'])];
      final now = DateTime(2026, 8, 3, 6);

      expect(
        MedicationReminderRefreshService.activeReminderDates(schedules, now: now),
        [DateTime(2026, 8, 3), DateTime(2026, 8, 4), DateTime(2026, 8, 5)],
      );
      expect(
        MedicationReminderRefreshService.activeReminderDates(
          schedules,
          now: now,
          slotCompletedToday: true,
        ),
        [DateTime(2026, 8, 4), DateTime(2026, 8, 5)],
      );
    });
  });
  // Function Name: unknown-duration test
  // Description: Verifies that a course without a duration fills the fourteen-day reminder window while a finite course stops at its last active day.
  // Parameters: None.
  // Returns: void; fails if the unknown course is truncated or the finite course extends beyond its duration.
  test('a course of unknown duration is reminded through the whole window', () {
    final now = DateTime(2026, 8, 3, 6);
    final unknown = MedicationSchedule(
      medicationName: '약-A',
      prescriptionDate: DateTime(2026, 7, 1),
      scheduleSlotKeys: const ['morning'],
    );
    final dated = MedicationSchedule(
      medicationName: '약-B',
      prescriptionDate: DateTime(2026, 8, 1),
      medicationTime: 4,
      scheduleSlotKeys: const ['morning'],
    );

    expect(
      MedicationReminderRefreshService.activeReminderDates([unknown], now: now),
      [for (var day = 3; day <= 16; day++) DateTime(2026, 8, day)],
    );
    expect(
      MedicationReminderRefreshService.activeReminderDates([dated], now: now),
      [DateTime(2026, 8, 3), DateTime(2026, 8, 4)],
    );
  });

  // Dose days: a medication that is not taken every day is reminded on its dose days only.
  // Function Name: dose-cycle test group
  // Description: Registers weekly, mixed daily/weekly, and unspecified-cycle cases, including background refresh on a rest day.
  // Parameters: None.
  // Returns: void; creates shared synthetic courses and registers date-selection tests.
  group('dose days', () {
    final now = DateTime(2026, 8, 3, 6);
    final weekly = MedicationSchedule(
      medicationName: '주간약',
      prescriptionDate: DateTime(2026, 8, 3),
      medicationTime: 60,
      scheduleSlotKeys: const ['morning'],
      doseCycleDays: 7,
      doseCycleOffsets: const [0],
      doseCycleAnchor: DateTime(2026, 8, 3),
    );
    final daily = MedicationSchedule(
      medicationName: '매일약',
      prescriptionDate: DateTime(2026, 8, 3),
      medicationTime: 60,
      scheduleSlotKeys: const ['morning'],
    );

    // Function Name: weekly test
    // Description: Verifies seven-day spacing from both a dose day and a rest day, and confirms that a completion flag removes only today's weekly dose.
    // Parameters: None.
    // Returns: void; fails if the rolling window includes rest days or drops a future dose.
    test('a weekly medication is reminded every seventh day only', () {
      expect(
        MedicationReminderRefreshService.activeReminderDates([weekly], now: now),
        [DateTime(2026, 8, 3), DateTime(2026, 8, 10)],
      );
      // Between dose days the window starts on a rest day and still finds both dose days in it.
      expect(
        MedicationReminderRefreshService.activeReminderDates(
          [weekly],
          now: DateTime(2026, 8, 5, 6),
        ),
        [DateTime(2026, 8, 10), DateTime(2026, 8, 17)],
      );
      // A dose taken today removes today only.
      expect(
        MedicationReminderRefreshService.activeReminderDates(
          [weekly],
          now: now,
          slotCompletedToday: true,
        ),
        [DateTime(2026, 8, 10)],
      );
    });

    // Function Name: mixed-slot test
    // Description: Verifies that a daily course keeps all fourteen shared-slot reminder dates while the weekly course is due on only its two cycle dates.
    // Parameters: None.
    // Returns: void; fails if combined dates or per-course due-day checks differ.
    test('a daily medication in the same slot keeps every day', () {
      final dates = MedicationReminderRefreshService.activeReminderDates(
        [weekly, daily],
        now: now,
      );
      expect(dates, [for (var day = 3; day <= 16; day++) DateTime(2026, 8, day)]);
      expect(
        [for (final date in dates) if (weekly.isDoseDay(date)) date],
        [DateTime(2026, 8, 3), DateTime(2026, 8, 10)],
      );
      expect(dates.every(daily.isDoseDay), isTrue);
    });

    // Function Name: no-cycle test
    // Description: Verifies that an unspecified dose cycle preserves daily reminders through the remaining three days of a five-day course.
    // Parameters: None.
    // Returns: void; fails if the returned dates skip a remaining course day or extend beyond the course.
    test('a schedule without a dose cycle behaves as before', () {
      final plain = MedicationSchedule(
        medicationName: '약-A',
        prescriptionDate: DateTime(2026, 8, 1),
        medicationTime: 5,
        scheduleSlotKeys: const ['morning'],
      );
      expect(
        MedicationReminderRefreshService.activeReminderDates([plain], now: now),
        [DateTime(2026, 8, 3), DateTime(2026, 8, 4), DateTime(2026, 8, 5)],
      );
    });

    // Function Name: weekly rest-day worker test
    // Description: Supplies an empty today response on a weekly rest day and verifies registration of the next two weekly dates while only the other slots are canceled.
    // Parameters: None.
    // Returns: Future<void>; fails if the weekly slot is canceled or its future reminder dates change.
    test('the worker keeps a weekly-only slot on a rest day', () async {
      SharedPreferences.setMockInitialValues({});
      final registered = <String, List<DateTime>>{};
      final cancelled = <String>[];
      final service = MedicationReminderRefreshService(
        loadSettings: () async => const [
          MedicationAlarm(slotKey: 'morning', hour: 8, minute: 0, enabled: true),
        ],
        loadSchedules: () async => [weekly],
        // The server lists only medications due today; Aug 5 is a rest day.
        loadTodaySchedules: () async => const [],
        registerReminder: ({required id, required slotKey, required slotTitle,
          required hour, required minute,
          required activeDates, language = 'ko'}) async {
          registered[slotKey] = List<DateTime>.from(activeDates);
        },
        cancelReminder: (id, {slotKey}) async => cancelled.add(slotKey ?? ''),
        now: () => DateTime(2026, 8, 5, 6),
      );

      expect(await service.synchronize(), isTrue);
      expect(registered, {
        'morning': [DateTime(2026, 8, 10), DateTime(2026, 8, 17)],
      });
      expect(cancelled, ['lunch', 'evening', 'bedtime']);
      service.dispose();
    });
  });
}
