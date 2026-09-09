// File Name: medication_reminder_background_service_test.dart
// Role: Verifies rolling reminder replenishment for long medication courses.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/app_language_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
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
  // - Verify that each reminder body includes only medications active on that reminder date.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('각 날짜의 알림 본문에는 그날 복용 중인 약만 포함한다', () async {
    SharedPreferences.setMockInitialValues({});
    Map<String, List<String>>? registeredNamesByDate;
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
          // - Capture date-specific medication names passed to local reminder registration.
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
          // - language (String): Language code used for labels or notification content. Accepted but not
          //   consumed by this fixture.
          // Returns:
          // - Future<void>; stores the per-date medication-name map.
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
            registeredNamesByDate = medicationNamesByDate;
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
    expect(registeredNamesByDate, {
      '2026-08-01': ['약-A'],
      '2026-08-02': ['약-A', '약-B'],
      '2026-08-03': ['약-B'],
    });
  });
}
