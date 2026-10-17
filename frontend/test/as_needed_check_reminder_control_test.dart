// 필요시 확인 알림의 단발 예약·계정 범위·실패 복구를 검증한다.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/controls/as_needed_check_reminder_control.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'support/fake_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final now = DateTime.utc(2026, 10, 17, 10);

  test(
    'explicit reminder reserves exactly one Korean date and persists per patient',
    () async {
      final notifications = RecordingNotificationService();
      final control = AsNeededCheckReminderControl(
        patientHash: 'patient-a',
        ensureSession: () {},
        notifications: notifications,
        now: () => now,
      );
      addTearDown(control.dispose);
      await control.restore(allowed: true, isEnglish: false);
      expect(notifications.registrations, isEmpty);
      await control.save(now.add(const Duration(hours: 1)), isEnglish: false);
      expect(control.enabled, isTrue);
      final registration = notifications.registrations.single;
      expect(registration.slotKey, 'as_needed');
      expect(registration.hour, 20);
      expect(registration.activeDates, [DateTime(2026, 10, 17)]);
      expect(registration.medicationNames, isEmpty);
      final other = AsNeededCheckReminderControl(
        patientHash: 'patient-b',
        ensureSession: () {},
        notifications: notifications,
        now: () => now,
      );
      addTearDown(other.dispose);
      await other.restore(allowed: true, isEnglish: false);
      expect(other.enabled, isFalse);
      expect(notifications.registrations, hasLength(1));
    },
  );

  test(
    'expired reminder does not repeat and master switch disables it',
    () async {
      final notifications = RecordingNotificationService();
      var clock = now;
      final control = AsNeededCheckReminderControl(
        patientHash: 'a',
        ensureSession: () {},
        notifications: notifications,
        now: () => clock,
      );
      addTearDown(control.dispose);
      await control.save(now.add(const Duration(hours: 1)), isEnglish: true);
      clock = now.add(const Duration(hours: 2));
      await control.restore(allowed: true, isEnglish: true);
      expect(control.enabled, isFalse);
      expect(notifications.registrations, hasLength(1));
      await control.save(clock.add(const Duration(hours: 1)), isEnglish: true);
      await control.restore(allowed: false, isEnglish: true);
      expect(control.enabled, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'medbuddy_as_needed_check_a',
        ),
        isNull,
      );
      expect(notifications.cancellations.last.slotKey, 'as_needed');
    },
  );

  test(
    'permission and scheduling failures never leave an enabled preference',
    () async {
      final notifications = RecordingNotificationService()
        ..permissionGranted = false;
      final control = AsNeededCheckReminderControl(
        patientHash: 'a',
        ensureSession: () {},
        notifications: notifications,
        now: () => now,
      );
      addTearDown(control.dispose);
      await expectLater(
        control.save(now.add(const Duration(hours: 1)), isEnglish: true),
        throwsStateError,
      );
      expect(notifications.registrations, isEmpty);
      notifications.permissionGranted = true;
      notifications.failRegistration = true;
      await expectLater(
        control.save(now.add(const Duration(hours: 1)), isEnglish: true),
        throwsStateError,
      );
      expect(control.enabled, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'medbuddy_as_needed_check_a',
        ),
        isNull,
      );
    },
  );

  test(
    'session change while loading preferences prevents scheduling',
    () async {
      final notifications = RecordingNotificationService();
      final prefs = Completer<SharedPreferences>();
      var current = true;
      final control = AsNeededCheckReminderControl(
        patientHash: 'a',
        ensureSession: () {
          if (!current) throw StateError('session changed');
        },
        notifications: notifications,
        preferences: () => prefs.future,
        now: () => now,
      );
      addTearDown(control.dispose);
      final result = control.save(
        now.add(const Duration(hours: 1)),
        isEnglish: false,
      );
      final expectation = expectLater(result, throwsStateError);
      current = false;
      prefs.complete(await SharedPreferences.getInstance());
      await expectation;
      expect(notifications.registrations, isEmpty);
      expect(notifications.cancellations, isEmpty);
    },
  );

  test('PRN payload only opens schedule even with supplied quick action', () {
    for (final action in [
      null,
      NotificationService.markSlotTakenActionId,
      NotificationService.snoozeTenMinutesActionId,
    ]) {
      final selection = NotificationService.selectionFromPayload(
        'schedule:as_needed:84005:2026-10-17',
        actionId: action,
      );
      expect(
        selection?.destination,
        MedicationNotificationDestination.schedule,
      );
      expect(selection?.action, MedicationNotificationAction.open);
    }
  });
}
