// File Name: medication_reminder_background_service_test.dart
// Role: Verifies rolling reminder replenishment for long medication courses.

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/app_language_control.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/medication_reminder_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('백그라운드 동기화가 14일 이후의 장기 복약 알림을 보충한다', () async {
    SharedPreferences.setMockInitialValues({
      AppLanguageControl.preferenceKey: 'ko',
    });
    final courseStart = DateTime(2026, 8, 1);
    var currentTime = DateTime(2026, 8, 1, 7);
    final registeredWindows = <List<DateTime>>[];
    final service = MedicationReminderRefreshService(
      loadSettings: () async => const [
        MedicationAlarm(
          patientHash: 'patient-a',
          slotKey: 'morning',
          hour: 8,
          minute: 0,
          enabled: true,
        ),
      ],
      loadSchedules: () async => [
        MedicationSchedule(
          medicationName: '장기복용정',
          prescriptionDate: courseStart,
          medicationTime: 40,
          scheduleSlotKeys: const ['morning'],
        ),
      ],
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
            registeredWindows.add(List<DateTime>.from(activeDates));
          },
      cancelReminder: (id, {slotKey}) async {},
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

  test('비활성화된 시간대는 서버 설정을 바꾸지 않고 로컬 알림만 취소한다', () async {
    SharedPreferences.setMockInitialValues({});
    final canceledSlots = <String>[];
    final service = MedicationReminderRefreshService(
      loadSettings: () async => const [
        MedicationAlarm(
          patientHash: 'patient-a',
          slotKey: 'morning',
          hour: 8,
          minute: 0,
          enabled: false,
        ),
      ],
      loadSchedules: () async => const [],
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
            fail('Disabled reminder should not be registered.');
          },
      cancelReminder: (id, {slotKey}) async {
        canceledSlots.add(slotKey ?? '');
      },
      now: () => DateTime(2026, 8, 1),
    );

    expect(await service.synchronize(), isTrue);
    expect(canceledSlots, ['morning', 'lunch', 'evening', 'bedtime']);
  });

  test('각 날짜의 알림 본문에는 그날 복용 중인 약만 포함한다', () async {
    SharedPreferences.setMockInitialValues({});
    Map<String, List<String>>? registeredNamesByDate;
    final service = MedicationReminderRefreshService(
      loadSettings: () async => const [
        MedicationAlarm(
          patientHash: 'patient-a',
          slotKey: 'morning',
          hour: 8,
          minute: 0,
          enabled: true,
        ),
      ],
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
      cancelReminder: (id, {slotKey}) async {},
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
