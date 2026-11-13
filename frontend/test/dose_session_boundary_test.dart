// 파일명: dose_session_boundary_test.dart
// 역할: 폐기된 복약 동기화의 계정 재활성화와 자정 전 응답의 오늘 캐시 덮어쓰기를 방지하는지 검증한다.

import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/entities/dose_widget_state.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/json_http.dart';

// 클래스명: _DelayedOwnerKeyStore
// 역할: 계정 키 조회 도중 세션을 전환할 수 있도록 최초 조회만 대기시키는 저장소 대역이다.
// 주요 책임:
// - 최초 키 조회 진입을 알리고 외부에서 해제한 뒤 실제 키 계산을 이어 간다.
// 속성:
// - entered(Completer<void>): 최초 조회가 대기 지점에 도달했음을 알리는 신호.
// - release(Completer<void>): 테스트가 세션을 바꾼 뒤 조회를 재개하는 신호.
class _DelayedOwnerKeyStore extends DoseOutboxStore {
  // 함수이름: _DelayedOwnerKeyStore
  // 함수역할:
  // - 기존 저장소와 같은 데이터베이스와 암호화 키를 사용해 지연 대역을 만든다.
  // 매개변수:
  // - db(Database): 테스트가 열고 정리하는 메모리 데이터베이스.
  // - key(SecretKey): 기존 복약 데이터와 호환되는 암호화 키.
  // 반환값:
  // - _DelayedOwnerKeyStore: 첫 키 조회를 제어할 수 있는 저장소.
  _DelayedOwnerKeyStore(super.db, super.key);

  final entered = Completer<void>();
  final release = Completer<void>();

  // 함수이름: ownerKey
  // 함수역할:
  // - 최초 호출은 release를 기다리고 이후 호출은 바로 상위 저장소의 키를 조회한다.
  // 매개변수:
  // - owner(String): 키를 계산할 계정 식별자.
  // 반환값:
  // - Future<String>: 계정 저장 키; 실제 키 계산 오류는 호출자에게 전달된다.
  @override
  Future<String> ownerKey(String owner) async {
    if (!entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return super.ownerKey(owner);
  }
}

// 함수이름: main
// 함수역할:
// - 메모리 저장소를 이용해 초기화 중 계정 변경과 날짜가 바뀐 뒤 도착하는 영수증을 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 각 비동기 사례와 저장소 준비·정리 훅을 등록한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late DoseOutboxStore store;
  late http.Client client;
  final now = DateTime.utc(2026, 10, 21, 3);

