// 파일명: dose_sync_service_test.dart
// 역할: 오프라인 복용 기록의 암호화 보존, 순차 재전송과 날짜·계정 격리를 검증한다.
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

// 함수이름: main
// 함수역할: 실제 암호화 저장소를 사용한 대기 기록 보존·재전송·계정 격리 테스트를 등록한다.
// 매개변수: 없음. 반환값: 없음.
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
  // 함수이름: op
  // 함수역할: 고정 날짜의 아침 복용 요청을 만들어 완료와 취소를 같은 일정으로 검사한다.
  // 매개변수: id: 요청 식별자, completed: 완료 또는 취소 여부. 반환값: 전송 대기열에 넣을 요청 데이터.
  Map<String, dynamic> op(String id, {bool completed = true}) => {
    'operation_id': id,
    'schedule_date': '2026-09-21',
    'slot_key': 'morning',
    'medication_ids': [91],
    'completed': completed,
    'medication_names': ['private-dose-name'],
  };

  // 함수이름: setUp
  // 함수역할: 테스트마다 임시 SQLite DB와 별도 암호화 키를 만들고 테스트 계정을 활성화한다.
  // 매개변수: 없음. 반환값: 테스트 저장소 준비 Future.
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
  // 함수이름: tearDown
  // 함수역할: 테스트 DB 연결을 닫고 해당 테스트의 임시 디렉터리를 정리한다.
  // 매개변수: 없음. 반환값: 정리 완료 Future.
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  // 위젯 갱신이 지연되어도 영속 저장과 서버 전송은 완료되어야 한다.
  test('slow widget publication never blocks durable recording or delivery', () async {
    final widgetGate = Completer<void>();
    final posted = Completer<void>();
    var publications = 0;
    final client = MockClient((request) async {
      if (!posted.isCompleted) posted.complete();
      return http.Response('offline', 503);
    });
    final sync = DoseSyncService(owner: 'patient-a', client: client,
      openStore: () async => store, clock: () => now,
      onStateChanged: () async { publications++; await widgetGate.future; },
    );
    await sync.initialize();
    await sync.cacheSchedules([medication], scheduleDate: doseScheduleDay(now));
    final saved = await sync.record(medicationIds: [91], slotKey: 'morning',
        scheduleDate: doseScheduleDay(now), completed: true)
        .timeout(const Duration(seconds: 3));
    expect(saved, isTrue);
    await posted.future.timeout(const Duration(seconds: 3));
    await sync.drain();
    expect(await store.pending('patient-a'), hasLength(1));
    expect(publications, 1);
    widgetGate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(publications, 2);
    sync.dispose();
    client.close();
  });

  // 로그아웃 직전의 전송 시도는 정해진 시간만 기다린다. 응답이 없으면 기록을 대기열에 둔 채 돌아온다.
  test('flushPending uploads what it can and never waits past its limit', () async {
    final hanging = Completer<http.Response>();
    var online = false;
    var posts = 0;
    final client = MockClient((request) async {
      posts++;
      if (!online) return hanging.future;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'operation_id': body['operation_id'],
          'schedule_date': body['schedule_date'],
          'data': [medication.toJson()],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    await store.enqueue('patient-a', op('dose_flush_1'));
    final stalled = DoseSyncService(owner: 'patient-a', client: client,
      openStore: () async => store, clock: () => now);
    final watch = Stopwatch()..start();
    await stalled.flushPending(limit: const Duration(milliseconds: 200));
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    expect(posts, 1);
    expect(await store.pending('patient-a'), hasLength(1));
    // 늦게 도착한 실패 응답은 기록을 재시도 대기로 되돌린다.
    hanging.complete(http.Response('offline', 503));
    await stalled.drain();
    stalled.dispose();
    expect((await store.pending('patient-a')).single['state'], 'pending');

    online = true;
    final sync = DoseSyncService(owner: 'patient-a', client: client,
      openStore: () async => store, clock: () => now.add(const Duration(minutes: 5)));
    await sync.flushPending();
    expect(await store.pending('patient-a'), isEmpty);

    // 서버가 거부해 보류된 기록만 남았으면 다시 보내지 않는다.
    await store.enqueue('patient-a', op('dose_flush_2'));
    final lease = 'lease-1';
    await store.claim('patient-a', lease, 0);
    await store.finish('patient-a', 'dose_flush_2', lease, blocked: true);
    final before = posts;
    await sync.flushPending();
    expect(posts, before);
    expect((await store.pending('patient-a')).single['state'], 'blocked');
    sync.dispose();
    client.close();
  });

  // Both foreground read boundaries must reject yesterday's delayed response,
  // then recover on an explicit same-day refresh without queueing any writes.
  for (final summary in [false, true]) {
    // Function Name: midnight delayed-read test
    // Description: Verify both read endpoints reject a response crossing midnight, then recover on a same-day refresh.
    // Parameters: None; summary selects the read endpoint.
    // Returns: Completion of asynchronous assertions.
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
              'success': true,
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
              'success': true,
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
  // Function Name: initialization midnight test
  // Parameters: None.
  // Returns: Completion of asynchronous assertions.
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
  // Function Name: persistence midnight test
  // Parameters: None.
  // Returns: Completion of asynchronous assertions.
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
  // Function Name: publication midnight test
  // Parameters: None.
  // Returns: Completion of asynchronous assertions.
  test(
    'midnight during cache publication preserves the original date',
    () async {
      var current = now;
      var crossMidnight = false;
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
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

  // 함수이름: 암호화 기록 재시작 복구 테스트
  // 함수역할: DB를 다시 열어도 대기 요청·일정을 복구하되 다른 계정이나 잘못된 암호화 키로는 읽을 수 없는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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

  // 함수이름: 전송 작업 소유권 테스트
  // 함수역할: 동시에 한 작업자만 요청을 처리하고 만료된 작업자의 완료 통지가 재시도 요청을 지우지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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

  // 함수이름: 오프라인 완료·취소 순서 테스트
  // 함수역할: 재시작과 날짜 변경 뒤에도 완료·취소를 원래 날짜와 순서대로 전송하고 전날 일정을 오늘 화면에 적용하지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test(
    'offline taken and undo survive restart and sync in original date order',
    () async {
      var online = false;
      final requests = <Map<String, dynamic>>[];
      final sent = <http.Request>[];
      final client = MockClient((request) async {
        if (!online) throw const SocketException('offline');
        sent.add(request);
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
        medicationNames: ['private-dose-name'],
      );
      await service.drain();
      expect(service.schedules.single.isSlotCompleted('morning'), isTrue);
      // 화면 표시용 약 이름은 기기 대기열에만 남는다.
      expect(service.operations.single['medication_names'], [
        'private-dose-name',
      ]);
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
      // 요청은 계정 범위가 붙은 전송 경로로만 나가고 약 이름은 서버로 보내지 않는다.
      // (콜백 안의 expect는 전송 재시도 처리에 가려지므로 요청을 모아 밖에서 검사한다.)
      for (final request in sent) {
        expect(request.method, 'POST');
        expect(request.url.path, endsWith('/schedule/completion-operations'));
        expect(request.url.queryParameters, {'patient_hash': 'patient-a'});
        expect(request.headers['content-type'], contains('application/json'));
        expect(request.body, isNot(contains('private-dose-name')));
      }
      expect(requests.every((op) => !op.containsKey('medication_names')), isTrue);
      expect(requests.map((op) => op['slot_key']).toSet(), {'morning'});
      expect(requests.map((op) => op['medication_ids']).toList(), [
        [91],
        [91],
      ]);
      expect(service.pendingCount, 0);
      client.close();
    },
  );

  // 함수이름: 거부 기록 재시도 테스트
  // 함수역할: 서버가 거부한 요청 뒤의 작업을 보류하고 명시적 재시도 성공 시 순서대로 처리하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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

  // 함수이름: 저장소 열기 재시도 테스트
  // 함수역할: 저장소를 한 번 열지 못해도 다음 요청에서 다시 열어 복용 기록을 받을 수 있는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('a failed store open is retried on the next request', () async {
    var attempts = 0;
    final client = MockClient((_) async => http.Response('{}', 500));
    addTearDown(client.close);
    final sync = DoseSyncService(
      owner: 'patient-a',
      client: client,
      openStore: () async {
        if (attempts++ == 0) throw StateError('storage unavailable');
        return store;
      },
      clock: () => now,
    );
    addTearDown(sync.dispose);
    await expectLater(sync.initialize(), throwsStateError);
    await sync.initialize();
    expect(attempts, 2);
    await sync.cacheSchedules([medication], scheduleDate: doseScheduleDay(now));
    expect(sync.hasCache, isTrue);
  });

  // 함수이름: 계정별 대기 기록 삭제 테스트
  // 함수역할: 한 계정의 기록을 지워도 다른 계정의 전송 대기 기록이 유지되는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('account deletion clears only that account', () async {
    await store.enqueue('patient-a', op('account-a-operation'));
    await store.activate('patient-b');
    await store.enqueue('patient-b', op('account-b-operation'));
    await store.clearAccount('patient-a');
    expect(await store.pending('patient-a'), isEmpty);
    expect(await store.pending('patient-b'), hasLength(1));
  });

  // 함수이름: 오래된 응답 덮어쓰기 방지 테스트
  // 함수역할: 만료된 작업자의 응답과 이전 버전의 조회 결과가 최신 승인 캐시를 덮어쓰지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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

  // 함수이름: 거부 요청 폐기 조건 테스트
  // 함수역할: 아직 대기 중인 요청은 보존하고 서버가 거부한 요청만 명시적으로 폐기할 수 있는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('only rejected entries can be discarded', () async {
    await store.enqueue('patient-a', op('pending'));
    await store.discardRejected('patient-a', 'pending');
    expect(await store.pending('patient-a'), hasLength(1));
    await store.claim('patient-a', 'worker', 0);
    await store.finish('patient-a', 'pending', 'worker', blocked: true);
    await store.discardRejected('patient-a', 'pending');
    expect(await store.pending('patient-a'), isEmpty);
  });

  // 함수이름: 기준일 만료 기록 테스트
  // 함수역할: 날짜가 지난 캐시로 새 날짜의 기록을 만들지 않으며 원래 날짜를 명시한 선택만 그 날짜로 대기열에 저장하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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

  // 함수이름: 일정 저장 후 변경 알림 테스트
  // 함수역할: 서버 일정을 저장한 뒤의 다음 재조회가 같은 상태를 새 변경으로 다시 알리거나 발행하지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('a cached snapshot is published once, not again by the next reload', () async {
    var publications = 0;
    var notifications = 0;
    final client = MockClient((_) async => http.Response('offline', 503));
    addTearDown(client.close);
    final service = DoseSyncService(
      owner: 'patient-a',
      client: client,
      openStore: () async => store,
      clock: () => now,
      onStateChanged: () async => publications++,
    );
    addTearDown(service.dispose);
    await service.initialize();
    await Future<void>.delayed(Duration.zero);
    service.addListener(() => notifications++);
    publications = 0;

    await service.cacheSchedules([medication], scheduleDate: doseScheduleDay(now));
    await Future<void>.delayed(Duration.zero);
    expect(publications, 1);

    await service.reload();
    await service.drain();
    await Future<void>.delayed(Duration.zero);
    expect(publications, 1);
    expect(notifications, 0);

    // 실제로 바뀐 상태는 계속 알린다.
    await service.record(medicationIds: [91], slotKey: 'morning', completed: true);
    await service.drain();
    await Future<void>.delayed(Duration.zero);
    expect(publications, greaterThan(1));
    expect(notifications, greaterThan(0));
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
