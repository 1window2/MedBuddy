import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/medication_reminder_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final notificationsEnabled in [false, true]) {
    test(
      'a stale worker cannot cancel the new account alarms (enabled=$notificationsEnabled)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final settings = Completer<List<MedicationAlarm>>();
        var ownsReminders = true;
        final cancelled = <String?>[];
        final privacy = <bool>[];
        final service = MedicationReminderRefreshService(
          loadSettings: () => settings.future,
          loadSchedules: () async => [],
          loadUserSetting: () async => UserSetting(
            medicationNotificationsEnabled: notificationsEnabled,
            notificationDetailMode: 'full',
          ),
          registerReminder:
              ({
                required id,
                required slotKey,
                required slotTitle,
                required hour,
                required minute,
                required activeDates,
                language = 'ko',
              }) async => fail('A stale account must not register reminders'),
          cancelReminder: (id, {slotKey}) async {
            cancelled.add(slotKey);
          },
          setPrivacy: privacy.add,
          ownsReminders: () async => ownsReminders,
        );
        addTearDown(service.dispose);
        final pending = service.synchronize();
        ownsReminders = false;
        settings.complete(const []);

        expect(await pending, isTrue);
        expect(cancelled, isEmpty);
        expect(privacy, isEmpty);
      },
    );

    test(
      'cancellation stops between slots at account switch (enabled=$notificationsEnabled)',
      () async {
        SharedPreferences.setMockInitialValues({});
        var ownsReminders = true;
        final cancelled = <String?>[];
        final service = MedicationReminderRefreshService(
          loadSettings: () async => [],
          loadSchedules: () async => [],
          loadUserSetting: () async =>
              UserSetting(medicationNotificationsEnabled: notificationsEnabled),
          registerReminder:
              ({
                required id,
                required slotKey,
                required slotTitle,
                required hour,
                required minute,
                required activeDates,
                language = 'ko',
              }) async => fail('Disabled slots must not register reminders'),
          cancelReminder: (id, {slotKey}) async {
            cancelled.add(slotKey);
            ownsReminders = false;
          },
          ownsReminders: () async => ownsReminders,
        );
        addTearDown(service.dispose);

        expect(await service.synchronize(), isTrue);
        expect(cancelled, ['morning']);
      },
    );
  }

  test(
    'sign-out during registration still removes the just-armed reminder',
    () async {
      SharedPreferences.setMockInitialValues({});
      var ownsReminders = true;
      final armed = <String>{};
      final service = MedicationReminderRefreshService(
        loadSettings: () async => const [
          MedicationAlarm(
            slotKey: 'morning',
            hour: 8,
            minute: 0,
            enabled: true,
          ),
        ],
        loadSchedules: () async => [
          MedicationSchedule(
            medicationName: 'synthetic',
            prescriptionDate: DateTime(2026, 10, 21),
            medicationTime: 14,
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
              required activeDates,
              language = 'ko',
            }) async {
              armed.add(slotKey);
              ownsReminders = false;
            },
        cancelReminder: (id, {slotKey}) async {
          armed.remove(slotKey);
        },
        ownsReminders: () async => ownsReminders,
        now: () => DateTime(2026, 10, 21, 7),
      );
      addTearDown(service.dispose);

      expect(await service.synchronize(), isTrue);
      expect(armed, isEmpty);
    },
  );
}
