// File Name: medication_reminder_background_service_test.dart
// Role: Verifies rolling reminder replenishment for long medication courses.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/app_language_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:medbuddy_frontend/services/medication_reminder_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Function Name: main
// Description:
// - Register regression cases for background reminder replenishment and date-specific medication
//   content.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
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
        required hour, required minute, required medicationNames,
        required activeDates, medicationNamesByDate = const <String, List<String>>{},
        language = 'ko'}) async { registered++; },
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
  // Function Name: test callback
  // Description:
  // - Verify that background synchronization replenishes long-course reminders beyond fourteen days.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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
          // - medicationNames (List<String>): Medication names eligible for this reminder. Accepted but not
          //   consumed by this fixture.
          // - activeDates (List<DateTime>): Dates on which this dose is active.
          // - medicationNamesByDate (Map<String, List<String>>): Medication names active on each scheduled date.
          //   Accepted but not consumed by this fixture.
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
            required medicationNames,
            required activeDates,
            medicationNamesByDate = const <String, List<String>>{},
            language = 'ko',
          }) async {
            registeredWindows.add(List<DateTime>.from(activeDates));
          },
      // Function Name: cancelReminder callback
      // Description:
      // - Acknowledge unrelated reminder cancellations without device access.
      // Parameters:
      // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
      //   consumed by this fixture.
      // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime. Accepted but not consumed
      //   by this fixture.
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

  // Function Name: test callback
  // Description:
  // - Verify that disabled slots cancel only local reminders without changing server settings.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
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
          // - medicationNames (List<String>): Medication names eligible for this reminder. Accepted but not
          //   consumed by this fixture.
          // - activeDates (List<DateTime>): Dates on which this dose is active. Accepted but not consumed by
          //   this fixture.
          // - medicationNamesByDate (Map<String, List<String>>): Medication names active on each scheduled date.
          //   Accepted but not consumed by this fixture.
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
            required medicationNames,
            required activeDates,
            medicationNamesByDate = const <String, List<String>>{},
            language = 'ko',
          }) async {
            fail('Disabled reminder should not be registered.');
          },
      // Function Name: cancelReminder callback
      // Description:
      // - Record the slot canceled by background synchronization of a disabled alarm.
      // Parameters:
      // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
      //   consumed by this fixture.
      // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime.
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

  // Function Name: test callback
  // Description:
  // - Verify that the refresh registers every date on which any course of the slot is active and no
  //   longer builds medication-name snapshots, because the reminder text never uses them.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('겹치는 복용 기간의 모든 날짜를 등록하고 약 이름은 넘기지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    List<String>? registeredNames;
    Map<String, List<String>>? registeredNamesByDate;
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
          // - Capture the dates and the name arguments passed to local reminder registration.
          // Parameters:
          // - id, slotKey, slotTitle, hour, minute, language: Accepted but not consumed by this fixture.
          // - medicationNames (List<String>): Medication names passed for the reminder.
          // - activeDates (List<DateTime>): Dates on which this dose is active.
          // - medicationNamesByDate (Map<String, List<String>>): Medication names passed per date.
          // Returns:
          // - Future<void>; stores the registration arguments.
          ({
            required id,
            required slotKey,
            required slotTitle,
            required hour,
            required minute,
            required medicationNames,
            required activeDates,
            medicationNamesByDate = const <String, List<String>>{},
            language = 'ko',
          }) async {
            registeredNames = medicationNames;
            registeredNamesByDate = medicationNamesByDate;
            registeredDates = activeDates;
          },
      // Function Name: cancelReminder callback
      // Description:
      // - Acknowledge unrelated reminder cancellations without device access.
      // Parameters:
      // - id (int): Identifier of the medication, message, or notification fixture. Accepted but not
      //   consumed by this fixture.
      // - slotKey (String): Dose slot such as morning, lunch, evening, or bedtime. Accepted but not consumed
      //   by this fixture.
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
    expect(registeredNames, isEmpty);
    expect(registeredNamesByDate, isEmpty);
  });

  // Group: reminders for a slot already taken today
  // Description:
  // - The reminder-window response carries no completion records, so the refresh reads today's schedule
  //   to learn which slots are already taken. These cases pin both directions: a taken slot is not
  //   re-armed for today, and a slot that is not (or not provably) taken always keeps today's reminder.
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
    // Description: Builds a five-day course in the given slots with the given completion flags.
    // Parameters: name - medication name; slots - slot keys; taken - completion flag per slot.
    // Returns: The medication schedule fixture.
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
    // Description: Creates the refresh service with enabled morning and evening alarms, a window
    //   response without completion records, and the supplied today response.
    // Parameters: loadToday - today's schedule loader, or null to omit it; evening - whether the
    //   evening alarm is enabled; window - courses returned by the window read.
    // Returns: The service under test.
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
            required medicationNames,
            required activeDates,
            medicationNamesByDate = const <String, List<String>>{},
            language = 'ko',
          }) async {
            registered[slotKey] = List<DateTime>.from(activeDates);
          },
      cancelReminder: (id, {slotKey}) async => cancelled.add(slotKey ?? ''),
      now: () => currentTime,
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      currentTime = DateTime(2026, 8, 1, sameDayHour);
      registered = {};
      cancelled = [];
      todayReads = 0;
    });

    // Function Name: completed-slot test
    // Description: A slot whose medications are all taken today is registered without today, while its
    //   later dates and the other slot keep every date.
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
    // Description: Today's reminder stays when any medication of the slot is still untaken, or when
    //   the slot has no medication in today's response.
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
    // Description: When the day changes while today's schedule is being read, the completion belongs
    //   to yesterday and must not remove the new day's reminder.
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
    // Description: When today's schedule cannot be read the refresh reports failure for a retry and
    //   registers nothing, so existing device reminders stay as they are.
    test('failed today read leaves reminders untouched and asks for a retry', () async {
      final service = build(
        loadToday: () async => throw StateError('network unavailable'),
      );

      expect(await service.synchronize(), isFalse);

      expect(registered, isEmpty);
      expect(cancelled, isEmpty);
    });

    // Function Name: no reminder slot test
    // Description: Today's schedule is not requested when no slot has a reminder to register.
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

    // Function Name: shared rule test
    // Description: The shared date rule removes only today and only when the slot is completed.
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
}
