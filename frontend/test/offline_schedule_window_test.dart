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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late DoseOutboxStore store;
  late DateTime now;
  late http.Client client;
  late DoseSyncService sync;
  var status = 503;
  final uploads = <Map<String, dynamic>>[];
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
  Future<void> seed(List<MedicationSchedule> courses) async {
    await sync.cacheSchedules(courses, scheduleDate: '2026-10-21');
    await sync.cacheScheduleWindow(
      courses,
      startDay: '2026-10-21',
      expectedRevision: await sync.cacheRevision(),
    );
  }

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
  tearDown(() async {
    sync.dispose();
    client.close();
    await store.db.close();
  });

  // 처방 변경 요청이 실패하면 비워 둔 일정을 되돌려, 오프라인에서 실패한 수정 때문에
  // 오늘과 이후의 기록할 일정이 사라지지 않게 한다.
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

  test('a restore does not overwrite a schedule saved in between', () async {
    await seed([course(1), course(2)]);
    final backup = await sync.suspendSchedule();
    await sync.cacheSchedules([course(2)], scheduleDate: '2026-10-21');
    await sync.restoreSchedule(backup);
    // 그사이 다른 기록이 있으면 되돌리지 않고 이전처럼 비운다.
    expect(sync.hasCache, isFalse);
    expect(await store.readOfflineScheduleWindow('owner'), isNull);
  });

  test('a restore never crosses into another account', () async {
    await seed([course(1)]);
    final backup = await sync.suspendSchedule();
    await store.activate('other');
    await sync.restoreSchedule(backup);
    await store.activate('owner');
    await sync.reload();
    expect(sync.hasCache, isFalse);
  });

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
