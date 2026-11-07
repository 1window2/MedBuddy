// 파일명: medication_reminder_refresh_factory_test.dart
// 역할: 백그라운드 알림 갱신의 일정 캐시·오프라인 범위·계정별 설정 계약을 검증한다.

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/composition/medication_reminder_refresh_factory.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:medbuddy_frontend/services/medication_reminder_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'support/fake_notification_service.dart';

// 클래스명: _ReceiptDuringCacheReadStore
// 역할: 로컬 캐시 스냅샷을 읽는 도중 서버 승인 수신을 끼워 넣는 저장소.
// 주요 책임: 오래된 캐시와 최신 승인 사이 경합을 첫 유효 읽기에서 재현한다.
// 속성: receive는 승인 처리 콜백, received는 한 번 실행했는지 나타내는 표식.
class _ReceiptDuringCacheReadStore extends DoseOutboxStore {
  // 함수이름: _ReceiptDuringCacheReadStore
  // 함수역할:
  // - 실제 DB·암호화 키를 공유하며 캐시 조회 중 실행할 승인 콜백을 저장한다.
  // 매개변수:
  // - db(Database): 기존 대기열 DB.
  // - key(SecretKey): 기존 저장소의 암호화 키.
  // - receive(Future<void> Function()): 첫 유효 스냅샷 읽기 후 실행할 처리.
  // 반환값:
  // - 새 _ReceiptDuringCacheReadStore 인스턴스.
  _ReceiptDuringCacheReadStore(super.db, super.key, this.receive);

  final Future<void> Function() receive;
  bool received = false;

  // 함수이름: readCache
  // 함수역할:
  // - 상위 캐시를 먼저 읽고 첫 비어 있지 않은 스냅샷에서 receive를 기다린 뒤 이전 스냅샷을 반환한다.
  // 매개변수:
  // - owner(String): 캐시 소유 계정.
  // 반환값:
  // - Future<Map<String, dynamic>?>: 조회 당시 캐시 또는 null; 저장소·콜백 오류는 전달된다.
  @override
  Future<Map<String, dynamic>?> readCache(String owner) async {
    final snapshot = await super.readCache(owner);
    if (snapshot != null && !received) {
      received = true;
      await receive();
    }
    return snapshot;
  }
}

