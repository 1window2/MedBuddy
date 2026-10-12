import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/set_notification_control.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_reminder_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_notification_service.dart';

const _owner = 'reminder-race-patient';
const _cacheKey =
    'medbuddy_medication_reminder_patient_${_owner}_${_owner}_morning';
const _schedules = [
  MedicationSchedule(
    medicationID: '91',
    medicationName: '테스트정',
    scheduleSlotKeys: ['morning'],
  ),
];

Map<String, Object> _alarm(int hour, {bool enabled = true}) => {
  'patient_hash': _owner,
  'slot_key': 'morning',
  'hour': hour,
  'minute': 0,
  'is_enabled': enabled,
};

http.Response _response(Object data) => http.Response(
  jsonEncode({'success': true, 'data': data}),
  200,
  headers: {'content-type': 'application/json'},
);

MedBuddyReminderViewModel _model(
  http.Client client,
  RecordingNotificationService notifications, {
  List<MedicationSchedule> Function()? readSchedules,
}) => MedBuddyReminderViewModel(
  setNotification: SetNotification(
    patientHash: _owner,
    client: client,
    notificationRegistrar: notifications.registerNotification,
  ),
  notificationService: notifications,
  patientHash: _owner,
  readUserSetting: () => const UserSetting(),
  readSchedules: readSchedules ?? () => _schedules,
  scheduleIsFresh: () => true,
  onChanged: (_) {},
);

Future<bool> _save(MedBuddyReminderViewModel model, int hour) =>
    model.requestMedicationReminderSave(
      slotKey: 'morning',
      slotTitle: '아침',
      hour: hour,
      minute: 0,
      schedules: _schedules,
    );

class _PendingPermission extends RecordingNotificationService {
  final result = Completer<bool>();

  @override
  Future<bool> requestPermission() => result.future;
}

class _PendingFirstCancellation extends RecordingNotificationService {
  final started = Completer<void>();
  final release = Completer<void>();
  bool firstFinished = false;

  @override
  Future<void> cancelReminder(int id, {String? slotKey}) async {
    final first = cancellations.isEmpty;
    await super.cancelReminder(id, slotKey: slotKey);
    if (first) {
      started.complete();
      await release.future;
      firstFinished = true;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('시만 지정한 꺼짐 저장은 정각으로 저장하고 성공으로 안내한다', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.method, 'PATCH');
      expect(
        request.url.path,
        endsWith('/notification/settings/morning/disable'),
      );
      expect(request.url.queryParameters['patient_hash'], _owner);
      expect(jsonDecode(request.body), {'hour': 19, 'minute': 0});
      return _response(_alarm(19, enabled: false));
    });
    addTearDown(client.close);
    final notifications = RecordingNotificationService();
    final model = _model(client, notifications);
    addTearDown(model.dispose);

