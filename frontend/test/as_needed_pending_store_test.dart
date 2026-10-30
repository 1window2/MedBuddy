import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/medication_history_control.dart';
import 'package:medbuddy_frontend/entities/medication_history_entity.dart';
import 'package:medbuddy_frontend/services/as_needed_pending_store.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_as_needed_pending_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late DoseOutboxStore store;
  late AsNeededPendingStore pending;
  String? key;
  final now = DateTime.utc(2026, 10, 22, 3);
  const owner = 'test-patient';

  Future<void> open() async {
    store = await DoseOutboxStore.openWith(
      readKey: () async => key,
      writeKey: (value) async {
        key = value;
      },
      openDatabase: () => databaseFactoryFfi.openDatabase(
        '${directory.path}/outbox.db',
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: DoseOutboxStore.createSchema,
        ),
      ),
    );
    await store.activate(owner);
    pending = AsNeededPendingStore(openStore: () async => store);
  }

  MedicationHistoryChange change({int id = 1}) => MedicationHistoryChange(
    entry: MedicationHistoryEntry(
      medicationId: id,
      itemName: 'private-test-medication-$id',
      scheduleDate: DateTime(2026, 10, 22),
      slotKey: 'as_needed:${MedicationHistoryControl.newOperationId()}',
      status: MedicationHistoryStatus.unrecorded,
      revision: 0,
      dosingMode: 'as_needed',
    ),
    status: MedicationHistoryStatus.taken,
    actualTakenAt: now.subtract(const Duration(minutes: 2)),
    operationId: MedicationHistoryControl.newOperationId(),
  );

  MedicationHistoryControl control(
    http.Client client, {
    AsNeededPendingStore? storage,
    DateTime? clock,
  }) => MedicationHistoryControl(
    patientHash: owner,
    client: client,
    now: () => clock ?? now,
    pendingStore: storage ?? pending,
    sessionKeyProvider: () => owner,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('medbuddy-prn-test-');
    key = null;
    await open();
  });
  tearDown(() async {
    await store.db.close();
    await directory.delete(recursive: true);
  });

  test(
    'encrypted pending batch survives database reopen with identical intent',
    () async {
      final original = change();
      await pending.stage(owner, [original]);
      final raw = jsonEncode(await store.db.query('metadata'));
      expect(raw, isNot(contains(original.entry.itemName)));
      expect(raw, isNot(contains(original.operationId)));
      expect(raw, isNot(contains('2026-10-22')));
      await store.db.close();
      await open();
      final restored = (await pending.read(owner)).single;
      expect(restored.operationId, original.operationId);
      expect(restored.entry.key, original.entry.key);
      expect(restored.actualTakenAt, original.actualTakenAt);
      expect(restored.toJson(owner), original.toJson(owner));
    },
  );

  test(
    'response lost then restart retries same event without a second server write',
    () async {
      final original = change();
      final serverEvents = <String>{};
      final requests = <String>[];
      var loseResponse = true;
      final client = MockClient((request) async {
        requests.add(request.body);
        serverEvents.add(request.url.path);
        if (loseResponse) throw TimeoutException('Response lost');
        return http.Response('{"success":true}', 200);
      });
      final first = control(client);
      await expectLater(first.save(original), throwsA(isA<TimeoutException>()));
      first.dispose();
      await store.db.close();
      await open();
      // 자정을 지나도 원래 날짜와 실제 복용 시각을 그대로 재전송한다.
      final restarted = control(
        client,
        clock: now.add(const Duration(days: 1)),
      );
      await restarted.restorePendingAsNeeded();
      loseResponse = false;
      await restarted.save(restarted.pendingAsNeededChanges.single);
      expect(requests, hasLength(2));
      expect(requests.first, requests.last);
      expect(serverEvents, hasLength(1));
      expect(await pending.read(owner), isEmpty);
      restarted.dispose();
    },
  );

  test(
    'partial batch acknowledgement preserves only the unfinished event',
    () async {
      final first = change();
      final second = change(id: 2);
      await pending.stage(owner, [first, second]);
      await pending.remove(owner, {first.operationId});
      await store.db.close();
      await open();
      expect(
        (await pending.read(owner)).single.operationId,
        second.operationId,
      );
    },
  );

  test('another stage cannot replace the durable unresolved request', () async {
    final original = change();
    await pending.stage(owner, [original]);
    final result = await pending.stage(owner, [change(id: 2)]);
    expect(result.single.operationId, original.operationId);
  });

  test(
    'inactive owner cannot read, overwrite or remove pending requests',
    () async {
      final original = change();
      await pending.stage(owner, [original]);
      await store.activate('other-patient');
      await expectLater(pending.read(owner), throwsStateError);
      await expectLater(pending.stage(owner, [change()]), throwsStateError);
      await expectLater(
        pending.remove(owner, {original.operationId}),
        throwsStateError,
      );
      expect(await pending.read('other-patient'), isEmpty);
      await store.activate(owner);
      expect(
        (await pending.read(owner)).single.operationId,
        original.operationId,
      );
    },
  );

  test('account deletion removes payload and recovery count', () async {
    await pending.stage(owner, [change()]);
    await store.clearAccount(owner);
    final rows = await store.db.query(
      'metadata',
      where: 'name LIKE ?',
      whereArgs: ['history-pending%'],
    );
    expect(rows, isEmpty);
  });

  test('local staging failure sends no network request', () async {
    var sent = 0;
    final fake = FakeAsNeededPendingStore()..failStage = true;
    final controller = control(
      MockClient((_) async {
        sent++;
        return http.Response('{"success":true}', 200);
      }),
      storage: fake,
    );
    await expectLater(controller.save(change()), throwsStateError);
    expect(sent, 0);
    controller.dispose();
  });

  test(
    'key loss reports pending count without retaining health data',
    () async {
      await pending.stage(owner, [change(), change(id: 2)]);
      await store.db.close();
      key = null;
      await open();
      expect(await store.lostOperationCount(owner), 2);
      expect(await pending.read(owner), isEmpty);
      expect(
        jsonEncode(await store.db.query('metadata')),
        isNot(contains('private-test-medication')),
      );
    },
  );

  test(
    'failed local acknowledgement retains the identical retry intent',
    () async {
      final fake = FakeAsNeededPendingStore()..failRemove = true;
      final controller = control(
        MockClient((_) async => http.Response('{"success":true}', 200)),
        storage: fake,
      );
      final original = change();
      await expectLater(controller.save(original), throwsStateError);
      expect((await fake.read(owner)).single.operationId, original.operationId);
      fake.failRemove = false;
      await controller.save(controller.pendingAsNeededChanges.single);
      expect(await fake.read(owner), isEmpty);
      controller.dispose();
    },
  );

  test(
    'restore failure is visible and retryable instead of a permanent spinner',
    () async {
      await store.activate('other-patient');
      final controller = control(
        MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(controller.restorePendingAsNeeded(), throwsStateError);
      expect(controller.error, isA<StateError>());
      await store.activate(owner);
      await controller.restorePendingAsNeeded();
      controller.dispose();
    },
  );
}
