// Widget regressions against real SQLite/crypto, without real dose records.
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

void main() {
  sqfliteFfiInit();
  late Database db;
  late DoseOutboxStore store;
  late SecretKey key;
  late Directory directory;
  final now = DateTime.utc(2026, 9, 21, 1);
  const medication = MedicationSchedule(
    medicationID: '91',
    medicationName: 'private medicine',
    scheduleSlotKeys: ['morning', 'evening'],
    slotStatuses: {'morning': false, 'evening': false},
  );
  Future<void> cache({
    String date = '2026-09-21',
    List<MedicationSchedule> schedules = const [medication],
  }) async {
    await store.saveCache('patient-a', {
      'date': date,
      'schedules': schedules.map((s) => s.toJson()).toList(),
    });
  }

  Future<DoseWidgetState> state({
    DateTime? at,
    Map<String, dynamic>? config,
  }) async => (await store.updateWidget(
    owner: 'patient-a',
    now: at ?? now,
    configuration: config,
  ))!;
  Future<DoseWidgetState?> tap(DoseWidgetState value, {DateTime? at}) =>
      store.updateWidget(
        now: at ?? now,
        action: value.view['action'] as String,
        actionToken: value.view['token'] as String,
      );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('medbuddy-widget-');
    db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/doses.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
      ),
    );
    key = await AesGcm.with256bits().newSecretKey();
    store = DoseOutboxStore(db, key);
    await store.activate('patient-a');
    await cache();
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });
  test('recording immediately shows the next remaining slot', () async {
    final before = await state();
    expect(before.view['heading'], '아침 08:00');
    expect(before.view['done'], 0);
    expect(before.view['total'], 2);
    final after = (await tap(before))!;
    final op = (await store.pending('patient-a')).single;
    expect(op['slot_key'], 'morning');
    expect(op['medication_ids'], [91]);
    expect(op['schedule_date'], '2026-09-21');
    expect(op['completed'], true);
    expect(after.view['done'], 1);
    expect(after.view['heading'], '저녁 18:00');
    expect(after.view['action'], 'take');
    expect(after.view['button'], '복용했어요');
    expect(after.view['token'], isNot(before.view['token']));
    expect(after.view['status'], contains('전송 대기'));
    expect(op['operation_id'].toString().length, lessThanOrEqualTo(64));
  });
  test('duplicate taps and different widgets share one operation', () async {
    final before = await state();
    expect((await state()).view['token'], before.view['token']);
    await Future.wait([tap(before), tap(before), tap(before)]);
    expect(await store.pending('patient-a'), hasLength(1));
  });
  // 아침부터 마지막 시간대까지 별도 확인 없이 넘어가며 마지막에는 기록 버튼을 없앤다.
  test('morning lunch evening and bedtime advance in order', () async {
    await cache(
      schedules: [
        medication.copyWith(
          scheduleSlotKeys: ['morning', 'lunch', 'evening', 'bedtime'],
          slotStatuses: {
            'morning': false,
            'lunch': false,
            'evening': false,
            'bedtime': false,
          },
        ),
      ],
    );
    var current = await state();
    for (final slot in ['morning', 'lunch', 'evening', 'bedtime']) {
      expect(current.view['slot'], slot);
      expect(current.view['action'], 'take');
      current = (await tap(current))!;
      expect(current.data, isNot(contains('undo')));
    }
    expect(current.view['done'], 4);
    expect(current.view['heading'], '오늘 복약 기록 완료');
    expect(current.view['action'], 'open');
    expect(current.view['button'], '일정 열기');
    await tap(current);
    final ops = await store.pending('patient-a');
    expect(ops.map((op) => op['slot_key']), [
      'morning',
      'lunch',
      'evening',
      'bedtime',
    ]);
    expect(ops.every((op) => op['completed'] == true), isTrue);
  });
  // 다른 곳에서 완료된 약은 제외하고 표시된 시간대의 남은 약만 기록한다.
  test('only incomplete medicines in the selected slot are queued', () async {
    await cache(
      schedules: [
        medication.copyWith(slotStatuses: {'morning': true, 'evening': true}),
        medication.copyWith(medicationID: '92'),
      ],
    );
    final taken = (await tap(await state()))!;
    final ops = await store.pending('patient-a');
    expect(ops.single['medication_ids'], [92]);
    expect(ops.single['slot_key'], 'morning');
    expect(taken.view['done'], 3);
    expect(taken.view['heading'], '저녁 18:00');
  });
  // 직전 화면의 지연된 클릭이 새로 표시된 다음 시간대까지 완료 처리하면 안 된다.
  test('replayed previous slot never completes the next slot', () async {
    final morning = await state();
    final evening = (await tap(morning))!;
    final replayed = (await tap(morning))!;
    expect(replayed.view['token'], evening.view['token']);
    expect(replayed.view['done'], 1);
    expect(await store.pending('patient-a'), hasLength(1));
  });
  // 앱 업데이트 전의 되돌리기 표시와 버튼 토큰은 새 기록을 만들지 않는다.
  test(
    'legacy undo state is ignored and stale undo actions cannot write',
    () async {
      final morning = await state();
      final evening = (await tap(morning))!;
      final legacy = DoseWidgetState.build(
        owner: 'patient-a',
        cache: await store.readCache('patient-a'),
        operations: await store.pending('patient-a'),
        previous: {
          ...evening.data,
          'undo': {
            ...(morning.data['take'] as Map),
            'token': '${morning.view['token']}_undo',
            'expires': now
                .add(const Duration(minutes: 1))
                .millisecondsSinceEpoch,
          },
        },
        now: now,
      );
      expect(legacy.view['heading'], '저녁 18:00');
      expect(legacy.view['action'], 'take');
      expect(legacy.data, isNot(contains('undo')));
      final rejected = (await store.updateWidget(
        now: now,
        action: 'undo',
        actionToken: '${morning.view['token']}_undo',
      ))!;
      expect(rejected.view['done'], 1);
      expect(await store.pending('patient-a'), hasLength(1));
    },
  );
  test('old account buttons cannot change another account', () async {
    final before = await state();
    await store.activate('patient-b');
    expect(await tap(before), isNull);
    expect(await store.pending('patient-a'), isEmpty);
    expect(await store.pending('patient-b'), isEmpty);
    expect(await store.updateWidget(owner: 'patient-a', now: now), isNull);
  });
  test('logout rejects cached buttons', () async {
    final before = await state();
    await store.activate(null);
    expect(await tap(before), isNull);
    expect(await store.pending('patient-a'), isEmpty);
  });
  test(
    'midnight rejects yesterday buttons without reassigning the date',
    () async {
      final before = await state();
      final after = (await tap(before, at: DateTime.utc(2026, 9, 21, 15)))!;
      expect(await store.pending('patient-a'), isEmpty);
      expect(after.view['action'], 'open');
      expect(after.view['heading'], contains('불러와'));
    },
  );
  test(
    'changed schedule never substitutes medicines into an old tap',
    () async {
      final before = await state();
      await cache(schedules: const []);
      await tap(before);
      expect(await store.pending('patient-a'), isEmpty);
      expect((await state()).view['total'], 0);
    },
  );
  test('already completed dose is not overwritten', () async {
    final before = await state();
    await cache(
      schedules: [
        medication.copyWith(slotStatuses: {'morning': true, 'evening': false}),
      ],
    );
    await tap(before);
    expect(await store.pending('patient-a'), isEmpty);
  });
  test('encrypted action state survives process restart', () async {
    final before = await state();
    final raw = await db.query('metadata');
    expect(raw.toString(), isNot(contains('private medicine')));
    expect(raw.toString(), isNot(contains(before.view['token'])));
    await db.close();
    db = await databaseFactoryFfi.openDatabase('${directory.path}/doses.db');
    store = DoseOutboxStore(db, key);
    await tap(before);
    expect(await store.pending('patient-a'), hasLength(1));
  });
  test('privacy hides names in native display', () async {
    final value = await state(config: {'hide_names': true, 'language': 'en'});
    expect(value.view['details'], '1 scheduled medicines');
    expect(jsonEncode(value.view), isNot(contains('private medicine')));
    expect(value.view['button'], 'Taken');
  });
  test('custom reminder times determine remaining slot order', () async {
    final value = await state(
      config: {
        'alarms': {'morning': '10:30', 'evening': '09:00'},
      },
    );
    expect(value.view['heading'], '저녁 09:00');
    expect(value.view['overdue'], isTrue);
    expect((await tap(value))!.view['heading'], '아침 10:30');
  });
  // 모든 시간이 지난 경우에도 마지막 시간대로 건너뛰지 않고 남은 일정 순서를 지킨다.
  test('overdue slots retain their order and warning', () async {
    final late = DateTime.utc(2026, 9, 21, 14);
    final morning = await state(at: late);
    expect(morning.view['heading'], '아침 08:00');
    expect(morning.view['overdue'], isTrue);
    final evening = (await tap(morning, at: late))!;
    expect(evening.view['heading'], '저녁 18:00');
    expect(evening.view['overdue'], isTrue);
  });
  test('empty and completed schedules have no completion action', () async {
    await cache(schedules: const []);
    expect((await state()).view['action'], 'open');
    await cache(
      schedules: [
        medication.copyWith(slotStatuses: {'morning': true, 'evening': true}),
      ],
    );
    final complete = await state();
    expect(complete.view['done'], 2);
    expect(complete.view['action'], 'open');
  });
  test('offline slots advance and upload in order without undo', () async {
    await tap((await tap(await state()))!);
    var online = false;
    final uploaded = <Map<String, dynamic>>[];
    final confirmed = {'morning': false, 'evening': false};
    final client = MockClient((request) async {
      if (!online) throw const SocketException('offline');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      uploaded.add(body);
      expect(request.url.path, endsWith('/schedule/completion-operations'));
      confirmed[body['slot_key'] as String] = body['completed'] as bool;
      return http.Response(
        jsonEncode({
          'operation_id': body['operation_id'],
          'schedule_date': '2026-09-21',
          'data': [
            medication.copyWith(slotStatuses: {...confirmed}).toJson(),
          ],
        }),
        200,
      );
    });
    final sync = DoseSyncService(
      owner: 'patient-a',
      client: client,
      openStore: () async => store,
      clock: () => now,
    );
    try {
      await sync.drain();
      expect(sync.pendingCount, 2);
      expect((await state()).view['heading'], '오늘 복약 기록 완료');
      online = true;
      await sync.drain();
      expect(uploaded.map((o) => o['completed']), [true, true]);
      expect(uploaded.map((o) => o['slot_key']), ['morning', 'evening']);
      expect(sync.pendingCount, 0);
      expect((await state()).view['done'], 2);
    } finally {
      sync.dispose();
      client.close();
    }
  });
}
