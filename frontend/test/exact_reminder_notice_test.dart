// File Name: exact_reminder_notice_test.dart
// Role: Verifies the notice that asks for the "Alarms & reminders" permission on devices where
//   medication reminders would otherwise be delivered late.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/widgets/exact_reminder_notice.dart';

import 'support/fake_notification_service.dart';
import 'support/test_viewport.dart';

// Function Name: _host
// Description: Wraps the notice in a scrollable page, as the schedule and settings screens do.
// Parameters: service - notification fake; isEnglish - wording; textScale - text scale factor.
// Returns: The application widget to pump.
Widget _host(
  RecordingNotificationService service, {
  bool isEnglish = false,
  double textScale = 1,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ExactReminderNotice(
            notificationService: service,
            isEnglish: isEnglish,
          ),
          const Text('content'),
        ],
      ),
    ),
  );
}

// Function Name: main
// Description: Registers the notice tests.
// Parameters: None. Returns: None.
void main() {
  // Nothing is shown, and no space is taken, on a device that already schedules exact alarms.
  testWidgets('the notice stays hidden while exact alarms are allowed', (tester) async {
    final service = RecordingNotificationService();
    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exact-reminder-notice')), findsNothing);
    expect(find.text('content'), findsOneWidget);
    // Reminders left inexact by an earlier run are still upgraded.
    expect(service.exactRescheduleCount, 1);
  });

  // Denied: the reason and one button are shown. The button opens the system screen; when the
  // user allowed the alarms there, the scheduled reminders are replaced and the notice goes away.
  for (final isEnglish in [false, true]) {
    testWidgets('allowing from the notice reschedules and hides it (english=$isEnglish)', (
      tester,
    ) async {
      final service = RecordingNotificationService()..exactRemindersAllowed = false;
      await tester.pumpWidget(_host(service, isEnglish: isEnglish));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('exact-reminder-notice')), findsOneWidget);
      expect(
        find.textContaining(isEnglish ? 'Alarms & reminders' : '알람 및 리마인더'),
        findsOneWidget,
      );
      expect(service.exactRescheduleCount, 0);
      final button = find.widgetWithText(
        OutlinedButton,
        isEnglish ? 'Allow on-time reminders' : '정확한 시각에 알림 받기',
      );
      expect(button, findsOneWidget);

      service.exactPermissionAfterRequest = true;
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(service.exactPermissionRequestCount, 1);
      expect(service.exactRescheduleCount, 1);
      expect(find.byKey(const Key('exact-reminder-notice')), findsNothing);
    });
  }

  // The user may come back without allowing anything: the notice stays, nothing is rescheduled,
  // and the button can be used again.
  testWidgets('declining keeps the notice usable', (tester) async {
    final service = RecordingNotificationService()..exactRemindersAllowed = false;
    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('exact-reminder-allow')));
    await tester.pumpAndSettle();

    expect(service.exactPermissionRequestCount, 1);
    expect(service.exactRescheduleCount, 0);
    expect(find.byKey(const Key('exact-reminder-notice')), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byKey(const Key('exact-reminder-allow'))).onPressed,
      isNotNull,
    );
  });

  // The permission can also be granted in the system settings while the app is in the background.
  testWidgets('returning to the app with the permission granted hides the notice', (
    tester,
  ) async {
    final service = RecordingNotificationService()..exactRemindersAllowed = false;
    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exact-reminder-notice')), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    service.exactRemindersAllowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exact-reminder-notice')), findsNothing);
    expect(service.exactRescheduleCount, 1);
  });

  // Largest text setting on a small phone: the whole message and the button stay readable.
  for (final isEnglish in [false, true]) {
    testWidgets('the notice fits a 320 px screen at double text size (english=$isEnglish)', (
      tester,
    ) async {
      setTestViewport(tester, const Size(320, 568));
      final service = RecordingNotificationService()..exactRemindersAllowed = false;
      await tester.pumpWidget(_host(service, isEnglish: isEnglish, textScale: 2));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final button = find.byKey(const Key('exact-reminder-allow'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
