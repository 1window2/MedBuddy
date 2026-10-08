// 파일명: background_task_test.dart
// 역할: Android가 깨운 백그라운드 작업이 종류별로 필요한 일만 하는지 검증한다. 복용 기록 작업은 보낼 것이
//   없으면 인증과 통신을 준비하지 않고, 복약 알림·보호자 작업은 인증한 통신 수단 하나를 쓰고 닫는다.
// 복용 기록 저장소는 실제 SQLite·암호화 구현을 쓰고, 인증·위젯·알림·감시 호출은 기록용 대역으로 바꾼다.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/api_config.dart';
import 'package:medbuddy_frontend/composition/caregiver_notification_background_service.dart';
import 'package:medbuddy_frontend/services/dose_home_widget_service.dart';
import 'package:medbuddy_frontend/services/dose_outbox_store.dart';
import 'package:medbuddy_frontend/services/dose_sync_background_service.dart';
import 'package:medbuddy_frontend/services/dose_sync_service.dart';
import 'package:medbuddy_frontend/services/medication_reminder_background_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/dose_sync_harness.dart';

// 클래스명: _ClosingClient
// 역할: 요청을 대역 서버로 넘기고 작업이 통신 수단을 닫았는지 기록한다.
class _ClosingClient extends http.BaseClient {
  // 함수이름: _ClosingClient
  // 함수역할: 요청을 처리할 대역 클라이언트를 감싼다. 매개변수: _inner - 대역 서버. 반환값: 기록용 클라이언트.
  _ClosingClient(this._inner);

  final http.Client _inner;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() => closed = true;
}

// 클래스명: _RecordingDeps
// 역할: 백그라운드 작업이 부른 서비스 호출을 순서대로 기록하는 대역.
// 주요 책임: 인증 실패, 통신 필요 여부, 알림 갱신·감시 결과와 오류를 테스트가 정한 대로 재현한다.
// 속성: calls 호출 순서, store 복용 기록 저장소, client 인증된 통신 수단(null이면 인증 복원 실패),
//   needsNetwork 통신 필요 여부(null이면 실제 판정 사용), reminderResult/caregiverResult 작업 결과,
//   failure 알림 갱신·감시가 던질 오류, widgetSyncs 위젯 갱신에 넘어온 동기화 서비스.
class _RecordingDeps extends BackgroundTaskDeps {
  // 함수이름: _RecordingDeps
  // 함수역할: 저장소와 통신 수단을 정한 기록용 대역을 만든다. 매개변수: store, client. 반환값: 대역.
  _RecordingDeps({this.store, this.client});

  final DoseOutboxStore? store;
  final _ClosingClient? client;
  final List<String> calls = [];
  final List<DoseSyncService?> widgetSyncs = [];
  final List<http.Client?> widgetClients = [];
  bool? needsNetwork;
  bool reminderResult = true;
  bool caregiverResult = true;
  Object? failure;

  @override
  Future<http.Client?> openClient() async {
    calls.add('openClient');
    return client;
  }

  @override
  Future<DoseOutboxStore> openDoseStore() async {
    calls.add('openDoseStore');
    return store!;
  }

  @override
  Future<bool> doseNeedsNetwork(String owner) async {
    calls.add('doseNeedsNetwork');
    return needsNetwork ?? await super.doseNeedsNetwork(owner);
  }

  @override
  Future<void> refreshDoseWidget({
    DoseSyncService? sync,
    http.Client? client,
  }) async {
    calls.add(sync == null ? 'refreshDoseWidget:local' : 'refreshDoseWidget');
    widgetSyncs.add(sync);
    widgetClients.add(client);
  }

  @override
  Future<void> initializeNotifications() async {
    calls.add('initializeNotifications');
  }

  @override
  Future<bool> refreshReminders({
    required String patientHash,
    required String baseUrl,
    required http.Client client,
  }) async {
    calls.add('refreshReminders:$patientHash:$baseUrl');
    expect(client, same(this.client));
    if (failure != null) throw failure!;
    return reminderResult;
  }

  @override
  Future<bool> checkCaregiverAlerts({
    required String caregiverHash,
    required String baseUrl,
    required http.Client client,
  }) async {
    calls.add('checkCaregiverAlerts:$caregiverHash:$baseUrl');
    expect(client, same(this.client));
    if (failure != null) throw failure!;
    return caregiverResult;
  }
}

// 클래스명: _NoWidgetPlatform
// 역할: 홈 화면에 위젯이 없고 처리할 클릭도 없는 Android 기기를 재현해 실제 통신 필요 판정을 쓰게 한다.
class _NoWidgetPlatform extends DoseHomeWidgetPlatform {
  // 함수이름: _NoWidgetPlatform
  // 함수역할: 테스트 저장소를 쓰는 플랫폼 대역을 만든다. 매개변수: store. 반환값: 대역.
  _NoWidgetPlatform(this.store);

  final DoseOutboxStore store;

  @override
  bool get supported => true;

  @override
  Future<String?> readJournal() async => '[]';

  @override
  Future<bool> hasInstalledWidget() async => false;

