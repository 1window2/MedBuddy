import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/foreground_recovery_service.dart';

void main() {
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
