// 실제 암호화 저장소와 두 전송 작업자로 계정별 순서 및 응답 역전을 검증한다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/entities/dose_widget_state.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _owner = 'synthetic-patient-a';
const _day = '2026-10-16';
final _now = DateTime.utc(2026, 10, 16, 3);

Map<String, dynamic> _operation(String id, String slot) => {
  'operation_id': id,
  'schedule_date': _day,
  'slot_key': slot,
  'medication_ids': [slot == 'morning' ? 91 : 92],
  'completed': true,
};

Map<String, dynamic> _cache(bool morning, bool evening) => {
  'date': _day,
  'schedules': [
    for (final entry in {'morning': morning, 'evening': evening}.entries)
      MedicationSchedule(
        medicationID: entry.key == 'morning' ? '91' : '92',
        medicationName: 'Synthetic ${entry.key} medication',
        scheduleSlotKeys: [entry.key],
        slotStatuses: {entry.key: entry.value},
        medicationStatus: entry.value,
      ).toJson(),
  ],
};

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late Database db;
  late DoseOutboxStore foregroundStore;
  late DoseOutboxStore backgroundStore;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dose-sync-race-');
    db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/outbox.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
      ),
    );
    final key = await AesGcm.with256bits().newSecretKey();
    foregroundStore = DoseOutboxStore(db, key);
    backgroundStore = DoseOutboxStore(db, key);
    await foregroundStore.activate(_owner);
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  for (final firstSlot in ['morning', 'evening']) {
    test('two workers retain 2/2 when the $firstSlot ACK is delayed', () async {
      final secondSlot = firstSlot == 'morning' ? 'evening' : 'morning';
      await foregroundStore.saveCache(_owner, _cache(false, false));
      final initialRevision = await foregroundStore.cacheRevision(_owner);
      await foregroundStore.enqueue(_owner, _operation('first', firstSlot));
      await foregroundStore.enqueue(_owner, _operation('second', secondSlot));

      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final sent = <String>[];
      final server = {'morning': false, 'evening': false};
      final client = MockClient((request) async {
        final operation = jsonDecode(request.body) as Map<String, dynamic>;
        final id = operation['operation_id'] as String;
        sent.add(id);
        server[operation['slot_key'] as String] = true;
        // 서버의 첫 일정은 1/2 상태로 고정하고, 전달만 늦춰 오래된 ACK를 재현한다.
        final receipt = http.Response(
          jsonEncode({
            'operation_id': id,
            'schedule_date': _day,
            'data': _cache(server['morning']!, server['evening']!)['schedules'],
          }),
          200,
        );
        if (id == 'first') {
          firstStarted.complete();
          await releaseFirst.future;
        }
        return receipt;
      });
      final foreground = DoseSyncService(
        owner: _owner,
        client: client,
        openStore: () async => foregroundStore,
        clock: () => _now,
      );
      final background = DoseSyncService(
        owner: _owner,
        client: client,
        openStore: () async => backgroundStore,
        clock: () => _now,
      );
      addTearDown(() {
        foreground.dispose();
        background.dispose();
        client.close();
      });

      final firstDrain = foreground.drain();
      Future<void>? secondDrain;
      late List<String> sentWhileLeased;
      late bool retryScheduled;
      try {
        await firstStarted.future.timeout(const Duration(seconds: 3));
        secondDrain = background.drain();
        await secondDrain.timeout(const Duration(seconds: 3));
        sentWhileLeased = List.of(sent);
        retryScheduled = background.hasScheduledRetry;
      } finally {
        releaseFirst.complete();
        await firstDrain;
        if (secondDrain != null) await secondDrain;
      }
      await background.drain();
      await foreground.reload();

      final cache = await foregroundStore.readCache(_owner);
      final pending = await foregroundStore.pending(_owner);
      final widget = DoseWidgetState.build(
        owner: _owner,
        cache: cache,
        operations: pending,
        previous: const {},
        now: _now,
        configuration: const {'language': 'en'},
      );
      expect(widget.view['done'], 2);
      expect(widget.view['total'], 2);
      expect(widget.view['action'], 'open');
      expect(widget.data['takes'], isEmpty);
      expect(widget.view['status'], 'Synced');
      expect(pending, isEmpty);
      for (final service in [foreground, background]) {
        expect(service.pendingCount, 0);
        expect(
          service.schedules.every((schedule) => schedule.medicationStatus),
          isTrue,
        );
        expect(service.hasScheduledRetry, isFalse);
      }
      expect(await foregroundStore.cacheRevision(_owner), initialRevision + 2);
      expect(sent, ['first', 'second']);
      expect(sentWhileLeased, ['first']);
      expect(retryScheduled, isTrue);
    });
  }

  for (final distinct in <String, Map<String, dynamic>>{
    'slot': {'slot_key': 'evening'},
    'medication': {
      'medication_ids': [92],
    },
    'day': {'schedule_date': '2026-10-15'},
  }.entries) {
    test('an active lease also holds an unrelated ${distinct.key}', () async {
      await foregroundStore.enqueue(_owner, _operation('first', 'morning'));
      await foregroundStore.enqueue(_owner, {
        ..._operation('second', 'morning'),
        ...distinct.value,
      });
      await foregroundStore.claim(_owner, 'foreground', 0);
      expect(await backgroundStore.claim(_owner, 'background', 119999), isNull);
      expect(await backgroundStore.hasUploadableOperation(_owner), isTrue);
      await foregroundStore.finish(_owner, 'first', 'foreground');
      expect(
        (await backgroundStore.claim(
          _owner,
          'background',
          119999,
        ))!['operation_id'],
        'second',
      );
    });
  }

  test(
    'active leases are isolated by account during an account switch',
    () async {
      const other = 'synthetic-patient-b';
      await foregroundStore.enqueue(_owner, _operation('a-first', 'morning'));
      await foregroundStore.claim(_owner, 'a-worker', 0);
      await backgroundStore.activate(other);
      await backgroundStore.enqueue(other, _operation('b-first', 'evening'));
      expect(
        (await backgroundStore.claim(other, 'b-worker', 1000))!['operation_id'],
        'b-first',
      );
      expect(
        await foregroundStore.claim(_owner, 'inactive-worker', 1000),
        isNull,
      );

      await foregroundStore.activate(_owner);
      await foregroundStore.enqueue(_owner, _operation('a-second', 'evening'));
      expect(await foregroundStore.claim(_owner, 'new-a-worker', 1000), isNull);
      await foregroundStore.finish(_owner, 'a-first', 'a-worker');
      expect(
        (await foregroundStore.claim(
          _owner,
          'new-a-worker',
          1000,
        ))!['operation_id'],
        'a-second',
      );
    },
  );

  test(
    'expired lease retries keep ownership and same-dose undo order',
    () async {
      await foregroundStore.saveCache(_owner, _cache(false, false));
      await foregroundStore.enqueue(_owner, _operation('taken', 'morning'));
      await foregroundStore.enqueue(_owner, {
        ..._operation('undo', 'morning'),
        'completed': false,
      });
      await foregroundStore.enqueue(_owner, _operation('evening', 'evening'));
      await foregroundStore.claim(_owner, 'expired-worker', 0);
      expect(
        (await backgroundStore.claim(
          _owner,
          'retry-worker',
          120000,
        ))!['operation_id'],
        'taken',
      );
      final before = await backgroundStore.cacheRevision(_owner);
      await foregroundStore.acknowledge(
        _owner,
        'taken',
        'expired-worker',
        _cache(true, false),
      );
      await foregroundStore.finish(
        _owner,
        'taken',
        'expired-worker',
        retry: true,
      );
      expect(await foregroundStore.cacheRevision(_owner), before);
      expect(await foregroundStore.pending(_owner), hasLength(3));
      expect(
        await foregroundStore.claim(_owner, 'third-worker', 120001),
        isNull,
      );

      await backgroundStore.acknowledge(
        _owner,
        'taken',
        'retry-worker',
        _cache(true, false),
      );
      expect(
        (await backgroundStore.claim(
          _owner,
          'undo-worker',
          120001,
        ))!['operation_id'],
        'undo',
      );
      await backgroundStore.acknowledge(
        _owner,
        'undo',
        'undo-worker',
        _cache(false, false),
      );
      expect(
        (await backgroundStore.claim(
          _owner,
          'evening-worker',
          120002,
        ))!['operation_id'],
        'evening',
      );
      await backgroundStore.acknowledge(
        _owner,
        'evening',
        'evening-worker',
        _cache(false, true),
      );
      await foregroundStore.acknowledge(
        _owner,
        'taken',
        'expired-worker',
        _cache(true, false),
      );
      expect(await foregroundStore.readCache(_owner), _cache(false, true));
      expect(await foregroundStore.pending(_owner), isEmpty);
      expect(await foregroundStore.cacheRevision(_owner), before + 3);
    },
  );
}