    expect(
      await model.requestMedicationReminderCancel(
        slotKey: 'morning',
        slotTitle: '아침',
        hour: 19,
      ),
      isTrue,
    );
    expect(calls, 1);
    final setting = model.medicationReminderSettings['morning']!;
    expect(setting.timeLabel, '19:00');
    expect(setting.isEnabled, isFalse);
    expect(notifications.registrations, isEmpty);
    expect(notifications.cancellations, isNotEmpty);
    final preferences = await SharedPreferences.getInstance();
    final cached = jsonDecode(preferences.getString(_cacheKey)!) as Map;
    expect(cached['hour'], 19);
    expect(cached['minute'], 0);
    expect(cached['is_enabled'], isFalse);
  });

  for (final enabled in [true, false]) {
    test('진행 중인 ${enabled ? '예약' : '취소'} 동기화가 새 저장을 뒤늦게 덮어쓰지 않는다', () async {
      final notifications = _PendingFirstCancellation();
      var writeOvertookCancellation = false;
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          return _response([_alarm(8, enabled: enabled)]);
        }
        writeOvertookCancellation = !notifications.firstFinished;
        return _response(_alarm(9));
      });
      addTearDown(client.close);
      final model = _model(client, notifications);
      addTearDown(model.dispose);
      await model.loadMedicationReminderSettings();
      final sync = model.synchronizeIfFresh();
      await notifications.started.future;
      final save = _save(model, 9);
      // 실제 취소가 끝나기 전에 새 저장의 비동기 연속 동작을 진행시킨다.
      await Future<void>.delayed(Duration.zero);
      notifications.release.complete();
      await sync;
      expect(await save, isTrue);
      expect(notifications.registrations.map((item) => item.hour), [9]);
      expect(notifications.cancellations, hasLength(2));
      expect(writeOvertookCancellation, isFalse);
      expect(model.medicationReminderSettings['morning']!.hour, 9);
      expect(model.medicationReminderSettings['morning']!.isEnabled, isTrue);
      final cached = jsonDecode(
        (await SharedPreferences.getInstance()).getString(_cacheKey)!,
      );
      expect(cached['hour'], 9);
      expect(cached['is_enabled'], isTrue);
    });
  }

  test('빈 시간대의 진행 중인 서버 비활성화보다 사용자 저장이 나중에 적용된다', () async {
    final disableStarted = Completer<void>();
    final releaseDisable = Completer<void>();
    final applied = <String>[];
    var serverSetting = _alarm(8);
    final client = MockClient((request) async {
      if (request.method == 'GET') return _response([serverSetting]);
      if (request.method == 'PATCH') {
        disableStarted.complete();
        await releaseDisable.future;
        serverSetting = _alarm(8, enabled: false);
        applied.add('disable');
      } else {
        serverSetting = _alarm(9);
        applied.add('save');
      }
      return _response(serverSetting);
    });
    addTearDown(client.close);
    final notifications = RecordingNotificationService();
    var schedules = <MedicationSchedule>[];
    final model = _model(client, notifications, readSchedules: () => schedules);
    addTearDown(model.dispose);
    await model.loadMedicationReminderSettings();
    final sync = model.synchronizeIfFresh();
    await disableStarted.future;
    schedules = _schedules;
    final save = _save(model, 9);
    await Future<void>.delayed(Duration.zero);
    releaseDisable.complete();
    await sync;
    expect(await save, isTrue);
    expect(applied, ['disable', 'save']);
    expect(serverSetting, _alarm(9));
    expect(notifications.registrations.map((item) => item.hour), [9]);
    expect(model.medicationReminderSettings['morning']!.hour, 9);
    final cached = jsonDecode(
      (await SharedPreferences.getInstance()).getString(_cacheKey)!,
    );
    expect(cached['hour'], 9);
    expect(cached['is_enabled'], isTrue);
  });

  test('이전 예약 동기화를 기다린 꺼짐 저장은 기기 예약과 캐시를 꺼진 상태로 유지한다', () async {
    final notifications = _PendingFirstCancellation();
    final client = MockClient((request) async {
      if (request.method == 'GET') return _response([_alarm(8)]);
      return _response(_alarm(19, enabled: false));
    });
    addTearDown(client.close);
    final model = _model(client, notifications);
    addTearDown(model.dispose);
    await model.loadMedicationReminderSettings();
    final sync = model.synchronizeIfFresh();
    await notifications.started.future;
    final save = model.requestMedicationReminderCancel(
      slotKey: 'morning',
      slotTitle: '아침',
      hour: 19,
      minute: 0,
    );
    await Future<void>.delayed(Duration.zero);
    notifications.release.complete();
    await sync;
    expect(await save, isTrue);
    expect(notifications.registrations, isEmpty);
    expect(model.medicationReminderSettings['morning']!.isEnabled, isFalse);
    final cached = jsonDecode(
      (await SharedPreferences.getInstance()).getString(_cacheKey)!,
    );
    expect(cached['hour'], 19);
    expect(cached['is_enabled'], isFalse);
  });

  test('진행 중인 동기화 뒤에 새 조회 세대의 동기화를 누락하지 않는다', () async {
    final notifications = _PendingFirstCancellation();
    var reads = 0;
    final client = MockClient(
      (_) async => _response([_alarm(++reads == 1 ? 8 : 9)]),
    );
    addTearDown(client.close);
    final model = _model(client, notifications);
    addTearDown(model.dispose);
    await model.loadMedicationReminderSettings();
    final oldSync = model.synchronizeIfFresh();
    await notifications.started.future;
    await model.loadMedicationReminderSettings();
    final newSync = model.synchronizeIfFresh();
    notifications.release.complete();
    await oldSync;
    await newSync;
    expect(notifications.registrations.map((item) => item.hour), [9]);
  });

  test('무효화된 동기화의 취소 실패는 대기 중인 저장과 후속 동기화를 막지 않는다', () async {
    final notifications = _PendingFirstCancellation();
    final client = MockClient((request) async {
      if (request.method == 'GET') return _response([_alarm(8)]);
      return _response(_alarm(9));
    });
    addTearDown(client.close);
    final model = _model(client, notifications);
    addTearDown(model.dispose);
    await model.loadMedicationReminderSettings();
    final sync = model.synchronizeIfFresh();
    await notifications.started.future;
    final save = _save(model, 9);
    await Future<void>.delayed(Duration.zero);
    notifications.release.completeError(StateError('취소 실패 테스트'));
    await sync;
    expect(await save, isTrue);
    expect(model.statusMessage, contains('설정되었습니다'));
    await model.synchronizeIfFresh();
    expect(notifications.registrations.map((item) => item.hour), [9, 9]);
  });

  test('꺼짐 저장 뒤 도착한 이전 조회가 설정과 캐시를 되돌리지 않는다', () async {
    final pendingRead = Completer<http.Response>();
    final readStarted = Completer<void>();
    var reads = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        if (++reads == 1) return _response([_alarm(8)]);
        readStarted.complete();
        return pendingRead.future;
      }
      return _response(_alarm(19, enabled: false));
    });
    final model = _model(client, RecordingNotificationService());
    addTearDown(model.dispose);
    addTearDown(client.close);
    await model.loadMedicationReminderSettings();
    final load = model.loadMedicationReminderSettings();
    await readStarted.future;
    expect(
      await model.requestMedicationReminderCancel(
        slotKey: 'morning',
        slotTitle: '아침',
        hour: 19,
        minute: 0,
      ),
      isTrue,
    );
    pendingRead.complete(_response([_alarm(8)]));
    await load;
    expect(model.medicationReminderSettings['morning']!.isEnabled, isFalse);
    expect(model.medicationReminderSettings['morning']!.hour, 19);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(_cacheKey)!)['hour'], 19);
  });

  test('계정 전환으로 종료한 모델의 늦은 저장은 기기 알림을 예약하지 않는다', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final client = MockClient((request) async {
      started.complete();
      return response.future;
    });
    final notifications = RecordingNotificationService();
    final model = _model(client, notifications);
    addTearDown(client.close);
    final save = _save(model, 9);
    await started.future;
    model.dispose();
    response.complete(_response(_alarm(9)));
    expect(await save, isFalse);
    expect(notifications.registrations, isEmpty);
    expect(notifications.cancellations, isEmpty);
    expect(model.medicationReminderSettings, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString(_cacheKey),
      isNull,
    );
  });

  test('같은 시간대 저장이 진행 중이면 중복 쓰기를 시작하지 않는다', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    var writes = 0;
    final client = MockClient((request) async {
      if (++writes == 1) {
        started.complete();
        return response.future;
      }
      return _response(_alarm(10));
    });
    final model = _model(client, RecordingNotificationService());
    addTearDown(model.dispose);
    addTearDown(client.close);
    final first = _save(model, 9);
    await started.future;
    final repeated = await _save(model, 10);
    response.complete(_response(_alarm(9)));
    expect(await first, isTrue);
    expect(repeated, isFalse);
    expect(writes, 1);
    expect(model.medicationReminderSettings['morning']!.hour, 9);
  });

  test('권한 응답 전에 계정이 종료되면 서버 쓰기를 시작하지 않는다', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return _response(_alarm(9));
    });
    addTearDown(client.close);
    final notifications = _PendingPermission();
    final model = _model(client, notifications);
    final save = _save(model, 9);
    model.dispose();
    notifications.result.complete(true);
    expect(await save, isFalse);
    expect(requests, 0);
    expect(notifications.registrations, isEmpty);
  });

  test('계정 종료 후 도착한 꺼짐 응답은 기기 예약과 캐시를 건드리지 않는다', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final client = MockClient((_) async {
      started.complete();
      return response.future;
    });
    addTearDown(client.close);
    final notifications = RecordingNotificationService();
    final model = _model(client, notifications);
    final save = model.requestMedicationReminderCancel(
      slotKey: 'morning',
      slotTitle: '아침',
      hour: 19,
      minute: 0,
    );
    await started.future;
    model.dispose();
    response.complete(_response(_alarm(19, enabled: false)));
    expect(await save, isFalse);
    expect(notifications.cancellations, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString(_cacheKey),
      isNull,
    );
  });

  test('저장 중 자동 조회는 건너뛰고 실패 뒤에는 저장을 다시 시도할 수 있다', () async {
    var reads = 0;
    var writes = 0;
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        reads++;
        return _response([_alarm(8)]);
      }
      if (++writes == 1) {
        started.complete();
        return response.future;
      }
      return _response(_alarm(10));
    });
    addTearDown(client.close);
    final model = _model(client, RecordingNotificationService());
    addTearDown(model.dispose);
    final first = _save(model, 9);
    await started.future;
    await model.loadMedicationReminderSettings();
    expect(reads, 0);
    response.complete(http.Response('{}', 500));
    expect(await first, isFalse);
    expect(await _save(model, 10), isTrue);
    expect(writes, 2);
    expect(model.medicationReminderSettings['morning']!.hour, 10);
  });
}
