// File Name: dose_outbox_store_recovery_test.dart
// Role: Checks encrypted outbox recovery after key loss and per-account reporting of unreadable records.
// Real SQLite/crypto with an in-memory stand-in for the device key storage; no production data.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Class Name: _KeyStorage
// Role: In-memory substitute for one device encryption key.
// Responsibilities: Simulate key read/write failures and delayed writes while counting successful writes.
// Attributes: value (String?): Stored key; failRead, failWrite (bool): Failure switches.
// - writeDelay (Duration): Delay before a write; writes (int): Successful write count.
class _KeyStorage {
  String? value;
  bool failRead = false;
  bool failWrite = false;
  Duration writeDelay = Duration.zero;
  int writes = 0;

  // Function Name: read
  // Description:
  // - Returns the stored key unless the read-failure switch is set.
  // Parameters:
  // - None.
  // Returns:
  // - Future<String?>: Stored key or null; throws StateError when failRead is true.
  Future<String?> read() async {
    if (failRead) throw StateError('Keystore unavailable.');
    return value;
  }

  // Function Name: write
  // Description:
  // - Waits for writeDelay, then stores the new key and increments writes unless failWrite is set.
  // Parameters:
  // - next (String): Replacement encryption key.
  // Returns:
  // - Future<void>: Completes after storage, or throws StateError before updating state.
  Future<void> write(String next) async {
    await Future<void>.delayed(writeDelay);
    if (failWrite) throw StateError('Keystore write failed.');
    writes++;
    value = next;
  }
}

