// 파일명: dose_store_open_gate.dart
// 역할: 같은 프로세스의 Flutter 엔진들이 복약 저장소를 한 번에 하나씩 열게 한다.
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

// Class Name: DoseStoreOpenGate
// Role: Serializes outbox opening across foreground and Workmanager engines in one process.
// Responsibilities: Prevent overlapping sqflite opens from creating connections that can stall each other's commits;
// - recover a stale name registration after the wait limit and release only this instance's registration.
// Attributes: register/lookup/remove - process-wide port-registry callbacks;
// - pollInterval/waitLimit (Duration): Registration retry interval and takeover threshold, not an action timeout.
class DoseStoreOpenGate {
  static const _portName = 'medbuddy_dose_store_open_gate';

  final bool Function(SendPort port, String name) register;
  final SendPort? Function(String name) lookup;
  final bool Function(String name) remove;
  final Duration pollInterval;
  final Duration waitLimit;

  // Function Name: DoseStoreOpenGate
  // Description: Configures the cross-engine registry and waiting policy without acquiring the gate.
  // Parameters: register/lookup/remove - named-port registry functions, defaulting to IsolateNameServer;
  // - pollInterval (Duration): Delay between attempts; waitLimit (Duration): Time before removing a stale registration.
  // Returns: A reusable gate; defaults poll every 20 ms and attempt takeover after 5 seconds.
  const DoseStoreOpenGate({
    this.register = IsolateNameServer.registerPortWithName,
    this.lookup = IsolateNameServer.lookupPortByName,
    this.remove = IsolateNameServer.removePortNameMapping,
    this.pollInterval = const Duration(milliseconds: 20),
    this.waitLimit = const Duration(seconds: 5),
  });

  // Function Name: run
  // Description: Acquires the named gate, runs an asynchronous opener, and releases its own registration after success or failure.
  // Parameters: action (Future<T> Function()) - database-opening operation; T - its result type.
  // Returns: The action's result or error; waiting retries after stale-registration takeover rather than timing out the action.
  Future<T> run<T>(Future<T> Function() action) async {
    final port = ReceivePort();
    final waited = Stopwatch()..start();
    while (!register(port.sendPort, _portName)) {
      if (waited.elapsed >= waitLimit) {
        // 열던 엔진이 종료되면 이름이 남는다. 이 저장소를 영영 못 여는 것보다 넘겨받는 편이 낫다.
        remove(_portName);
        waited.reset();
        continue;
      }
      await Future<void>.delayed(pollInterval);
    }
    try {
      return await action();
    } finally {
      // 한도를 넘겨 문을 넘겨받은 엔진의 등록은 지우지 않는다.
      if (lookup(_portName) == port.sendPort) remove(_portName);
      port.close();
    }
  }
}
