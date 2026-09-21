// Real SQLite/crypto regressions; no production accounts or dose records.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late DoseOutboxStore store;
  late SecretKey key;
  late Directory directory;
  final now = DateTime.utc(2026, 9, 21, 3);
  const medication = MedicationSchedule(
    medicationID: '91',
    medicationName: 'private-dose-name',
    scheduleSlotKeys: ['morning'],
    slotStatuses: {'morning': false},
  );
  Map<String, dynamic> op(String id, {bool completed = true}) => {
    'operation_id': id,
    'schedule_date': '2026-09-21',
    'slot_key': 'morning',
    'medication_ids': [91],
    'completed': completed,
    'medication_names': ['private-dose-name'],
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dose-outbox-test-');
    db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/outbox.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
      ),
    );
    key = await AesGcm.with256bits().newSecretKey();
    store = DoseOutboxStore(db, key);
    await store.activate('patient-a');
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'encrypted queue and cached schedule survive a database reopen',
    () async {
      await store.enqueue('patient-a', op('persistent-operation'));
      await store.saveCache('patient-a', {
        'date': '2026-09-21',
        'schedules': [medication.toJson()],
      });
      final raw = await db.query('operations');
      expect(raw.toString(), isNot(contains('private-dose-name')));
      expect(raw.toString(), isNot(contains('patient-a')));
      await db.close();
      db = await databaseFactoryFfi.openDatabase('${directory.path}/outbox.db');
      store = DoseOutboxStore(db, key);
      expect(
        (await store.pending('patient-a')).single['operation_id'],
        'persistent-operation',
      );
      expect(await store.pending('patient-b'), isEmpty);
      expect((await store.readCache('patient-a'))!['date'], '2026-09-21');
      await expectLater(
        DoseOutboxStore(
          db,
          await AesGcm.with256bits().newSecretKey(),
        ).pending('patient-a'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    },
  );

  test(
    'leases serialize workers and stale acknowledgments cannot delete retries',
    () async {
      await store.enqueue('patient-a', op('first-operation'));
      await store.enqueue(
        'patient-a',
        op('second-operation', completed: false),
      );
      expect(
        (await store.claim('patient-a', 'worker-a', 0))!['operation_id'],
        'first-operation',
      );
      expect(await store.claim('patient-a', 'worker-b', 1000), isNull);
      expect(
        (await store.claim('patient-a', 'worker-b', 120001))!['operation_id'],
        'first-operation',
      );
      await store.finish('patient-a', 'first-operation', 'worker-a');
      expect(await store.pending('patient-a'), hasLength(2));
      await store.finish('patient-a', 'first-operation', 'worker-b');
      expect(
        (await store.claim('patient-a', 'worker-b', 120002))!['operation_id'],
        'second-operation',
      );
      await store.activate('patient-b');
      expect(await store.claim('patient-a', 'worker-c', 999999), isNull);
      await expectLater(
        store.enqueue('patient-a', op('wrong-account')),
        throwsStateError,
      );
    },
  );

  test(
    'offline taken and undo survive restart and sync in original date order',
    () async {
      var online = false;
      final requests = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        if (!online) throw const SocketException('offline');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(payload);
        return http.Response(
          jsonEncode({
            'operation_id': payload['operation_id'],
            'data': [medication.toJson()],
          }),
          200,
        );
      });
      var service = DoseSyncService(
        owner: 'patient-a',
        client: client,
        openStore: () async => store,
        clock: () => now,
      );
      await service.initialize(activate: true);
      await service.cacheSchedules([medication]);
      await service.record(
        medicationIds: [91],
        slotKey: 'morning',
        completed: true,
      );
      await service.drain();
      expect(service.schedules.single.isSlotCompleted('morning'), isTrue);
      await service.record(
        medicationIds: [91],
        slotKey: 'morning',
        completed: false,
      );
      await service.drain();
      expect(service.pendingCount, 2);
      expect(service.schedules.single.isSlotCompleted('morning'), isFalse);
      final ids = service.operations.map((op) => op['operation_id']).toList();
      service.dispose();
      service = DoseSyncService(
        owner: 'patient-a',
        client: client,
        openStore: () async => store,
        clock: () => now.add(const Duration(days: 1)),
      );
      addTearDown(service.dispose);
      await service.initialize(activate: true);
      expect(
        service.schedules,
        isEmpty,
      ); // Yesterday is never projected onto today.
      online = true;
      await service.drain();
      expect(requests.map((op) => op['operation_id']).toList(), ids);
      expect(requests.map((op) => op['completed']).toList(), [true, false]);
      expect(
        requests.every((op) => op['schedule_date'] == '2026-09-21'),
        isTrue,
      );
      expect(service.pendingCount, 0);
      client.close();
    },
  );

  test(
    'blocked records stay visible and hold later writes until explicit retry',
    () async {
      var status = 409;
      var calls = 0;
      await store.enqueue('patient-a', op('blocked-operation'));
      await store.enqueue(
        'patient-a',
        op('following-operation', completed: false),
      );
      final client = MockClient((request) async {
        calls++;
        final payload = jsonDecode(request.body) as Map;
        return http.Response(
          jsonEncode({'operation_id': payload['operation_id'], 'data': []}),
          status,
        );
      });
      final service = DoseSyncService(
        owner: 'patient-a',
        client: client,
        openStore: () async => store,
        clock: () => now,
      );
      addTearDown(service.dispose);
      await service.drain();
      expect(service.hasBlocked, isTrue);
      expect(service.pendingCount, 2);
      await service.drain();
      expect(calls, 1);
      status = 200;
      await service.retryNow();
      expect(service.pendingCount, 0);
      expect(calls, 3);
      client.close();
    },
  );

  test('account deletion clears only that account', () async {
    await store.enqueue('patient-a', op('account-a-operation'));
    await store.activate('patient-b');
    await store.enqueue('patient-b', op('account-b-operation'));
    await store.clearAccount('patient-a');
    expect(await store.pending('patient-a'), isEmpty);
    expect(await store.pending('patient-b'), hasLength(1));
  });

  test(
    'stale reads and expired workers cannot overwrite an acknowledged undo',
    () async {
      await store.saveCache('patient-a', {
        'date': '2026-09-21',
        'schedules': [medication.toJson()],
      });
      final before = await store.cacheRevision('patient-a');
      await store.enqueue('patient-a', op('first'));
      await store.claim('patient-a', 'stale', 0);
      await store.claim('patient-a', 'current', 120001);
      await store.acknowledge('patient-a', 'first', 'current', {
        'version': 'current',
      });
      await store.acknowledge('patient-a', 'first', 'stale', {
        'version': 'stale',
      });
      expect((await store.readCache('patient-a'))!['version'], 'current');
      expect(
        await store.saveCache('patient-a', {
          'version': 'old-read',
        }, expectedRevision: before),
        isFalse,
      );
      expect((await store.readCache('patient-a'))!['version'], 'current');
    },
  );

  test('only rejected entries can be discarded', () async {
    await store.enqueue('patient-a', op('pending'));
    await store.discardRejected('patient-a', 'pending');
    expect(await store.pending('patient-a'), hasLength(1));
    await store.claim('patient-a', 'worker', 0);
    await store.finish('patient-a', 'pending', 'worker', blocked: true);
    await store.discardRejected('patient-a', 'pending');
    expect(await store.pending('patient-a'), isEmpty);
  });

  test('an expired schedule is never recorded as a new day dose', () async {
    var current = now;
    final client = MockClient(
      (_) async => throw const SocketException('offline'),
    );
    final service = DoseSyncService(
      owner: 'patient-a',
      client: client,
      openStore: () async => store,
      clock: () => current,
    );
    addTearDown(service.dispose);
    addTearDown(client.close);
    await service.initialize(activate: true);
    await service.cacheSchedules([medication]);
    current = now.add(const Duration(days: 1));
    expect(
      await service.record(
        medicationIds: [91],
        slotKey: 'morning',
        completed: true,
      ),
      isFalse,
    );
    expect(await store.pending('patient-a'), isEmpty);
    // An explicit original date remains valid for an already selected chat slot.
    expect(
      await service.record(
        medicationIds: [91],
        slotKey: 'morning',
        completed: true,
        scheduleDate: '2026-09-21',
      ),
      isTrue,
    );
    await service.drain();
    expect(service.operations.single['schedule_date'], '2026-09-21');
    expect(service.schedules, isEmpty);
  });
}
