// 파일명: dose_home_widget_service_test.dart
// 역할: 위젯 발행과 백그라운드 갱신이 복용 기록을 잃지 않고 한 번만 전송하며, 보낼 기록도
//   표시할 위젯도 없을 때에만 일을 건너뛰는지 검증한다.
// Real SQLite/crypto and the production DoseSyncService; the widget plugin, WorkManager and the
//   notification plugin are replaced by recording substitutes. No production accounts or records.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/composition/dose_home_widget_background.dart';
import 'package:medbuddy_frontend/entities/dose_widget_state.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_home_widget_service.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_background_service.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/json_http.dart';

// 클래스명: _RecordingWidgetPlatform
// 역할: 위젯 플러그인·알림·전송 예약·통신 준비 호출을 기록하는 대역.
// 주요 책임: Android 위젯처럼 처리된 클릭을 목록에서 지우고, 테스트가 정한 위젯 유무와 실패를 재현한다.
// 속성: journal 처리 전 클릭 목록, installed 위젯 유무, savedStates 발행한 상태,
//   cancelledReminders 취소한 재알림, registered 전송 예약 계정, openedClients 직접 만든 통신 수단 수.
class _RecordingWidgetPlatform extends DoseHomeWidgetPlatform {
  // 함수이름: _RecordingWidgetPlatform
  // 함수역할: 테스트 저장소와 통신 대역을 사용하는 기록용 플랫폼을 만든다.
  // 매개변수: store - 암호화 테스트 저장소, client - 서비스가 직접 만들 통신 수단의 대역.
  _RecordingWidgetPlatform(this.store, this.client);

  final DoseOutboxStore store;
  final http.Client client;
  String journal = '[]';
  bool installed = true;
  bool failInstalledLookup = false;
  bool failReminderCancel = false;
  final List<Map<String, dynamic>> savedStates = [];
  final List<DateTime> scheduledUpdates = [];
  final List<({String owner, String slotKey, DateTime date})>
  cancelledReminders = [];
  final List<String> registered = [];
  int openedClients = 0;
  int cancelledScheduledUpdates = 0;

  @override
  bool get supported => true;

  @override
  Future<String?> readJournal() async => journal;

  @override
  Future<void> saveState(String state) async {
    savedStates.add(Map<String, dynamic>.from(jsonDecode(state) as Map));
  }

  // 함수이름: updateWidget
  // 함수역할: Android 위젯과 같이 처리 완료로 표시된 클릭을 대기 목록에서 지운다.
  @override
  Future<void> updateWidget() async {
    final handled = (savedStates.last['handled'] as List? ?? []).toSet();
    journal = jsonEncode([
      for (final entry in (jsonDecode(journal) as List).whereType<Map>())
        if (!handled.contains(entry['token'])) entry,
    ]);
  }

  @override
  Future<void> scheduleUpdate(DateTime at) async => scheduledUpdates.add(at);

  @override
  Future<void> cancelScheduledUpdates() async => cancelledScheduledUpdates++;

  @override
  Future<bool> hasInstalledWidget() async {
    if (failInstalledLookup) throw StateError('widget lookup unavailable');
    return installed;
  }

  @override
  Future<DoseOutboxStore> openStore() async => store;

  @override
  Future<void> cancelReminder({
    required String owner,
    required String slotKey,
    required DateTime date,
  }) async {
    if (failReminderCancel) throw StateError('notification plugin unavailable');
    cancelledReminders.add((owner: owner, slotKey: slotKey, date: date));
  }

  @override
  Future<void> registerSync(String owner) async => registered.add(owner);

  @override
  Future<http.Client> openClient() async {
    openedClients++;
    return client;
  }
}

// 클래스명: _RecordingWorkPlatform
// 역할: WorkManager 호출 순서를 기록하고 저장소 열기 실패를 재현하는 대역.
// 속성: calls 호출 순서, store 열어 줄 저장소(null이면 열기 실패).
class _RecordingWorkPlatform extends DoseSyncWorkPlatform {
  // 함수이름: _RecordingWorkPlatform
  // 함수역할: store를 돌려주거나, null이면 열기 실패를 내는 대역을 만든다.
  _RecordingWorkPlatform(this.store);

