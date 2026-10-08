// File Name: notification_legacy_reminder_test.dart
// Role: Verifies that the fixed reminder IDs of old builds (1001-1004) are cleaned up once per install
//   and that the completion flag is written only after all four were really cancelled.
// Runs in its own file because the notification service is a process-wide singleton that remembers
//   which legacy IDs it cancelled; other test files would leave that record behind.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Function Name: main
// Description: Registers the legacy reminder cleanup cases against a recording notification channel.
// Parameters: None.
// Returns: No value; the test framework executes the registered cases.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final cancelled = <int>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationService.instance.setHistoryUser(null, persistSession: false);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    cancelled.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'pendingNotificationRequests':
            case 'getActiveNotifications':
              return const <Map<String, Object?>>[];
            case 'cancel':
              cancelled.add((call.arguments as Map)['id'] as int);
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  // Function Name: flag timing test
  // Description: The flag stays unset while any of the four legacy IDs is still uncancelled, and a
  //   cancellation of another ID never counts.
  test('the flag is written only after all four legacy ids were cancelled', () async {
    final service = NotificationService.instance;
    final preferences = await SharedPreferences.getInstance();
    bool? flag() =>
        preferences.getBool(NotificationService.legacyReminderIdsCancelledKey);
    final legacyIds = [
      for (final slot in ['morning', 'lunch', 'evening', 'bedtime'])
        MedicationAlarm.legacyNotificationIdForSlot(slot),
    ];
    expect(legacyIds, [1001, 1002, 1003, 1004]);

    await service.cancelReminder(987654);
    for (final id in legacyIds.take(3)) {
      await service.cancelReminder(id);
    }
    expect(cancelled, [987654, 1001, 1002, 1003]);
    expect(flag(), isNull);

    await service.cancelReminder(legacyIds.last);
    expect(cancelled.last, 1004);
    expect(flag(), isTrue);
  });

  // Function Name: cancel-all test
  // Description: Turning reminders off cancels the four legacy IDs itself, so it records the cleanup
  //   on an install whose flag is not yet set.
  test('turning all reminders off also records the cleanup', () async {
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(NotificationService.legacyReminderIdsCancelledKey),
      isNull,
    );

    await NotificationService.instance.cancelAllScheduledMedicationReminders();

    expect(cancelled, containsAll([1001, 1002, 1003, 1004]));
    expect(
      preferences.getBool(NotificationService.legacyReminderIdsCancelledKey),
      isTrue,
    );
  });
}
