// 파일명: as_needed_pending_store_test.dart
// 역할: 필요시 복약 대기 기록의 암호화·재시작·계정 격리와 실패 후 동일 요청 재시도를 검증한다.

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

// 함수이름: main
// 함수역할:
// - 실제 SQLite 저장소와 제어 대역으로 전송 전 영속화 및 전송 후 확인 실패를 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 저장소 준비·정리와 대기 기록 회귀 사례를 등록한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late DoseOutboxStore store;
  late AsNeededPendingStore pending;
  String? key;
  final now = DateTime.utc(2026, 10, 22, 3);
  const owner = 'test-patient';

  // 함수이름: open
  // 함수역할:
  // - 현재 테스트 폴더의 DB를 열고 메모리에 보관한 키로 지정 계정을 활성화한다.
  // - 키가 null이면 새 키를 저장하여 재시작 또는 키 유실 상황을 재현한다.
  // 매개변수:
  // - 없음; directory, key, owner를 외부 테스트 상태에서 읽는다.
  // 반환값:
  // - Future<void>: store와 pending 초기화 완료; 파일·DB 오류는 호출자에게 전달한다.
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

  // 함수이름: change
  // 함수역할:
  // - 고정 날짜의 필요시 복용을 미기록에서 복용 완료로 바꾸는 새 작업을 만든다.
  // 매개변수:
  // - id(int): 가상 약 식별자; 기본값은 1이다.
  // 반환값:
  // - MedicationHistoryChange: 고유 시간대·작업 ID와 now보다 2분 앞선 실제 복용 시각을 가진 변경.
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

  // 함수이름: control
  // 함수역할:
  // - 같은 계정의 고정 세션에 전송 대역과 대기 저장소를 연결한다.
  // 매개변수:
  // - client(http.Client): 응답 손실·승인 등을 재현하는 HTTP 대역.
  // - storage(AsNeededPendingStore?): 생략하면 현재 실제 암호화 저장소를 사용한다.
  // - clock(DateTime?): 생략하면 고정 now, 지정하면 재시작 후 날짜를 사용한다.
  // 반환값:
  // - MedicationHistoryControl: 호출자가 dispose해야 하는 이력 제어기.
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

  // 함수이름: setUp 콜백
  // 함수역할:
  // - 각 테스트용 디렉터리와 새 키를 준비하고 활성 계정의 저장소를 연다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 격리된 실제 저장소 준비 완료.
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('medbuddy-prn-test-');
    key = null;
    await open();
  });
  // 함수이름: tearDown 콜백
  // 함수역할:
  // - 현재 DB 연결을 닫은 뒤 테스트 디렉터리의 저장 파일을 제거한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 저장소 정리 완료.
  tearDown(() async {
    await store.db.close();
    await directory.delete(recursive: true);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 암호화 메타데이터에 약 이름·작업 ID·날짜 평문이 없고 DB를 다시 열어도 동일 작업과 실제 복용 시각이 복원되는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 서버 응답을 잃은 뒤 다음 날 재시작해도 같은 요청 본문·이벤트 경로로 재전송하고 승인 후 대기 기록을 제거하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 두 작업 중 하나만 승인 삭제한 뒤 DB를 다시 열면 미승인 작업 하나만 복원되는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 이미 영속화된 미해결 요청이 있으면 새 약의 등록 시도가 기존 작업 ID를 바꾸지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('another stage cannot replace the durable unresolved request', () async {
    final original = change();
    await pending.stage(owner, [original]);
    final result = await pending.stage(owner, [change(id: 2)]);
    expect(result.single.operationId, original.operationId);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 다른 계정 활성화 중 이전 계정의 읽기·덮어쓰기·삭제를 모두 거부하고 다시 활성화하면 원래 요청을 복원하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 계정 삭제 후 history-pending 메타데이터가 모두 없어져 요청 본문과 복구 개수가 함께 지워지는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 대기 저장소가 등록에 실패하면 StateError를 전달하고 HTTP 요청은 한 번도 보내지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 두 작업 저장 뒤 키를 잃고 다시 열면 유실 개수 2만 보고하고 대기 요청과 평문 건강정보는 남기지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 서버 성공 뒤 로컬 삭제가 실패해도 같은 작업 ID가 남고 삭제 복구 후 재시도하면 대기열이 비워지는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 비활성 계정의 복원이 실패하면 제어기 오류에 반영되고 원래 계정을 활성화한 뒤 복원을 다시 완료할 수 있는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
