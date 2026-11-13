// File Name: foreground_recovery_service_test.dart
// Role: Verifies bounded foreground recovery, lifecycle interruption and late-response handling.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/foreground_recovery_service.dart';

// Function Name: main
// Description:
// - Register fake-clock widget cases for retry timing, suspension and disposal.
// Parameters:
// - None.
// Returns:
// - No value; the framework runs the registered cases.
void main() {
  // Function Name: testWidgets callback
  // Description:
  // - Require one immediate read despite duplicate starts, retries after 5 then 15 seconds, and no further calls after the third read succeeds.
  // Parameters:
  // - tester (WidgetTester): Drives the widget tree and advances the test clock.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  testWidgets('offline reads retry with backoff and stop after recovery', (tester) async {
    var calls = 0;
    final service = ForegroundRecoveryService(() async => ++calls >= 3);
    service.start();
    service.start();
    await tester.pump();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 2);
    await tester.pump(const Duration(seconds: 14));
    expect(calls, 2);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 3);
    await tester.pump(const Duration(minutes: 5));
    expect(calls, 3);
    service.dispose();
  });

  // Function Name: testWidgets callback
  // Description:
  // - A throwing recovery stops retrying while inactive, retries immediately on restart and cannot restart once disposed.
  // Parameters:
  // - tester (WidgetTester): Drives the widget tree and advances the test clock.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  testWidgets('background stops retries and foreground resumes immediately', (tester) async {
    var calls = 0;
    final service = ForegroundRecoveryService(() async {
      calls++;
      throw StateError('offline');
    });
    service.start();
    await tester.pump();
    service.stop();
    await tester.pump(const Duration(minutes: 5));
    expect(calls, 1);
    service.start();
    await tester.pump();
    expect(calls, 2);
    service.dispose();
    service.start();
    await tester.pump(const Duration(minutes: 5));
    expect(calls, 2);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Stop and restart while the first read is pending; the resumed read must begin only after that pending read finishes.
  // Parameters:
  // - tester (WidgetTester): Drives the widget tree and advances the test clock.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  testWidgets('resume does not overlap an in-flight read', (tester) async {
    final pending = Completer<bool>();
    var calls = 0;
    final service = ForegroundRecoveryService(() {
      calls++;
      return calls == 1 ? pending.future : Future.value(true);
    });
    service.start();
    service.stop();
    service.start();
    expect(calls, 1);
    pending.complete(true);
    await tester.pump();
    expect(calls, 2);
    service.dispose();
  });

  // Function Name: testWidgets callback
  // Description:
  // - Dispose before a delayed false result arrives and advance ten minutes; the old owner must not schedule another attempt.
  // Parameters:
  // - tester (WidgetTester): Drives the widget tree and advances the test clock.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  testWidgets('disposed owner ignores a late failed response', (tester) async {
    final pending = Completer<bool>();
    var calls = 0;
    final service = ForegroundRecoveryService(() {
      calls++;
      return pending.future;
    });
    service.start();
    service.dispose();
    pending.complete(false);
    await tester.pump(const Duration(minutes: 10));
    expect(calls, 1);
  });
}
