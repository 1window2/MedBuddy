// 파일명: dose_sync_concurrency_test.dart
// 역할: 실제 암호화 저장소와 두 전송 작업자로 계정별 순서 및 응답 역전을 검증한다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/entities/dose_widget_state.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_store_change_signal.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _owner = 'synthetic-patient-a';
const _day = '2026-10-16';
final _now = DateTime.utc(2026, 10, 16, 3);

// 함수이름: _operation
// 함수역할:
// - 고정 테스트 날짜에 한 시간대의 복용 완료를 기록하는 대기 작업을 만든다.
// 매개변수:
// - id(String): 전송·승인 순서를 추적할 작업 ID.
// - slot(String): 시간대 키; morning이면 약 91, 그 외에는 약 92를 선택한다.
// 반환값:
// - Map<String, dynamic>: completed가 true인 암호화 저장소 입력 맵.
Map<String, dynamic> _operation(String id, String slot) => {
  'operation_id': id,
  'schedule_date': _day,
  'slot_key': slot,
  'medication_ids': [slot == 'morning' ? 91 : 92],
  'completed': true,
};

// 함수이름: _cache
// 함수역할:
// - 아침·저녁 약의 시간대 상태와 약 전체 상태를 일치시킨 일정 캐시를 만든다.
// 매개변수:
// - morning(bool): 아침 약 91의 복용 완료 여부.
// - evening(bool): 저녁 약 92의 복용 완료 여부.
// 반환값:
// - Map<String, dynamic>: 고정 날짜와 두 약의 JSON 일정을 포함한 캐시.
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

// 함수이름: main
// 함수역할:
// - 두 작업자의 전송 대기·임대 충돌·늦은 승인 상황에서 복약 상태 보존을 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  sqfliteFfiInit();
  late Directory directory;
  late Database db;
  late DoseOutboxStore foregroundStore;
  late DoseOutboxStore backgroundStore;

  // 함수이름: setUp 콜백
  // 함수역할:
  // - 독립 DB와 암호화 키를 만들고 이를 공유하는 전경·백그라운드 저장소를 활성화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 동일 계정과 DB를 공유하는 두 작업자의 저장소 준비 완료.
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

  // 함수이름: tearDown 콜백
  // 함수역할:
  // - 공용 DB 연결을 닫고 테스트 전용 디렉터리를 제거한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 저장소 정리 완료.
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  for (final firstSlot in ['morning', 'evening']) {
    // 함수이름: test callback
    // 함수역할:
    // - 첫 승인 응답을 보류하면 두 번째 작업자는 전송 대신 재시도하며, 해제 후 순차 승인으로 캐시·위젯 모두 2/2 완료와 빈 대기열을 유지하는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
    // 함수이름: test callback
    // 함수역할:
    // - 시간대·약·날짜가 다른 작업이라도 같은 계정의 활성 임대 동안 가져올 수 없고 첫 작업 완료 후에만 가져오는지 검증한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test callback
  // 함수역할:
  // - 새 계정은 이전 계정의 임대에 막히지 않지만 이전 계정으로 돌아오면 그 임대가 끝날 때까지 다음 작업을 가져오지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test callback
  // 함수역할:
  // - 만료 작업자의 승인·재시도 종료를 무시하고 새 임대에서 복용·취소·저녁 기록 순서를 지켜 최종 캐시와 리비전을 보존하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // Function Name: background upload notice test
  // Description: The background job's upload of a record the foreground queued reaches the foreground
  //   service through the store-change signal, so its pending list and projected schedule follow the
  //   server at once (the emulator showed 2/3 and "2 records waiting" for about a minute without it).
  // Parameters: None.
  // Returns: Future<void>; fails when the foreground service keeps the uploaded record as pending.
  test('a background upload reaches the foreground service', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await foregroundStore.saveCache(_owner, _cache(true, false));
    await foregroundStore.enqueue(
      _owner,
      _operation('evening-dose', 'evening'),
    );
    final ports = <String, SendPort>{};
    DoseStoreChangeSignal signal() => DoseStoreChangeSignal(
      register: (port, name) {
        if (ports.containsKey(name)) return false;
        ports[name] = port;
        return true;
      },
      lookup: (name) => ports[name],
      remove: (name) => ports.remove(name) != null,
    );
    // The foreground cannot reach the server; only the background job uploads.
    final offline = MockClient((_) async => http.Response('', 503));
    final online = MockClient((request) async {
      final operation = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'operation_id': operation['operation_id'],
          'schedule_date': _day,
          'data': _cache(true, true)['schedules'],
        }),
        200,
      );
    });
    final foreground = DoseSyncService(
      owner: _owner,
      client: offline,
      openStore: () async => foregroundStore,
      clock: () => _now,
      changeSignal: signal(),
    );
    final background = DoseSyncService(
      owner: _owner,
      client: online,
      openStore: () async => backgroundStore,
      clock: () => _now,
      changeSignal: signal(),
    );
    addTearDown(() {
      foreground.dispose();
      background.dispose();
      offline.close();
      online.close();
    });
    await foreground.start();
    await foreground.drain();
    expect(foreground.pendingCount, 1);

    final caughtUp = Completer<void>();
    foreground.addListener(() {
      if (foreground.pendingCount == 0 && !caughtUp.isCompleted) {
        caughtUp.complete();
      }
    });
    await background.drain();
    await caughtUp.future.timeout(const Duration(seconds: 3));

    expect(
      foreground.schedules
          .singleWhere((s) => s.medicationID == '92')
          .isSlotCompleted('evening'),
      isTrue,
    );
  });
}