// 함수이름: main
// 함수역할:
// - 갱신 서비스 팩터리에 조회·저장소 대역을 연결해 캐시와 알림 동기화 경계를 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  timezone_data.initializeTimeZones();
  final seoul = timezone.getLocation('Asia/Seoul');
  late Directory directory;
  late Database db;
  late DoseOutboxStore store;
  late RecordingNotificationService notifications;
  late MockClient client;
  late DateTime now;
  late List<http.Request> requests;
  late bool serverTaken;
  late bool secondMorningMedication;
  late List<MedicationSchedule> futureCourses;
  Future<void> Function()? duringTodayRead;

  // 함수이름: medication
  // 함수역할:
  // - 5일짜리 아침·저녁 일정에 선택한 아침 복용 상태를 담는다.
  // 매개변수:
  // - id(String): 약 ID; 기본 91.
  // - taken(bool): 아침 완료 여부; 기본 false.
  // 반환값:
  // - MedicationSchedule: 2026-10-10 시작, 저녁 미완료인 일정.
  MedicationSchedule medication({String id = '91', bool taken = false}) =>
      MedicationSchedule(
        medicationID: id,
        medicationName: 'TEST_ONLY',
        prescriptionDate: DateTime(2026, 10, 10),
        medicationTime: 5,
        scheduleSlotKeys: const ['morning', 'evening'],
        slotStatuses: {'morning': taken, 'evening': false},
      );

  // 함수이름: enqueue
  // 함수역할:
  // - 현재 한국 날짜의 아침 약 91 완료/취소 작업을 실제 암호화 대기열에 저장한다.
  // 매개변수:
  // - id(String): 작업 식별자.
  // - completed(bool): 완료 또는 취소 상태.
  // - owner(String): 저장 계정; 기본 patient-a.
  // 반환값:
  // - Future<void>: 저장 완료; 저장소 오류는 전달된다.
  Future<void> enqueue(
    String id, {
    bool completed = true,
    String owner = 'patient-a',
  }) => store.enqueue(owner, {
    'operation_id': id,
    'schedule_date': doseScheduleDay(now),
    'slot_key': 'morning',
    'medication_ids': [91],
    'completed': completed,
  });

  // 함수이름: dates
  // 함수역할:
  // - 지정 시간대의 마지막 알림 등록에서 활성 날짜를 읽는다.
  // 매개변수:
  // - slot(String): 조회할 시간대 키.
  // 반환값:
  // - List<DateTime>: 마지막 등록의 날짜 목록; 해당 등록이 없으면 StateError.
  List<DateTime> dates(String slot) => notifications.registrations
      .lastWhere((registration) => registration.slotKey == slot)
      .activeDates;

  // Function Name: setUp
  // Description:
  // - Creates an encrypted file-backed outbox and deterministic Seoul clock, then installs GET-only patient fixtures with validated offline-window dates.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes independent storage, notification and HTTP setup; unexpected requests fail.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('reminder-outbox-test-');
    db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/outbox.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
      ),
    );
    store = DoseOutboxStore(db, await AesGcm.with256bits().newSecretKey());
    await store.activate('patient-a');
    notifications = RecordingNotificationService();
    now = timezone.TZDateTime(seoul, 2026, 10, 10, 7);
    requests = [];
    serverTaken = false;
    secondMorningMedication = false;
    futureCourses = [];
    duringTodayRead = null;
    client = MockClient((request) async {
      requests.add(request);
      if (request.method != 'GET' ||
          request.url.queryParameters['patient_hash'] != 'patient-a') {
        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      }
      switch (request.url.path) {
        case '/notification/settings':
          return http.Response(
            jsonEncode({
              'data': [
                for (final slot in ['morning', 'evening'])
                  {
                    'patient_hash': 'patient-a',
                    'slot_key': slot,
                    'hour': slot == 'morning' ? 8 : 20,
                    'minute': 0,
                    'enabled': true,
                  },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        case '/schedule/window':
          return http.Response(
            jsonEncode({
              'success': true,
              // 서버처럼 조회 기간을 함께 보내 오프라인 저장 검증을 통과한다.
              'window_start': doseScheduleDay(now),
              // 끝 날짜는 한국 날짜 문자열에서 계산한다. 기기 자정을 한국 날짜로 바꾸면 한국보다
              // 동쪽 시간대에서 하루 이르게 나온다.
              'window_end': () {
                final start = DateTime.parse(doseScheduleDay(now));
                return DateTime(
                  start.year,
                  start.month,
                  start.day + 13,
                ).toIso8601String().substring(0, 10);
              }(),
              'data': [
                medication().toJson(),
                if (secondMorningMedication) medication(id: '92').toJson(),
                ...futureCourses.map((schedule) => schedule.toJson()),
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        case '/schedule/today':
          final snapshot = [
            medication(taken: serverTaken).toJson(),
            if (secondMorningMedication) medication(id: '92').toJson(),
          ];
          await duringTodayRead?.call();
          return http.Response(
            jsonEncode({'success': true, 'data': snapshot}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        default:
          throw StateError('Unexpected URL: ${request.url}');
      }
    });
  });

  // 함수이름: tearDown
  // 함수역할:
  // - HTTP와 DB를 닫은 뒤 테스트 임시 디렉터리를 제거한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 저장소 및 파일 정리 완료.
  tearDown(() async {
    client.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  // 함수이름: build
  // 함수역할:
  // - 현재 시계와 기록기를 연결한 갱신 서비스를 만들고 종료 정리를 등록한다.
  // 매개변수:
  // - openDoseStore(Future<DoseOutboxStore> Function()?): 저장소 공급자; 생략하면 현재 store.
  // 반환값:
  // - MedicationReminderRefreshService: patient-a 전용 서비스.
  MedicationReminderRefreshService build({
    Future<DoseOutboxStore> Function()? openDoseStore,
  }) {
    final service = MedicationReminderRefreshFactory.create(
      patientHash: 'patient-a',
      baseUrl: 'http://test.invalid',
      client: client,
      notificationService: notifications,
      openDoseStore: openDoseStore ?? () async => store,
      now: () => now,
    );
    addTearDown(service.dispose);
    return service;
  }

  // 12시간 작업이 오늘 일정을 저장해도 자정 뒤 오프라인 기록에 쓸 14일 일정이 남아야 한다.
  // Function Name: background refresh offline window
  // Description:
  // - Verifies a successful refresh persists a dated offline window containing the fixture medication for later-day use.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: Completes the checks; an unexpected result fails the test.
  test('the background refresh keeps an offline window for the next days', () async {
    final service = build();
    expect(await service.synchronize(), isTrue);
    final window = await store.readOfflineScheduleWindow('patient-a');
    expect(window, isNotNull);
    expect(window!['start'], '2026-10-10');
    expect(
      (window['courses'] as List).map((course) => course['medication_id']),
      contains('91'),
    );
  });

  // 함수이름: 오프라인 완료의 재예약 방지
  // 함수역할:
  // - 저장된 완료를 오늘 아침 예약에서 제외하되 저녁과 다음날은 유지하며 대기열·활성 계정을 바꾸거나 GET 이외 요청을 보내지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'completed offline is not rearmed by the real background refresh factory',
    () async {
      await enqueue('offline-taken');
      final before = await store.pending('patient-a');
      final service = build();

      expect(await service.synchronize(), isTrue);
      expect(dates('morning'), isNot(contains(DateTime(2026, 10, 10))));
      expect(dates('morning').first, DateTime(2026, 10, 11));
      expect(dates('evening').first, DateTime(2026, 10, 10));
      expect(await store.pending('patient-a'), before);
      expect(await store.isActive('patient-a'), isTrue);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
    },
  );

  // 함수이름: 완료 취소 재완료의 대기열 순서
  // 함수역할:
  // - 각 갱신이 최신 완료/취소를 순서대로 반영하되 작업 순서와 대기열을 보존하고 전송하지 않는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'refresh rereads durable undo and retake in queue order without sending them',
    () async {
      final service = build();
      for (final (id, completed) in [
        ('taken', true),
        ('undo', false),
        ('retake', true),
      ]) {
        await enqueue(id, completed: completed);
        serverTaken = !completed;
        final before = await store.pending('patient-a');
        expect(await service.synchronize(), isTrue);
        expect(dates('morning').contains(DateTime(2026, 10, 10)), !completed);
        expect(dates('evening').first, DateTime(2026, 10, 10));
        expect(await store.pending('patient-a'), before);
      }
      expect(
        (await store.pending('patient-a')).map((op) => op['operation_id']),
        ['taken', 'undo', 'retake'],
      );
      expect(requests.every((request) => request.method == 'GET'), isTrue);
    },
  );

  // 함수이름: 미래 주간 일정과 오프라인 완료
  // 함수역할:
  // - 완료·취소가 오늘 아침에만 영향을 주고 미래 주간 과정과 저녁 날짜 목록 및 미전송 작업은 유지되는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'offline completion removes only today alongside a future weekly course',
    () async {
      futureCourses = [
        MedicationSchedule(
          medicationID: '92',
          medicationName: 'TEST_ONLY_WEEKLY',
          prescriptionDate: DateTime(2026, 10, 11),
          medicationTime: 14,
          scheduleSlotKeys: const ['morning'],
          doseCycleDays: 7,
          doseCycleOffsets: const [0],
          doseCycleAnchor: DateTime(2026, 10, 11),
        ),
      ];
      final service = build();
      final futureMorningDates = [
        DateTime(2026, 10, 11),
        DateTime(2026, 10, 12),
        DateTime(2026, 10, 13),
        DateTime(2026, 10, 14),
        DateTime(2026, 10, 18),
      ];
      for (final (id, completed) in [('taken', true), ('undo', false)]) {
        await enqueue(id, completed: completed);
        final before = await store.pending('patient-a');

        expect(await service.synchronize(), isTrue);
        expect(dates('morning'), [
          if (!completed) DateTime(2026, 10, 10),
          ...futureMorningDates,
        ]);
        expect(dates('evening'), [
          for (var day = 10; day <= 14; day++) DateTime(2026, 10, day),
        ]);
        expect(await store.pending('patient-a'), before);
      }
      expect(requests.every((request) => request.method == 'GET'), isTrue);
    },
  );

  // 함수이름: 어제 완료와 오늘 알림 분리
  // 함수역할:
  // - 날짜가 바뀐 뒤에도 새 날짜의 아침 알림은 유지하고 이전 날짜의 미전송 완료 작업은 그대로 남기는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'yesterday offline completion cannot remove the new day reminder',
    () async {
      final service = build();
      await enqueue('yesterday-taken');
      expect(await service.synchronize(), isTrue);
      expect(dates('morning').first, DateTime(2026, 10, 11));
      now = timezone.TZDateTime(seoul, 2026, 10, 11, 7);

      expect(await service.synchronize(), isTrue);
      expect(dates('morning').first, DateTime(2026, 10, 11));
      final pending = await store.pending('patient-a');
      expect(pending, hasLength(1));
      expect(pending.single['schedule_date'], '2026-10-10');
    },
  );

  // 함수이름: 조회 중 자정 통과
  // 함수역할:
  // - 오늘 조회 중 날짜가 바뀌면 예약·취소·캐시 저장 없이 재시도를 요구하고 다음 갱신은 새 날짜로 성공하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'a today read crossing midnight is retried without relabeling the cache',
    () async {
      final service = build();
      await enqueue('yesterday-taken');
      serverTaken = true;
      now = timezone.TZDateTime(seoul, 2026, 10, 10, 23, 59);
      duringTodayRead = () async {
        now = timezone.TZDateTime(seoul, 2026, 10, 11, 0, 1);
      };
      expect(await service.synchronize(), isFalse);
      expect(notifications.registrations, isEmpty);
      expect(notifications.cancellations, isEmpty);
      expect(await store.readCache('patient-a'), isNull);
      expect(await store.pending('patient-a'), hasLength(1));

      duringTodayRead = null;
      serverTaken = false;
      expect(await service.synchronize(), isTrue);
      expect(dates('morning').first, DateTime(2026, 10, 11));
      expect(
        (await store.pending('patient-a')).single['schedule_date'],
        '2026-10-10',
      );
    },
  );

  // 함수이름: 시간대 일부 약만 완료
  // 함수역할:
  // - 두 아침 약 중 하나만 오프라인 완료한 경우 오늘 시간대 알림과 대기 작업을 유지하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test('a partial offline completion preserves the slot reminder', () async {
    secondMorningMedication = true;
    await enqueue('one-of-two-taken');
    expect(await build().synchronize(), isTrue);
    expect(dates('morning').first, DateTime(2026, 10, 10));
    expect(await store.pending('patient-a'), hasLength(1));
  });

  // 함수이름: 다른 환자 대기열 격리
  // 함수역할:
  // - 다른 환자의 완료를 현재 환자의 알림에 투영하지 않으며 양쪽 대기열과 현재 활성 계정을 보존하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'another patient queue is not projected or activated by refresh',
    () async {
      await store.activate('patient-b');
      await enqueue('other-patient-taken', owner: 'patient-b');
      await store.activate('patient-a');
      expect(await build().synchronize(), isTrue);
      expect(dates('morning').first, DateTime(2026, 10, 10));
      expect(await store.pending('patient-b'), hasLength(1));
      expect(await store.pending('patient-a'), isEmpty);
      expect(await store.isActive('patient-a'), isTrue);
    },
  );

  // 함수이름: 저장소 일시 실패와 복구
  // 함수역할:
  // - 저장소를 열 수 없으면 알림을 변경하지 않고 대기 기록을 남기며 복구 후 완료를 반영해 오늘 아침을 제외하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'temporary outbox failure leaves reminders and queued events intact then recovers',
    () async {
      await enqueue('offline-taken');
      var unavailable = true;
      final service = build(
        openDoseStore: () async {
          if (unavailable) throw StateError('temporary storage failure');
          return store;
        },
      );
      expect(await service.synchronize(), isFalse);
      expect(notifications.registrations, isEmpty);
      expect(notifications.cancellations, isEmpty);
      expect(await store.pending('patient-a'), hasLength(1));

      unavailable = false;
      expect(await service.synchronize(), isTrue);
      expect(dates('morning').first, DateTime(2026, 10, 11));
      expect(await store.pending('patient-a'), hasLength(1));
    },
  );

  // 함수이름: 서버 조회 중 승인 수신
  // 함수역할:
  // - 조회 중 도착한 승인 결과가 오래된 서버 스냅샷보다 우선해 완료 캐시와 내일 아침 예약을 유지하고 대기열을 비우는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'a sync receipt arriving during the read wins over the stale server snapshot',
    () async {
      await enqueue('taken-in-flight');
      final claimed = await store.claim(
        'patient-a',
        'test-lease',
        now.millisecondsSinceEpoch,
      );
      expect(claimed, isNotNull);
      duringTodayRead = () =>
          store.acknowledge('patient-a', 'taken-in-flight', 'test-lease', {
            'date': doseScheduleDay(now),
            'schedules': [medication(taken: true).toJson()],
          });
      expect(await build().synchronize(), isTrue);
      expect(dates('morning').first, DateTime(2026, 10, 11));
      expect(await store.pending('patient-a'), isEmpty);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      final cache = await store.readCache('patient-a');
      expect(
        MedicationSchedule.fromScheduleJsonList(
          cache?['schedules'],
        ).single.isSlotCompleted('morning'),
        isTrue,
      );
    },
  );

  // 함수이름: 로컬 스냅샷 중 승인 변경
  // 함수역할:
  // - 캐시 읽기 도중 승인이 바뀌면 예약·취소 없이 재시도를 요구하고 최신 서버 상태로 후속 갱신이 성공하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
  test(
    'a receipt changing during the local snapshot requests retry instead of rearming',
    () async {
      await enqueue('taken-in-flight');
      await store.claim('patient-a', 'test-lease', now.millisecondsSinceEpoch);
      final interleaved = _ReceiptDuringCacheReadStore(
        db,
        store.key,
        () => store.acknowledge('patient-a', 'taken-in-flight', 'test-lease', {
          'date': doseScheduleDay(now),
          'schedules': [medication(taken: true).toJson()],
        }),
      );
      final service = build(openDoseStore: () async => interleaved);
      expect(await service.synchronize(), isFalse);
      expect(interleaved.received, isTrue);
      expect(notifications.registrations, isEmpty);
      expect(notifications.cancellations, isEmpty);

      serverTaken = true;
      expect(await service.synchronize(), isTrue);
      expect(dates('morning').first, DateTime(2026, 10, 11));
      expect(requests.every((request) => request.method == 'GET'), isTrue);
    },
  );
}