  final DoseOutboxStore? store;
  final List<String> calls = [];

  @override
  bool get supported => true;

  @override
  Future<void> registerOneOff(String owner) async => calls.add('one-off:$owner');

  @override
  Future<void> registerPeriodic(String owner) async =>
      calls.add('periodic:$owner');

  @override
  Future<void> cancelAll() async => calls.add('cancel');

  @override
  Future<DoseOutboxStore> openStore() async {
    calls.add('open');
    return store ?? (throw StateError('Dose storage unavailable.'));
  }
}

// 함수이름: main
// 함수역할: 위젯 발행·백그라운드 갱신·전송 예약의 회귀 테스트를 등록한다.
// 매개변수: 없음. 반환값: 없음.
void main() {
  sqfliteFfiInit();
  const owner = 'patient-a';
  late Database db;
  late DoseOutboxStore store;
  late Directory directory;
  late _RecordingWidgetPlatform platform;
  late http.Client client;
  late List<Map<String, dynamic>> uploads;
  late int scheduleReads;
  late int snapshotReads;
  late bool online;
  late int uploadStatus;
  late int snapshotStatus;
  late Duration uploadDelay;

  // 함수이름: today
  // 함수역할: 서비스가 쓰는 것과 같은 기준으로 오늘 복약 기준일을 계산한다. 반환값: YYYY-MM-DD.
  String today() => doseWidgetDay(DateTime.now());

  // 함수이름: medication
  // 함수역할: 아침 한 번 복용하는 테스트 약 일정을 만든다.
  // 매개변수: taken - 아침 복용 완료 여부. 반환값: 일정.
  MedicationSchedule medication({bool taken = false}) => MedicationSchedule(
    medicationID: '91',
    medicationName: 'private medicine',
    scheduleSlotKeys: const ['morning'],
    slotStatuses: {'morning': taken},
  );

  // 함수이름: prepare
  // 함수역할: 로그인한 계정에 일정 캐시와 이전에 발행한 위젯 상태를 만들어 둔다.
  // 매개변수: date - 캐시 기준일(null이면 오늘), taken - 아침 완료 여부, config - 위젯 표시 설정.
  // 반환값: 저장된 위젯 상태.
  Future<DoseWidgetState> prepare({
    String? date,
    bool taken = false,
    Map<String, dynamic> config = const {},
  }) async {
    await store.activate(owner);
    await store.saveCache(owner, {
      'date': date ?? today(),
      'schedules': [medication(taken: taken).toJson()],
    });
    return (await store.updateWidget(
      owner: owner,
      now: DateTime.now(),
      configuration: config,
    ))!;
  }

  // 함수이름: enqueue
  // 함수역할: 앱에서 기록해 아직 전송하지 못한 아침 복용 요청을 대기열에 넣는다.
  // 매개변수: id - 요청 ID, date - 복약 기준일(null이면 오늘). 반환값: 저장 완료 Future.
  Future<void> enqueue(String id, {String? date}) => store.enqueue(owner, {
    'operation_id': id,
    'schedule_date': date ?? today(),
    'slot_key': 'morning',
    'medication_ids': [91],
    'completed': true,
    'medication_names': ['private medicine'],
  });

  // 함수이름: uploadedIds
  // 함수역할: 서버가 받은 복용 기록 요청의 ID를 받은 순서대로 돌려준다.
  List<Object?> uploadedIds() => [for (final u in uploads) u['operation_id']];

  setUp(() async {
    // Production installs the server readers at every entry point; the tests use the same wiring.
    installDoseHomeWidgetReaders();
    directory = await Directory.systemTemp.createTemp('dose-widget-service-');
    db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/outbox.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
      ),
    );
    store = DoseOutboxStore(db, await AesGcm.with256bits().newSecretKey());
    uploads = [];
    scheduleReads = 0;
    snapshotReads = 0;
    online = true;
    uploadStatus = 200;
    snapshotStatus = 200;
    uploadDelay = Duration.zero;
    client = MockClient((request) async {
      if (!online) throw const SocketException('offline');
      final path = request.url.path;
      if (request.method == 'POST' &&
          path.endsWith('/schedule/completion-operations')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        uploads.add(body);
        await Future<void>.delayed(uploadDelay);
        if (uploadStatus != 200) return http.Response('rejected', uploadStatus);
        return jsonResponse({
          'operation_id': body['operation_id'],
          'schedule_date': today(),
          'data': [medication(taken: body['completed'] == true).toJson()],
        });
      }
      if (request.method == 'GET' && path.endsWith('/schedule/today')) {
        scheduleReads++;
        return jsonResponse({
          'success': true,
          'data': [medication().toJson()],
        });
      }
      if (request.method == 'GET' && path.endsWith('/caregiver/schedules')) {
        snapshotReads++;
        if (snapshotStatus != 200) {
          return http.Response('unavailable', snapshotStatus);
        }
        return jsonResponse({
          'success': true,
          'data': {
            'caregiver_hash': owner,
            'patients': [
              {
                'link': {
                  'link_id': 3,
                  'patient_hash': 'patient-b',
                  'caregiver_hash': owner,
                  'patient_alias': '어머니',
                  'link_status': true,
                },
                'today_medication_info': [medication().toJson()],
              },
            ],
          },
        });
      }
      return http.Response('{"detail":"unexpected"}', 500);
    });
    platform = _RecordingWidgetPlatform(store, client);
    DoseHomeWidget.platform = platform;
  });

  tearDown(() async {
    DoseHomeWidget.resetForTest();
    DoseSyncBackgroundScheduler.platform = const DoseSyncWorkPlatform();
    client.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  group('주기 작업의 건너뛰기 조건', () {
    // 함수이름: 할 일 없는 주기 작업 테스트
    // 함수역할: 위젯도 전송 대기 기록도 없으면 통신·발행·작업 재등록을 전혀 하지 않는지 검증한다.
    test('nothing pending and no widget: no request, no publish, no job', () async {
      await prepare();
      platform.installed = false;

      await DoseHomeWidget.refreshInBackground();

      expect(uploads, isEmpty);
      expect(scheduleReads, 0);
      expect(platform.savedStates, isEmpty);
      expect(platform.openedClients, 0);
      expect(platform.registered, isEmpty);
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isFalse);
    });

    // 함수이름: 위젯만 있는 주기 작업 테스트
    // 함수역할: 오늘 일정이 이미 있으면 통신 없이 위젯만 한 번 다시 그리는지 검증한다.
    test('widget with today\'s schedule: one local publish, no request', () async {
      await prepare();

      await DoseHomeWidget.refreshInBackground();

      expect(uploads, isEmpty);
      expect(scheduleReads, 0);
      expect(platform.openedClients, 0);
      expect(platform.savedStates, hasLength(1));
      expect(platform.savedStates.single['date'], today());
      expect(platform.registered, isEmpty);
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isFalse);
    });

    // 함수이름: 날짜가 바뀐 위젯 테스트
    // 함수역할: 위젯이 있고 오늘 일정이 없으면 서버 일정을 한 번만 읽어 발행하는지 검증한다.
    test('widget without today\'s schedule: one read, two publishes', () async {
      await prepare(date: '2000-01-01');
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isTrue);

      await DoseHomeWidget.refreshInBackground();

      expect(scheduleReads, 1);
      expect(uploads, isEmpty);
      expect(platform.savedStates, hasLength(2));
      expect(platform.savedStates.last['total'], 1);
      expect((await store.readCache(owner))!['date'], today());
      expect(platform.registered, isEmpty);

      await DoseHomeWidget.refreshInBackground();
      expect(scheduleReads, 1);
    });

    // 함수이름: 위젯 없는 날짜 변경 테스트
    // 함수역할: 표시할 위젯이 없으면 날짜가 바뀌어도 서버 일정을 읽지 않는지 검증한다.
    test('no widget and no pending record: a stale schedule is not read', () async {
      await prepare(date: '2000-01-01');
      platform.installed = false;

      await DoseHomeWidget.refreshInBackground();

      expect(scheduleReads, 0);
      expect(platform.savedStates, isEmpty);
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isFalse);
    });

    // 함수이름: 위젯 확인 실패 테스트
    // 함수역할: 위젯 유무를 확인하지 못하면 있는 것으로 보고 기존처럼 갱신하는지 검증한다.
    test('an unknown widget state is treated as installed', () async {
      await prepare(date: '2000-01-01');
      platform.failInstalledLookup = true;

      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isTrue);
      await DoseHomeWidget.refreshInBackground();

      expect(scheduleReads, 1);
      expect(platform.savedStates, hasLength(2));
    });
  });

  group('전송 대기 기록', () {
    // 함수이름: 주기 작업 전송 테스트
    // 함수역할: 대기 기록을 한 번 전송하고 확인 응답의 일정으로 위젯을 갱신하며 일정은 다시 읽지 않는지 검증한다.
    test('a pending record is uploaded once and the widget is refreshed', () async {
      await prepare();
      await enqueue('op-1');
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isTrue);

      await DoseHomeWidget.refreshInBackground();

      expect(uploadedIds(), ['op-1']);
      expect(uploads.single.containsKey('medication_names'), isFalse);
      expect(scheduleReads, 0);
      expect(await store.pending(owner), isEmpty);
      expect(platform.openedClients, 1);
      expect(platform.savedStates, hasLength(2));
      expect(platform.savedStates.first['status'], contains('전송 대기 1건'));
      expect(platform.savedStates.last['status'], '서버 저장 완료');
      expect(platform.savedStates.last['done'], 1);
      // 갱신 작업이 스스로를 다시 예약하지 않는다.
      expect(platform.registered, isEmpty);

      await DoseHomeWidget.refreshInBackground();
      expect(uploadedIds(), ['op-1']);
    });

    // 함수이름: 위젯 없는 전송 테스트
    // 함수역할: 위젯이 없어도 주기 작업이 대기 기록을 전송하는지 검증한다.
    test('a pending record is uploaded even without a widget', () async {
      await prepare();
      await enqueue('op-1');
      platform.installed = false;
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isTrue);

      await DoseHomeWidget.refreshInBackground();

      expect(uploadedIds(), ['op-1']);
      expect(await store.pending(owner), isEmpty);
      expect(scheduleReads, 0);
    });

    // 함수이름: 전송 실패 테스트
    // 함수역할: 서버가 받지 못한 기록을 지우지 않고 대기 상태로 표시하며 발행 횟수가 늘지 않는지 검증한다.
    test('a failed upload keeps the record and still publishes once more', () async {
      await prepare(date: '2000-01-01');
      await enqueue('op-1', date: '2000-01-01');
      uploadStatus = 503;

      await DoseHomeWidget.refreshInBackground();

      expect(uploadedIds(), ['op-1']);
      expect(scheduleReads, 1);
      expect(
        (await store.pending(owner)).map((op) => op['operation_id']),
        ['op-1'],
      );
      expect(platform.savedStates, hasLength(2));
      expect(platform.savedStates.last['status'], contains('전송 대기 1건'));
    });

    // 함수이름: 중복 전송 방지 테스트
    // 함수역할: 앱의 전송과 주기 작업이 겹쳐도 같은 기록을 한 번만 보내는지 검증한다.
    test('the app and the periodic worker never upload one record twice', () async {
      await prepare();
      await enqueue('op-1');
      uploadDelay = const Duration(milliseconds: 40);
      final foreground = DoseSyncService(
        owner: owner,
        client: client,
        openStore: () async => store,
      );
      addTearDown(foreground.dispose);

      await Future.wait([
        foreground.drain(),
        DoseHomeWidget.refreshInBackground(),
      ]);
      await DoseHomeWidget.refreshInBackground();

      expect(uploadedIds(), ['op-1']);
      expect(await store.pending(owner), isEmpty);
    });

    // 함수이름: 거부된 기록 테스트
    // 함수역할: 서버가 거부해 보류된 기록만 남았으면 주기 작업이 통신을 준비하지 않는지 검증한다.
    test('a rejected record does not wake the network every period', () async {
      await prepare();
      await enqueue('op-1');
      uploadStatus = 409;
      await DoseHomeWidget.refreshInBackground();
      expect((await store.pending(owner)).single['state'], 'blocked');
      final opened = platform.openedClients;

      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isFalse);
      await DoseHomeWidget.refreshInBackground();

      expect(uploadedIds(), ['op-1']);
      expect(platform.openedClients, opened);
      expect(
        platform.savedStates.last['status'],
        '전송 확인 필요 · 앱에서 확인',
      );
    });
  });

  group('호출자가 준비한 동기화 서비스', () {
    // 함수이름: 전달받은 서비스 재사용 테스트
    // 함수역할: 호출자가 전송까지 마친 서비스를 넘기면 다시 전송하거나 닫지 않고 그 통신 수단을 쓰는지 검증한다.
    test('a caller-provided service is reused, not drained or disposed', () async {
      await prepare(date: '2000-01-01');
      await enqueue('op-1', date: '2000-01-01');
      uploadStatus = 503;
      final sync = DoseSyncService(
        owner: owner,
        client: client,
        openStore: () async => store,
      );
      addTearDown(sync.dispose);
      await sync.drain();
      expect(uploadedIds(), ['op-1']);

      await DoseHomeWidget.refreshInBackground(sync: sync, client: client);

      // 호출자가 방금 시도한 전송을 반복하지 않고, 필요한 일정 조회만 한다.
      expect(uploadedIds(), ['op-1']);
      expect(scheduleReads, 1);
      expect(platform.openedClients, 0);
      expect(platform.savedStates, hasLength(2));
      expect(() => sync.addListener(() {}), returnsNormally);
      expect(sync.pendingCount, 1);
    });

    // 함수이름: 전달받은 서비스의 계정 불일치 테스트
    // 함수역할: 다른 계정의 서비스를 넘겨도 현재 계정의 기록을 그 서비스로 보내지 않는지 검증한다.
    test('a service of another account is never used for this account', () async {
      await prepare();
      await enqueue('op-1');
      final other = DoseSyncService(
        owner: 'patient-b',
        client: client,
        openStore: () async => store,
      );
      addTearDown(other.dispose);

      await DoseHomeWidget.refreshInBackground(sync: other, client: client);

      expect(uploads, isEmpty);
      expect(await store.pending(owner), hasLength(1));
    });
  });

  group('위젯에서 누른 버튼', () {
    // 함수이름: journalFor
    // 함수역할: 위젯에 표시된 버튼을 눌렀을 때 Android가 먼저 저장하는 클릭 목록을 만든다.
    String journalFor(DoseWidgetState state) => jsonEncode([
      {
        'action': state.view['action'],
        'token': state.view['token'],
        'widget': 1,
      },
    ]);

    // 함수이름: 위젯 복용 기록 테스트
    // 함수역할: 위젯의 복용 버튼이 대기열에 저장된 뒤 전송되고, 전송 작업 예약은 발행이 한 번만 하는지 검증한다.
    test('a widget tap is stored, uploaded once and acknowledged', () async {
      final shown = await prepare();
      expect(shown.view['action'], 'take');
      platform.journal = journalFor(shown);
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isTrue);

      await DoseHomeWidget.refreshInBackground(requestedByWidget: true);

      expect(uploadedIds(), [shown.view['token']]);
      expect(uploads.single['completed'], isTrue);
      expect(uploads.single['slot_key'], 'morning');
      expect(uploads.single['schedule_date'], today());
      expect(platform.savedStates.first['handled'], [shown.view['token']]);
      expect(platform.journal, '[]');
      expect(platform.registered, [owner]);
      // 클릭으로 깨어난 갱신은 확인 응답의 일정을 쓰고 다시 조회하지 않는다.
      expect(scheduleReads, 0);
      expect(platform.savedStates, hasLength(2));
      expect(platform.savedStates.last['done'], 1);
      expect(await store.pending(owner), isEmpty);
    });

    // 함수이름: 오프라인 위젯 복용 기록 테스트
    // 함수역할: 연결이 없어도 위젯의 복용 기록이 대기열에 남고 위젯에 전송 대기로 표시되는지 검증한다.
    test('an offline widget tap stays queued and is shown as pending', () async {
      final shown = await prepare();
      platform.journal = journalFor(shown);
      online = false;

      await DoseHomeWidget.refreshInBackground(requestedByWidget: true);

      final pending = await store.pending(owner);
      expect(pending.single['operation_id'], shown.view['token']);
      expect(pending.single['completed'], isTrue);
      expect(pending.single['state'], 'pending');
      expect(platform.savedStates.first['handled'], [shown.view['token']]);
      expect(platform.savedStates.last['done'], 1);
      expect(platform.savedStates.last['status'], contains('전송 대기 1건'));
      // 연결되면 전송하도록 작업을 한 번 예약한다.
      expect(platform.registered, [owner]);

      online = true;
      await DoseHomeWidget.refreshInBackground();
      expect(uploadedIds(), [shown.view['token']]);
      expect(await store.pending(owner), isEmpty);
    });

    // 함수이름: 호출자 서비스와 위젯 클릭 테스트
    // 함수역할: 호출자가 전송을 마친 뒤에 남아 있던 위젯 클릭도 같은 갱신에서 전송하는지 검증한다.
    test('a tap found after the caller drained is still uploaded', () async {
      final shown = await prepare();
      final sync = DoseSyncService(
        owner: owner,
        client: client,
        openStore: () async => store,
      );
      addTearDown(sync.dispose);
      await sync.drain();
      platform.journal = journalFor(shown);

      await DoseHomeWidget.refreshInBackground(sync: sync, client: client);

      expect(uploadedIds(), [shown.view['token']]);
      expect(sync.pendingCount, 0);
      expect(platform.openedClients, 0);
    });

    // 함수이름: 위젯 새로고침 버튼 테스트
    // 함수역할: 위젯의 새로고침 요청은 오늘 일정이 있어도 서버에서 다시 읽는지 검증한다.
    test('a refresh requested by the widget always reads the server', () async {
      await prepare();

      await DoseHomeWidget.refreshInBackground(requestedByWidget: true);

      expect(scheduleReads, 1);
      expect(uploads, isEmpty);
      expect(platform.savedStates, hasLength(2));
    });
  });

  group('환자 조회 위젯', () {
    const patients = {'source': 'patients'};

    // 함수이름: 환자 일정 조회 테스트
    // 함수역할: 환자 조회 결과가 없을 때만 한 번 읽어 발행하고, 오늘 결과가 있으면 다시 읽지 않는지 검증한다.
    test('patient snapshots are read once per day by the periodic worker', () async {
      await prepare(config: patients);
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isTrue);

      await DoseHomeWidget.refreshInBackground();

      expect(snapshotReads, 1);
      expect(scheduleReads, 0);
      expect(platform.savedStates, hasLength(2));
      final shown = platform.savedStates.last['patients'] as List;
      expect((shown.single as Map)['title'], '어머니');

      await DoseHomeWidget.refreshInBackground();
      expect(snapshotReads, 1);
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isFalse);

      await DoseHomeWidget.refreshInBackground(requestedByWidget: true);
      expect(snapshotReads, 2);
    });

    // 함수이름: 환자 일정 조회 실패 테스트
    // 함수역할: 조회 실패를 위젯에 표시하고 다음 주기 작업에서 다시 시도하는지 검증한다.
    test('a failed patient read is shown and retried next period', () async {
      await prepare(config: patients);
      snapshotStatus = 503;

      await DoseHomeWidget.refreshInBackground();

      expect(snapshotReads, 1);
      expect(platform.savedStates.last['heading'], '환자 일정을 새로고침해주세요');
      expect(await DoseHomeWidget.needsNetworkRefresh(owner), isTrue);

      snapshotStatus = 200;
      await DoseHomeWidget.refreshInBackground();
      expect(snapshotReads, 2);
      expect(platform.savedStates.last['patients'], hasLength(1));
    });
  });

  group('완료한 시간대의 재알림 취소', () {
    // 함수이름: 재알림 취소 반복 방지 테스트
    // 함수역할: 같은 완료 상태를 다시 발행해도 재알림을 한 번만 취소하고, 복용을 취소했다가 다시 완료하면
    //   다시 취소하는지 검증한다.
    test('a completed slot is cancelled once, and again after an undo', () async {
      await prepare(taken: true);

      await DoseHomeWidget.publish(owner: owner);
      await DoseHomeWidget.publish(owner: owner);
      await DoseHomeWidget.publish(owner: owner);

      expect(platform.cancelledReminders, hasLength(1));
      expect(platform.cancelledReminders.single.owner, owner);
      expect(platform.cancelledReminders.single.slotKey, 'morning');
      expect(platform.cancelledReminders.single.date, DateTime.parse(today()));
      expect(platform.scheduledUpdates, hasLength(3));

      await prepare(taken: false);
      await DoseHomeWidget.publish(owner: owner);
      expect(platform.cancelledReminders, hasLength(1));

      await prepare(taken: true);
      await DoseHomeWidget.publish(owner: owner);
      await DoseHomeWidget.publish(owner: owner);
      expect(platform.cancelledReminders, hasLength(2));
    });

    // 함수이름: 재알림 취소 실패 재시도 테스트
    // 함수역할: 취소가 실패해도 위젯 발행은 끝나고 다음 발행에서 다시 취소를 시도하는지 검증한다.
    test('a failed cancellation is retried by the next publish', () async {
      await prepare(taken: true);
      platform.failReminderCancel = true;

      final state = await DoseHomeWidget.publish(owner: owner);

      expect(state, isNotNull);
      expect(platform.savedStates, hasLength(1));
      expect(platform.scheduledUpdates, hasLength(1));
      expect(platform.cancelledReminders, isEmpty);

      platform.failReminderCancel = false;
      await DoseHomeWidget.publish(owner: owner);
      expect(platform.cancelledReminders, hasLength(1));
    });
  });

  group('전송 작업 예약', () {
    // 함수이름: 전송 작업 등록 테스트
    // 함수역할: 일회성 작업과 주기 작업을 계정별로 한 번씩 등록하는지 검증한다.
    test('register schedules the one-off and the periodic task', () async {
      final work = _RecordingWorkPlatform(store);
      DoseSyncBackgroundScheduler.platform = work;

      await DoseSyncBackgroundScheduler.register(owner);

      expect(work.calls, ['one-off:$owner', 'periodic:$owner']);
    });

    // 함수이름: 로그아웃 중단 테스트
    // 함수역할: 로그아웃 때 작업을 취소하고 저장소의 활성 계정을 해제하되 대기 기록은 남기는지 검증한다.
    test('suspend cancels the workers and deactivates the account', () async {
      await prepare();
      await enqueue('op-1');
      final work = _RecordingWorkPlatform(store);
      DoseSyncBackgroundScheduler.platform = work;

      await DoseSyncBackgroundScheduler.suspend();

      expect(work.calls, ['cancel', 'open']);
      expect(await store.isActive(owner), isFalse);
      expect(await store.pending(owner), hasLength(1));
    });

    // 함수이름: 저장소 실패 시 중단 테스트
    // 함수역할: 저장소를 열지 못해도 작업은 먼저 취소하고 그 오류를 호출자에게 전달하는지 검증한다.
    test('suspend cancels the workers even when the store cannot open', () async {
      final work = _RecordingWorkPlatform(null);
      DoseSyncBackgroundScheduler.platform = work;

      await expectLater(DoseSyncBackgroundScheduler.suspend(), throwsStateError);

      expect(work.calls, ['cancel', 'open']);
    });
  });

  // 함수이름: 로그아웃 위젯 정리 테스트
  // 함수역할: 로그아웃 때 위젯 표시를 비우고 처리하지 못한 클릭을 처리 완료로 표시하는지 검증한다.
  test('clear blanks the widget and discards unhandled taps', () async {
    platform.journal = jsonEncode([
      {'action': 'take', 'token': 'widget_old', 'widget': 1},
    ]);

    await DoseHomeWidget.clear();

    expect(platform.cancelledScheduledUpdates, 1);
    expect(platform.savedStates.single, {
      'handled': ['widget_old'],
    });
    expect(platform.journal, '[]');
  });
}
