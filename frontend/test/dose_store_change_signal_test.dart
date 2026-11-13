// File Name: dose_store_change_signal_test.dart
// Role: Verify the cross-engine dose-store notice in one test process.
// 다른 엔진은 만들지 않는다. 두 엔진 사이의 전달은 Android 에뮬레이터에서 따로 확인했다.
import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/dose_store_change_signal.dart';

// Class Name: _Registry
// Role: In-memory substitute for the process-wide named-port registry.
// Responsibilities: Reject duplicate registrations and expose the current owner of a name.
// Attributes: ports maps names to SendPort values.
class _Registry {
  final Map<String, SendPort> ports = {};

  // Function Name: signal
  // Description: Creates a signal backed by this registry.
  // Parameters: None.
  // Returns: DoseStoreChangeSignal sharing this registry.
  DoseStoreChangeSignal signal() => DoseStoreChangeSignal(
    register: (port, name) {
      if (ports.containsKey(name)) return false;
      ports[name] = port;
      return true;
    },
    lookup: (name) => ports[name],
    remove: (name) => ports.remove(name) != null,
  );
}

// Function Name: main
// Description: Registers delivery, own-write, replacement and close tests.
// Parameters: None.
// Returns: void; the test framework runs the registered cases.
void main() {
  // Function Name: delivery test
  // Description: Another instance's notice reaches the listener; the listener's own notice does not.
  // Parameters: None. Returns: Future<void>; fails on a missing or extra notice.
  test('another engine reaches the listener, its own writes do not', () async {
    final registry = _Registry();
    final listener = registry.signal();
    final writer = registry.signal();
    var notices = 0;
    final received = Completer<void>();
    listener.listen(() {
      notices++;
      if (!received.isCompleted) received.complete();
    });
    addTearDown(listener.close);

    listener.notify();
    writer.notify();
    await received.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(notices, 1);
  });

  // Function Name: replacement and close test
  // Description: A new listener replaces a name left behind, and closing removes only its own name.
  // Parameters: None. Returns: Future<void>; fails when the stale or closed listener still receives.
  test(
    'the newest listener takes over and close removes only its own name',
    () async {
      final registry = _Registry();
      final stale = ReceivePort();
      addTearDown(stale.close);
      registry.ports['medbuddy_dose_store_changed'] = stale.sendPort;
      final listener = registry.signal();
      final received = Completer<void>();
      listener.listen(() {
        if (!received.isCompleted) received.complete();
      });

      registry.signal().notify();
      await received.future.timeout(const Duration(seconds: 1));

      listener.close();
      expect(registry.ports, isEmpty);
      final next = registry.signal()..listen(() {});
      addTearDown(next.close);
      listener.close();
      expect(registry.ports, hasLength(1));
    },
  );
}