  @override
  Future<DoseOutboxStore> openStore() async => store;
}

// 함수이름: main
// 함수역할: 작업 종류별 백그라운드 실행 시나리오를 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  const owner = 'patient-a';
  late Database db;
  late DoseOutboxStore store;
  late List<http.Request> requests;
  late int uploadStatus;
  late _ClosingClient client;

  // 함수이름: medication
  // 함수역할: 아침 한 번 복용하는 테스트 약 일정을 만든다. 반환값: 일정.
  MedicationSchedule medication() => const MedicationSchedule(
    medicationID: '91',
    medicationName: 'test medicine',
    scheduleSlotKeys: ['morning'],
    slotStatuses: {'morning': true},
  );

  // 함수이름: enqueue
  // 함수역할: 앱에서 기록해 아직 전송하지 못한 아침 복용 요청을 대기열에 넣는다. 반환값: 저장 완료 Future.
  Future<void> enqueue() => store.enqueue(owner, {
    'operation_id': 'op-1',
    'schedule_date': doseScheduleDay(DateTime.now()),
    'slot_key': 'morning',
    'medication_ids': [91],
    'completed': true,
  });

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: DoseOutboxStore.createSchema,
        singleInstance: false,
      ),
    );
    store = DoseOutboxStore(db, await AesGcm.with256bits().newSecretKey());
    requests = [];
    uploadStatus = 200;
    client = _ClosingClient(
      MockClient((request) async {
        requests.add(request);
        if (uploadStatus != 200) return http.Response('unavailable', uploadStatus);
        return doseSyncReceipt(request, [medication()]);
      }),
    );
    DoseHomeWidget.platform = _NoWidgetPlatform(store);
  });

  tearDown(() async {
    DoseHomeWidget.resetForTest();
    await db.close();
  });

  group('복용 기록 작업', () {
    // 함수이름: 할 일 없는 작업 테스트
    // 함수역할: 보낼 기록도 새로 읽을 위젯 일정도 없으면 인증과 통신을 준비하지 않고, 기기 안의 위젯 상태만
    //   맞춘 뒤 성공으로 끝나는지 검증한다.
    test('nothing to upload: no authentication, no request, local widget refresh only', () async {
      await store.activate(owner);
      final deps = _RecordingDeps(store: store, client: client);

      final result = await runBackgroundTask(doseSyncBackgroundTask, {
        'patient_hash': owner,
      }, deps);

      expect(result, isTrue);
      expect(deps.calls, [
        'openDoseStore',
        'doseNeedsNetwork',
        'refreshDoseWidget:local',
      ]);
      expect(requests, isEmpty);
      expect(client.closed, isFalse);
    });

    // 함수이름: 전송 대기 기록 테스트
    // 함수역할: 전송할 기록이 있으면 인증한 통신 수단으로 한 번 전송하고, 전송을 마친 같은 동기화 서비스와
    //   통신 수단을 위젯 갱신에 넘긴 뒤 닫는지 검증한다.
    test('pending record: one upload, the drained service is handed to the widget', () async {
      await store.activate(owner);
      await enqueue();
      final deps = _RecordingDeps(store: store, client: client);

      final result = await runBackgroundTask(doseSyncBackgroundTask, {
        'patient_hash': owner,
      }, deps);

      expect(result, isTrue);
      expect(deps.calls, [
        'openDoseStore',
        'doseNeedsNetwork',
        'openClient',
        'refreshDoseWidget',
      ]);
      expect(requests, hasLength(1));
      expect(requests.single.url.path, endsWith('/schedule/completion-operations'));
      expect(jsonDecode(requests.single.body), containsPair('operation_id', 'op-1'));
      expect(deps.widgetSyncs.single!.owner, owner);
      expect(deps.widgetSyncs.single!.client, same(client));
      expect(deps.widgetClients.single, same(client));
      expect(await store.hasUploadableOperation(owner), isFalse);
      expect(client.closed, isTrue);
    });

    // 함수이름: 전송 실패 테스트
    // 함수역할: 서버가 일시적으로 받지 못하면 기록을 남긴 채 실패를 돌려 작업이 다시 예약되게 하는지 검증한다.
    test('upload rejected temporarily: the record stays and the task asks for a retry', () async {
      await store.activate(owner);
      await enqueue();
      uploadStatus = 503;
      final deps = _RecordingDeps(store: store, client: client);

      final result = await runBackgroundTask(doseSyncBackgroundTask, {
        'patient_hash': owner,
      }, deps);

      expect(result, isFalse);
      expect(requests, hasLength(1));
      expect(await store.hasUploadableOperation(owner), isTrue);
      expect(client.closed, isTrue);
    });

    // 함수이름: 인증 복원 실패 테스트
    // 함수역할: 전송할 기록이 있는데 로그인 사용자를 복원하지 못하면 전송하지 않고 실패를 돌리는지 검증한다.
    test('pending record without a restored session: no request and a retry', () async {
      await store.activate(owner);
      await enqueue();
      final deps = _RecordingDeps(store: store);

      final result = await runBackgroundTask(doseSyncBackgroundTask, {
        'patient_hash': owner,
      }, deps);

      expect(result, isFalse);
      expect(deps.calls, ['openDoseStore', 'doseNeedsNetwork', 'openClient']);
      expect(requests, isEmpty);
      expect(await store.hasUploadableOperation(owner), isTrue);
    });

    // 함수이름: 다른 계정 작업 테스트
    // 함수역할: 로그아웃했거나 다른 계정으로 바뀐 뒤 남은 작업, 계정 없는 작업은 아무 일도 하지 않는지 검증한다.
    test('signed-out or foreign owner: nothing is opened beyond the store', () async {
      await store.activate('patient-b');
      final deps = _RecordingDeps(store: store, client: client);

      expect(
        await runBackgroundTask(doseSyncBackgroundTask, {
          'patient_hash': owner,
        }, deps),
        isTrue,
      );
      expect(deps.calls, ['openDoseStore']);

      deps.calls.clear();
      expect(await runBackgroundTask(doseSyncBackgroundTask, {}, deps), isTrue);
      expect(deps.calls, isEmpty);
      expect(requests, isEmpty);
    });
  });

  group('복약 알림 작업', () {
    // 함수이름: 알림 갱신 테스트
    // 함수역할: 인증 뒤 알림 서비스를 준비하고 작업에 저장된 환자·API 주소로 알림을 갱신하며, 그 결과를 그대로
    //   돌려주고 통신 수단을 닫는지 검증한다.
    test('reminder refresh runs with the task scope and returns its result', () async {
      for (final outcome in [true, false]) {
        final taskClient = _ClosingClient(MockClient((_) async => http.Response('{}', 200)));
        final deps = _RecordingDeps(client: taskClient)..reminderResult = outcome;

        final result = await runBackgroundTask(medicationReminderBackgroundTask, {
          'patient_hash': owner,
          'base_url': 'https://api.test/v1',
        }, deps);

        expect(result, outcome);
        expect(deps.calls, [
          'openClient',
          'initializeNotifications',
          'refreshReminders:$owner:https://api.test/v1',
        ]);
        expect(taskClient.closed, isTrue);
      }
    });

    // 함수이름: 알림 갱신 예외 테스트
    // 함수역할: 계정 없는 작업은 인증 없이 끝내고, 인증 복원 실패와 실행 중 오류는 실패로 돌리며 통신 수단을
    //   닫는지 검증한다.
    test('missing scope is ignored; missing session and errors ask for a retry', () async {
      final empty = _RecordingDeps(client: client);
      expect(
        await runBackgroundTask(medicationReminderBackgroundTask, {
          'patient_hash': '  ',
        }, empty),
        isTrue,
      );
      expect(empty.calls, isEmpty);

      final signedOut = _RecordingDeps();
      expect(
        await runBackgroundTask(medicationReminderBackgroundTask, {
          'patient_hash': owner,
        }, signedOut),
        isFalse,
      );
      expect(signedOut.calls, ['openClient']);

      final failing = _RecordingDeps(client: client)
        ..failure = StateError('network unavailable');
      expect(
        await runBackgroundTask(medicationReminderBackgroundTask, {
          'patient_hash': owner,
        }, failing),
        isFalse,
      );
      expect(failing.calls.last, 'refreshReminders:$owner:${ApiConfig.baseUrl}');
      expect(client.closed, isTrue);
    });
  });

  group('보호자 감시 작업', () {
    // 함수이름: 보호자 감시 테스트
    // 함수역할: 보호자 계정 범위로 감시를 한 번 실행해 결과를 돌려주고, 환자 알림 갱신은 하지 않는지 검증한다.
    test('caregiver check runs with the caregiver scope and returns its result', () async {
      for (final outcome in [true, false]) {
        final taskClient = _ClosingClient(MockClient((_) async => http.Response('{}', 200)));
        final deps = _RecordingDeps(client: taskClient)..caregiverResult = outcome;

        final result = await runBackgroundTask(
          caregiverNotificationBackgroundTask,
          {'caregiver_hash': 'caregiver-a', 'patient_hash': owner},
          deps,
        );

        expect(result, outcome);
        expect(deps.calls, [
          'openClient',
          'initializeNotifications',
          'checkCaregiverAlerts:caregiver-a:${ApiConfig.baseUrl}',
        ]);
        expect(taskClient.closed, isTrue);
      }
    });

    // 함수이름: 범위 없는 감시 테스트
    // 함수역할: 보호자 계정이 없는 작업과 알 수 없는 작업 이름은 아무 호출 없이 성공으로 끝나는지 검증한다.
    test('missing caregiver scope and unknown task names do nothing', () async {
      final deps = _RecordingDeps(client: client);

      expect(
        await runBackgroundTask(caregiverNotificationBackgroundTask, {
          'patient_hash': owner,
        }, deps),
        isTrue,
      );
      expect(await runBackgroundTask('some_other_task', null, deps), isTrue);

      expect(deps.calls, isEmpty);
      expect(client.closed, isFalse);
    });
  });
}