  // 함수이름: setUp 콜백
  // 함수역할:
  // - 독립 메모리 DB와 암호화 키를 만들고 patient-a를 활성화하며 HTTP 요청은 503으로 응답한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 격리된 저장소 준비 완료; DB나 키 생성 실패는 테스트 준비 실패가 된다.
  setUp(() async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
        singleInstance: false,
      ),
    );
    store = DoseOutboxStore(db, await AesGcm.with256bits().newSecretKey());
    client = MockClient((_) async => http.Response('offline', 503));
    await store.activate('patient-a');
  });

  // 함수이름: tearDown 콜백
  // 함수역할:
  // - 테스트에서 교체했을 수도 있는 현재 HTTP 클라이언트와 메모리 DB를 닫는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 데이터베이스 닫기 완료.
  tearDown(() async {
    client.close();
    await store.db.close();
  });

  for (final nextOwner in <String?>[null, 'patient-b']) {
    // 함수이름: 폐기된 초기화의 계정 재활성화 차단 테스트
    // 함수역할:
    // - 저장소 열기를 지연한 채 동기화를 폐기하고 로그아웃하거나 다른 계정을 활성화한다.
    // - 늦은 초기화 완료가 patient-a를 되살리거나 다음 계정을 비활성화하면 실패한다.
    // 매개변수:
    // - 없음; nextOwner(String?)는 로그아웃 또는 전환할 계정을 나타낸다.
    // 반환값:
    // - Future<void>: 초기화 종료 후 활성 계정 검증 완료.
    test('a disposed initializer cannot reactivate after $nextOwner', () async {
      final opened = Completer<DoseOutboxStore>();
      final sync = DoseSyncService(
        owner: 'patient-a',
        client: client,
        openStore: () => opened.future,
        clock: () => now,
      );
      final initialization = sync.initialize(activate: true);
      sync.dispose();
      await store.activate(nextOwner);
      opened.complete(store);
      await initialization;

      expect(await store.isActive('patient-a'), isFalse);
      if (nextOwner != null) expect(await store.isActive(nextOwner), isTrue);
    });
  }

  // 함수이름: 키 조회 뒤 세션 소유권 재검사 테스트
  // 함수역할:
  // - 계정 키를 기다리는 동안 서비스를 폐기하고 patient-b로 전환한다.
  // - 키 조회가 끝나도 새 계정만 활성 상태로 남아야 한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 지연 해제 후 두 계정의 활성 상태 검증 완료.
  test(
    'activation rechecks the session after asynchronous key lookup',
    () async {
      final delayed = _DelayedOwnerKeyStore(store.db, store.key);
      final sync = DoseSyncService(
        owner: 'patient-a',
        client: client,
        openStore: () async => delayed,
        clock: () => now,
      );
      final initialization = sync.initialize(activate: true);
      await delayed.entered.future;
      sync.dispose();
      await store.activate('patient-b');
      delayed.release.complete();
      await initialization;

      expect(await store.isActive('patient-b'), isTrue);
      expect(await store.isActive('patient-a'), isFalse);
    },
  );

  for (final withOfflineWindow in [false, true]) {
    // 함수이름: 전날 영수증의 오늘 캐시 보존 테스트
    // 함수역할:
    // - 전날 복약 전송을 대기시킨 뒤 시계를 하루 옮기고 오늘의 완료 상태를 저장한다.
    // - 늦은 영수증은 대기열에서만 제거되고 오늘 캐시·완료 표시·위젯 날짜는 유지되어야 한다.
    // 매개변수:
    // - 없음; withOfflineWindow(bool)는 다일 오프라인 일정 캐시의 사용 여부이다.
    // 반환값:
    // - Future<void>: 대기열, 캐시, 승인 리비전, 재시도 및 위젯 상태 검증 완료.
    test(
      'a pre-midnight receipt preserves today (window=$withOfflineWindow)',
      () async {
        var current = now;
        const previousDay = '2026-10-21';
        const today = '2026-10-22';
        final medication = MedicationSchedule(
          medicationID: '91',
          medicationName: 'synthetic',
          prescriptionDate: DateTime(2026, 10, 21),
          medicationTime: 14,
          scheduleSlotKeys: const ['morning'],
          slotStatuses: const {'morning': false},
        );
        final requestStarted = Completer<void>();
        final receipt = Completer<http.Response>();
        client.close();
        client = MockClient((_) {
          requestStarted.complete();
          return receipt.future;
        });
        final sync = DoseSyncService(
          owner: 'patient-a',
          client: client,
          openStore: () async => store,
          clock: () => current,
        );
        addTearDown(sync.dispose);
        await sync.cacheSchedules([medication], scheduleDate: previousDay);
        if (withOfflineWindow) {
          await sync.cacheScheduleWindow(
            [medication],
            startDay: previousDay,
            expectedRevision: await sync.cacheRevision(),
          );
        }
        await store.enqueue('patient-a', {
          'operation_id': 'before-midnight',
          'schedule_date': previousDay,
          'slot_key': 'morning',
          'medication_ids': [91],
          'completed': false,
        });
        final draining = sync.drain();
        await requestStarted.future;
        current = current.add(const Duration(days: 1));
        final todayCache = {
          'date': today,
          'schedules': [
            medication
                .copyWith(
                  slotStatuses: {'morning': true},
                  medicationStatus: true,
                )
                .toJson(),
          ],
        };
        await store.saveCache('patient-a', todayCache);
        receipt.complete(
          jsonResponse({
            'operation_id': 'before-midnight',
            'schedule_date': previousDay,
            'data': [medication.toJson()],
          }),
        );
        await draining;

        expect(await store.pending('patient-a'), isEmpty);
        expect(await store.readCache('patient-a'), todayCache);
        expect(sync.hasCache, isTrue);
        expect(sync.schedules.single.isSlotCompleted('morning'), isTrue);
        expect(sync.acceptedRevision, 1);
        expect(sync.hasScheduledRetry, isFalse);
        final widget = await store.updateWidget(
          owner: 'patient-a',
          now: current,
        );
        expect(widget!.view['date'], doseWidgetDay(current));
        expect(widget.view['done'], 1);
      },
    );
  }
}