// Function Name: main
// Description:
// - Registers real SQLite/encryption recovery tests using isolated temporary databases and fake key storage.
// Parameters:
// - None.
// Returns:
// - No value; registers recovery checks and cleanup hooks.
void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String path;
  late _KeyStorage keys;
  final opened = <Database>[];
  final now = DateTime.utc(2026, 9, 21, 3);
  const medication = MedicationSchedule(
    medicationID: '91',
    medicationName: 'private-dose-name',
    scheduleSlotKeys: ['morning'],
    slotStatuses: {'morning': false},
  );

  // Function Name: openDb
  // Description:
  // - Opens the test database with the production schema and tracks it for cleanup.
  // Parameters:
  // - None; uses the captured temporary path and opened list.
  // Returns:
  // - Future<Database>: The opened SQLite database.
  Future<Database> openDb() async {
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
      ),
    );
    if (!opened.contains(db)) opened.add(db);
    return db;
  }

  // Function Name: open
  // Description:
  // - Runs production outbox initialization with the fake key store and isolated database.
  // Parameters:
  // - None; uses captured keys and openDb.
  // Returns:
  // - Future<DoseOutboxStore>: Ready store, or the key/database initialization error.
  Future<DoseOutboxStore> open() => DoseOutboxStore.openWith(
    readKey: keys.read,
    writeKey: keys.write,
    openDatabase: openDb,
  );

  // Function Name: op
  // Description:
  // - Builds a synthetic completed morning dose for the fixed test date and medication.
  // Parameters:
  // - id (String): Unique operation identifier.
  // Returns:
  // - Map<String, dynamic>: Queue payload for medication 91.
  Map<String, dynamic> op(String id) => {
    'operation_id': id,
    'schedule_date': '2026-09-21',
    'slot_key': 'morning',
    'medication_ids': [91],
    'completed': true,
    'medication_names': ['private-dose-name'],
  };

  // Function Name: setUp callback
  // Description:
  // - Creates a fresh temporary database path and key-storage fake for each test.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Isolated storage is ready.
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dose-outbox-recovery-');
    path = '${directory.path}/outbox.db';
    keys = _KeyStorage();
  });

  // Function Name: tearDown callback
  // Description:
  // - Closes all opened databases before deleting the isolated test directory.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Database handles and temporary files are removed.
  tearDown(() async {
    for (final db in opened) {
      await db.close();
    }
    opened.clear();
    await directory.delete(recursive: true);
  });

  // Function Name: test callback
  // Description:
  // - Creates one encryption key, retains the first queued operation and reports no lost records.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('a first open creates one key and reports nothing lost', () async {
    final store = await open();
    await store.activate('patient-a');
    await store.enqueue('patient-a', op('first'));

    expect(keys.writes, 1);
    expect(await store.lostOperationCount('patient-a'), 0);
    expect(await store.pending('patient-a'), hasLength(1));
  });

  // Function Name: test callback
  // Description:
  // - Reuses the existing key while retaining both queued records, cached schedule date and active account with no reported loss.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('reopening with the key keeps every queued record', () async {
    var store = await open();
    await store.activate('patient-a');
    await store.enqueue('patient-a', op('kept-1'));
    await store.enqueue('patient-a', op('kept-2'));
    await store.saveCache('patient-a', {
      'date': '2026-09-21',
      'schedules': [medication.toJson()],
    });
    final key = keys.value;

    store = await open();

    expect(keys.value, key);
    expect(keys.writes, 1);
    expect(
      (await store.pending('patient-a')).map((o) => o['operation_id']),
      ['kept-1', 'kept-2'],
    );
    expect((await store.readCache('patient-a'))!['date'], '2026-09-21');
    expect(await store.isActive('patient-a'), isTrue);
    expect(await store.lostOperationCount('patient-a'), 0);
  });

  // Function Name: test callback
  // Description:
  // - Rotates a missing key, counts losses per account, rejects writes until reactivation and retains loss counts until acknowledgment or account clearing.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('a missing key restarts the store and reports the lost records', () async {
    var store = await open();
    await store.activate('patient-a');
    await store.enqueue('patient-a', op('lost-1'));
    await store.enqueue('patient-a', op('lost-2'));
    await store.activate('patient-b');
    await store.enqueue('patient-b', op('lost-3'));
    final oldKey = keys.value;
    keys.value = null;

    store = await open();

    expect(keys.value, isNotNull);
    expect(keys.value, isNot(oldKey));
    expect(await store.lostOperationCount('patient-a'), 2);
    expect(await store.lostOperationCount('patient-b'), 1);
    expect(await store.lostOperationCount('patient-c'), 0);
    expect(await store.pending('patient-a'), isEmpty);
    expect(await store.readCache('patient-a'), isNull);
    // 이전 계정 활성 상태도 지워져, 앱이 계정을 다시 활성화하기 전에는 기록을 받지 않는다.
    expect(await store.isActive('patient-b'), isFalse);
    await expectLater(
      store.enqueue('patient-b', op('too-early')),
      throwsStateError,
    );

    await store.activate('patient-a');
    await store.enqueue('patient-a', op('after-recovery'));
    expect(
      (await store.pending('patient-a')).single['operation_id'],
      'after-recovery',
    );

    // 다음 실행에서도 같은 키로 열리고, 확인하기 전까지 유실 건수가 유지된다.
    final recoveredKey = keys.value;
    store = await open();
    expect(keys.value, recoveredKey);
    expect(await store.pending('patient-a'), hasLength(1));
    expect(await store.lostOperationCount('patient-a'), 2);

    await store.clearLostOperations('patient-a');
    expect(await store.lostOperationCount('patient-a'), 0);
    expect(await store.lostOperationCount('patient-b'), 1);
    await store.clearAccount('patient-b');
    expect(await store.lostOperationCount('patient-b'), 0);
  });

  // Function Name: test callback
  // Description:
  // - Accumulates three unacknowledged losses across two key resets and leaves no unreadable pending rows.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('unacknowledged losses add up across a second key loss', () async {
    var store = await open();
    await store.activate('patient-a');
    await store.enqueue('patient-a', op('lost-1'));
    keys.value = null;
    store = await open();
    await store.activate('patient-a');
    await store.enqueue('patient-a', op('lost-2'));
    await store.enqueue('patient-a', op('lost-3'));
    keys.value = null;

    store = await open();

    expect(await store.lostOperationCount('patient-a'), 3);
    expect(await store.pending('patient-a'), isEmpty);
  });

  // Function Name: test callback
  // Description:
  // - Propagates a key-store read error without rotating the key or discarding the queued record.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('a key read error never discards records', () async {
    var store = await open();
    await store.activate('patient-a');
    await store.enqueue('patient-a', op('kept'));
    keys.failRead = true;

    await expectLater(open(), throwsStateError);

    keys.failRead = false;
    store = await open();
    expect(keys.writes, 1);
    expect(
      (await store.pending('patient-a')).single['operation_id'],
      'kept',
    );
    expect(await store.lostOperationCount('patient-a'), 0);
  });

  // Function Name: test callback
  // Description:
  // - Retries a failed replacement-key write on reopen, preserves the loss count and accepts new records after recovery.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('a failed key write is retried without losing the count', () async {
    var store = await open();
    await store.activate('patient-a');
    await store.enqueue('patient-a', op('lost-1'));
    keys.value = null;
    keys.failWrite = true;

    await expectLater(open(), throwsStateError);
    expect(keys.value, isNull);

    keys.failWrite = false;
    store = await open();
    expect(keys.value, isNotNull);
    expect(await store.lostOperationCount('patient-a'), 1);
    await store.activate('patient-a');
    await store.enqueue('patient-a', op('after-recovery'));
    expect(await store.pending('patient-a'), hasLength(1));
  });

  // Function Name: test callback
  // Description:
  // - Serializes overlapping recovery opens so they write one key and can read each other's newly queued record.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('concurrent recoveries share one key and can read each other', () async {
    final first = await open();
    await first.activate('patient-a');
    await first.enqueue('patient-a', op('lost-1'));
    keys.value = null;
    keys.writes = 0;
    keys.writeDelay = const Duration(milliseconds: 30);

    final stores = await Future.wait([open(), open()]);

    expect(keys.writes, 1);
    await stores[0].activate('patient-a');
    await stores[0].enqueue('patient-a', op('from-app'));
    expect(
      (await stores[1].pending('patient-a')).single['operation_id'],
      'from-app',
    );
    expect(await stores[1].lostOperationCount('patient-a'), 1);
  });

  // Function Name: test callback
  // Description:
  // - Initializes after key loss, queues a new dose despite offline upload and acknowledges only the loss notice with one listener notification.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('the sync service works after recovery and surfaces the loss', () async {
    var store = await open();
    await store.activate('patient-a');
    await store.enqueue('patient-a', op('lost-1'));
    keys.value = null;
    final client = MockClient((_) async => http.Response('offline', 503));
    addTearDown(client.close);
    var notifications = 0;
    final service = DoseSyncService(
      owner: 'patient-a',
      client: client,
      openStore: open,
      clock: () => now,
    )..addListener(() => notifications++);
    addTearDown(service.dispose);

    await service.initialize(activate: true);

    expect(service.lostRecordCount, 1);
    expect(service.pendingCount, 0);
    await service.cacheSchedules([medication], scheduleDate: doseScheduleDay(now));
    expect(
      await service.record(
        medicationIds: [91],
        slotKey: 'morning',
        completed: true,
      ),
      isTrue,
    );
    await service.drain();
    expect(service.pendingCount, 1);
    expect(jsonEncode(service.operations), isNot(contains('lost-1')));

    notifications = 0;
    await service.acknowledgeLostRecords();
    expect(service.lostRecordCount, 0);
    expect(notifications, 1);
    expect(service.pendingCount, 1);
  });
}
