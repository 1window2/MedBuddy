// Real SQLite/crypto regressions; no production accounts or dose records.
import 'dart:async';
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
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/check_today_medication_info_control.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';

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

  // Both foreground read boundaries must reject yesterday's delayed response,
  // then recover on an explicit same-day refresh without queueing any writes.
  for (final summary in [false, true]) {
    test(
      'midnight rejects delayed ${summary ? "summary" : "schedule"} reads',
      () async {
        var current = DateTime.utc(2026, 9, 21, 14, 59, 59);
        final started = Completer<void>();
        final response = Completer<http.Response>();
        var delayed = true;
        final client = MockClient((_) async {
          if (delayed) {
            started.complete();
            return response.future;
          }
          return http.Response(
            jsonEncode({
              'data': [medication.toJson()],
            }),
            200,
          );
        });
        final service = DoseSyncService(
          owner: 'patient-a',
          client: client,
          openStore: () async => store,
          clock: () => current,
        );
        await service.initialize();
        final viewModel = MedBuddyViewModel(
          checkSchedule: CheckSchedule(
            patientHash: 'patient-a',
            client: client,
          ),
          checkTodayMedicationInfo: CheckTodayMedicationInfo(
            patientHash: 'patient-a',
            client: client,
          ),
        )..doseSync = service;
        addTearDown(viewModel.dispose);
        addTearDown(client.close);
        final load = summary
            ? viewModel.fetchTodayMedicationInfo
            : viewModel.fetchTodayMedicationSchedule;
        final pending = load();
        await started.future;
        current = current.add(const Duration(seconds: 2));
        response.complete(
          http.Response(
            jsonEncode({
              'data': [medication.toJson()],
            }),
            200,
          ),
        );
        await pending;
        expect(viewModel.hasTodayScheduleLoadError, isTrue);
        expect(viewModel.isTodayScheduleLoading, isFalse);
        expect(viewModel.todayMedicationScheduleList, isEmpty);
        expect(service.hasCache, isFalse);
        expect(await store.readCache('patient-a'), isNull);
        expect(
          await service.record(
            medicationIds: [91],
            slotKey: 'morning',
            completed: true,
          ),
          isFalse,
        );
        expect(await store.pending('patient-a'), isEmpty);
        delayed = false;
        await load();
        expect(viewModel.hasTodayScheduleLoadError, isFalse);
        expect(viewModel.todayMedicationScheduleList, hasLength(1));
        expect((await store.readCache('patient-a'))!['date'], '2026-09-22');
      },
    );
  }

  // Initialization may block behind storage work; reject an expired request day
  // after it completes instead of stamping the snapshot with a new date.
  test('cache rejects a read that expires during initialization', () async {
    var current = now;
    final opened = Completer<DoseOutboxStore>();
    final client = MockClient((_) async => http.Response('{}', 500));
    final service = DoseSyncService(
      owner: 'patient-a',
      client: client,
      openStore: () => opened.future,
      clock: () => current,
    );
    addTearDown(service.dispose);
    addTearDown(client.close);
    final pending = service.cacheSchedules([
      medication,
    ], scheduleDate: doseScheduleDay(current));
    final rejected = expectLater(pending, throwsStateError);
    current = current.add(const Duration(days: 1));
    opened.complete(store);
    await rejected;
    expect(service.hasCache, isFalse);
    expect(await store.readCache('patient-a'), isNull);
  });

  // A durable write finishing after midnight must not advance the in-memory
  // date, which otherwise permits recording today's dose from yesterday's data.
  test(
    'midnight during persistence cannot enable current-day writes',
    () async {
      var current = now;
      final delayedStore = _MidnightStore(db, key, () {
        current = now.add(const Duration(days: 1));
      });
      final client = MockClient((_) async => http.Response('{}', 500));
      final service = DoseSyncService(
        owner: 'patient-a',
        client: client,
        openStore: () async => delayedStore,
        clock: () => current,
      );
      addTearDown(service.dispose);
      addTearDown(client.close);
      await service.cacheSchedules([
        medication,
      ], scheduleDate: doseScheduleDay(now));
      expect(service.hasCache, isFalse);
      expect(service.schedules, isEmpty);
      expect(
        (await store.readCache('patient-a'))!['date'],
        doseScheduleDay(now),
      );
      expect(
        await service.record(
          medicationIds: [91],
          slotKey: 'morning',
          completed: true,
        ),
        isFalse,
      );
      expect(await store.pending('patient-a'), isEmpty);
    },
  );

  // Widget publication is asynchronous too; a day change here must not publish
  // stale foreground state, even though the old dated snapshot was persisted.
  test(
    'midnight during cache publication preserves the original date',
    () async {
      var current = now;
      var crossMidnight = false;
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': [medication.toJson()],
          }),
          200,
        ),
      );
      final service = DoseSyncService(
        owner: 'patient-a',
        client: client,
        openStore: () async => store,
        clock: () => current,
        onStateChanged: () async {
          if (crossMidnight) current = now.add(const Duration(days: 1));
        },
      );
      await service.initialize();
      final viewModel = MedBuddyViewModel(
        checkSchedule: CheckSchedule(patientHash: 'patient-a', client: client),
      )..doseSync = service;
      addTearDown(viewModel.dispose);
      addTearDown(client.close);
      crossMidnight = true;
      await viewModel.fetchTodayMedicationSchedule();
      expect(viewModel.hasTodayScheduleLoadError, isTrue);
      expect(viewModel.todayMedicationScheduleList, isEmpty);
      expect(service.schedules, isEmpty);
      expect(service.hasCache, isFalse);
      expect(
        (await store.readCache('patient-a'))!['date'],
        doseScheduleDay(now),
      );
    },
  );

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
      await service.cacheSchedules([
        medication,
      ], scheduleDate: doseScheduleDay(now));
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
    await service.cacheSchedules([
      medication,
    ], scheduleDate: doseScheduleDay(now));
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

// Class Name: _MidnightStore
// Role: Advance the test clock after a real encrypted cache write completes.
// Responsibilities: Expose the persistence await boundary deterministically.
// Attributes: onSaved - simulated clock change, without changing stored data.
class _MidnightStore extends DoseOutboxStore {
  final void Function() onSaved;

  // Function Name: _MidnightStore
  // Description: Bind the real test database/key and the post-save callback.
  // Parameters: db/key - encrypted test store; onSaved - clock advancement.
  // Returns: A store that retains normal database behavior.
  _MidnightStore(super.db, super.key, this.onSaved);

  // Function Name: saveCache
  // Description: Save normally, then simulate midnight before returning.
  // Parameters: owner/cache/expectedRevision - unchanged persistence inputs.
  // Returns: The underlying revision guard's result.
  @override
  Future<bool> saveCache(
    String owner,
    Map<String, dynamic> cache, {
    int? expectedRevision,
  }) async {
    final saved = await super.saveCache(
      owner,
      cache,
      expectedRevision: expectedRevision,
    );
    onSaved();
    return saved;
  }
}
