// File Name: dose_store_open_gate_test.dart
// Role: Verify serialized dose-store opening and gate recovery in a single test process.
// 다른 엔진은 만들지 않는다. 두 엔진의 실제 경합은 Android 에뮬레이터에서 따로 확인했다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_store_open_gate.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Class Name: _Registry
// Role: In-memory substitute for the process-wide named-port registry.
// Responsibilities: Reject duplicate registrations, expose the current owner, and count removal attempts for gate-ownership tests.
// Attributes: ports maps names to SendPort values; removals counts calls to the removal callback.
class _Registry {
  final Map<String, SendPort> ports = {};
  int removals = 0;

  // Function Name: gate
  // Description: Creates a gate backed by this registry, with one-millisecond polling and observable ownership changes.
  // Parameters: waitLimit (Duration) - time before taking over an unresponsive owner; defaults to five seconds.
  // Returns: DoseStoreOpenGate; registration callbacks share this instance's ports and removal counter.
  DoseStoreOpenGate gate({Duration waitLimit = const Duration(seconds: 5)}) =>
      DoseStoreOpenGate(
        register: (port, name) {
          if (ports.containsKey(name)) return false;
          ports[name] = port;
          return true;
        },
        lookup: (name) => ports[name],
        remove: (name) {
          removals++;
          return ports.remove(name) != null;
        },
        pollInterval: const Duration(milliseconds: 1),
        waitLimit: waitLimit,
      );
}

// Function Name: main
// Description: Initializes SQLite FFI and registers gate serialization, failure recovery, stale-owner takeover, and real-store opening tests.
// Parameters: None.
// Returns: void; the test framework runs the registered cases.
void main() {
  sqfliteFfiInit();

  // Function Name: process-wide gate serialization test
  // Description: Holds one operation open and verifies that a second cannot start until the first releases the real process-wide gate.
  // Parameters: None.
  // Returns: Future<void>; fails if the second operation starts early or does not run after release.
  test('opens one at a time on the process-wide registry', () async {
    const gate = DoseStoreOpenGate(pollInterval: Duration(milliseconds: 1));
    final firstMayFinish = Completer<void>();
    var secondStarted = false;

    final first = gate.run(() => firstMayFinish.future);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final second = gate.run(() async => secondStarted = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(secondStarted, isFalse);

    firstMayFinish.complete();
    await Future.wait([first, second]);
    expect(secondStarted, isTrue);
  });

  // Function Name: failed-open gate release test
  // Description: Verifies that a failed operation propagates StateError, clears its registry entry, and lets the next operation return normally.
  // Parameters: None.
  // Returns: Future<void>; fails if the exception is swallowed or stale ownership blocks the next caller.
  test('a failed open passes the gate to the next caller', () async {
    final registry = _Registry();
    final gate = registry.gate();

    await expectLater(
      gate.run<void>(() async => throw StateError('open failed')),
      throwsStateError,
    );

    expect(registry.ports, isEmpty);
    expect(await gate.run(() async => 'opened'), 'opened');
  });

  // Function Name: abandoned gate takeover test
  // Description: Seeds a nonresponding registered port and verifies that a short wait limit permits takeover and final registry cleanup.
  // Parameters: None.
  // Returns: Future<void>; fails if the new operation cannot finish or leaves a registered owner.
  test('takes over a gate left behind by an engine that stopped', () async {
    final registry = _Registry();
    final stale = ReceivePort();
    addTearDown(stale.close);
    final gate = registry.gate(waitLimit: const Duration(milliseconds: 10));
    registry.ports['medbuddy_dose_store_open_gate'] = stale.sendPort;

    expect(await gate.run(() async => 'opened'), 'opened');

    expect(registry.ports, isEmpty);
  });

  // Function Name: successor ownership preservation test
  // Description: Replaces the registered port while an operation runs and verifies that the old owner's cleanup neither removes nor overwrites its successor.
  // Parameters: None.
  // Returns: Future<void>; fails if the successor port changes or any removal is attempted.
  test('a slow engine keeps the registration of its successor', () async {
    final registry = _Registry();
    final next = ReceivePort();
    addTearDown(next.close);
    final gate = registry.gate();

    await gate.run(() async {
      registry.ports['medbuddy_dose_store_open_gate'] = next.sendPort;
    });

    expect(registry.ports.values, [next.sendPort]);
    expect(registry.removals, 0);
  });

  // Function Name: DoseOutboxStore.openWith test group
  // Description: Registers isolated SQLite fixtures and an integration case for serialized store opening through the shared gate.
  // Parameters: None.
  // Returns: void; registers setup, cleanup, and the concurrent-open test.
  group('DoseOutboxStore.openWith', () {
    late Directory directory;
    late List<Database> opened;

    // Function Name: setUp callback
    // Description: Creates a temporary database directory and resets the list of opened connections.
    // Parameters: None.
    // Returns: Future<void>; completes when the directory is ready, or propagates its creation failure.
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('dose-open-gate-');
      opened = [];
    });

    // Function Name: tearDown callback
    // Description: Closes recorded SQLite connections before deleting the temporary database directory.
    // Parameters: None.
    // Returns: Future<void>; completes after cleanup, or propagates a close or deletion failure.
    tearDown(() async {
      for (final db in opened) {
        await db.close();
      }
      await directory.delete(recursive: true);
    });

    // Function Name: serialized store initialization test
    // Description: Starts two store opens on the process-wide gate and verifies that the second database callback waits for the first to finish.
    // Parameters: None.
    // Returns: Future<void>; fails if the recorded start/end order interleaves the two opens.
    test('a second engine waits until the first finished opening', () async {
      final key = base64Encode(List<int>.filled(32, 7));
      final firstMayFinish = Completer<void>();
      final order = <String>[];
      // Function Name: open
      // Description: Opens a store with a fixed encryption key and real SQLite schema, recording database callback order and retaining the connection for cleanup.
      // Parameters:
      // - name (String): Database filename stem and start/end event label.
      // - hold (Completer<void>?): Optional barrier awaited before opening the database.
      // Returns: Future<DoseOutboxStore>; the initialized store, or a propagated barrier/database initialization failure.
      Future<DoseOutboxStore> open(String name, {Completer<void>? hold}) {
        return DoseOutboxStore.openWith(
          readKey: () async => key,
          writeKey: (_) async {},
          openDatabase: () async {
            order.add('$name start');
            await hold?.future;
            final db = await databaseFactoryFfi.openDatabase(
              '${directory.path}/$name.db',
              options: OpenDatabaseOptions(
                version: 1,
                onCreate: DoseOutboxStore.createSchema,
              ),
            );
            opened.add(db);
            order.add('$name end');
            return db;
          },
          openGate: const DoseStoreOpenGate(
            pollInterval: Duration(milliseconds: 1),
          ),
        );
      }

      final first = open('first', hold: firstMayFinish);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final second = open('second');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(order, ['first start']);

      firstMayFinish.complete();
      await Future.wait([first, second]);
      expect(order, [
        'first start',
        'first end',
        'second start',
        'second end',
      ]);
    });
  });
}
