// 파일명: dose_home_widget_test.dart
// 역할: 위젯 복용·취소·시간대 탐색과 환자 읽기 전용 상태의 저장 안전성을 검증한다.
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

// 함수이름: main
// 함수역할: 실제 암호화 저장소에서 위젯의 시간대 탐색·복용·취소와 환자 읽기 전용 표시를 검증한다.
// 매개변수: 없음. 반환값: 없음.
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
  // 함수이름: cache
  // 함수역할: 지정 날짜와 일정으로 본인 위젯 캐시를 저장해 일정 변경과 만료를 재현한다.
  // 매개변수: date: 복약 기준일, schedules: 표시할 일정. 반환값: 캐시 저장 완료 Future.
  Future<void> cache({
    String date = '2026-09-21',
    List<MedicationSchedule> schedules = const [medication],
  }) async {
    await store.saveCache('patient-a', {
      'date': date,
      'schedules': schedules.map((s) => s.toJson()).toList(),
    });
  }

  // 함수이름: state
  // 함수역할: 시각과 설정을 적용해 현재 계정의 위젯 상태를 갱신한다.
  // 매개변수: at: 검사 시각, config: 위젯 표시 설정. 반환값: 갱신된 위젯 상태 Future.
  Future<DoseWidgetState> state({
    DateTime? at,
    Map<String, dynamic>? config,
  }) async => (await store.updateWidget(
    owner: 'patient-a',
    now: at ?? now,
    configuration: config,
  ))!;
  // 함수이름: tap
  // 함수역할: 화면에 발급된 동작·토큰을 저장소에 전달해 실제 위젯 버튼 입력을 재현한다.
  // 매개변수: value: 누를 화면 상태, at: 입력 시각. 반환값: 갱신 상태 Future; 비활성 계정이면 null.
  Future<DoseWidgetState?> tap(DoseWidgetState value, {DateTime? at}) =>
      store.updateWidget(
        now: at ?? now,
        action: value.view['action'] as String,
        actionToken: value.view['token'] as String,
      );
  // 함수이름: setUp
  // 함수역할: 각 테스트에 별도 임시 DB와 암호화 키를 만들고 테스트 계정의 기본 일정을 저장한다.
  // 매개변수: 없음. 반환값: 저장소 준비 완료 Future.
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
  // 함수이름: tearDown
  // 함수역할: DB 연결을 닫고 해당 테스트에서 만든 임시 디렉터리를 정리한다.
  // 매개변수: 없음. 반환값: 정리 완료 Future.
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  // 함수이름: patient
  // 함수역할: 소유 계정·별칭·활성 여부·일정을 지정한 환자 조회 응답을 만든다.
  // 매개변수: id: 연동 식별자, alias: 별칭, caregiver: 보호자 계정, active: 연결 상태, schedules: 일정. 반환값: 환자 연동과 일정을 담은 응답 데이터.
  Map<String, dynamic> patient(
    int id, {
    String alias = '엄마',
    String caregiver = 'patient-a',
    bool active = true,
    List<MedicationSchedule>? schedules,
  }) => {
    'link': {
      'link_id': id,
      'patient_hash': 'linked-$id',
      'caregiver_hash': caregiver,
      'patient_alias': alias,
      'link_status': active,
    },
    'schedules': (schedules ?? [medication]).map((s) => s.toJson()).toList(),
  };
  // 함수이름: patients
  // 함수역할: 환자 조회 결과나 실패를 현재 날짜의 캐시에 반영하며 버전 충돌을 재현한다.
  // 매개변수: entries: 조회 환자 목록, revision: 기대 캐시 버전, failed: 조회 실패 여부. 반환값: 환자 위젯 상태 Future.
  Future<DoseWidgetState> patients(
    List<Map<String, dynamic>> entries, {
    String? revision,
    bool failed = false,
  }) async => (await store.updateWidget(
    owner: 'patient-a',
    now: now,
    patientCache: {
      'date': doseWidgetDay(now),
      'patients': entries,
      'failed': failed,
    },
    expectedPatientRevision: revision,
  ))!;

  // 함수이름: 환자 일정 읽기 전용 테스트
  // 함수역할: 환자 모드가 본인 약·알림 설정과 분리되고 환자의 모든 시간대에서 기록 동작과 토큰을 제공하지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test(
    'patient setting uses read-only linked schedules, not owner doses or alarms',
    () async {
      final own = await state();
      await tap(own);
      await state(
        config: {
          'source': 'patients',
          'alarms': {'morning': '19:55'},
        },
      );
      final result = await patients([patient(1), patient(2, alias: '아빠')]);
      final views = result.view['patients'] as List;
      expect(views.map((p) => p['title']), ['엄마', '아빠']);
      expect(views.first['done'], 0);
      expect(views.first['heading'], '아침');
      expect(result.data['takes'], isEmpty);
      expect(result.data['cancels'], isEmpty);
      for (final p in views) {
        for (final page in p['pages'] as List) {
          expect(page['action'], 'open');
          expect(page['token'], isEmpty);
          expect(page['overdue'], false);
        }
      }
      expect((await store.pending('patient-a')).length, 1);
    },
  );

  // 함수이름: 일정 출처 변경 경합 테스트
  // 함수역할: 본인에서 환자 모드로 바꾸는 동시에 이전 복용 버튼이 도착해도 기록을 만들지 않고 출처 전환 시 탐색 키를 갱신하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('changing source rejects the old own-dose action atomically', () async {
    final own = await state();
    final result = (await store.updateWidget(
      owner: 'patient-a',
      now: now,
      action: 'take',
      actionToken: own.view['token'],
      configuration: {'source': 'patients'},
    ))!;
    expect(await store.pending('patient-a'), isEmpty);
    await tap(own);
    expect(await store.pending('patient-a'), isEmpty);
    final back = await state(config: {'source': 'self'});
    expect(back.view['token'], isNot(own.view['token']));
    expect(back.view['navigation_key'], isNot(result.view['navigation_key']));
  });

  // 함수이름: 환자 탐색 식별자 수명 테스트
  // 함수역할: 별칭 수정·재정렬에는 환자 식별자를 유지하고 연결 해제·재연결·날짜 변경에는 이전 식별자를 무효화하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test(
    'patient keys survive alias changes and reorder but not unlink or day change',
    () async {
      await state(config: {'source': 'patients'});
      final first = await patients([patient(1), patient(2)]);
      final key = (first.view['patients'] as List).first['patient_key'];
      final reordered = await patients([patient(2), patient(1, alias: '어머니')]);
      expect((reordered.view['patients'] as List).last['patient_key'], key);
      expect((reordered.view['patients'] as List).last['title'], '어머니');
      // 함수이름: resolve
      // 함수역할: 저장해 둔 환자·탐색 키가 현재 계정과 날짜에도 유효한 연동인지 조회한다.
      // 매개변수: at: 검사 시각, owner: 조회 계정. 반환값: 유효한 연동 정보 Future; 무효하면 null.
      Future<String?> resolve({DateTime? at, String owner = 'patient-a'}) =>
          store.resolveWidgetPatient(
            owner: owner,
            patientKey: key,
            navigationKey: first.view['navigation_key'],
            now: at ?? now,
          );
      expect(await resolve(), 'linked-1');
      expect(await resolve(owner: 'another-account'), isNull);
      await patients([patient(2)]);
      expect(await resolve(), isNull);
      final linkedAgain = await patients([patient(1)]);
      expect(
        (linkedAgain.view['patients'] as List).first['patient_key'],
        isNot(key),
      );
      expect(
        (await state(at: now.add(const Duration(days: 1)))).view['patients'],
        isEmpty,
      );
      expect(await resolve(at: now.add(const Duration(days: 1))), isNull);
    },
  );

  // 함수이름: 환자 지연 조회 거부 테스트
  // 함수역할: 연결 해제나 출처 변경 전의 캐시 버전으로 도착한 응답을 무시하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test(
    'patient refresh discards stale responses after unlink or source change',
    () async {
      await state(config: {'source': 'patients'});
      final before = await patients([patient(1)]);
      final revision = before.data['patient_revision'] as String;
      await patients([]);
      final stale = await patients([patient(1)], revision: revision);
      expect(stale.view['patients'], isEmpty);
      await state(config: {'source': 'self'});
      final self = await patients([patient(1)], revision: revision);
      expect(self.view['patients'], isNull);
    },
  );

  // 함수이름: 환자 조회 범위·실패 구분 테스트
  // 함수역할: 현재 보호자의 활성 연동만 중복 없이 표시하고 통신 실패와 연결된 환자 없음을 구분하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test(
    'only active owned links appear; failed query is not empty success',
    () async {
      await state(config: {'source': 'patients'});
      final filtered = await patients([
        patient(1),
        patient(1),
        patient(2, caregiver: 'foreign'),
        patient(3, active: false),
        patient(0),
      ]);
      expect((filtered.view['patients'] as List).length, 1);
      final failed = await patients([], failed: true);
      expect(failed.view['heading'], '환자 일정을 새로고침해주세요');
      expect((await patients([])).view['heading'], '연결된 환자가 없습니다');
    },
  );

  // 함수이름: 환자 정보 보호 테스트
  // 함수역할: 완료된 환자 일정도 읽기 전용으로 유지하고 이름 숨김·저장 암호화·계정 변경 후 접근 제한을 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test(
    'patient privacy and complete doses stay read-only and encrypted',
    () async {
      await state(config: {'source': 'patients', 'hide_names': true});
      final result = await patients([
        patient(
          1,
          schedules: [
            medication.copyWith(
              slotStatuses: {'morning': true, 'evening': true},
            ),
          ],
        ),
      ]);
      final view = (result.view['patients'] as List).single;
      expect(view['done'], 2);
      expect(jsonEncode(view), isNot(contains('private medicine')));
      expect((view['pages'] as List).every((p) => p['action'] == 'open'), true);
      final rows = await db.query('metadata');
      expect(jsonEncode(rows), isNot(contains('linked-1')));
      expect(jsonEncode(rows), isNot(contains('엄마')));
      await store.activate('other');
      expect(
        await store.resolveWidgetPatient(
          owner: 'patient-a',
          patientKey: view['patient_key'],
          navigationKey: result.view['navigation_key'],
          now: now,
        ),
        isNull,
      );
    },
  );
  // 함수이름: 복용 후 다음 일정 테스트
  // 함수역할: 표시한 시간대만 대기열에 기록한 뒤 완료 수와 버튼 토큰을 갱신하고 다음 미복용 일정을 보여주는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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

  // 함수이름: 환자 일정 미조회·빈 목록 테스트
  // 함수역할: 일정 데이터를 받지 못한 상태를 실제 빈 일정과 구분하고 별칭이 없으면 대체 이름을 표시하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test(
    'missing patient schedules are distinct from an empty schedule',
    () async {
      await state(config: {'source': 'patients'});
      final missing = await patients([
        {...patient(1, alias: ''), 'schedules': null},
      ]);
      final view = (missing.view['patients'] as List).single;
      expect(view['counts_known'], false);
      expect(view['pages'], isEmpty);
      expect(view['title'], '환자 ED-1');
      final empty = await patients([patient(1, schedules: [])]);
      expect((empty.view['patients'] as List).single['counts_known'], true);
      expect(
        (empty.view['patients'] as List).single['heading'],
        '등록된 복약 일정이 없어요',
      );
    },
  );
  // 함수이름: 위젯 중복 입력 테스트
  // 함수역할: 여러 위젯의 동일 버튼 동시 입력이 하나의 복용 요청만 만드는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('duplicate taps and different widgets share one operation', () async {
    final before = await state();
    expect((await state()).view['token'], before.view['token']);
    await Future.wait([tap(before), tap(before), tap(before)]);
    expect(await store.pending('patient-a'), hasLength(1));
  });
  // 아침부터 마지막 시간대까지 별도 확인 없이 넘어가며 마지막에는 기록 버튼을 없앤다.
  // 함수이름: 하루 시간대 순차 완료 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 미완료 약 선택 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 이전 시간대 입력 재수신 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('replayed previous slot never completes the next slot', () async {
    final morning = await state();
    final evening = (await tap(morning))!;
    final replayed = (await tap(morning))!;
    expect(replayed.view['token'], evening.view['token']);
    expect(replayed.view['done'], 1);
    expect(await store.pending('patient-a'), hasLength(1));
  });
  // 앱 업데이트 전의 되돌리기 표시와 버튼 토큰은 새 기록을 만들지 않는다.
  // 함수이름: 이전 버전 되돌리기 호환 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 계정 전환 후 복용 버튼 거부 테스트
  // 함수역할: 이전 계정의 화면 토큰으로 새 계정이나 이전 계정에 기록이 추가되지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('old account buttons cannot change another account', () async {
    final before = await state();
    await store.activate('patient-b');
    expect(await tap(before), isNull);
    expect(await store.pending('patient-a'), isEmpty);
    expect(await store.pending('patient-b'), isEmpty);
    expect(await store.updateWidget(owner: 'patient-a', now: now), isNull);
  });
  // 함수이름: 로그아웃 후 복용 버튼 거부 테스트
  // 함수역할: 로그아웃 뒤 남은 위젯 버튼을 눌러도 기록을 만들지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('logout rejects cached buttons', () async {
    final before = await state();
    await store.activate(null);
    expect(await tap(before), isNull);
    expect(await store.pending('patient-a'), isEmpty);
  });
  // 함수이름: 자정 이후 복용 버튼 거부 테스트
  // 함수역할: 전날 버튼을 다음 날 누르면 날짜를 바꿔 기록하지 않고 일정 새로고침을 안내하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 일정 변경 후 이전 입력 거부 테스트
  // 함수역할: 표시한 일정이 제거되면 이전 버튼으로 다른 약을 대신 기록하지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 외부 완료 상태 보존 테스트
  // 함수역할: 앱 등에서 이미 완료된 약을 이전 위젯 버튼으로 중복 기록하지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 위젯 동작 상태 재시작 복구 테스트
  // 함수역할: 약명과 버튼 토큰을 암호화해 저장하며 DB를 다시 열어도 유효한 버튼 입력을 처리하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 본인 위젯 이름 숨김 테스트
  // 함수역할: 이름 숨김 설정에서 약명 대신 개수를 표시하고 영문 복용 버튼을 유지하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('privacy hides names in native display', () async {
    final value = await state(config: {'hide_names': true, 'language': 'en'});
    expect(value.view['details'], '1 scheduled medicines');
    expect(jsonEncode(value.view), isNot(contains('private medicine')));
    expect(value.view['button'], 'Taken');
  });
  // 함수이름: 사용자 알림 시각 적용 테스트
  // 함수역할: 변경한 알림 시각으로 다음 미복용 일정을 정하되 페이지 순서는 시간대 기준으로 유지하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 지난 시간대 순서 유지 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('overdue slots retain their order and warning', () async {
    final late = DateTime.utc(2026, 9, 21, 14);
    final morning = await state(at: late);
    expect(morning.view['heading'], '아침 08:00');
    expect(morning.view['overdue'], isTrue);
    final evening = (await tap(morning, at: late))!;
    expect(evening.view['heading'], '저녁 18:00');
    expect(evening.view['overdue'], isTrue);
  });
  // 함수이름: 빈 일정·전체 완료 동작 테스트
  // 함수역할: 빈 일정이나 전체 완료 요약에는 추가 복용 버튼 대신 일정 열기를 제공하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 오프라인 시간대 순차 전송 테스트
  // 함수역할: 통신이 끊겨도 다음 일정으로 넘어가고 복구 후 아침·저녁 기록을 순서대로 전송하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 완료 페이지 명시적 취소 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 직접 탐색한 시간대 기록 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 일부 완료 시간대 표시 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 모든 페이지 이름 숨김 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 탐색 위치 유효 범위 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 전체 완료 후 취소 탐색 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test(
    'all completed slots retain cancellation but no completion tokens',
    () async {
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
    },
  );

  // 함수역할: 지정 시간대의 표시 데이터를 실제 버튼 입력과 같은 형태로 감싼다.
  // 매개변수: value 전체 상태, slot 조회 시간대. 반환값: 해당 페이지의 동작·토큰.
  // 함수이름: page
  DoseWidgetState page(DoseWidgetState value, String slot) => DoseWidgetState({
    'view': (value.view['pages'] as List).cast<Map>().singleWhere(
      (p) => p['slot'] == slot,
    ),
  });

  // 날짜 표시는 기기 UTC 날짜가 아닌 복약 기준일에 맞추고 언어 설정을 따른다.
  // 함수이름: 복약 기준일 날짜 표시 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test(
    'date label follows the medication timezone and language at midnight',
    () async {
      expect((await state()).view['date_label'], '9월 21일 (월)');
      final english = await state(config: {'language': 'en'});
      expect(english.view['date_label'], '9/21 (Mon)');
      final tomorrow = await state(
        at: DateTime.utc(2026, 9, 21, 15),
        config: {'language': 'ko'},
      );
      expect(tomorrow.view['date'], '2026-09-22');
      expect(tomorrow.view['date_label'], '9월 22일 (화)');
      expect(tomorrow.view['utc_offset_minutes'], doseWidgetUtcOffset);
    },
  );

  // 취소를 중복 수신하거나 재복용 뒤 이전 취소를 수신해도 새 기록에 적용하지 않는다.
  // 함수이름: 중복·오래된 취소 입력 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test(
    'duplicate cancellation and stale tokens cannot undo a later completion',
    () async {
      final before = await state();
      final taken = (await tap(before))!;
      final cancel = page(taken, 'morning');
      expect(
        page(await state(), 'morning').view['token'],
        cancel.view['token'],
      );
      final cancelled = (await tap(cancel))!;
      await tap(cancel);
      expect(await store.pending('patient-a'), hasLength(2));
      final retake = page(cancelled, 'morning');
      expect(retake.view['token'], isNot(before.view['token']));
      await tap(retake);
      final replay = (await tap(cancel))!;
      expect(replay.view['done'], 1);
      expect(
        page(replay, 'morning').view['token'],
        isNot(cancel.view['token']),
      );
      expect((await store.pending('patient-a')).map((op) => op['completed']), [
        true,
        false,
        true,
      ]);
    },
  );

  // 완료/취소 토큰은 서로 바꿔서 사용할 수 없다.
  // 함수이름: 토큰과 동작 종류 일치 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('action kind is bound to its token', () async {
    final before = await state();
    await store.updateWidget(
      now: now,
      action: 'cancel',
      actionToken: before.view['token'],
    );
    expect(await store.pending('patient-a'), isEmpty);
    final taken = (await tap(before))!;
    await store.updateWidget(
      now: now,
      action: 'take',
      actionToken: page(taken, 'morning').view['token'],
    );
    expect(await store.pending('patient-a'), hasLength(1));
  });

  // 자정 이후에는 이전 날짜의 완료 기록도 위젯으로 수정하지 않는다.
  // 함수이름: 전날 취소 입력 거부 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test(
    'yesterday cancellation does not write or change the operation date',
    () async {
      final taken = (await tap(await state()))!;
      await tap(page(taken, 'morning'), at: DateTime.utc(2026, 9, 21, 15));
      expect(await store.pending('patient-a'), hasLength(1));
    },
  );

  // 다른 계정으로 바뀌거나 로그아웃하면 완료된 페이지의 취소 토큰도 거부한다.
  // 함수이름: 계정 전환·로그아웃 취소 거부 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
  // 함수이름: 취소 대상 일정 변경 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test(
    'cancel checks the complete displayed medication set and prior status',
    () async {
      final completed = medication.copyWith(
        slotStatuses: {'morning': true, 'evening': false},
      );
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
    },
  );

  // 앱에서 완료한 시간대의 모든 약을 취소하되 다른 시간대의 기록은 유지한다.
  // 함수이름: 시간대 전체 취소 범위 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test(
    'server-completed slot cancels all its medicines and retains other slots',
    () async {
      final completed = medication.copyWith(
        slotStatuses: {'morning': true, 'evening': true},
      );
      await cache(
        schedules: [
          completed,
          completed.copyWith(medicationID: '92'),
        ],
      );
      final result = (await tap(page(await state(), 'morning')))!;
      expect(result.view['done'], 2);
      expect(page(result, 'evening').view['completed'], isTrue);
      final op = (await store.pending('patient-a')).single;
      expect(op['medication_ids'], [91, 92]);
      expect(op['completed'], false);
    },
  );

  // 서버가 거부한 기록이 있으면 위젯에서 추가 취소하지 않고 앱 확인으로 유도한다.
  // 함수이름: 서버 거부 후 위젯 취소 제한 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('blocked sync rejects cancellation and removes action tokens', () async {
    final taken = (await tap(await state()))!;
    final op = (await store.claim(
      'patient-a',
      'test-lease',
      now.millisecondsSinceEpoch,
    ))!;
    await store.finish(
      'patient-a',
      op['operation_id'],
      'test-lease',
      blocked: true,
    );
    final blocked = (await tap(page(taken, 'morning')))!;
    expect(await store.pending('patient-a'), hasLength(1));
    expect(page(blocked, 'morning').view['action'], 'open');
    expect(blocked.data['cancels'], isEmpty);
  });

  // 오프라인 복용→취소→재복용은 앱 재시작 후에도 같은 순서로 한 번씩 전송한다.
  // 함수이름: 오프라인 취소 재시작 복구 테스트
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
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
      return http.Response(
        jsonEncode({
          'operation_id': body['operation_id'],
          'schedule_date': '2026-09-21',
          'data': [
            medication
                .copyWith(
                  slotStatuses: {
                    'morning': body['completed'],
                    'evening': false,
                  },
                )
                .toJson(),
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
