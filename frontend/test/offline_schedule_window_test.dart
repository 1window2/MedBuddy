// 파일명: offline_schedule_window_test.dart
// 역할: 오프라인 일정 범위의 보존·날짜 이동·계정 격리와 실패한 변경의 복원을 검증한다.

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/offline_schedule_window.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 함수이름: main
// 함수역할:
// - 실제 복약 저장소에서 일정 중단·복원, 날짜별 캐시와 계정 교체 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late DoseOutboxStore store;
  late DateTime now;
  late http.Client client;
  late DoseSyncService sync;
  var status = 503;
  final uploads = <Map<String, dynamic>>[];
  // 함수이름: course
  // 함수역할:
  // - 고정 시작일과 버전으로 아침 정기복용 과정을 만들며 주기·기간·중단일·완료 상태를 바꾼다.
  // 매개변수:
  // - id(int): 약 식별자.
  // - cycle(int): 주기 일수; 기본 1.
  // - days(int): 처방 기간; 기본 30.
  // - stopped(DateTime?): 복용 중단일.
  // - completed(bool): 아침 완료 여부; 기본 false.
  // 반환값:
  // - MedicationSchedule: 2026-10-21 기준 revision 3 일정.
  MedicationSchedule course(
    int id, {
    int cycle = 1,
    int days = 30,
    DateTime? stopped,
    bool completed = false,
  }) => MedicationSchedule(
    medicationID: '$id',
    medicationName: 'synthetic-$id',
    dosage: '1',
    prescriptionDate: DateTime(2026, 10, 21),
    medicationTime: days,
    scheduleSlotKeys: ['morning'],
    slotStatuses: {'morning': completed},
    doseCycleDays: cycle,
    doseCycleOffsets: [0],
    doseCycleAnchor: DateTime(2026, 10, 21),
    regimenRevision: 3,
    stoppedOn: stopped,
  );
  // 함수이름: seed
  // 함수역할:
  // - 기준일의 일일 캐시를 저장한 뒤 최신 버전을 사용해 같은 과정의 기간 캐시를 저장한다.
  // 매개변수:
  // - courses(List<MedicationSchedule>): 초기 캐시에 넣을 과정.
  // 반환값:
  // - Future<void>: 두 캐시의 초기화 완료; 저장 오류는 전달된다.
  Future<void> seed(List<MedicationSchedule> courses) async {
    await sync.cacheSchedules(courses, scheduleDate: '2026-10-21');
    await sync.cacheScheduleWindow(
      courses,
      startDay: '2026-10-21',
      expectedRevision: await sync.cacheRevision(),
    );
  }

  // 함수이름: setUp
  // 함수역할:
  // - 메모리 암호화 저장소·고정 시계·응답 상태를 초기화하고 전송 본문을 기록하는 동기화 서비스를 시작한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 독립된 활성 owner 세션 준비 완료.
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
    await store.activate('owner');
    now = DateTime.utc(2026, 10, 21, 3);
    uploads.clear();
    status = 503;
    client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      uploads.add(body);
      return http.Response(
        status == 200
            ? jsonEncode({
                'operation_id': body['operation_id'],
                'schedule_date': doseScheduleDay(now),
                'data': [],
              })
            : 'offline or rejected',
        status,
      );
    });
    sync = DoseSyncService(
      owner: 'owner',
      client: client,
      openStore: () async => store,
      clock: () => now,
    );
    await sync.initialize();
  });
  // 함수이름: tearDown
  // 함수역할:
  // - 동기화 서비스와 HTTP 클라이언트를 종료하고 메모리 DB를 닫는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 리소스 정리 완료.
  tearDown(() async {
    sync.dispose();
    client.close();
    await store.db.close();
  });

  // 처방 변경 요청이 실패하면 비워 둔 일정을 되돌려, 오프라인에서 실패한 수정 때문에
  // 오늘과 이후의 기록할 일정이 사라지지 않게 한다.
  // Function Name: restore suspended schedules after failure
  // Description:
  // - Suspends daily and future caches, restores both medications, and verifies the next day still projects them offline.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('a failed medication change restores the suspended schedule and window', () async {
    await seed([course(1), course(2)]);
    final backup = await sync.suspendSchedule();
    expect(sync.hasCache, isFalse);
    expect(await store.readOfflineScheduleWindow('owner'), isNull);
    await sync.restoreSchedule(backup);
    expect(sync.hasCache, isTrue);
    expect(sync.schedules.map((s) => s.medicationID), ['1', '2']);
    // 되돌린 14일 일정으로 다음 날도 오프라인 기록이 가능하다.
    now = DateTime.utc(2026, 10, 22, 3);
    await sync.reload();
    expect(sync.hasCache, isTrue);
    expect(sync.schedules.map((s) => s.medicationID), ['1', '2']);
  });

  // Function Name: restore refuses an intervening cache write
  // Description:
  // - Writes a newer daily cache after suspension and verifies restoration leaves both daily and future support unavailable instead of restoring stale data.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('a restore does not overwrite a schedule saved in between', () async {
    await seed([course(1), course(2)]);
    final backup = await sync.suspendSchedule();
    await sync.cacheSchedules([course(2)], scheduleDate: '2026-10-21');
    await sync.restoreSchedule(backup);
    // 그사이 다른 기록이 있으면 되돌리지 않고 이전처럼 비운다.
    expect(sync.hasCache, isFalse);
    expect(await store.readOfflineScheduleWindow('owner'), isNull);
  });

  // Function Name: restore preserves account boundaries
  // Description:
  // - Attempts restoration while another account is active and verifies the original account has no restored cache when reactivated.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('a restore never crosses into another account', () async {
    await seed([course(1)]);
    final backup = await sync.suspendSchedule();
    await store.activate('other');
    await sync.restoreSchedule(backup);
    await store.activate('owner');
    await sync.reload();
    expect(sync.hasCache, isFalse);
  });

  // 함수이름: 다음날 오프라인 기록
  // 함수역할:
  // - 어제 완료·격일 휴약·중단·기간 만료를 오늘 일정에 맞게 필터링하고 새 기록에 오늘 날짜와 처방 버전을 담는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'next day offline clears yesterday checks and enqueues the new day with regimen versions',
    () async {
      await seed([
        course(1, completed: true),
        course(2, cycle: 2),
        course(3, stopped: DateTime(2026, 10, 22)),
        course(4, days: 1),
      ]);
      now = DateTime.utc(2026, 10, 22, 3);
      await sync.reload();
      expect(sync.hasCache, isTrue);
      expect(sync.schedules.map((s) => s.medicationID), ['1']);
      expect(sync.schedules.single.isSlotCompleted('morning'), isFalse);
      expect(
        await sync.record(
          medicationIds: [1],
          slotKey: 'morning',
          completed: true,
        ),
        isTrue,
      );
      await sync.drain();
      final pending = await store.pending('owner');
      expect(pending.single['schedule_date'], '2026-10-22');
      expect(pending.single['regimen_revisions'], {'1': 3});
      expect(sync.schedules.single.isSlotCompleted('morning'), isTrue);
    },
  );

  // 함수이름: 재시작 후 기간 일정 복원
  // 함수역할:
  // - 새 저장소 인스턴스가 해당 날짜의 일정만 복원하고 어제 완료를 투영하지 않으며 기존 대기 날짜와 암호화된 메타데이터를 보존하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'restart projects the persisted window and keeps only that day queued checks',
    () async {
      await seed([course(1), course(2, cycle: 2)]);
      await sync.record(
        medicationIds: [1],
        slotKey: 'morning',
        completed: true,
      );
      await sync.drain();
      sync.dispose();
      now = DateTime.utc(2026, 10, 23, 3);
      sync = DoseSyncService(
        owner: 'owner',
        client: client,
        openStore: () async => DoseOutboxStore(store.db, store.key),
        clock: () => now,
      );
      await sync.initialize();
      expect(sync.schedules.map((s) => s.medicationID), ['1', '2']);
      expect(
        sync.schedules.every((s) => !s.isSlotCompleted('morning')),
        isTrue,
      );
      expect(
        (await store.pending('owner')).single['schedule_date'],
        '2026-10-21',
      );
      final raw = await store.db.query('metadata');
      expect(jsonEncode(raw), isNot(contains('synthetic-1')));
    },
  );

  // 함수이름: 서버 조회 실패 후 화면 모델
  // 함수역할:
  // - 오늘 서버 조회가 503이면 오프라인 기간으로 오늘 약을 표시하고 화면 모델의 복용 입력을 오늘 날짜로 저장하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'app schedule view model displays and checks the projected day when today GET fails',
    () async {
      SharedPreferences.setMockInitialValues({});
      await seed([course(1), course(2, cycle: 2)]);
      now = DateTime.utc(2026, 10, 22, 3);
      final readClient = MockClient(
        (request) async => http.Response('offline', 503),
      );
      final model = MedBuddyViewModel(
        patientHash: 'owner',
        apiClient: readClient,
      );
      model.doseSync = sync;
      await model.fetchTodayMedicationSchedule();
      expect(model.todayMedicationScheduleList.map((s) => s.medicationID), [
        '1',
      ]);
      expect(
        await model.requestMedicationDoseStatusUpdate(
          'morning',
          model.todayMedicationScheduleList.single,
          true,
        ),
        isTrue,
      );
      await sync.drain();
      expect(
        (await store.pending('owner')).single['schedule_date'],
        '2026-10-22',
      );
      model.doseSync = null;
      model.dispose();
      readClient.close();
    },
  );

  // 함수이름: 위젯 날짜 이동과 동작 토큰
  // 함수역할:
  // - 날짜 변경 후 어제 토큰은 기록하지 않고 오늘 위젯 토큰만 오늘 날짜와 처방 버전으로 기록하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'widget rollover uses the same projection and rejects yesterday action token',
    () async {
      await seed([course(1, completed: false), course(2, cycle: 2)]);
      final yesterday = (await store.updateWidget(owner: 'owner', now: now))!;
      final oldToken =
          ((yesterday.data['takes'] as Map).values.first as Map)['token']
              as String;
      now = DateTime.utc(2026, 10, 22, 3);
      await DoseSyncService.prepareOfflineCache(store, now: now);
      var state = (await store.updateWidget(
        now: now,
        action: 'take',
        actionToken: oldToken,
      ))!;
      expect(await store.pending('owner'), isEmpty);
      final take = (state.data['takes'] as Map).values.first as Map;
      expect(take['date'], '2026-10-22');
      expect(take['ids'], [1]);
      state = (await store.updateWidget(
        now: now,
        action: 'take',
        actionToken: take['token'] as String,
      ))!;
      final op = (await store.pending('owner')).single;
      expect(op['schedule_date'], '2026-10-22');
      expect(op['regimen_revisions'], {'1': 3});
    },
  );

  // 함수이름: 기간과 계정 경계의 차단
  // 함수역할:
  // - 14일 범위 밖·시계 역행·다른 활성 계정에서는 캐시를 제공하지 않으며 범위 밖 기록도 거부하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'bounded horizon, inactive account and backwards clock fail closed',
    () async {
      await seed([course(1)]);
      now = DateTime.utc(2026, 11, 4, 3);
      await sync.reload();
      expect(sync.hasCache, isFalse);
      expect(
        await sync.record(
          medicationIds: [1],
          slotKey: 'morning',
          completed: true,
        ),
        isFalse,
      );
      now = DateTime.utc(2026, 10, 20, 3);
      await sync.reload();
      expect(sync.hasCache, isFalse);
      await store.activate('someone-else');
      now = DateTime.utc(2026, 10, 22, 3);
      await sync.reload();
      expect(sync.hasCache, isFalse);
      expect(await store.readOfflineScheduleWindow('owner'), isNull);
    },
  );

  // 함수이름: 주기와 명시 날짜의 일정 투영
  // 함수역할:
  // - 주간·30일 과정과 날짜 없는 약에서 해당 날짜의 주기에 맞는 약만 반환하고 범위 밖 요청은 null인지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대값과 다르면 테스트가 실패한다.
  test(
    'weekly and monthly rhythm follow server cycles and explicit dates only',
    () {
      final window = {
        'start': '2026-10-21',
        'end': '2026-11-03',
        'courses': [
          course(1, cycle: 7).toJson(),
          course(2, cycle: 30).toJson(),
          const MedicationSchedule(
            medicationID: '3',
            medicationName: 'no dates',
          ).toJson(),
        ],
      };
      expect(OfflineScheduleWindow.project(window, '2026-10-22'), isEmpty);
      expect(
        OfflineScheduleWindow.project(
          window,
          '2026-10-28',
        )!.map((s) => s.medicationID),
        ['1'],
      );
      expect(OfflineScheduleWindow.project(window, '2026-11-04'), isNull);
    },
  );

  // 함수이름: 처방 무효화 후 오래된 기간 응답
  // 함수역할:
  // - 무효화 이전 버전으로 기간 캐시를 다시 저장하려 해도 오늘·기간 캐시가 비어 있고 다음날에도 복구되지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'regimen invalidation removes daily and future cache and refuses stale window completion',
    () async {
      await seed([course(1)]);
      final oldRevision = await sync.cacheRevision();
      await sync.invalidateSchedule();
      await sync.cacheScheduleWindow(
        [course(1)],
        startDay: '2026-10-21',
        expectedRevision: oldRevision,
      );
      expect(await store.readCache('owner'), isNull);
      expect(await store.readOfflineScheduleWindow('owner'), isNull);
      now = DateTime.utc(2026, 10, 22, 3);
      await sync.reload();
      expect(sync.hasCache, isFalse);
    },
  );

  // 함수이름: 오래된 기간 갱신과 최신 캐시
  // 함수역할:
  // - 새 약으로 일일·기간 캐시를 바꾼 뒤 이전 버전의 응답이 도착해도 다음 날짜에는 새 약만 투영하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('late refresh cannot overwrite a newer server cache', () async {
    await seed([course(1)]);
    final oldRevision = await sync.cacheRevision();
    await sync.cacheSchedules([course(2)], scheduleDate: '2026-10-21');
    await sync.cacheScheduleWindow(
      [course(2)],
      startDay: '2026-10-21',
      expectedRevision: await sync.cacheRevision(),
    );
    await sync.cacheScheduleWindow(
      [course(1)],
      startDay: '2026-10-21',
      expectedRevision: oldRevision,
    );
    now = DateTime.utc(2026, 10, 23, 3);
    await sync.reload();
    expect(sync.schedules.map((s) => s.medicationID), ['2']);
  });

  // 함수이름: 오늘 빈 일정으로 기간 무효화
  // 함수역할:
  // - 오늘 조회가 빈 목록으로 성공하면 이전 기간을 제거하여 다음날 오래된 약을 다시 표시하지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'successful today refresh invalidates yesterday regimen window even if window request fails',
    () async {
      await seed([course(1)]);
      await sync.cacheSchedules([], scheduleDate: '2026-10-21');
      expect(await store.readOfflineScheduleWindow('owner'), isNull);
      now = DateTime.utc(2026, 10, 22, 3);
      await sync.reload();
      expect(sync.hasCache, isFalse);
      expect(sync.schedules, isEmpty);
    },
  );

  for (final rejected in [404, 409, 422]) {
    // 함수이름: 서버 거부 작업 보존
    // 함수역할:
    // - 404·409·422 응답은 작업을 차단 상태로 표시하되 최초 operation_id의 오프라인 기록을 버리지 않는지 확인한다.
    // 매개변수:
    // - 없음.
    // 반환값:
    // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
    test(
      'server conflict $rejected blocks an offline record without discarding it',
      () async {
        await seed([course(1)]);
        now = DateTime.utc(2026, 10, 22, 3);
        await sync.record(
          medicationIds: [1],
          slotKey: 'morning',
          completed: true,
        );
        await sync.drain();
        final id = (await store.pending('owner')).single['operation_id'];
        status = rejected;
        await sync.drain();
        expect(sync.hasBlocked, isTrue);
        expect((await store.pending('owner')).single['operation_id'], id);
      },
    );
  }

  // 기간 일정을 받는 사이 복용 전송이 확인되면 저장 버전이 올라 그 기간이 거부된다. 다시 받아 두지
  // 않으면 오프라인으로 돌아온 사용자가 다음 날 기록할 일정이 없다.
  // Function Name: dose upload racing a window download
  // Description:
  // - Acknowledges an upload while the period request is pending, then verifies a second read persists a usable window for the next day.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('a dose upload during the window download still leaves a window', () async {
    final windowRead = Completer<List<MedicationSchedule>>();
    var windowReads = 0;
    final windowed = DoseSyncService(
      owner: 'owner',
      client: client,
      openStore: () async => store,
      clock: () => now,
      loadScheduleWindow: () {
        windowReads++;
        return windowRead.future;
      },
    );
    addTearDown(windowed.dispose);
    await windowed.initialize();
    await windowed.cacheSchedules([course(1)], scheduleDate: '2026-10-21');
    status = 200;
    expect(
      await windowed.record(
        medicationIds: [1],
        slotKey: 'morning',
        completed: true,
      ),
      isTrue,
    );
    await windowed.drain();
    expect(await store.pending('owner'), isEmpty);
    windowRead.complete([course(1)]);
    await pumpEventQueue();
    expect(windowReads, 2);
    expect(await store.readOfflineScheduleWindow('owner'), isNotNull);
    now = DateTime.utc(2026, 10, 22, 3);
    await windowed.reload();
    expect(windowed.hasCache, isTrue);
    expect(windowed.schedules.map((s) => s.medicationID), ['1']);
  });

  // 함수이름: 서버 기간 날짜 검증
  // 함수역할:
  // - 서버가 요청 시작일과 다른 기간을 반환하면 오프라인 기간 조회가 StateError로 실패하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'server window dates must match before persisting offline support',
    () async {
      final control = CheckSchedule(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'success': true,
              'window_start': '2026-10-20',
              'window_end': '2026-11-02',
              'data': [],
            }),
            200,
          ),
        ),
      );
      await expectLater(
        control.requestOfflineScheduleWindow(expectedStartDay: '2026-10-21'),
        throwsA(isA<StateError>()),
      );
      control.dispose();
    },
  );
}
