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
    expect((value.view['pages'] as List).map((page) => page['slot']), [
      'morning',
      'evening',
    ]);
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

  // 완료 시간대를 조회만 하면 기록하지 않고, 취소 버튼을 눌렀을 때만 해당 기록을 바꾼다.
  test(
    'completed page cancels only its own slot when explicitly tapped',
    () async {
      await cache(
        schedules: [
          medication.copyWith(
            slotStatuses: {'morning': true, 'evening': false},
          ),
        ],
      );
      final value = await state();
      final pages = (value.view['pages'] as List).cast<Map>();
      expect(pages.map((page) => page['slot']), ['morning', 'evening']);
      expect(pages.first['details'], 'private medicine · 복용 완료');
      expect(pages.first['action'], 'cancel');
      expect(pages.first['button'], '복용 취소');
      expect(pages.first['token'], isNotEmpty);
      expect(pages.first['overdue'], isFalse);
      expect(pages.last['details'], 'private medicine · 미복용');
      expect(value.view['slot'], 'evening');
      expect(await store.pending('patient-a'), isEmpty);
      final cancelled = (await tap(DoseWidgetState({'view': pages.first})))!;
      final op = (await store.pending('patient-a')).single;
      expect(op['slot_key'], 'morning');
      expect(op['medication_ids'], [91]);
      expect(op['completed'], false);
      expect(cancelled.view['done'], 0);
      expect((cancelled.view['pages'] as List).first['button'], '복용했어요');
    },
  );

  // 사용자가 넘겨 본 시간대의 토큰은 기본 표시 시간대가 아닌 해당 시간대만 기록한다.
  test(
    'a browsed later page records only its own slot and resists replay',
    () async {
      final value = await state();
      final page = (value.view['pages'] as List).cast<Map>().last;
      final selected = DoseWidgetState({'view': page});
      final result = (await tap(selected))!;
      final op = (await store.pending('patient-a')).single;
      expect(op['slot_key'], 'evening');
      expect(op['medication_ids'], [91]);
      expect(result.view['slot'], 'morning');
      expect(result.view['done'], 1);
      expect((result.view['pages'] as List).last['action'], 'cancel');
      await tap(selected);
      expect(await store.pending('patient-a'), hasLength(1));
    },
  );

  // 시간대 일부를 앱에서 기록한 경우에도 완료·미완료를 구분하고 남은 약만 제출한다.
  test(
    'partly taken page shows both statuses and queues only remaining IDs',
    () async {
      await cache(
        schedules: [
          medication.copyWith(
            slotStatuses: {'morning': true, 'evening': false},
          ),
          medication.copyWith(
            medicationID: '92',
            medicationName: 'another medicine',
          ),
        ],
      );
      final value = await state();
      final page = (value.view['pages'] as List).first as Map;
      expect(
        page['details'],
        'private medicine · 복용 완료\nanother medicine · 미복용',
      );
      await tap(DoseWidgetState({'view': page}));
      expect((await store.pending('patient-a')).single['medication_ids'], [92]);
    },
  );

  // 페이지를 추가해도 약 이름 숨김이 완료된 약에까지 적용되어야 한다.
  test(
    'privacy setting hides both taken and remaining medicine names on every page',
    () async {
      await cache(
        schedules: [
          medication.copyWith(
            slotStatuses: {'morning': true, 'evening': false},
          ),
        ],
      );
      final value = await state(config: {'hide_names': true, 'language': 'en'});
      final pages = (value.view['pages'] as List).cast<Map>();
      expect(pages.first['details'], '1 taken · 0 not taken');
      expect(pages.last['details'], '0 taken · 1 not taken');
      expect(jsonEncode(value.view), isNot(contains('private medicine')));
    },
  );

  // 새로고침은 조회 위치를 보존하지만 날짜·계정이 바뀌면 이전 선택을 폐기한다.
  test(
    'navigation scope is stable for refresh and changes for day or account',
    () async {
      final value = await state();
      expect(
        (await state()).view['navigation_key'],
        value.view['navigation_key'],
      );
      final tomorrow = await state(at: DateTime.utc(2026, 9, 21, 15));
      expect(
        tomorrow.view['navigation_key'],
        isNot(value.view['navigation_key']),
      );
      expect(tomorrow.view['pages'], isEmpty);
      final other = DoseWidgetState.build(
        owner: 'patient-b',
        cache: null,
        operations: [],
        previous: value.data,
        now: now,
      );
      expect(other.view['navigation_key'], isNot(value.view['navigation_key']));
      expect(other.view['pages'], isEmpty);
    },
  );

  // 모든 복약을 기록한 뒤에도 각 시간대의 약과 완료 여부를 다시 볼 수 있다.
  test('all completed slots retain cancellation but no completion tokens', () async {
    await cache(
      schedules: [
        medication.copyWith(slotStatuses: {'morning': true, 'evening': true}),
      ],
    );
    final value = await state();
    final pages = (value.view['pages'] as List).cast<Map>();
    expect(pages, hasLength(2));
    expect(pages.every((page) => page['completed'] == true), isTrue);
    expect(pages.every((page) => page['action'] == 'cancel'), isTrue);
    expect(pages.every((page) => page['token'] != ''), isTrue);
    expect(value.data['takes'], isEmpty);
    expect(value.data['cancels'], hasLength(2));
    expect(value.view['heading'], '오늘 복약 기록 완료');
  });

  // 함수역할: 지정 시간대의 표시 데이터를 실제 버튼 입력과 같은 형태로 감싼다.
  // 매개변수: value 전체 상태, slot 조회 시간대. 반환값: 해당 페이지의 동작·토큰.
  DoseWidgetState page(DoseWidgetState value, String slot) => DoseWidgetState({
    'view': (value.view['pages'] as List).cast<Map>().singleWhere((p) => p['slot'] == slot),
  });

  // 날짜 표시는 기기 UTC 날짜가 아닌 복약 기준일에 맞추고 언어 설정을 따른다.
  test('date label follows the medication timezone and language at midnight', () async {
    expect((await state()).view['date_label'], '9월 21일 (월)');
    final english = await state(config: {'language': 'en'});
    expect(english.view['date_label'], '9/21 (Mon)');
    final tomorrow = await state(at: DateTime.utc(2026, 9, 21, 15), config: {'language': 'ko'});
    expect(tomorrow.view['date'], '2026-09-22');
    expect(tomorrow.view['date_label'], '9월 22일 (화)');
    expect(tomorrow.view['utc_offset_minutes'], doseWidgetUtcOffset);
  });

  // 취소를 중복 수신하거나 재복용 뒤 이전 취소를 수신해도 새 기록에 적용하지 않는다.
  test('duplicate cancellation and stale tokens cannot undo a later completion', () async {
    final before = await state();
    final taken = (await tap(before))!;
    final cancel = page(taken, 'morning');
    expect(page(await state(), 'morning').view['token'], cancel.view['token']);
    final cancelled = (await tap(cancel))!;
    await tap(cancel);
    expect(await store.pending('patient-a'), hasLength(2));
    final retake = page(cancelled, 'morning');
    expect(retake.view['token'], isNot(before.view['token']));
    await tap(retake);
    final replay = (await tap(cancel))!;
    expect(replay.view['done'], 1);
    expect(page(replay, 'morning').view['token'], isNot(cancel.view['token']));
    expect((await store.pending('patient-a')).map((op) => op['completed']), [true, false, true]);
  });

  // 완료/취소 토큰은 서로 바꿔서 사용할 수 없다.
  test('action kind is bound to its token', () async {
    final before = await state();
    await store.updateWidget(now: now, action: 'cancel', actionToken: before.view['token']);
    expect(await store.pending('patient-a'), isEmpty);
    final taken = (await tap(before))!;
    await store.updateWidget(now: now, action: 'take', actionToken: page(taken, 'morning').view['token']);
    expect(await store.pending('patient-a'), hasLength(1));
  });

  // 자정 이후에는 이전 날짜의 완료 기록도 위젯으로 수정하지 않는다.
  test('yesterday cancellation does not write or change the operation date', () async {
    final taken = (await tap(await state()))!;
    await tap(page(taken, 'morning'), at: DateTime.utc(2026, 9, 21, 15));
    expect(await store.pending('patient-a'), hasLength(1));
  });

  // 다른 계정으로 바뀌거나 로그아웃하면 완료된 페이지의 취소 토큰도 거부한다.
  test('cancel token cannot survive an account switch or logout', () async {
    final taken = (await tap(await state()))!;
    final cancel = page(taken, 'morning');
    await store.activate('patient-b');
    expect(await tap(cancel), isNull);
    expect(await store.pending('patient-b'), isEmpty);
    await store.activate(null);
    expect(await tap(cancel), isNull);
    expect(await store.pending('patient-a'), hasLength(1));
  });

  // 새 약이 추가되거나 기존 약이 삭제·미완료로 변경되면 오래된 전체 취소를 거부한다.
  test('cancel checks the complete displayed medication set and prior status', () async {
    final completed = medication.copyWith(slotStatuses: {'morning': true, 'evening': false});
    for (final changed in <List<MedicationSchedule>>[
      [],
      [medication],
      [completed, completed.copyWith(medicationID: '92')],
      [completed, medication.copyWith(medicationID: '92')],
    ]) {
      await cache(schedules: [completed]);
      final cancel = page(await state(), 'morning');
      await cache(schedules: changed);
      await tap(cancel);
      expect(await store.pending('patient-a'), isEmpty);
    }
  });

  // 앱에서 완료한 시간대의 모든 약을 취소하되 다른 시간대의 기록은 유지한다.
  test('server-completed slot cancels all its medicines and retains other slots', () async {
    final completed = medication.copyWith(slotStatuses: {'morning': true, 'evening': true});
    await cache(schedules: [completed, completed.copyWith(medicationID: '92')]);
    final result = (await tap(page(await state(), 'morning')))!;
    expect(result.view['done'], 2);
    expect(page(result, 'evening').view['completed'], isTrue);
    final op = (await store.pending('patient-a')).single;
    expect(op['medication_ids'], [91, 92]);
    expect(op['completed'], false);
  });

  // 서버가 거부한 기록이 있으면 위젯에서 추가 취소하지 않고 앱 확인으로 유도한다.
  test('blocked sync rejects cancellation and removes action tokens', () async {
    final taken = (await tap(await state()))!;
    final op = (await store.claim('patient-a', 'test-lease', now.millisecondsSinceEpoch))!;
    await store.finish('patient-a', op['operation_id'], 'test-lease', blocked: true);
    final blocked = (await tap(page(taken, 'morning')))!;
    expect(await store.pending('patient-a'), hasLength(1));
    expect(page(blocked, 'morning').view['action'], 'open');
    expect(blocked.data['cancels'], isEmpty);
  });

  // 오프라인 복용→취소→재복용은 앱 재시작 후에도 같은 순서로 한 번씩 전송한다.
  test('offline cancellation survives restart and uploads in order', () async {
    final taken = (await tap(await state()))!;
    final cancelled = (await tap(page(taken, 'morning')))!;
    expect(cancelled.view['status'], contains('전송 대기 2건'));
    await tap(page(cancelled, 'morning'));
    await db.close();
    db = await databaseFactoryFfi.openDatabase('${directory.path}/doses.db');
    store = DoseOutboxStore(db, key);
    expect((await state()).view['done'], 1);
    var online = false;
    final uploaded = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (!online) throw const SocketException('offline');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      uploaded.add(body);
      return http.Response(jsonEncode({
        'operation_id': body['operation_id'],
        'schedule_date': '2026-09-21',
        'data': [medication.copyWith(slotStatuses: {'morning': body['completed'], 'evening': false}).toJson()],
      }), 200);
    });
    final sync = DoseSyncService(owner: 'patient-a', client: client, openStore: () async => store, clock: () => now);
    try {
      await sync.drain();
      expect(sync.pendingCount, 3);
      online = true;
      await sync.drain();
      expect(uploaded.map((op) => op['completed']), [true, false, true]);
      expect(uploaded.every((op) => op['slot_key'] == 'morning'), isTrue);
      expect(uploaded.map((op) => op['operation_id']).toSet(), hasLength(3));
      expect(sync.pendingCount, 0);
      expect((await state()).view['done'], 1);
    } finally {
      sync.dispose();
      client.close();
    }
  });
}
