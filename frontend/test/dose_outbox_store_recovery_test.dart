// 파일명: dose_outbox_store_recovery_test.dart
// 역할: 기기 보안 저장소의 키가 사라진 뒤에도 복용 기록 저장소가 다시 열리고, 읽을 수 없게 된
//   전송 대기 기록의 건수를 사용자에게 알릴 수 있는지 검증한다.
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

// 클래스명: _KeyStorage
// 역할: 기기 보안 저장소의 키 한 개를 메모리에 보관하는 대역.
// 주요 책임: 읽기·쓰기 횟수를 세고, 읽기 오류와 쓰기 실패·지연을 재현한다.
// 속성: value 저장된 키(null이면 없음), failRead/failWrite 실패 재현, writes 쓰기 횟수.
class _KeyStorage {
  String? value;
  bool failRead = false;
  bool failWrite = false;
  Duration writeDelay = Duration.zero;
  int writes = 0;

  // 함수이름: read
  // 함수역할: 저장된 키를 돌려주거나 보안 저장소 오류를 재현한다. 반환값: 키 또는 null.
  Future<String?> read() async {
    if (failRead) throw StateError('Keystore unavailable.');
    return value;
  }

  // 함수이름: write
  // 함수역할: 지연 뒤 키를 저장하거나 쓰기 실패를 재현한다. 매개변수: next - 새 키.
  Future<void> write(String next) async {
    await Future<void>.delayed(writeDelay);
    if (failWrite) throw StateError('Keystore write failed.');
    writes++;
    value = next;
  }
}

// 함수이름: main
// 함수역할: 키 분실 복구와 유실 안내의 회귀 테스트를 등록한다. 매개변수: 없음. 반환값: 없음.
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

  // 함수이름: openDb
  // 함수역할: 운영 코드와 같은 스키마로 테스트 DB 파일을 연다. 반환값: 열린 DB.
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

  // 함수이름: open
  // 함수역할: 운영 코드의 열기 절차를 테스트 키 저장소와 DB로 실행한다. 반환값: 열린 저장소.
  Future<DoseOutboxStore> open() => DoseOutboxStore.openWith(
    readKey: keys.read,
    writeKey: keys.write,
    openDatabase: openDb,
  );

  // 함수이름: op
  // 함수역할: 아침 복용 완료 요청을 만든다. 매개변수: id - 요청 ID. 반환값: 대기열 요청.
  Map<String, dynamic> op(String id) => {
    'operation_id': id,
    'schedule_date': '2026-09-21',
    'slot_key': 'morning',
    'medication_ids': [91],
    'completed': true,
    'medication_names': ['private-dose-name'],
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dose-outbox-recovery-');
    path = '${directory.path}/outbox.db';
    keys = _KeyStorage();
  });

  tearDown(() async {
    for (final db in opened) {
      await db.close();
    }
    opened.clear();
    await directory.delete(recursive: true);
  });

  // 함수이름: 첫 설치 테스트
  // 함수역할: 키와 DB가 모두 없으면 새 키를 만들고 유실 안내 없이 시작하는지 검증한다.
  test('a first open creates one key and reports nothing lost', () async {
    final store = await open();
    await store.activate('patient-a');
    await store.enqueue('patient-a', op('first'));

    expect(keys.writes, 1);
    expect(await store.lostOperationCount('patient-a'), 0);
    expect(await store.pending('patient-a'), hasLength(1));
  });

  // 함수이름: 키가 있는 재시작 테스트
  // 함수역할: 키가 남아 있으면 다시 열어도 대기 기록과 일정이 그대로이고 키를 바꾸지 않는지 검증한다.
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

  // 함수이름: 키 분실 복구 테스트
  // 함수역할: 키만 사라지면 예외를 반복하지 않고 새 키로 다시 시작하며, 읽을 수 없게 된 기록의 건수를
  //   계정별로 남기고 다시 로그인한 계정이 새 기록을 저장할 수 있는지 검증한다.
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

  // 함수이름: 반복 키 분실 테스트
  // 함수역할: 확인하지 않은 유실 건수가 다음 키 분실에서도 합산되어 남는지 검증한다.
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

  // 함수이름: 보안 저장소 오류 테스트
  // 함수역할: 키를 읽다 오류가 나면 키가 없는 것으로 보지 않고 기록을 그대로 둔 채 실패하는지 검증한다.
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

  // 함수이름: 키 저장 실패 테스트
  // 함수역할: 새 키 저장이 실패하면 열기가 실패하고, 다음 열기에서 유실 건수를 잃지 않고 복구를 마치는지 검증한다.
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

  // 함수이름: 동시 복구 테스트
  // 함수역할: 앱과 백그라운드 작업이 동시에 열어도 키를 하나만 만들고 서로의 기록을 읽을 수 있는지 검증한다.
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

  // 함수이름: 복구 후 동기화 서비스 테스트
  // 함수역할: 키 분실 뒤에도 서비스가 열리고 복용 기록을 받으며, 유실 건수를 알리고 확인하면 지우는지 검증한다.
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
